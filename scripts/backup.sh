#!/usr/bin/env bash
# Back up the Vaultwarden data folder to BACKUP_DIR/vaultwarden-<timestamp>.tar.gz.
# Safe to run while the server is up: the database is copied with Vaultwarden's
# own `backup` command (SQLite VACUUM INTO), not by copying live files.
# Usage: scripts/backup.sh
# shellcheck source=scripts/_common.sh
source "$(dirname "$0")/_common.sh"

[[ -f "$DATA_DIR/db.sqlite3" ]] || die "No database found at $DATA_DIR/db.sqlite3"
require_writable "$DATA_DIR"

backup_dir=$(env_get BACKUP_DIR ./backups)
keep_days=$(env_get BACKUP_KEEP_DAYS 30)
remote=$(env_get BACKUP_RCLONE_REMOTE)
archive="$backup_dir/vaultwarden-$(date +%Y%m%d-%H%M%S).tar.gz"
mkdir -p "$backup_dir"

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT

log "Snapshotting database"
if [[ -n $(compose ps -q --status running vaultwarden) ]]; then
  output=$(compose exec -T vaultwarden /vaultwarden backup)
else
  output=$(compose run --rm --no-deps -T vaultwarden /vaultwarden backup)
fi
# Prints: Backup to 'data/db_20261029_031500.sqlite3' was successful
snapshot=$(sed -n "s/.*Backup to '\(.*\)' was successful.*/\1/p" <<<"$output")
[[ -n $snapshot && -f "$DATA_DIR/$(basename "$snapshot")" ]] || die "Database backup failed: $output"
mv "$DATA_DIR/$(basename "$snapshot")" "$staging/db.sqlite3"

log "Collecting keys, attachments and sends"
for item in rsa_key.pem rsa_key.pub.pem config.json attachments sends; do
  [[ -e "$DATA_DIR/$item" ]] && cp -a "$DATA_DIR/$item" "$staging/"
done

tar -czf "$archive" -C "$staging" .
chmod 600 "$archive"
log "Wrote $archive ($(du -h "$archive" | cut -f1))"

if [[ -n $remote ]]; then
  command -v rclone >/dev/null || die "BACKUP_RCLONE_REMOTE is set but rclone is not installed."
  log "Uploading to $remote"
  rclone copy "$archive" "$remote"
fi

find "$backup_dir" -name 'vaultwarden-*.tar.gz' -mtime "+$keep_days" -print -delete \
  | sed 's/^/    pruned /'
