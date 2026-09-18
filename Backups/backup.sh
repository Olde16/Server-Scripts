#!/usr/bin/env bash
# Copyright (C) 2026 Olde16
# SPDX-License-Identifier: GPL-3.0-or-later
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${BACKUP_CONFIG:-$SCRIPT_DIR/backup.conf}"
if [[ ! -r "$CONFIG_FILE" ]]; then
  echo "ERROR: Configuration file not found: $CONFIG_FILE" >&2
  echo "Copy backup.conf.example to backup.conf and edit it." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${SOURCE_HOST:?SOURCE_HOST is required}"
: "${SOURCE_USER:?SOURCE_USER is required}"
: "${SOURCE_PATH:?SOURCE_PATH is required}"
: "${BACKUP_DIR:?BACKUP_DIR is required}"
: "${LOG_DIR:?LOG_DIR is required}"
: "${FULL_EVERY_DAYS:?FULL_EVERY_DAYS is required}"
: "${RETENTION_DAYS:?RETENTION_DAYS is required}"

DRY_RUN="${DRY_RUN:-false}"
RSYNC_SSH_OPTS="${RSYNC_SSH_OPTS:--}"
RSYNC_EXTRA_OPTS="${RSYNC_EXTRA_OPTS:-}"
LOCK_FILE="${LOCK_FILE:-$BACKUP_DIR/.backup.lock}"

for cmd in date mkdir rsync tee ln readlink rm find flock cat basename; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: Required command not found: $cmd" >&2; exit 1; }
done
[[ "$FULL_EVERY_DAYS" =~ ^[0-9]+$ && "$RETENTION_DAYS" =~ ^[0-9]+$ ]] || exit 1

mkdir -p "$BACKUP_DIR" "$LOG_DIR"
TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
DEST="$BACKUP_DIR/$TIMESTAMP"
LATEST="$BACKUP_DIR/latest"
LATEST_FULL="$BACKUP_DIR/latest_full"
LOG_FILE="$LOG_DIR/backup_$TIMESTAMP.log"

exec > >(tee -a "$LOG_FILE") 2>&1
exec 9>"$LOCK_FILE"
flock -n 9 || { echo "ERROR: Another backup is already running."; exit 1; }

cleanup() {
  local rc=$?
  if (( rc != 0 )) && [[ -d "$DEST" ]]; then
    echo "Backup failed; removing incomplete snapshot: $DEST"
    rm -rf -- "$DEST"
  fi
  exit "$rc"
}
trap cleanup EXIT

full_backup=false
last_full=""
if [[ ! -f "$LATEST_FULL" ]]; then
  full_backup=true
else
  last_full="$(cat "$LATEST_FULL")"
  if [[ "$last_full" =~ ^[0-9]+$ ]]; then
    days_since_full=$(( ( $(date +%s) - last_full ) / 86400 ))
    if (( days_since_full >= FULL_EVERY_DAYS )); then
      full_backup=true
    fi
  else
    full_backup=true
  fi
fi

link_target=""
if [[ -L "$LATEST" ]]; then
  link_target="$(readlink -- "$LATEST")"
  [[ -d "$link_target" ]] || link_target=""
elif [[ -e "$LATEST" ]]; then
  echo "ERROR: $LATEST exists but is not a symlink." >&2
  exit 1
fi

mkdir -p "$DEST"
rsync_args=(-a --delete --itemize-changes)
if [[ "$full_backup" == true ]]; then
  rsync_args+=(--checksum)
fi
if [[ "$full_backup" != true && -n "$link_target" ]]; then
  rsync_args+=("--link-dest=$link_target")
fi
if [[ -n "$RSYNC_EXTRA_OPTS" ]]; then
  # shellcheck disable=SC2206
  extra_opts=( $RSYNC_EXTRA_OPTS )
  rsync_args+=( "${extra_opts[@]}" )
fi
[[ "$DRY_RUN" == "true" ]] && rsync_args+=(--dry-run)

echo "Snapshot type: $([[ "$full_backup" == true ]] && echo FULL || echo INCREMENTAL)"
echo "Source: ${SOURCE_USER}@${SOURCE_HOST}:${SOURCE_PATH}"
rsync "${rsync_args[@]}" -e "ssh $RSYNC_SSH_OPTS" "${SOURCE_USER}@${SOURCE_HOST}:${SOURCE_PATH%/}/" "$DEST/"

if [[ "$DRY_RUN" == "true" ]]; then
  rm -rf -- "$DEST"
  echo "Dry run completed successfully."
  exit 0
fi

if [[ "$full_backup" == true ]]; then
  date +%s > "$LATEST_FULL"
elif [[ -n "$last_full" ]]; then
  printf '%s\\n' "$last_full" > "$LATEST_FULL"
fi
ln -sfn -- "$DEST" "$LATEST"

echo "Applying retention: deleting snapshots older than $RETENTION_DAYS day(s)."
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
done < <(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -print0)

echo "Backup completed successfully: $DEST"
echo "Logfile: $LOG_FILE"
