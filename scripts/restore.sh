#!/usr/bin/env bash
# Restore Vaultwarden data into the Docker volume Coolify manages.
#
# Accepts a Coolify storage-backup archive, the old aaPanel backup
# (bitwarden_FULL_*.tar.gz) or a directory: it finds db.sqlite3 wherever it is
# inside. The volume's current contents are first saved to
# ./pre-restore-<volume>-<timestamp>.tar.gz.
#
# Stop the application in Coolify, then on the server:
#   sudo ./restore.sh [-y] <backup.tar.gz | directory> [volume]
# The volume is detected automatically when exactly one *_vaultwarden-data exists.
set -euo pipefail

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# Run sqlite3 against a database file, falling back to a throwaway container
# when the host has no sqlite3 binary.
sqlite() {
  local db=$1; shift
  if command -v sqlite3 >/dev/null 2>&1; then
    sqlite3 "$db" "$@"
  else
    docker run --rm -v "$(dirname "$db"):/db" alpine:3.22 \
      sh -c 'apk add -q --no-cache sqlite >/dev/null && sqlite3 "/db/$0" "$@"' "$(basename "$db")" "$@"
  fi
}

assume_yes=false
if [[ ${1:-} == -y ]]; then assume_yes=true; shift; fi
src=${1:-}
volume=${2:-}
[[ -n $src ]] || die "Usage: restore.sh [-y] <backup.tar.gz | directory> [volume]"
[[ -e $src ]] || die "$src not found"
src=$(cd "$(dirname "$src")" && pwd)/$(basename "$src")

if [[ -z $volume ]]; then
  mapfile -t found < <(docker volume ls -q | grep -E '(^|_)vaultwarden-data$' || true)
  (( ${#found[@]} == 1 )) \
    || die "Found ${#found[@]} vaultwarden-data volumes (${found[*]:-none}). Pass the volume name as the second argument."
  volume=${found[0]}
fi
docker volume inspect "$volume" >/dev/null 2>&1 \
  || die "Docker volume $volume not found. Deploy the app in Coolify once so it exists."
[[ -z $(docker ps -q --filter "volume=$volume") ]] \
  || die "A container is still using $volume. Stop the application in Coolify first."
log "Target volume: $volume"

# Stage under the current directory: Docker Desktop cannot bind-mount /tmp.
staging=$(mktemp -d "$PWD/.restore-XXXXXX")
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
  read -rp "Replace the contents of $volume with this backup? [y/N] " answer
  [[ $answer == [yY]* ]] || die "Aborted."
fi

previous="pre-restore-$volume-$(date +%Y%m%d-%H%M%S).tar.gz"
docker run --rm -v "$volume:/data:ro" -v "$PWD:/out" alpine:3.22 tar -czf "/out/$previous" -C /data .
chmod 600 "$previous"
log "Previous volume contents saved to $previous"

docker run --rm -v "$volume:/data" -v "$work:/src:ro" alpine:3.22 \
  sh -c 'find /data -mindepth 1 -delete && cp -a /src/. /data/'

log "Restore complete. Start the application in Coolify."
