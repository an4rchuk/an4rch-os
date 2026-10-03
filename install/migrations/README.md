# Migrations

Scripts here run once per machine, in name order, after `lumen-update` pulls a
new version (see `install/migrate.sh`). Name them by date, e.g.
`2026-11-02-enable-foo.sh`. They must be idempotent and must not overwrite
user-edited files without a backup. A fresh install marks every existing
migration as done.
