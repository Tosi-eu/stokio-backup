#!/bin/bash
set -e

BACKUP_DIR="/backups"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_SQL="$BACKUP_DIR/backup_$TIMESTAMP.sql"
BACKUP_FILE="$BACKUP_DIR/backup_$TIMESTAMP.sql.gz"

echo "[Backup] Starting backup at $TIMESTAMP"

mkdir -p "$BACKUP_DIR"

export PGPASSWORD="${POSTGRES_PASSWORD:-$DB_PASSWORD}"

TOTAL_ROWS=$(psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -A -v ON_ERROR_STOP=1 -c \
  "ANALYZE; SELECT COALESCE(SUM(n_live_tup), 0)::bigint FROM pg_stat_user_tables WHERE schemaname = 'public';" 2>/dev/null | tail -1 || echo "0")
if [ -z "$TOTAL_ROWS" ] || [ "${TOTAL_ROWS:-0}" -le 0 ]; then
  echo "[Backup] Database appears empty (no rows in public tables), skipping backup"
  unset PGPASSWORD
  exit 0
fi

pg_dump -Fp --data-only  \
  -h "$POSTGRES_HOST" \
  -U "$POSTGRES_USER" \
  "$POSTGRES_DB" \
  -f "$BACKUP_SQL"

gzip -f "$BACKUP_SQL"

unset PGPASSWORD

echo "[Backup] Backup created: $BACKUP_FILE"

# R2 upload: production, or explicit BACKUP_UPLOAD_R2=1 (dedicated backup container in compose)
UPLOAD_R2=0
if [ "${NODE_ENV:-}" = "production" ] || [ "${BACKUP_UPLOAD_R2:-0}" = "1" ]; then
  UPLOAD_R2=1
fi

if [ "$UPLOAD_R2" = "1" ] && [ -n "${R2_ACCOUNT_ID}" ] && [ -n "${R2_ACCESS_KEY_ID}" ] && [ -n "${R2_SECRET_ACCESS_KEY}" ] && [ -n "${R2_BUCKET_NAME}" ]; then
  if echo "$R2_BUCKET_NAME" | grep -q '://'; then
    echo "[Backup] R2 skipped: R2_BUCKET_NAME must be the bucket name only (e.g. abrigo-backup), not the S3 API URL. Use R2_ACCOUNT_ID for the endpoint."
  else
  echo "[Backup] Uploading to R2 bucket: $R2_BUCKET_NAME"
  R2_ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
  export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
  export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
  export AWS_DEFAULT_REGION="${R2_REGION:-auto}"

  if aws s3 cp "$BACKUP_FILE" "s3://${R2_BUCKET_NAME}/backups/$(basename "$BACKUP_FILE")" --endpoint-url "$R2_ENDPOINT"; then
    echo "[Backup] R2 upload OK"
  else
    echo "[Backup] R2 upload failed (non-fatal)"
  fi
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION
  fi
else
  if [ "$UPLOAD_R2" != "1" ]; then
    echo "[Backup] R2 skipped (set NODE_ENV=production or BACKUP_UPLOAD_R2=1 with R2 credentials to upload)"
  else
    echo "[Backup] R2 skipped (missing R2 credentials)"
  fi
fi

KEEP_LOCAL="${R2_RETENTION_COUNT:-30}"
if [ "${KEEP_LOCAL}" -gt 0 ] 2>/dev/null; then
  OLD=$(ls -1t "$BACKUP_DIR"/backup_*.sql.gz 2>/dev/null | tail -n +"$((KEEP_LOCAL + 1))" || true)
  if [ -n "$OLD" ]; then
    echo "$OLD" | while read -r f; do
      [ -n "$f" ] && rm -f "$f" && echo "[Backup] Removed old local backup: $f"
    done
  fi
  echo "[Backup] Local retention: keeping up to ${KEEP_LOCAL} newest backup_*.sql.gz"
else
  echo "[Backup] Local retention disabled (R2_RETENTION_COUNT<=0)"
fi

if [ -n "${POSTGRES_HOST}" ] && [ -n "${POSTGRES_DB}" ] && [ -n "${POSTGRES_USER}" ]; then
  export PGPASSWORD="${POSTGRES_PASSWORD:-$DB_PASSWORD}"
  HAS_TABLE=$(psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -A -v ON_ERROR_STOP=1 -c \
    "SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'system_config';" 2>/dev/null || echo "")
  if [ "$HAS_TABLE" = "1" ]; then
    LAST_BACKUP_AT=$(date -Iseconds)
    if psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -t -c \
      "INSERT INTO system_config (key, value, created_at, updated_at) VALUES ('last_backup_at', '$LAST_BACKUP_AT', NOW(), NOW()) ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW();" 2>/dev/null; then
      echo "[Backup] system_config last_backup_at updated: $LAST_BACKUP_AT"
    fi
  fi
  unset PGPASSWORD
fi