#!/usr/bin/env bash
# Restore Vaultwarden data from a backup archive or directory.
# Accepts archives from scripts/backup.sh and the old aaPanel backup
# (bitwarden_FULL_*.tar.gz): it finds db.sqlite3 wherever it is inside.
# The current data/ folder is kept as data.pre-restore-<timestamp>.
# Usage: scripts/restore.sh [-y] <backup.tar.gz | directory>
# shellcheck source=scripts/_common.sh
source "$(dirname "$0")/_common.sh"

assume_yes=false
if [[ ${1:-} == -y ]]; then assume_yes=true; shift; fi
src=${1:-}
[[ -n $src ]] || die "Usage: scripts/restore.sh [-y] <backup.tar.gz | directory>"
[[ -e $src ]] || die "$src not found"
src=$(cd "$(dirname "$src")" && pwd)/$(basename "$src")
require_writable "$REPO_DIR"
require_writable "$DATA_DIR"

# Stage next to data/ so the final move is a rename and the sqlite container
# fallback can bind-mount it (Docker Desktop cannot mount /tmp).
staging=$(mktemp -d "$REPO_DIR/.restore-XXXXXX")
trap 'rm -rf "$staging"' EXIT

if [[ -f $src ]]; then
  log "Extracting $(basename "$src")"
  tar -xzf "$src" -C "$staging"
  search_root=$staging
else
  search_root=$src
fi

db=$(find "$search_root" -type f -name db.sqlite3 | head -n1)
[[ -n $db ]] || die "No db.sqlite3 found in $src"
from=$(dirname "$db")
rel=${from#"$search_root"}; rel=${rel#/}
log "Found Vaultwarden data in ${rel:-the backup root}"

# Fold any write-ahead log into the database before it moves; the old aaPanel
# backup carries un-checkpointed changes in db.sqlite3-wal.
work="$staging/restore"
mkdir -p "$work"
cp -a "$from/db.sqlite3" "$work/"
[[ -f "$from/db.sqlite3-wal" ]] && cp -a "$from/db.sqlite3-wal" "$work/"
sqlite "$work/db.sqlite3" 'PRAGMA wal_checkpoint(TRUNCATE);' >/dev/null
result=$(sqlite "$work/db.sqlite3" 'PRAGMA integrity_check;')
[[ $result == ok ]] || die "Integrity check failed: $result"
rm -f "$work/db.sqlite3-wal" "$work/db.sqlite3-shm"
users=$(sqlite "$work/db.sqlite3" 'SELECT count(*) FROM users;')
ciphers=$(sqlite "$work/db.sqlite3" 'SELECT count(*) FROM ciphers;')
log "Database OK: $users user(s), $ciphers vault item(s)"

for item in rsa_key.pem rsa_key.pub.pem config.json attachments sends; do
  [[ -e "$from/$item" ]] && cp -a "$from/$item" "$work/"
done
[[ -f "$work/rsa_key.pem" ]] || warn "No rsa_key.pem in backup: everyone will be logged out and must sign in again."

if ! $assume_yes; then
  read -rp "Replace the current data/ with this backup? [y/N] " answer
  [[ $answer == [yY]* ]] || die "Aborted."
fi

compose stop vaultwarden 2>/dev/null || true
if [[ -d $DATA_DIR ]] && [[ -n $(ls -A "$DATA_DIR") ]]; then
  previous="$REPO_DIR/data.pre-restore-$(date +%Y%m%d-%H%M%S)"
  mv "$DATA_DIR" "$previous"
  log "Previous data kept in $(basename "$previous")"
fi
rm -rf "$DATA_DIR"
mv "$work" "$DATA_DIR"

log "Restore complete. Start the stack with: docker compose up -d"
