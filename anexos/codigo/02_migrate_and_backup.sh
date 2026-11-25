#!/usr/bin/env bash
# Migracion MySQL 5.7 -> PostgreSQL 16 con pgloader + SQL declarativo,
# respaldo cifrado y prueba de restauracion.
# Salida: evidence/02_ejecucion_migracion.txt
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

mkdir -p "$EVIDENCE_DIR" "$BACKUP_DIR"
OUT="$EVIDENCE_DIR/02_ejecucion_migracion.txt"
exec > >(tee "$OUT") 2>&1

TS="$(date +%Y%m%d_%H%M%S)"
TMP_DUMP=""
RESTORE_DB="coop_horizonte_restore"
STG_SCHEMA="stg"
SQL_DIR=/app/src/migration/sql
LOAD_FILE=/tmp/mysql_to_stage.load
WORK_DIR=/tmp/pgloader-work
MIGRATED=0

cleanup() {
  rc=$?
  if [ -n "$TMP_DUMP" ] && [ -f "$TMP_DUMP" ]; then
    rm -f "$TMP_DUMP"
  fi
  psql_admin -c "DROP DATABASE IF EXISTS $RESTORE_DB;" >/dev/null 2>&1 || true
  compose exec -T migrador bash -lc "rm -f $LOAD_FILE" >/dev/null 2>&1 || true
  if [ "$MIGRATED" -eq 1 ]; then
    compose exec -T migrador bash -lc "rm -rf $WORK_DIR" >/dev/null 2>&1 || true
  else
    echo ""
    echo "NOTA: el schema $STG_SCHEMA se conserva para diagnostico."
    echo "      public no fue modificado si la falla ocurrio antes del COMMIT."
    echo "      Rechazos y archivos temporales de pgloader: $WORK_DIR"
  fi
  exit "$rc"
}
trap cleanup EXIT

require_var() {
  if [ -z "${!1:-}" ]; then
    echo "ERROR: variable $1 no definida en .env" >&2
    exit 1
  fi
}

echo "============================================================"
echo "EJECUCION DE LA MIGRACION Y RESPALDO CIFRADO"
echo "Cooperativa de Ahorro y Credito Horizonte PyME S.R.L."
echo "Herramienta de carga: pgloader + SQL declarativo"
echo "Generado: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "============================================================"
echo ""

for v in MYSQL_ROOT_PASSWORD MYSQL_APP_PASSWORD ADMIN_DBA_PASSWORD \
         MIGRATION_LOADER_PASSWORD BACKUP_PASSPHRASE; do
  require_var "$v"
done

log "Esperando servicios ..."
wait_healthy db-origen
wait_healthy db-destino
wait_running migrador

echo "== Herramientas =="
compose exec -T migrador pgloader --version
compose exec -T migrador psql --version
echo "Zona horaria del destino: $(psql_value 'SHOW timezone;')"
echo ""

echo "== Conteos en el origen antes de migrar =="
printf '%-24s %8s\n' "Tabla" "Filas"
printf '%-24s %8s\n' "------------------------" "--------"
for tabla in "${TABLES[@]}"; do
  printf '%-24s %8s\n' "$tabla" "$(count_mysql "$tabla")"
done
echo ""

echo "== Congelamiento de escrituras en el origen =="
echo "pgloader lee cada tabla con un SELECT independiente: no ofrece un snapshot"
echo "consistente entre tablas. La consistencia la garantiza el congelamiento de"
echo "escrituras durante esta ventana y el respaldo previo con mysqldump."
echo ""

echo "== Respaldo del origen (mysqldump + gzip) =="
ORIGIN_BACKUP="$BACKUP_DIR/origin_${TS}.sql.gz"
compose exec -T -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" db-origen \
  mysqldump -uroot --single-transaction --routines --triggers --events \
    --databases coop_horizonte_legacy \
  | gzip -9 > "$ORIGIN_BACKUP"
ORIGIN_SHA="$(sha256sum "$ORIGIN_BACKUP" | awk '{print $1}')"
ORIGIN_SIZE="$(du -h "$ORIGIN_BACKUP" | awk '{print $1}')"
echo "Archivo : $ORIGIN_BACKUP"
echo "Tamano  : $ORIGIN_SIZE"
echo "SHA256  : $ORIGIN_SHA"
echo ""

echo "== Preparacion del schema de staging =="
psql_admin < "$ROOT_DIR/src/migration/sql/00_prepare_staging.sql"
echo "Schema $STG_SCHEMA listo (owner: migration_loader)."
echo ""

echo "== Renderizado de la plantilla pgloader =="
compose exec -T migrador bash /app/src/migration/render_load.sh "$LOAD_FILE"
echo "Plantilla renderizada en $LOAD_FILE (modo 600)."
echo ""

echo "== Carga MySQL -> staging con pgloader =="
compose exec -T migrador bash -lc "rm -rf $WORK_DIR && mkdir -p $WORK_DIR"
set +e
compose exec -T migrador bash -lc "exec pgloader --root-dir $WORK_DIR $LOAD_FILE" 2>&1 \
  | sed -E 's#(://[^:/@]+):[^@]*@#\1:***@#g'
PGLOADER_RC=${PIPESTATUS[0]}
set -e
echo "pgloader exit code: $PGLOADER_RC"
REJECTS="$(compose exec -T migrador bash -lc "find $WORK_DIR -name '*.dat' | wc -l" | tr -d '[:space:]')"
echo "Archivos de rechazo: $REJECTS"
if [ "$PGLOADER_RC" -ne 0 ] || [ "$REJECTS" -ne 0 ]; then
  echo "ERROR: pgloader no completo la carga (rc=$PGLOADER_RC, rechazos=$REJECTS)."
  exit 1
