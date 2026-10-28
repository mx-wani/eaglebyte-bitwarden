# Operations

All commands run from `/opt/eaglebyte-bitwarden`. After any `.env` change, apply it with `sudo docker compose up -d`.

## Admin panel

`https://vault.mxwani.cloud/admin`, using the password `setup.sh` printed.

- **Lost the password:** set `ADMIN_TOKEN=''` in `.env`, run `sudo scripts/setup.sh` to generate a new one, then `sudo docker compose up -d`.
- **Settings saved in the panel win.** The panel writes them to `data/config.json`, which overrides `.env`. To go back to `.env`, click *Reset defaults* in the panel or delete `data/config.json`.
- **Restrict by IP:** uncomment the `@admin_blocked` block in `caddy/Caddyfile`, then `sudo docker compose restart caddy`.

## Users

Sign-up is closed (`SIGNUPS_ALLOWED=false`). Invite people from the admin panel. Without SMTP no email goes out, so tell them to register at the vault with the invited address. With SMTP configured they get an invitation link.

## Email

Uncomment the `SMTP_*` block in `.env`. Email enables invitation links, email 2FA, new-device alerts and email verification. Test it from the admin panel (*SMTP Email Settings* → *Send test email*).

## Mobile push notifications

Without push, the mobile apps only pick up changes when they sync. To enable instant sync:

1. Request an installation ID and key at <https://bitwarden.com/host/>.
2. Set `PUSH_ENABLED=true`, `PUSH_INSTALLATION_ID` and `PUSH_INSTALLATION_KEY` in `.env`. If you chose the EU region, also set the two `PUSH_*_URI` lines.
3. Log out and back in on each phone.

## Backups

`scripts/backup.sh` writes `backups/vaultwarden-<timestamp>.tar.gz`. It contains a consistent database snapshot taken by Vaultwarden itself (safe while running), `rsa_key.pem`, `config.json`, attachments and sends. Archives older than `BACKUP_KEEP_DAYS` (default 30) are deleted.

Treat archives as secrets. Vault items are encrypted with users' master passwords, but `rsa_key.pem` signs login sessions.

**Daily schedule (03:30):**

```bash
sudo cp host/systemd/vaultwarden-backup.* /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now vaultwarden-backup.timer
systemctl list-timers vaultwarden-backup.timer
```

**Off-site copy:** install [rclone](https://rclone.org/install/), run `sudo rclone config` to add a remote (Backblaze B2, S3, Google Drive…), then set `BACKUP_RCLONE_REMOTE=remote:bucket/path` in `.env`. Each backup is uploaded after it is written. Remote retention is managed on the remote side.

**Restore:** `sudo scripts/restore.sh <archive>`. It validates the database, stops Vaultwarden and moves the current `data/` to `data.pre-restore-<timestamp>`. Start the stack again afterwards. Test a restore now and then, ideally on a spare machine.

## Upgrades

1. Read the [Vaultwarden release notes](https://github.com/dani-garcia/vaultwarden/releases) for the new version.
2. Set `VW_VERSION` (and `CADDY_VERSION`, see [Caddy releases](https://github.com/caddyserver/caddy/releases)) in `.env`, and in `.env.example` so the repo stays current.
3. Run `sudo scripts/update.sh`. It backs up, pulls, and restarts.

To roll back, restore the pre-upgrade version in `.env` and restore the backup taken by `update.sh`. Database migrations only go forward.

## Logs

- `sudo docker compose logs -f vaultwarden` / `caddy`
- `data/vaultwarden.log`, the file fail2ban reads. Rotate it weekly:

```bash
sudo cp host/logrotate/vaultwarden /etc/logrotate.d/vaultwarden
```

## Brute-force protection (fail2ban)

```bash
sudo apt install fail2ban
sudo cp host/fail2ban/filter.d/*.local /etc/fail2ban/filter.d/
sudo cp host/fail2ban/jail.d/vaultwarden.local /etc/fail2ban/jail.d/
sudo systemctl restart fail2ban
sudo fail2ban-client status vaultwarden
```

Five failed vault logins in 15 minutes ban the IP for 4 hours. Three failed admin logins ban it for 24 hours. Bans go in the `DOCKER-USER` iptables chain, because traffic to Caddy is forwarded into a container and skips the host's `INPUT` rules.

## Firewall

Docker publishes ports past `ufw`, so ports 80 and 443 stay reachable whatever `ufw` says. Keep everything else closed, and leave SSH open:

```bash
sudo ufw allow OpenSSH
sudo ufw allow 80,443/tcp
sudo ufw allow 443/udp
sudo ufw enable
```

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Browser shows a certificate error | `sudo docker compose logs caddy`. The DNS record must point here, and ports 80 and 443 must be reachable from outside. Let's Encrypt rate-limits repeated failures, so fix DNS before retrying. |
| `caddy` won't start: "address already in use" | Another web server holds 80/443: `sudo ss -ltnp 'sport = :443'` |
| Admin page says it is disabled | `ADMIN_TOKEN` is empty in `.env`. Run `sudo scripts/setup.sh`. |
| Apps don't sync instantly | Configure push notifications (above). The web vault and desktop apps use WebSockets, which work out of the box. |
| `scripts/*.sh`: "not writable … Re-run with sudo" | `data/` is owned by root because the container runs as root. Use `sudo`. |
