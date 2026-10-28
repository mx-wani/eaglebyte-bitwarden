#!/usr/bin/env bash
# Generate a random admin panel password and its Argon2id hash (OWASP preset,
# same as `vaultwarden hash --preset owasp`, which needs an interactive TTY).
# Put the hash in Coolify as ADMIN_TOKEN with Interpolation set to Literal.
# Usage: scripts/admin-token.sh
set -euo pipefail

password=$(head -c 24 /dev/urandom | base64 | tr -d '/+=' | head -c 32)
salt=$(head -c 24 /dev/urandom | base64)

if command -v argon2 >/dev/null 2>&1; then
  hash=$(printf '%s' "$password" | argon2 "$salt" -e -id -k 19456 -t 2 -p 1)
elif command -v docker >/dev/null 2>&1; then
  hash=$(printf '%s' "$password" | docker run --rm -i alpine:3.22 \
    sh -c 'apk add -q --no-cache argon2 >/dev/null && argon2 "$0" -e -id -k 19456 -t 2 -p 1' "$salt")
else
  echo "Needs either the argon2 CLI or Docker." >&2
  exit 1
fi
[[ $hash == "\$argon2id\$"* ]] || { echo "Failed to generate the hash." >&2; exit 1; }

printf 'Admin password (log in to /admin with this, store it safely):\n  %s\n\n' "$password"
printf 'ADMIN_TOKEN (paste into Coolify, Interpolation: Literal):\n  %s\n' "$hash"
