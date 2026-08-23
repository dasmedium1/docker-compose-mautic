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

- `.env` and `.mautic_env` use `__TOKEN__` style: `__MYSQL_PASSWORD__`, `__MYSQL_ROOT_PASSWORD__`, `__DOMAIN__`, `__BRAND_NAME__`, `__DB_NAME__`, `__DB_USER__`.
- `setup-dc.sh` uses `{{TOKEN}}` style: `{{DOMAIN_NAME}}`, `{{EMAIL_ADDRESS}}`, `{{MAUTIC_PASSWORD}}`.

The workflows `sed`-replace these on the server. If you change a token, update BOTH the file and every workflow that does the `sed` replacement (`deploy.yml`, `rotate-secrets.yml`).

## Secrets vs variables

- GitHub **secrets**: `SSH_PRIVATE_KEY`, `MAUTIC_PASSWORD`, `MYSQL_PASSWORD`, `MYSQL_ROOT_PASSWORD`, `MYSQL_ROOT_PASSWORD_OLD` (only used by root-password rotation).
- GitHub **variables** (`vars.*`): `LINODE_IP`, `DOMAIN`, `EMAIL`, `DB_NAME`, `MYSQL_USER`, `ENABLE_BACKUP`, `MAUTIC_VERSION`.

Don't confuse `DB_NAME`/`MYSQL_USER` (variables) with the password secrets. `.env`/`.mautic_env` are deleted from the server post-deploy (`cleanup_env` step), so they are templates, not real secrets — do not add them to `.gitignore`.

## Shared SSH/scp action

The workflows call the composite action `.github/actions/run-remote-script` (inputs: `ssh_key`, `host`, `script`, `env`) to SCP a script and run it over SSH. Add new remote-run steps by reusing this action, not by re-pasting the `scp`/`ssh` boilerplate. The `deploy` and `recreate` steps still use `easingthemes/ssh-deploy@main` (they deploy the whole tree via `SCRIPT_AFTER`).

## Brand / environment model

- Each deployment is a "brand" = the Compose project name (`COMPOSE_PROJECT_NAME`). GitHub Actions `environment: mautic-<brand>` supplies the secrets/vars per brand.
- Docker volume names derive from the project name: `${BRAND_NAME}_mautic` (backup/restore scripts compute this). `mysql-data` is a named volume in compose, NOT project-prefixed.
- `.mautic_env` sets `MAUTIC_DB_HOST=mautic_db___BRAND_NAME__` (substituted to `mautic_db_<brand>`) to match the compose network alias, not the service name `mautic_db`. Preserve this.

## Hardcoded paths & branch

- Server deploy dir is hardcoded `/home/angelantonio/backup/root/mautic` in `setup-dc.sh` and all scripts/workflows. Renaming/moving the repo requires updating these.
- Deploy workflow triggers on push to branch `master` and on `workflow_dispatch`.
- `traefik_web` and `mysql_private` are external networks; `setup-dc.sh` creates `mysql_private` (`-d overlay --attachable`) if missing but expects `traefik_web` to already exist.

## Scripts

- `scripts/backup_mautic.sh` / `restore_mautic.sh` require env vars `BRAND_NAME`, `DB_NAME`, `MYSQL_ROOT_PASSWORD` and locate the MySQL container by compose labels (`com.docker.compose.service=mautic_db`, `com.docker.compose.project=$BRAND_NAME`).
- `restore_mautic.sh` restores only from `backups/<brand>/current/` (no date/prefix argument).
- `backup_mautic.sh` archives the prior backup to `archive/<timestamp>` and prunes archives beyond the last 14.
- `rotate_db_password.sh` / `rotate_mysql_root_password.sh` take their inputs from env vars, not args. Scripts pass MySQL credentials via `MYSQL_PWD` (`docker exec -e`), never `-p`.
- CI (`.github/workflows/ci.yml`) runs `shellcheck scripts/*.sh setup-dc.sh` and `docker compose config -q` on push to `master` and PRs.

## Known doc drift

README overstates some implemented behavior; trust the scripts/workflows over prose. For example, README's restore "actions" list "Fix permissions" and "Clear caches", but `restore_mautic.sh` only restores the filesystem volume and re-imports the database.
