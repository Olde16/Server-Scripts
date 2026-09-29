#!/usr/bin/env bash
# Copyright (C) 2026 Olde16
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Back up Windows directories via SSH/SFTP (sshfs), using rsync locally.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${BACKUP_CONFIG:-$SCRIPT_DIR/backup-windows.conf}"

if [[ ! -r "$CONFIG_FILE" ]]; then
  echo "ERROR: Configuration file not found: $CONFIG_FILE" >&2
  echo "Copy backup-windows.conf.example to backup-windows.conf and edit it." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${WINDOWS_USER:?WINDOWS_USER is required}"
: "${WINDOWS_SOURCES:?WINDOWS_SOURCES is required}"
: "${BACKUP_DIR:?BACKUP_DIR is required}"
: "${LOG_DIR:?LOG_DIR is required}"
: "${FULL_EVERY_DAYS:?FULL_EVERY_DAYS is required}"
: "${RETENTION_DAYS:?RETENTION_DAYS is required}"

DRY_RUN="${DRY_RUN:-false}"
SSHFS_OPTS="${SSHFS_OPTS:-}"
RSYNC_EXTRA_OPTS="${RSYNC_EXTRA_OPTS:-}"
LOCK_FILE="${LOCK_FILE:-$BACKUP_DIR/.backup-windows.lock}"
SSHFS_TIMEOUT="${SSHFS_TIMEOUT:-15}"

for cmd in date mkdir rsync sshfs fusermount find flock tee readlink rm cat basename mountpoint mktemp rmdir tr; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "ERROR: Required command not found: $cmd" >&2
    exit 1
  }
done

[[ "$FULL_EVERY_DAYS" =~ ^[0-9]+$ ]] || { echo "ERROR: FULL_EVERY_DAYS must be a number." >&2; exit 1; }
[[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]] || { echo "ERROR: RETENTION_DAYS must be a number." >&2; exit 1; }
[[ "$SSHFS_TIMEOUT" =~ ^[0-9]+$ ]] || { echo "ERROR: SSHFS_TIMEOUT must be a number." >&2; exit 1; }

mkdir -p "$BACKUP_DIR" "$LOG_DIR"
TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
LOG_FILE="$LOG_DIR/backup-windows_$TIMESTAMP.log"

exec > >(tee -a "$LOG_FILE") 2>&1
exec 9>"$LOCK_FILE"
flock -n 9 || { echo "ERROR: Another Windows backup is already running."; exit 1; }

declare -a MOUNTED_BY_SCRIPT=()

