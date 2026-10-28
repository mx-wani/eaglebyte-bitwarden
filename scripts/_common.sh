# shellcheck shell=bash
# Shared helpers for the scripts in this directory. Source it, don't run it.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC2034  # used by the scripts that source this file
DATA_DIR="$REPO_DIR/data"
cd "$REPO_DIR"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

compose() { docker compose "$@"; }

# Read KEY from .env without sourcing it (values such as ADMIN_TOKEN contain '$').
env_get() {
  local key=$1 default=${2:-} line val
  line=$(grep -E "^${key}=" .env 2>/dev/null | tail -n1 || true)
  val=${line#*=}
  val=${val#\'}; val=${val%\'}; val=${val#\"}; val=${val%\"}
  printf '%s' "${val:-$default}"
}

# Set KEY=VALUE in .env, replacing an existing uncommented line or appending one.
env_set() {
  local key=$1 value=$2 tmp
  tmp=$(mktemp)
  if grep -qE "^${key}=" .env; then
    K="$key" V="$value" awk '
      index($0, ENVIRON["K"] "=") == 1 { print ENVIRON["K"] "=" ENVIRON["V"]; next }
      { print }' .env > "$tmp"
    cat "$tmp" > .env
  else
    printf '%s=%s\n' "$key" "$value" >> .env
  fi
  rm -f "$tmp"
}

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

# On a normal Linux host Vaultwarden writes data/ as root.
require_writable() {
  local dir=$1
  if [[ -e "$dir" && ! -w "$dir" ]]; then
    die "$dir is not writable by $(id -un). Re-run with sudo."
  fi
}
