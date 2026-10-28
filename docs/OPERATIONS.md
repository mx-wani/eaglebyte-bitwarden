# Operations

Coolify manages the deployment. Settings are environment variables on the resource. Apply variable changes with **Restart**, and apply changes to `docker-compose.yml` with a push or **Deploy**.

## Admin panel

`https://vault.mxwani.cloud/admin`, using the password from `scripts/admin-token.sh`.

- **Lost the password:** run `scripts/admin-token.sh` again, replace `ADMIN_TOKEN` in Coolify (Interpolation: Literal), then **Restart**.
- **"plain text ADMIN_TOKEN" notice in the logs:** the hash was saved without Literal interpolation and Coolify mangled the `$` parts. Re-enter it with Literal set.
- **Settings saved in the panel win.** The panel writes them to `config.json` in the volume, which overrides Coolify's variables. To go back to the variables, click *Reset defaults* in the panel.

## Users

Sign-up is closed (`SIGNUPS_ALLOWED=false`). Invite people from the admin panel. Without email configured, no invitation is sent, so tell them to register at the vault with the invited address. With email configured, they get an invitation link.

## Email

Email enables invitation links, email 2FA, new-device alerts and email verification.

1. Uncomment the `SMTP_*` lines in `docker-compose.yml`, then commit and push. Vaultwarden refuses to start when `SMTP_HOST` and `SMTP_FROM` are set but empty, so these lines stay commented out until you have real values.
2. Coolify shows the new variables. `SMTP_HOST`, `SMTP_FROM`, `SMTP_USERNAME` and `SMTP_PASSWORD` are required. Port 587 with `starttls` is the default.
3. Deploy, then test from the admin panel (*SMTP Email Settings* → *Send test email*).

## Mobile push notifications

Without push, the mobile apps only pick up changes when they sync. To enable instant sync:

1. Request an installation ID and key at <https://bitwarden.com/host/>.
2. In Coolify, set `PUSH_ENABLED=true`, `PUSH_INSTALLATION_ID` and `PUSH_INSTALLATION_KEY`. If you chose the EU region, also set `PUSH_RELAY_URI=https://api.bitwarden.eu` and `PUSH_IDENTITY_URI=https://identity.bitwarden.eu`.
3. **Restart**, then log out and back in on each phone.

## Backups

Use Coolify's storage backups on the `vaultwarden-data` volume. The volume holds everything: the database, `rsa_key.pem` (which signs login sessions), attachments, sends and `config.json`.

1. In Coolify's S3 storage settings, add an S3-compatible destination (Backblaze B2, Cloudflare R2, AWS S3…) and validate it. Without it, backups live only on the same server.
2. Open the resource → **Backups** → **Storage backups** → **Add**. Pick `vaultwarden-data` and set the frequency to `daily`.
3. In the schedule:
   - Set **Archive behavior** to **Stop containers during archive**. SQLite files copied mid-write can be corrupt. The volume is a few MB, so the vault is down for seconds, and the apps keep working offline from their cache in the meantime.
   - Enable **S3**.
   - Keep 7 to 30 backups.
4. Click **Back up now** and confirm the execution shows **Success** for both locations.

**Restore:** download an archive from **Executions** (or from S3), stop the resource, run `./restore.sh <archive>` on the server as in [MIGRATION.md](MIGRATION.md#3-restore-on-the-coolify-server), then start the resource. Coolify has no restore button. Test a restore on a spare machine now and then, because a backup you haven't restored isn't proven.

Treat archives as secrets. Vault items are encrypted with users' master passwords, but `rsa_key.pem` is not.

## Upgrades

1. Read the [Vaultwarden release notes](https://github.com/dani-garcia/vaultwarden/releases).
2. Run **Back up now** on the storage backup.
3. Bump the `image:` tag in `docker-compose.yml`, then commit and push (or click **Deploy**).

Database migrations only go forward. To roll back, revert the tag and restore the pre-upgrade backup.

## Logs

The **Logs** tab in Coolify shows the container output. The same lines go to `vaultwarden.log` inside the volume, which fail2ban reads. Rotate it weekly on the server:

```bash
sudo cp host/logrotate/vaultwarden /etc/logrotate.d/vaultwarden
```

## Brute-force protection (fail2ban)

On the Coolify server, after the first deploy has created the log file:

```bash
sudo apt install fail2ban
sudo cp host/fail2ban/filter.d/*.local /etc/fail2ban/filter.d/
sudo cp host/fail2ban/jail.d/vaultwarden.local /etc/fail2ban/jail.d/
sudo systemctl restart fail2ban
sudo fail2ban-client status vaultwarden
```

Five failed vault logins in 15 minutes ban the IP for 4 hours. Three failed admin logins ban it for 24 hours. Bans go in the `DOCKER-USER` iptables chain, so a banned IP also loses access to the other apps on this Coolify server.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Deploy blocked: `ADMIN_TOKEN` required | Set it under Environment Variables (step 4 of the README). |
| Certificate error in the browser | The DNS record must point at the Coolify server, and ports 80/443 must be reachable. Check **Servers** → *your server* → **Proxy** logs. |
| Container exits: "Both `SMTP_HOST` and `SMTP_FROM` need to be set" | The SMTP lines are uncommented but have empty values. Fill them in or comment them out again. |
| `restore.sh`: "Found 2 vaultwarden-data volumes" | Another resource uses the same volume name. Pass the right one: `./restore.sh <archive> <uuid>_vaultwarden-data`. The UUID is in the resource's URL in Coolify. |
| Apps don't sync instantly | Set up push notifications (above). The web vault and desktop apps use WebSockets, which work through Coolify's proxy. |
