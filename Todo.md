# Todo

Branch cleanup done (2026-08-22): deleted `llm-testing`, `single`, `brands`, `m6-dev-1`. Only `master` remains.

## Fixes (implemented in PR)

- [x] **1. Fix deploy workflow branch trigger.** `deploy.yml` now triggers on `master`. Updated `README.md` and `AGENTS.md` references.
- [x] **2. Fix `restore_prefix` / date-restore dead code.** Removed the dead conditional-restore step from `deploy.yml` (restore is handled by `restore.yml`); fixed README restore docs.
- [x] **3. Fix broken root-password rotation.** `rotate-secrets.yml` now SCPs `rotate_mysql_root_password.sh` and runs it over SSH (like the other steps). Documented `MYSQL_ROOT_PASSWORD_OLD` in `AGENTS.md`.
- [x] **4. Implement 14-backup retention.** `backup_mautic.sh` now prunes archives beyond the last 14.
- [x] **5. Reduce secret exposure.** Scripts pass MySQL credentials via `MYSQL_PWD` (`docker exec -e`), never `-p"..."`.
- [x] **6. Remove dead `COMPOSE_NETWORK`.** Removed from `.env`.
- [x] **7. Delete `requirements.md`.** Removed the file and its `.gitignore` entry.
- [x] **8. Make `recreate-dc.sh` actually recreate.** Now runs `docker compose up -d --force-recreate`.
- [x] **9. Single source of truth for `.mautic_env`.** Converted to `__TOKEN__` placeholders; `deploy.yml`/`rotate-secrets.yml` now `sed`-substitute the committed template instead of regenerating it.
- [x] **10. DRY the SSH/scp boilerplate.** Extracted `.github/actions/run-remote-script` composite action and adopted it in all backup/restore/rotate steps.
- [x] **11. Add CI verification.** Added `.github/workflows/ci.yml` running `shellcheck` + `docker compose config -q`.