cleanup_mounts() {
  local i mount_point
  for (( i=${#MOUNTED_BY_SCRIPT[@]}-1; i>=0; i-- )); do
    mount_point="${MOUNTED_BY_SCRIPT[$i]}"
    if mountpoint -q "$mount_point"; then
      echo "Unmounting: $mount_point"
      fusermount -u "$mount_point" || fusermount -uz "$mount_point" || true
    fi
    rmdir "$mount_point" 2>/dev/null || true
  done
}
trap cleanup_mounts EXIT

windows_path_to_sftp_path() {
  local path="$1"
  path="${path//\\/\/}"
  if [[ "$path" =~ ^([A-Za-z]):/(.*)$ ]]; then
    printf '/%s:/%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  elif [[ "$path" =~ ^([A-Za-z]):$ ]]; then
    printf '/%s:/' "${BASH_REMATCH[1]}"
  else
    printf '%s' "$path"
  fi
}

safe_host_name() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

backup_one_source() {
  local entry="$1"
  local host windows_path remote_path host_dir mount_point
  local latest latest_full dest link_target last_full full_backup
  local now snapshot snapshot_time age_days name days_since_full
  local -a rsync_args extra_opts

  if [[ "$entry" != *"|"* ]]; then
    echo "ERROR: Invalid WINDOWS_SOURCES entry (expected IP|WindowsPath): $entry"
    return 1
  fi

  host="${entry%%|*}"
  windows_path="${entry#*|}"

  if [[ -z "$host" || -z "$windows_path" ]]; then
    echo "ERROR: Invalid WINDOWS_SOURCES entry: $entry"
    return 1
  fi

  remote_path="$(windows_path_to_sftp_path "$windows_path")"
  host_dir="$BACKUP_DIR/$(safe_host_name "$host")"
  latest="$host_dir/latest"
  latest_full="$host_dir/latest_full"

  mkdir -p "$host_dir"

  mount_point="$(mktemp -d "/tmp/backup-windows-$(safe_host_name "$host")-XXXXXX")"

  echo
  echo "============================================================"
  echo "Source: $WINDOWS_USER@$host:$windows_path"
  echo "SFTP path: $remote_path"
  echo "Backup directory: $host_dir"
  echo "============================================================"

  local sshfs_args=(-o "ConnectTimeout=$SSHFS_TIMEOUT" -o "ServerAliveInterval=15" -o "ServerAliveCountMax=3")
  if [[ -n "$SSHFS_OPTS" ]]; then
    # shellcheck disable=SC2206
    local extra_sshfs_opts=( $SSHFS_OPTS )
    sshfs_args+=( "${extra_sshfs_opts[@]}" )
  fi

  if ! sshfs "${sshfs_args[@]}" "$WINDOWS_USER@$host:$remote_path" "$mount_point"; then
    echo "ERROR: Could not mount $WINDOWS_USER@$host:$remote_path"
    rmdir "$mount_point" 2>/dev/null || true
    return 1
  fi

  MOUNTED_BY_SCRIPT+=( "$mount_point" )

  if [[ ! -d "$mount_point" ]]; then
    echo "ERROR: Mounted source is not a directory: $mount_point"
    return 1
  fi

  full_backup=false
  last_full=""
  if [[ ! -f "$latest_full" ]]; then
    full_backup=true
  else
    last_full="$(cat "$latest_full")"
    if [[ "$last_full" =~ ^[0-9]+$ ]]; then
      days_since_full=$(( ( $(date +%s) - last_full ) / 86400 ))
      if (( days_since_full >= FULL_EVERY_DAYS )); then
        full_backup=true
      fi
    else
      full_backup=true
    fi
  fi

  TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
  dest="$host_dir/$TIMESTAMP"

  link_target=""
  if [[ -L "$latest" ]]; then
    link_target="$(readlink -- "$latest")"
    [[ -d "$link_target" ]] || link_target=""
  elif [[ -e "$latest" ]]; then
    echo "ERROR: $latest exists but is not a symlink."
    return 1
  fi

  mkdir -p "$dest"

  rsync_args=(-a --delete --itemize-changes)
  if [[ "$full_backup" == true ]]; then
    rsync_args+=(--checksum)
  elif [[ -n "$link_target" ]]; then
    rsync_args+=( "--link-dest=$link_target" )
  fi

  if [[ -n "$RSYNC_EXTRA_OPTS" ]]; then
    # shellcheck disable=SC2206
    extra_opts=( $RSYNC_EXTRA_OPTS )
    rsync_args+=( "${extra_opts[@]}" )
  fi
  [[ "$DRY_RUN" == "true" ]] && rsync_args+=(--dry-run)

  echo "Snapshot type: $([[ "$full_backup" == true ]] && echo FULL || echo INCREMENTAL)"

  if ! rsync "${rsync_args[@]}" "$mount_point/" "$dest/"; then
    echo "ERROR: rsync failed for $host:$windows_path"
    rm -rf -- "$dest"
    return 1
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    rm -rf -- "$dest"
    echo "Dry run completed for $host:$windows_path"
    return 0
  fi

  if [[ "$full_backup" == true ]]; then
    date +%s > "$latest_full"
  elif [[ -n "$last_full" ]]; then
    printf '%s\n' "$last_full" > "$latest_full"
  fi
  ln -sfn -- "$dest" "$latest"

  echo "Applying retention for $host: deleting snapshots older than $RETENTION_DAYS day(s)."
  now="$(date +%s)"
  while IFS= read -r -d '' snapshot; do
    name="$(basename -- "$snapshot")"
    [[ "$name" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]] || continue
    snapshot_time="$(date -d "${name:0:10} ${name:11:2}:${name:14:2}:${name:17:2}" +%s 2>/dev/null || true)"
    [[ "$snapshot_time" =~ ^[0-9]+$ ]] || continue
    age_days=$(( (now - snapshot_time) / 86400 ))
    if (( age_days > RETENTION_DAYS )); then
      echo "Removing old snapshot: $snapshot"
      rm -rf -- "$snapshot"
    fi
  done < <(find "$host_dir" -mindepth 1 -maxdepth 1 -type d -print0)

  echo "Backup completed successfully for $host:$windows_path"
  return 0
}

success_count=0
failure_count=0

echo "=== Windows backup started ==="
echo "Backup target: $BACKUP_DIR"
echo "Logfile: $LOG_FILE"

for source in "${WINDOWS_SOURCES[@]}"; do
  if backup_one_source "$source"; then
    ((success_count+=1))
  else
    ((failure_count+=1))
    echo "WARNING: Source failed; continuing with next source."
  fi
done

echo
echo "=== Windows backup finished ==="
echo "Successful sources: $success_count"
echo "Failed sources: $failure_count"
echo "Logfile: $LOG_FILE"

(( failure_count == 0 ))
