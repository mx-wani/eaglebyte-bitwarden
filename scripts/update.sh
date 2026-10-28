#!/usr/bin/env bash
# Back up, then pull and restart on the image versions pinned in .env.
# To upgrade: bump VW_VERSION / CADDY_VERSION in .env, then run this.
# Usage: scripts/update.sh
# shellcheck source=scripts/_common.sh
source "$(dirname "$0")/_common.sh"

if [[ -f "$DATA_DIR/db.sqlite3" ]]; then
  "$REPO_DIR/scripts/backup.sh"
fi

log "Pulling vaultwarden:$(env_get VW_VERSION) and caddy:$(env_get CADDY_VERSION)"
compose pull
compose up -d --remove-orphans
docker image prune -f >/dev/null

compose ps
