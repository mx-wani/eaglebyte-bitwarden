#!/usr/bin/env bash
# First-time setup: create .env, generate the admin token, and check that DNS
# and ports are ready for Caddy to get a certificate.
# Usage: scripts/setup.sh
# shellcheck source=scripts/_common.sh
source "$(dirname "$0")/_common.sh"

command -v docker >/dev/null || die "Docker is not installed (https://docs.docker.com/engine/install/)."
docker compose version >/dev/null 2>&1 || die "The docker compose plugin is missing."

if [[ ! -f .env ]]; then
  cp .env.example .env
  log "Created .env from .env.example"
fi
chmod 600 .env

# --- Domain and ACME email ---------------------------------------------------
domain=$(env_get DOMAIN)
read -rp "Vault URL [$domain]: " answer
domain=${answer:-$domain}
[[ $domain == https://* ]] || domain="https://$domain"
env_set DOMAIN "$domain"

email=$(env_get ACME_EMAIL)
if [[ -z $email || $email == you@example.com ]]; then
  read -rp "Email for Let's Encrypt notices: " email
  [[ $email == *@* ]] || die "That doesn't look like an email address."
  env_set ACME_EMAIL "$email"
fi

# --- Admin token -------------------------------------------------------------
if [[ -z $(env_get ADMIN_TOKEN) ]]; then
  log "Generating admin panel password"
  password=$(head -c 24 /dev/urandom | base64 | tr -d '/+=' | head -c 32)
  salt=$(head -c 24 /dev/urandom | base64)
  # Argon2id with the OWASP preset, same as `vaultwarden hash --preset owasp`.
  if command -v argon2 >/dev/null 2>&1; then
    hash=$(printf '%s' "$password" | argon2 "$salt" -e -id -k 19456 -t 2 -p 1)
  else
    hash=$(printf '%s' "$password" | docker run --rm -i alpine:3.22 \
      sh -c 'apk add -q --no-cache argon2 >/dev/null && argon2 "$0" -e -id -k 19456 -t 2 -p 1' "$salt")
  fi
  [[ $hash == "\$argon2id\$"* ]] || die "Failed to generate the admin token hash."
  env_set ADMIN_TOKEN "'$hash'"
  printf '\n  Admin panel: %s/admin\n  Password:    \033[1m%s\033[0m\n\n' "$domain" "$password"
  printf '  Save this password now (it is only stored as a hash in .env).\n\n'
fi

mkdir -p data "$(env_get BACKUP_DIR ./backups)"

# --- Pre-flight checks -------------------------------------------------------
host=${domain#https://}; host=${host%%/*}
dns_ip=$(getent ahostsv4 "$host" 2>/dev/null | awk 'NR==1 {print $1}' || true)
public_ip=$(curl -fsS4 --max-time 5 https://api.ipify.org 2>/dev/null || true)
if [[ -z $dns_ip ]]; then
  warn "$host does not resolve yet. Create an A record pointing to ${public_ip:-this server}."
elif [[ -n $public_ip && $dns_ip != "$public_ip" ]]; then
  warn "$host resolves to $dns_ip but this server's public IP is $public_ip."
else
  log "DNS OK: $host -> $dns_ip"
fi

if command -v ss >/dev/null 2>&1; then
  for port in 80 443; do
    if ss -ltnH "sport = :$port" | grep -q . && ! docker ps --format '{{.Names}}' | grep -qx caddy; then
      warn "Port $port is already in use. Caddy needs 80 and 443 (stop nginx/apache/aaPanel's web server)."
    fi
  done
fi

log "Setup complete. Start the stack with: docker compose up -d"
