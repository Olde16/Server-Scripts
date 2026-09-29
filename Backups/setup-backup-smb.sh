#!/usr/bin/env bash
set -Eeuo pipefail

# Samba share for the Windows backup tree.
#
# Run as root:
#   sudo ./setup-backup-smb.sh
#
# The script configures one read-only SMB share for the complete backup tree.
# Example from Windows:
#   \\backupserver\windows-backups

BACKUP_DIR="/srv/backups/windows"
SHARE_NAME="windows-backups"
SMB_USER="backup"

SMB_CONF="/etc/samba/smb.conf"
BACKUP_SUFFIX="$(date +%Y%m%d_%H%M%S)"
MANAGED_BEGIN="# BEGIN Server-Scripts backup share"
MANAGED_END="# END Server-Scripts backup share"

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

cleanup_tmp() {
    [[ -n "${TMP_CONF:-}" && -f "$TMP_CONF" ]] && rm -f "$TMP_CONF"
}
trap cleanup_tmp EXIT

[[ $EUID -eq 0 ]] || die "Dieses Script muss als root ausgeführt werden."

install_samba() {
    if command -v smbd >/dev/null 2>&1; then
        return
    fi

    log "Samba wurde nicht gefunden. Versuche Installation ..."

    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y samba
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y samba
    elif command -v yum >/dev/null 2>&1; then
        yum install -y samba
    elif command -v zypper >/dev/null 2>&1; then
        zypper --non-interactive install samba
    else
        die "Kein unterstützter Paketmanager gefunden. Bitte Samba manuell installieren."
    fi

    command -v smbd >/dev/null 2>&1 || die "Samba konnte nicht installiert werden."
}

service_name() {
    if systemctl list-unit-files 2>/dev/null | grep -q '^smbd\.service'; then
        echo "smbd"
    elif systemctl list-unit-files 2>/dev/null | grep -q '^smb\.service'; then
        echo "smb"
    else
        echo "smbd"
    fi
}

install_samba

[[ -d "$BACKUP_DIR" ]] || {
    log "Backup-Verzeichnis existiert noch nicht, lege es an: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
}

[[ -f "$SMB_CONF" ]] || die "Samba-Konfiguration nicht gefunden: $SMB_CONF"

if [[ -n "$SMB_USER" ]]; then
    id "$SMB_USER" >/dev/null 2>&1 || die "Linux-Benutzer '$SMB_USER' existiert nicht."

    if ! pdbedit -L 2>/dev/null | cut -d: -f1 | grep -Fxq "$SMB_USER"; then
        cat >&2 <<EOF

Der Linux-Benutzer '$SMB_USER' ist noch kein Samba-Benutzer.

Einmalig ausführen:
  sudo smbpasswd -a $SMB_USER

Danach dieses Script erneut starten.
EOF
        exit 1
    fi
fi

# Backup der bestehenden Samba-Konfiguration.
cp -a "$SMB_CONF" "${SMB_CONF}.backup-$BACKUP_SUFFIX"
log "Samba-Konfiguration gesichert: ${SMB_CONF}.backup-$BACKUP_SUFFIX"

TMP_CONF="$(mktemp)"
awk -v begin="$MANAGED_BEGIN" -v end="$MANAGED_END" '
    $0 == begin { skip=1; next }
    $0 == end   { skip=0; next }
    !skip { print }
' "$SMB_CONF" > "$TMP_CONF"

cat >> "$TMP_CONF" <<EOF

$MANAGED_BEGIN
[$SHARE_NAME]
    path = $BACKUP_DIR
    browseable = yes
    read only = yes
    guest ok = no
    inherit permissions = yes
    force group = users
EOF

if [[ -n "$SMB_USER" ]]; then
    printf '    valid users = %s\n' "$SMB_USER" >> "$TMP_CONF"
fi

cat >> "$TMP_CONF" <<EOF
    smb encrypt = desired
$MANAGED_END
EOF

# Validate before replacing the active configuration.
if ! testparm -s "$TMP_CONF" >/dev/null 2>&1; then
    log "Neue Samba-Konfiguration ist ungültig. Original bleibt erhalten."
    testparm -s "$TMP_CONF" >&2 || true
    exit 1
fi

install -o root -g root -m 0644 "$TMP_CONF" "$SMB_CONF"

SERVICE="$(service_name)"

systemctl enable "$SERVICE"
systemctl restart "$SERVICE"

if ! systemctl is-active --quiet "$SERVICE"; then
    systemctl status "$SERVICE" --no-pager >&2 || true
    die "Samba-Service läuft nicht."
fi

log "Samba-Freigabe eingerichtet:"
log "  \\\\<SERVERNAME>\\$SHARE_NAME"
log "  Pfad: $BACKUP_DIR"
log "  Zugriff: read-only"
log "  Service: $SERVICE (automatisch nach Neustart)"
