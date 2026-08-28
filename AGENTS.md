# AGENTS.md

Infra/deployment repo (Mautic on Docker Compose + Traefik). No app code, no build/lint/test pipeline. Deployment runs from GitHub Actions, which SSH into a Linode VPS and run the shell scripts there. Verify changes with `docker compose config` and `bash -n scripts/*.sh` / `shellcheck` only.

## Development workflow (PR convention)

Never commit or push directly to `master`. All changes go through a feature branch + PR:

1. `git checkout -b <short-descriptive-name>` (e.g. `fix/deploy-trigger`).
2. Make the change, then verify (`shellcheck scripts/*.sh setup-dc.sh`, `docker compose config`).
3. Commit with a short imperative message, push the branch, and open a PR against `master` (`gh pr create`).
4. Do not merge locally or push to `master`; let the PR be the review/merge point.

For multi-item changes (see `Todo.md`), group related fixes into one PR per concern where practical.

## Placeholder substitution (do NOT "fix" these)

`.env`, `.mautic_env`, and `setup-dc.sh` are committed templates containing placeholder tokens that are filled at deploy time, not locally:

- `.env` and `.mautic_env` use `__TOKEN__` style: `__MYSQL_PASSWORD__`, `__MYSQL_ROOT_PASSWORD__`, `__DOMAIN__`, `__PROJECT_NAME__`, `__DB_NAME__`, `__DB_USER__`.
- `setup-dc.sh` uses `{{TOKEN}}` style: `{{DOMAIN_NAME}}`, `{{EMAIL_ADDRESS}}`, `{{MAUTIC_PASSWORD}}`.

The workflows `sed`-replace these on the server. If you change a token, update BOTH the file and every workflow that does the `sed` replacement (`deploy.yml`, `rotate-secrets.yml`).

## Secrets vs variables (repo-level)

- GitHub **secrets**: `SSH_PRIVATE_KEY`, `MAUTIC_PASSWORD`, `MYSQL_PASSWORD`, `MYSQL_ROOT_PASSWORD`, `MYSQL_ROOT_PASSWORD_OLD` (only used by root-password rotation).
- GitHub **variables** (`vars.*`): `LINODE_IP`, `DOMAIN`, `EMAIL`, `DB_NAME`, `MYSQL_USER`, `ENABLE_BACKUP`, `MAUTIC_VERSION`, `COMPOSE_PROJECT_NAME`, `DEPLOY_DIR`.

`COMPOSE_PROJECT_NAME` and `DEPLOY_DIR` make this repo deploy one site; fork the repo (one per website) and change these two variables to deploy a second site onto the same VPS. There is no runtime "brand" input — do not reintroduce one. Secrets/vars live at repo level (no GitHub `environment:` blocks).

Don't confuse `DB_NAME`/`MYSQL_USER` (variables) with the password secrets. `.env`/`.mautic_env` are deleted from the server post-deploy (`cleanup_env` step), so they are templates, not real secrets — do not add them to `.gitignore`.

## Changing DB credentials (MySQL env-init trap)

MySQL initializes `MYSQL_USER` / `MYSQL_PASSWORD` / `MYSQL_DATABASE` **only on the first boot of an empty data volume** (the `*_mysql-data` volume). Editing these in GitHub after a site is live does NOT update the running DB — the next deploy will regenerate `.env`/`.mautic_env` with the new values, but MySQL still has the old ones, and `mautic_web` exits with `Access denied` (the `mautic_db` healthcheck can still show "Healthy" because `mysqladmin ping` doesn't strictly require a working auth).

To change the DB password on a live site, use the `rotate-secrets` workflow (runs `ALTER USER ... IDENTIFIED BY` via `rotate_db_password.sh`), not secret-editing + redeploy. To change the DB user or database name (or wipe), reset the DB volume and redeploy:

```bash
docker compose -p "$COMPOSE_PROJECT_NAME" down -v   # then re-run deploy
```

## Shared SSH/scp action

The workflows call the composite action `.github/actions/run-remote-script` (inputs: `ssh_key`, `host`, `script`, `env`) to SCP a script and run it over SSH. Add new remote-run steps by reusing this action, not by re-pasting the `scp`/`ssh` boilerplate. The `deploy` and `recreate` steps still use `easingthemes/ssh-deploy@main` (they deploy the whole tree via `SCRIPT_AFTER`).

## Project / volume / network model

- `COMPOSE_PROJECT_NAME` is the Compose project name and must be unique per site on a VPS (it drives container names, volume names, and network aliases). It flows into `.env` via the `__PROJECT_NAME__` token.
- Persistent Mautic data lives in three named volumes, each mounted at the real Mautic path and shared by web/worker/cron: `${COMPOSE_PROJECT_NAME}_mautic_config` (`/var/www/html/config`), `${COMPOSE_PROJECT_NAME}_mautic_media_files` (`/var/www/html/docroot/media/files`), `${COMPOSE_PROJECT_NAME}_mautic_media_images` (`/var/www/html/docroot/media/images`). The DB uses `${COMPOSE_PROJECT_NAME}_mysql-data`. Backup/restore scripts archive these three app volumes (not logs/cron).
- `.mautic_env` sets `MAUTIC_DB_HOST=mautic_db___PROJECT_NAME__` (substituted to `mautic_db_<project>`) to match the compose network alias `mautic_db_${COMPOSE_PROJECT_NAME}`. The alias MUST stay project-scoped because `mysql_private` is shared across sites on one VPS. Preserve this.
- `traefik_web` and `mysql_private` are external networks; `setup-dc.sh` creates `mysql_private` (`-d overlay --attachable`) if missing but expects `traefik_web` to already exist.

## Deploy dir & branch

- The server deploy dir is NOT hardcoded: it comes from the `DEPLOY_DIR` repo variable, threaded through `setup-dc.sh` (`cd "${DEPLOY_DIR:?}"`), the scripts (`DEPLOY_ROOT="${DEPLOY_DIR:?}"`), and the workflows' `TARGET`. Each site repo sets its own `DEPLOY_DIR`.
- Deploy workflow triggers on push to branch `master` and on `workflow_dispatch`.

## Scripts

- `scripts/backup_mautic.sh` / `restore_mautic.sh` require env vars `COMPOSE_PROJECT_NAME`, `DEPLOY_DIR`, `DB_NAME`, `MYSQL_ROOT_PASSWORD` and locate the MySQL container by compose labels (`com.docker.compose.service=mautic_db`, `com.docker.compose.project=$COMPOSE_PROJECT_NAME`).
- `backup_mautic.sh` skips gracefully (exit 0) when the MySQL container doesn't exist yet (and skips any individual app volume that is missing), so the pre-deploy backup on a fresh site doesn't fail.
- `restore_mautic.sh` restores only from `$DEPLOY_DIR/backups/current/` (no date/prefix argument).
- `backup_mautic.sh` archives the prior backup to `archive/<timestamp>` and prunes archives beyond the last 14.
- `rotate_db_password.sh` / `rotate_mysql_root_password.sh` take their inputs from env vars, not args. Scripts pass MySQL credentials via `MYSQL_PWD` (`docker exec -e`), never `-p`.
- CI (`.github/workflows/ci.yml`) runs `shellcheck scripts/*.sh setup-dc.sh` and `docker compose config -q` on push to `master` and PRs.

## Known doc drift

README overstates some implemented behavior; trust the scripts/workflows over prose. For example, README's restore "actions" list "Fix permissions" and "Clear caches", but `restore_mautic.sh` only restores the filesystem volume and re-imports the database.
