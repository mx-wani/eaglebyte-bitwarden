# EagleByte Bitwarden

Self-hosted password manager for EagleByte at **https://vault.mxwani.cloud**.

It runs [Vaultwarden](https://github.com/dani-garcia/vaultwarden), a lightweight server compatible with every official Bitwarden app (browser extensions, desktop, iOS, Android, CLI). [Caddy](https://caddyserver.com) sits in front and gets and renews the HTTPS certificate on its own.

```
Bitwarden apps ──HTTPS :443──▶ Caddy ──HTTP :80 (private network)──▶ Vaultwarden ──▶ ./data
                               └─ Let's Encrypt certificate for vault.mxwani.cloud
```

## Requirements

- A Linux server with a public IP and at least 1 GB of RAM
- Docker Engine with the compose plugin ([install guide](https://docs.docker.com/engine/install/))
- Ports **80** and **443** reachable from the internet and not used by another web server (nginx, Apache, aaPanel)
- DNS: an `A` record for `vault.mxwani.cloud` pointing at the server (and an `AAAA` record if it has IPv6)

## Deploy

The paths in `host/` assume the repo lives at `/opt/eaglebyte-bitwarden`. The repo is private, so the server needs a [deploy key](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys) or `gh auth login` to clone it.

```bash
sudo git clone git@github.com:mx-wani/eaglebyte-bitwarden.git /opt/eaglebyte-bitwarden
cd /opt/eaglebyte-bitwarden

sudo scripts/setup.sh        # creates .env, generates the admin password, checks DNS and ports
sudo docker compose up -d    # Caddy fetches the certificate on first start
```

`setup.sh` prints the admin panel password once. Store it somewhere safe.

**Moving from the old aaPanel deployment?** Restore its backup before the first `up`. See [docs/MIGRATION.md](docs/MIGRATION.md).

**Starting fresh?** Public sign-up is disabled. Open `https://vault.mxwani.cloud/admin`, invite your email under *Users*, then create the account on the vault's sign-up page.

## Everyday commands

Run them from `/opt/eaglebyte-bitwarden`.

| Task | Command |
| --- | --- |
| Status | `sudo docker compose ps` |
| Logs | `sudo docker compose logs -f vaultwarden` (or `caddy`) |
| Back up now | `sudo scripts/backup.sh` |
| Restore | `sudo scripts/restore.sh backups/vaultwarden-YYYYMMDD-HHMMSS.tar.gz` |
| Upgrade | bump `VW_VERSION` / `CADDY_VERSION` in `.env`, then `sudo scripts/update.sh` |
| Apply `.env` changes | `sudo docker compose up -d` |

## Repository layout

| Path | Purpose |
| --- | --- |
| `docker-compose.yml` | Vaultwarden and Caddy services |
| `caddy/Caddyfile` | HTTPS, security headers, reverse proxy, optional admin IP allowlist |
| `.env.example` | Every setting, documented; copied to `.env` (never committed) |
| `scripts/` | `setup`, `backup`, `restore` and `update` helpers |
| `host/systemd/` | Daily backup timer |
| `host/fail2ban/` | Bans IPs that keep failing user or admin logins |
| `host/logrotate/` | Rotation for `data/vaultwarden.log` |
| `docs/` | [Migration](docs/MIGRATION.md) and [operations](docs/OPERATIONS.md) guides |

`data/`, `backups/` and `.env` hold secrets and are git-ignored.
