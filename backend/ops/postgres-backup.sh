#!/bin/sh
set -eu
umask 077

backup_dir=${BACKUP_DIR:-/backups}
interval=${BACKUP_INTERVAL_SECONDS:-86400}
retention=${BACKUP_RETENTION_DAYS:-7}
case "$interval:$retention" in *[!0-9:]*|:*|*:) echo "Invalid backup interval or retention" >&2; exit 1;; esac
if [ "$interval" -lt 60 ] || [ "$retention" -lt 1 ]; then
  echo "Backup interval must be >= 60 seconds and retention >= 1 day" >&2
  exit 1
fi
mkdir -p "$backup_dir"
chmod 700 "$backup_dir"

backup_once() {
  temporary=$(mktemp "$backup_dir/.craftai-pg-XXXXXX")
  trap 'rm -f "$temporary"' EXIT HUP INT TERM
  pg_dump --format=custom --no-owner --no-acl --file="$temporary"
  # A readable archive is required before publishing it as a successful backup.
  pg_restore --list "$temporary" >/dev/null
  suffix=${temporary##*-}
  destination="$backup_dir/craftai-$(date -u +%Y%m%dT%H%M%SZ)-$suffix.dump"
  mv "$temporary" "$destination"
  touch "$backup_dir/.last_success"
  trap - EXIT HUP INT TERM
  find "$backup_dir" -type f -name 'craftai-*.dump' -mtime +"$retention" -exec rm -f {} \;
  echo "PostgreSQL backup completed."
}

if [ "${1:-}" = "--once" ]; then
  backup_once
else
  while :; do
    backup_once
    sleep "$interval"
  done
fi
