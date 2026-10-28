# Migrating from the aaPanel deployment

The old instance ran `vaultwarden/server:latest` through aaPanel's Docker manager, with its data in:

```
/www/dk_project/dk_app/bitwarden/eaglebyte_bitwarden/data
```

The data format is the same, so the Coolify deployment picks up every account, vault item, organisation and 2FA setting.

## 1. Take a fresh backup (if the old server is still up)

`bitwarden_FULL_20260614.tar.gz` holds data up to **6 June 2026**. Anything saved after that only exists on the old server. To capture it, stop the container in aaPanel (or `docker stop` it) so the database is quiet, then:

```bash
sudo tar -czf ~/bitwarden_FULL_$(date +%Y%m%d).tar.gz \
  /www/dk_project/dk_app/bitwarden/eaglebyte_bitwarden
```

Keep the old container stopped from now on. Two servers taking writes would split your data.

## 2. Deploy once in Coolify, then stop it

Follow the [README](../README.md#deploy-on-coolify) through step 5. The first deploy creates the Docker volume and an empty vault. Then click **Stop** on the resource in Coolify.

## 3. Restore on the Coolify server

Copy the archive and the restore script to the server, then run the script:

```bash
scp bitwarden_FULL_20260614.tar.gz scripts/restore.sh root@<coolify-server>:~/
ssh root@<coolify-server>
./restore.sh bitwarden_FULL_20260614.tar.gz
```

The script:

1. Finds the volume Coolify created (`<resource-uuid>_vaultwarden-data`). If several exist, pass the volume name as a second argument.
2. Finds `db.sqlite3` inside the aaPanel folder structure.
3. Folds the SQLite write-ahead log (`db.sqlite3-wal`) into the database. **This matters for the June backup:** its WAL holds the last two vault items and every change from 16 May to 6 June. Copying `db.sqlite3` on its own would silently lose them.
4. Checks database integrity.
5. Saves the volume's current contents to `pre-restore-*.tar.gz`, then replaces them.

You should see `Database OK: 8 user(s), 116 vault item(s)`. Then click **Start** in Coolify.

## 4. Point the apps at the new address

In every Bitwarden app, on the login screen choose **Self-hosted** and set the server URL to `https://vault.mxwani.cloud`. Then log in with the same email and master password as before. Vault data is encrypted with each user's master password, so the new domain doesn't affect it.

## Gotchas

- **Security keys and passkeys are tied to the domain.** If the old instance used a different domain, WebAuthn 2FA and passkey logins registered there won't work on `vault.mxwani.cloud`. Users can sign in with a recovery code or another 2FA method. An admin can also remove a user's 2FA in `/admin` → *Users*. Authenticator-app (TOTP) codes keep working.
- **The old image tag was `latest`.** This repo pins an exact version, so the database migrates forward once on first start. Keep the original archive until you have confirmed everything works.