fi
echo ""

echo "== Conteos origen vs staging =="
printf '%-24s %8s %8s %s\n' "Tabla" "Origen" "Staging" "Estado"
printf '%-24s %8s %8s %s\n' "------------------------" "--------" "--------" "------"
STG_MISMATCH=0
for tabla in "${TABLES[@]}"; do
  origen="$(count_mysql "$tabla")"
  stage="$(count_stage "$tabla")"
  if [ "$origen" = "$stage" ]; then
    estado="OK"
  else
    estado="ERROR"
    STG_MISMATCH=$((STG_MISMATCH + 1))
  fi
  printf '%-24s %8s %8s %s\n' "$tabla" "$origen" "$stage" "$estado"
done
echo ""
if [ "$STG_MISMATCH" -ne 0 ]; then
  echo "ERROR: $STG_MISMATCH tablas difieren entre origen y staging."
  exit 1
fi

echo "== Precheck sobre staging =="
if ! psql_dba -f "$SQL_DIR/10_precheck.sql"; then
  echo "ERROR: precheck fallido. public NO fue modificado."
  exit 1
fi
echo ""

echo "== Carga transaccional staging -> public =="
if ! psql_dba --single-transaction \
      -f "$SQL_DIR/20_load.sql" \
      -f "$SQL_DIR/30_postcheck.sql" \
      -f "$SQL_DIR/35_sequences.sql"; then
  echo "ERROR: la transaccion fue revertida. public conserva sus datos previos."
  exit 1
fi
echo ""

echo "== Estadisticas del destino (ANALYZE) =="
psql_admin < "$ROOT_DIR/src/migration/sql/40_analyze.sql"
echo ""

echo "== Limpieza del staging =="
psql_admin < "$ROOT_DIR/src/migration/sql/50_cleanup.sql"
STG_EXISTS="$(psql_value "SELECT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = '$STG_SCHEMA');")"
if [ "$STG_EXISTS" != "f" ]; then
  echo "ERROR: el schema $STG_SCHEMA no se elimino."
  exit 1
fi
echo "Schema $STG_SCHEMA eliminado."
MIGRATED=1
echo ""

echo "== Respaldo cifrado del destino (pg_dump -Fc + AES-256-CBC) =="
TARGET_BACKUP="$BACKUP_DIR/target_${TS}.dump.enc"
compose exec -T -u postgres db-destino \
  pg_dump -U postgres -d coop_horizonte_core -Fc \
  | openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt \
      -pass env:BACKUP_PASSPHRASE -out "$TARGET_BACKUP"
TARGET_SHA="$(sha256sum "$TARGET_BACKUP" | awk '{print $1}')"
TARGET_SIZE="$(du -h "$TARGET_BACKUP" | awk '{print $1}')"
echo "Archivo : $TARGET_BACKUP"
echo "Tamano  : $TARGET_SIZE"
echo "SHA256  : $TARGET_SHA"
echo "Cifrado : AES-256-CBC + PBKDF2 (200000 iteraciones) + salt"
echo ""

echo "== Prueba de restauracion del respaldo cifrado =="
TMP_DUMP="$(mktemp /tmp/coop_restore.XXXXXX.dump)"
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
  -pass env:BACKUP_PASSPHRASE -in "$TARGET_BACKUP" -out "$TMP_DUMP"
echo "Descifrado OK: $(du -h "$TMP_DUMP" | awk '{print $1}')"

psql_admin -c "DROP DATABASE IF EXISTS $RESTORE_DB;"
psql_admin -c "CREATE DATABASE $RESTORE_DB;"
compose exec -T -u postgres db-destino \
  pg_restore -U postgres -d "$RESTORE_DB" --no-owner --no-privileges < "$TMP_DUMP"
RESTORE_COUNT="$(compose exec -T -u postgres db-destino \
  psql -U postgres -d "$RESTORE_DB" -tAc 'SELECT COUNT(*) FROM socios;' | tr -d '[:space:]')"
echo "Filas de socios restauradas: $RESTORE_COUNT"
if [ "$RESTORE_COUNT" = "$(count_mysql socios)" ]; then
  echo "Restauracion: OK (coincide con el origen)"
else
  echo "Restauracion: ERROR (no coincide con el origen)"
  exit 1
fi
echo ""

echo "== Comparativa de conteos origen vs destino =="
printf '%-24s %8s %8s %s\n' "Tabla" "Origen" "Destino" "Estado"
printf '%-24s %8s %8s %s\n' "------------------------" "--------" "--------" "------"
MISMATCH=0
for tabla in "${TABLES[@]}"; do
  origen="$(count_mysql "$tabla")"
  destino="$(count_pg "$tabla")"
  if [ "$origen" = "$destino" ]; then
    estado="OK"
  else
    estado="ERROR"
    MISMATCH=$((MISMATCH + 1))
  fi
  printf '%-24s %8s %8s %s\n' "$tabla" "$origen" "$destino" "$estado"
done
echo ""

echo "============================================================"
if [ "$MISMATCH" -eq 0 ]; then
  echo "RESULTADO: migracion pgloader + SQL y respaldo completados sin diferencias."
else
  echo "RESULTADO: $MISMATCH tablas con diferencias. Revisar la carga."
fi
echo "============================================================"

if [ "$MISMATCH" -ne 0 ]; then
  exit 1
fi
