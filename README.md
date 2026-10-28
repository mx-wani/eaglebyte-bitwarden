# EagleByte Bitwarden

Self-hosted password manager for EagleByte at **https://vault.mxwani.cloud**, deployed with [Coolify](https://coolify.io).

It runs [Vaultwarden](https://github.com/dani-garcia/vaultwarden), a lightweight server compatible with every official Bitwarden app (browser extensions, desktop, iOS, Android, CLI). Coolify's proxy issues the HTTPS certificate and routes the domain to the container.

```
Bitwarden apps ──HTTPS──▶ Coolify proxy (Let's Encrypt) ──▶ vaultwarden:80 ──▶ vaultwarden-data volume
```

## Deploy on Coolify

**Before you start:** the repo must be reachable from Coolify. Connect your GitHub account to Coolify through a GitHub App, or add a deploy key. Point an `A` record for `vault.mxwani.cloud` at the Coolify server.

1. **Generate the admin token** on any machine with Docker:

   ```bash
   scripts/admin-token.sh
   ```

   Store the password it prints. You'll paste the hash into Coolify in step 4.

2. **Create the resource.** In your Coolify project, choose **+ New** → **Private Repository (with GitHub App)**. Select `mx-wani/eaglebyte-bitwarden` on branch `main`. Set **Build Pack** to **Docker Compose** and **Docker Compose Location** to `/docker-compose.yml`.

3. **Set the domain.** Under **Domains**, give the `vaultwarden` service `https://vault.mxwani.cloud`. Vaultwarden listens on port 80, so no port suffix is needed.

4. **Set the environment variables.** Under **Environment Variables**, set `ADMIN_TOKEN` to the hash from step 1. Set its **Interpolation** to **Literal**, because the hash contains `$` characters. The other variables have working defaults (see [Settings](#settings)).

5. **Deploy.** When the deployment finishes, `https://vault.mxwani.cloud` shows the Bitwarden login page.

6. **Load data.** Either restore the old vault ([docs/MIGRATION.md](docs/MIGRATION.md)) or start fresh. Public sign-up is off, so a fresh start means inviting your email from `https://vault.mxwani.cloud/admin` → *Users*, then creating the account on the vault's sign-up page.

7. **Schedule backups.** See [docs/OPERATIONS.md](docs/OPERATIONS.md#backups).

## Settings

All settings are Coolify environment variables. Apply changes with **Restart**.

| Variable | Default | Purpose |
| --- | --- | --- |
| `ADMIN_TOKEN` | *(required)* | Argon2id hash for the `/admin` panel |
| `SIGNUPS_ALLOWED` | `false` | Open public registration |
| `INVITATIONS_ALLOWED` | `true` | Let admins and org owners invite users |
| `INVITATION_ORG_NAME` | `EagleByte Vault` | Name shown in invitation emails |
| `PUSH_ENABLED`, `PUSH_INSTALLATION_ID`, `PUSH_INSTALLATION_KEY` | off | Instant sync on mobile ([setup](docs/OPERATIONS.md#mobile-push-notifications)) |
| `TZ` | `UTC` | Timezone for logs |

Email needs a small change to `docker-compose.yml`; see [docs/OPERATIONS.md](docs/OPERATIONS.md#email).

## Upgrading

The image tag is pinned in `docker-compose.yml`. Check the [release notes](https://github.com/dani-garcia/vaultwarden/releases), bump the tag, then commit and push. Coolify redeploys on push when auto-deploy is on; otherwise click **Deploy**.

## Repository layout

| Path | Purpose |
| --- | --- |
| `docker-compose.yml` | The Vaultwarden service as Coolify deploys it |
| `scripts/admin-token.sh` | Generates the admin password and its Argon2id hash |
| `scripts/restore.sh` | Restores a backup into Coolify's Docker volume |
| `host/fail2ban/` | Bans IPs that keep failing user or admin logins |
| `host/logrotate/` | Rotation for Vaultwarden's log file |
| `docs/` | [Migration](docs/MIGRATION.md) and [operations](docs/OPERATIONS.md) guides |
