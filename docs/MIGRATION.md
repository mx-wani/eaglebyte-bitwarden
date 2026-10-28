# Migrating from the aaPanel deployment

The old instance ran `vaultwarden/server:latest` through aaPanel's Docker manager, with its data in:

```
/www/dk_project/dk_app/bitwarden/eaglebyte_bitwarden/data
```

The data format is the same, so the new stack picks up every account, vault item, organisation and 2FA setting.

## 1. Take a fresh backup (if the old server is still up)

`bitwarden_FULL_20260614.tar.gz` holds data up to **6 June 2026**. Anything saved after that only exists on the old server. To capture it, stop the container in aaPanel (or `docker stop` it) so the database is quiet, then:

```bash
sudo tar -czf ~/bitwarden_FULL_$(date +%Y%m%d).tar.gz \
  /www/dk_project/dk_app/bitwarden/eaglebyte_bitwarden
```

Keep the old container stopped from now on. Two servers taking writes would split your data.

## 2. Copy it to the new server

```bash
scp bitwarden_FULL_*.tar.gz user@new-server:/tmp/
```

## 3. Deploy and restore

```bash
cd /opt/eaglebyte-bitwarden
sudo scripts/setup.sh
sudo scripts/restore.sh /tmp/bitwarden_FULL_20260614.tar.gz
sudo docker compose up -d
```

`restore.sh` finds `db.sqlite3` inside the aaPanel folder structure and checks the database before replacing anything. It also folds the SQLite write-ahead log (`db.sqlite3-wal`) into the database. **This matters for the June backup:** its WAL holds the last two vault items and every change from 16 May to 6 June. Copying `db.sqlite3` on its own would silently lose them.

When it finishes you should see something like `Database OK: 8 user(s), 116 vault item(s)`.

## 4. Point the apps at the new address

In every Bitwarden app, on the login screen choose **Self-hosted** and set the server URL to `https://vault.mxwani.cloud`. Then log in with the same email and master password as before. Vault data is encrypted with each user's master password, so the new domain doesn't affect it.

## Gotchas

- **Same server as aaPanel?** aaPanel's nginx already listens on ports 80 and 443, so Caddy can't start. Either move the other aaPanel sites off this server and stop its web server, or run Vaultwarden behind aaPanel's nginx instead of Caddy: drop the `caddy` service and publish `127.0.0.1:<port>:80` on `vaultwarden`.
- **Security keys and passkeys are tied to the domain.** If the old instance used a different domain, WebAuthn 2FA and passkey logins registered there won't work on `vault.mxwani.cloud`. Users can sign in with a recovery code or another 2FA method. An admin can also remove a user's 2FA in `/admin` → *Users*. Authenticator-app (TOTP) codes keep working.
- **The old image tag was `latest`.** This repo pins exact versions, so the database migrates forward once on first start. Keep the original archive until you have confirmed everything works.
