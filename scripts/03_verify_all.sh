#!/usr/bin/env bash
# Verificacion integral del destino: SSL, roles, enmascaramiento, conteos,
# integridad referencial y rendimiento.
# Salida: evidence/03_pruebas_y_hardening.txt
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

mkdir -p "$EVIDENCE_DIR"
OUT="$EVIDENCE_DIR/03_pruebas_y_hardening.txt"
exec > >(tee "$OUT") 2>&1

PASS=0
FAIL=0

check_eq() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf 'PASS  %-58s (valor=%s)\n' "$name" "$actual"
    PASS=$((PASS + 1))
  else
    printf 'FAIL  %-58s (esperado=%s, obtenido=%s)\n' "$name" "$expected" "$actual"
    FAIL=$((FAIL + 1))
  fi
}

check_true() {
  local name="$1" condition="$2"
  if [ "$condition" = "1" ]; then
    printf 'PASS  %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf 'FAIL  %s\n' "$name"
    FAIL=$((FAIL + 1))
  fi
}

time_ms() {
  local start end
  start=$(date +%s%N)
  "$@" >/dev/null 2>&1
  end=$(date +%s%N)
  echo $(( (end - start) / 1000000 ))
}

CONN_BASE="host=db-destino port=5432 dbname=coop_horizonte_core"

echo "============================================================"
echo "PRUEBAS DE MIGRACION Y HARDENING - PostgreSQL 16"
echo "Cooperativa de Ahorro y Credito Horizonte PyME S.R.L."
echo "Generado: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "============================================================"
echo ""

log "Esperando servicios ..."
wait_healthy db-destino
wait_healthy db-origen
wait_running migrador

# ---------------------------------------------------------------------------
echo "== 1. Parametros de seguridad activos =="
check_eq "SHOW ssl" "on" "$(psql_value 'SHOW ssl;')"
check_eq "SHOW password_encryption" "scram-sha-256" "$(psql_value 'SHOW password_encryption;')"
check_eq "SHOW log_connections" "on" "$(psql_value 'SHOW log_connections;')"
check_eq "SHOW log_disconnections" "on" "$(psql_value 'SHOW log_disconnections;')"
check_eq "SHOW log_statement" "ddl" "$(psql_value 'SHOW log_statement;')"
echo ""

echo "== 2. Reglas efectivas de pg_hba.conf =="
psql_admin -c "SELECT line_number, type, database, user_name, address, auth_method FROM pg_hba_file_rules ORDER BY line_number;"
echo ""

# ---------------------------------------------------------------------------
echo "== 3. Rechazo de conexiones sin SSL =="
NOSSL_CONN="$CONN_BASE user=app_core_rw password=${APP_CORE_RW_PASSWORD} sslmode=disable"
set +e
NOSSL_OUT="$(compose exec -T migrador psql "$NOSSL_CONN" -tAc 'SELECT 1;' 2>&1)"
NOSSL_RC=$?
set -e
if [ "$NOSSL_RC" -ne 0 ] && echo "$NOSSL_OUT" | grep -qiE 'no pg_hba.conf entry|no encryption|SSL off'; then
  echo "PASS  Conexion TCP sin SSL rechazada"
  PASS=$((PASS + 1))
else
  echo "FAIL  Conexion TCP sin SSL NO fue rechazada (rc=$NOSSL_RC)"
  echo "$NOSSL_OUT"
  FAIL=$((FAIL + 1))
fi

SSL_CONN="$CONN_BASE user=app_core_rw password=${APP_CORE_RW_PASSWORD} sslmode=require"
set +e
SSL_OUT="$(compose exec -T migrador psql "$SSL_CONN" -tAc 'SELECT 1;' 2>&1)"
SSL_RC=$?
set -e
if [ "$SSL_RC" -eq 0 ] && [ "$(echo "$SSL_OUT" | tr -d '[:space:]')" = "1" ]; then
  echo "PASS  Conexion TCP con SSL (sslmode=require)"
  PASS=$((PASS + 1))
else
  echo "FAIL  Conexion TCP con SSL (rc=$SSL_RC): $SSL_OUT"
  FAIL=$((FAIL + 1))
fi

VERIFY_CONN="$CONN_BASE user=app_core_rw password=${APP_CORE_RW_PASSWORD} sslmode=verify-ca sslrootcert=/etc/postgresql/ssl/server.crt"
set +e
VERIFY_OUT="$(compose exec -T migrador psql "$VERIFY_CONN" -tAc 'SELECT 1;' 2>&1)"
VERIFY_RC=$?
set -e
if [ "$VERIFY_RC" -eq 0 ] && [ "$(echo "$VERIFY_OUT" | tr -d '[:space:]')" = "1" ]; then
  echo "PASS  Conexion TCP con SSL verificado (sslmode=verify-ca)"
  PASS=$((PASS + 1))
else
  echo "FAIL  Conexion TCP con SSL verificado (rc=$VERIFY_RC): $VERIFY_OUT"
  FAIL=$((FAIL + 1))
fi

PGR_CONN="$CONN_BASE user=postgres password=${POSTGRES_PASSWORD} sslmode=require"
set +e
PGR_OUT="$(compose exec -T migrador psql "$PGR_CONN" -tAc 'SELECT 1;' 2>&1)"
PGR_RC=$?
set -e
if [ "$PGR_RC" -ne 0 ] && echo "$PGR_OUT" | grep -qiE 'no pg_hba.conf entry|pg_hba'; then
  echo "PASS  Acceso remoto directo de postgres rechazado"
  PASS=$((PASS + 1))
else
  echo "FAIL  Acceso remoto directo de postgres NO fue rechazado (rc=$PGR_RC)"
  echo "$PGR_OUT"
  FAIL=$((FAIL + 1))
fi
echo ""

# ---------------------------------------------------------------------------
echo "== 4. Roles y privilegios de minimo privilegio =="
psql_admin -c "SELECT rolname, rolsuper, rolcanlogin, rolcreatedb, rolcreaterole, rolinherit FROM pg_roles WHERE rolname IN ('admin_dba', 'app_core_rw', 'auditor_ro', 'migration_loader') ORDER BY rolname;"
check_eq "admin_dba no es superusuario" "f" "$(psql_value "SELECT rolsuper FROM pg_roles WHERE rolname = 'admin_dba';")"
check_eq "app_core_rw no es superusuario" "f" "$(psql_value "SELECT rolsuper FROM pg_roles WHERE rolname = 'app_core_rw';")"
check_eq "app_core_rw puede iniciar sesion" "t" "$(psql_value "SELECT rolcanlogin FROM pg_roles WHERE rolname = 'app_core_rw';")"
check_eq "auditor_ro puede iniciar sesion" "t" "$(psql_value "SELECT rolcanlogin FROM pg_roles WHERE rolname = 'auditor_ro';")"
check_eq "PUBLIC sin CREATE en schema public" "f" "$(psql_value "SELECT COALESCE(bool_or(a.privilege_type = 'CREATE'), false) FROM pg_namespace n, aclexplode(n.nspacl) a WHERE n.nspname = 'public' AND a.grantee = 0;")"
check_eq "auditor_ro con USAGE en public" "t" "$(psql_value "SELECT has_schema_privilege('auditor_ro', 'public', 'USAGE');")"
check_eq "app_core_rw sin CREATE en public" "f" "$(psql_value "SELECT has_schema_privilege('app_core_rw', 'public', 'CREATE');")"
check_eq "auditor_ro no lee socios" "f" "$(psql_value "SELECT has_table_privilege('auditor_ro', 'socios', 'SELECT');")"
check_eq "auditor_ro lee vw_socios_audit" "t" "$(psql_value "SELECT has_table_privilege('auditor_ro', 'vw_socios_audit', 'SELECT');")"
check_eq "app_core_rw inserta en socios" "t" "$(psql_value "SELECT has_table_privilege('app_core_rw', 'socios', 'INSERT');")"
check_eq "app_core_rw no trunca socios" "f" "$(psql_value "SELECT has_table_privilege('app_core_rw', 'socios', 'TRUNCATE');")"
echo ""

# ---------------------------------------------------------------------------
echo "== 4.1 Rol de carga (migration_loader) =="
check_eq "migration_loader no es superusuario" "f" "$(psql_value "SELECT rolsuper FROM pg_roles WHERE rolname = 'migration_loader';")"
check_eq "migration_loader puede iniciar sesion" "t" "$(psql_value "SELECT rolcanlogin FROM pg_roles WHERE rolname = 'migration_loader';")"
check_eq "migration_loader sin CREATEDB" "f" "$(psql_value "SELECT rolcreatedb FROM pg_roles WHERE rolname = 'migration_loader';")"
check_eq "migration_loader sin CREATEROLE" "f" "$(psql_value "SELECT rolcreaterole FROM pg_roles WHERE rolname = 'migration_loader';")"
check_eq "migration_loader sin USAGE en public" "f" "$(psql_value "SELECT has_schema_privilege('migration_loader', 'public', 'USAGE');")"
check_eq "migration_loader no lee socios" "f" "$(psql_value "SELECT has_table_privilege('migration_loader', 'socios', 'SELECT');")"
check_eq "migration_loader no trunca socios" "f" "$(psql_value "SELECT has_table_privilege('migration_loader', 'socios', 'TRUNCATE');")"
check_eq "admin_dba puede truncar socios" "t" "$(psql_value "SELECT has_table_privilege('admin_dba', 'socios', 'TRUNCATE');")"
check_eq "schema stg eliminado tras la migracion" "f" "$(psql_value "SELECT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'stg');")"

LOADER_CONN="$CONN_BASE user=migration_loader password=${MIGRATION_LOADER_PASSWORD} sslmode=verify-ca sslrootcert=/etc/postgresql/ssl/server.crt"
set +e
LOADER_OUT="$(compose exec -T migrador psql "$LOADER_CONN" -tAc 'SELECT count(*) FROM public.socios;' 2>&1)"
LOADER_RC=$?
set -e
if [ "$LOADER_RC" -ne 0 ] && echo "$LOADER_OUT" | grep -qi 'permission denied'; then
  echo "PASS  migration_loader conecta pero no lee public.socios"
  PASS=$((PASS + 1))
else
  echo "FAIL  migration_loader pudo leer public.socios o no conecto (rc=$LOADER_RC)"
  echo "$LOADER_OUT"
  FAIL=$((FAIL + 1))
fi
echo ""

# ---------------------------------------------------------------------------
echo "== 4.2 Integrantes del equipo (perfil admin) =="
psql_admin -c "SELECT rolname, rolsuper, rolcanlogin, rolcreatedb, rolcreaterole FROM pg_roles WHERE rolname IN ('nicolas', 'joaquin', 'david', 'gustavo') ORDER BY rolname;"
for u in nicolas joaquin david gustavo; do
  check_eq "$u existe y puede iniciar sesion" "t" "$(psql_value "SELECT rolcanlogin FROM pg_roles WHERE rolname = '$u';")"
  check_eq "$u no es superusuario" "f" "$(psql_value "SELECT rolsuper FROM pg_roles WHERE rolname = '$u';")"
  check_eq "$u con privilegios de admin en socios" "t" "$(psql_value "SELECT has_table_privilege('$u', 'socios', 'TRUNCATE');")"

  TEAM_CONN="$CONN_BASE user=$u password=${ADMIN_TEAM_PASSWORD} sslmode=verify-ca sslrootcert=/etc/postgresql/ssl/server.crt"
  set +e
  TEAM_OUT="$(compose exec -T migrador psql "$TEAM_CONN" -tAc 'SELECT current_user;' 2>&1)"
  TEAM_RC=$?
  set -e
  if [ "$TEAM_RC" -eq 0 ] && [ "$(echo "$TEAM_OUT" | tr -d '[:space:]')" = "$u" ]; then
    echo "PASS  $u conecta por TLS como admin"
    PASS=$((PASS + 1))
  else
    echo "FAIL  $u no pudo conectar por TLS (rc=$TEAM_RC): $TEAM_OUT"
    FAIL=$((FAIL + 1))
  fi
done
echo ""

# ---------------------------------------------------------------------------
echo "== 5. Enmascaramiento de datos sensibles =="
AUD_CONN="$CONN_BASE user=auditor_ro password=${AUDITOR_RO_PASSWORD} sslmode=require"
set +e
AUD_MASK="$(compose exec -T migrador psql "$AUD_CONN" -tAc 'SELECT ci_nit, numero_cuenta FROM vw_socios_audit LIMIT 5;' 2>&1)"
AUD_RC=$?
set -e
echo "$AUD_MASK"
if [ "$AUD_RC" -eq 0 ] && echo "$AUD_MASK" | grep -q '\*\*\*\*'; then
  echo "PASS  vw_socios_audit devuelve valores enmascarados"
  PASS=$((PASS + 1))
else
  echo "FAIL  vw_socios_audit no devuelve valores enmascarados (rc=$AUD_RC)"
  FAIL=$((FAIL + 1))
fi
if echo "$AUD_MASK" | grep -qE '[0-9]{7}'; then
  echo "FAIL  Se detectaron identificadores sin enmascarar"
  FAIL=$((FAIL + 1))
else
  echo "PASS  No se detectaron identificadores completos en la vista"
  PASS=$((PASS + 1))
fi

set +e
AUD_SOCIOS="$(compose exec -T migrador psql "$AUD_CONN" -tAc 'SELECT * FROM socios LIMIT 1;' 2>&1)"
AUD_SOCIOS_RC=$?
set -e
if [ "$AUD_SOCIOS_RC" -ne 0 ] && echo "$AUD_SOCIOS" | grep -qi 'permission denied'; then
  echo "PASS  auditor_ro no puede leer la tabla socios"
  PASS=$((PASS + 1))
else
  echo "FAIL  auditor_ro pudo leer la tabla socios o el error no es de permisos (rc=$AUD_SOCIOS_RC)"
  FAIL=$((FAIL + 1))
fi
echo ""

# ---------------------------------------------------------------------------
echo "== 6. Conteos origen vs destino =="
printf '%-24s %8s %8s %s\n' "Tabla" "Origen" "Destino" "Estado"
printf '%-24s %8s %8s %s\n' "------------------------" "--------" "--------" "------"
for tabla in "${TABLES[@]}"; do
  origen="$(count_mysql "$tabla")"
  destino="$(count_pg "$tabla")"
  if [ "$origen" = "$destino" ]; then
    estado="OK"
    PASS=$((PASS + 1))
  else
    estado="ERROR"
    FAIL=$((FAIL + 1))
  fi
  printf '%-24s %8s %8s %s\n' "$tabla" "$origen" "$destino" "$estado"
done
echo ""

# ---------------------------------------------------------------------------
echo "== 6.1 Secuencias de identidad =="
for tabla in "${TABLES[@]}"; do
  seq="$(psql_value "SELECT pg_get_serial_sequence('public.$tabla', 'id');")"
  if [ -z "$seq" ]; then
    printf 'FAIL  %-58s (sin secuencia de identidad)\n' "Secuencia alineada: $tabla"
    FAIL=$((FAIL + 1))
    continue
  fi
  last="$(psql_value "SELECT last_value FROM $seq;")"
  maxid="$(psql_value "SELECT COALESCE(max(id), 0) FROM $tabla;")"
  check_eq "Secuencia alineada: $tabla" "$maxid" "$last"
done
echo ""

# ---------------------------------------------------------------------------
echo "== 7. Integridad referencial =="
check_eq "Cantidad de claves foraneas en destino" "9" "$(psql_value "SELECT COUNT(*) FROM pg_constraint WHERE contype = 'f';")"
FKS=(
  "cuentas_ahorro socio_id socios id"
  "solicitudes_credito socio_id socios id"
  "solicitudes_credito tipo_credito_id tipos_credito id"
  "prestamos solicitud_id solicitudes_credito id"
  "prestamos socio_id socios id"
  "cuotas_amortizacion prestamo_id prestamos id"
  "transacciones socio_id socios id"
  "transacciones cuenta_ahorro_id cuentas_ahorro id"
  "transacciones prestamo_id prestamos id"
)
for fk in "${FKS[@]}"; do
  read -r child ccol parent pcol <<< "$fk"
  orphans="$(psql_value "SELECT COUNT(*) FROM $child c LEFT JOIN $parent p ON c.$ccol = p.$pcol WHERE c.$ccol IS NOT NULL AND p.$pcol IS NULL;")"
  check_eq "Sin huerfanos: $child.$ccol -> $parent.$pcol" "0" "$orphans"
done
echo ""

# ---------------------------------------------------------------------------
echo "== 8. Rendimiento de consultas criticas =="
PG_MORA_PLAN="$(psql_admin -c 'EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM vw_cartera_mora;')"
echo "$PG_MORA_PLAN"
PG_MORA_SERVER="$(echo "$PG_MORA_PLAN" | grep -oE 'Execution Time: [0-9.]+' | awk '{print $3}' | tail -1)"

PG_SALDOS_PLAN="$(psql_admin -c 'EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM vw_resumen_saldos_socio;')"
echo "$PG_SALDOS_PLAN"
PG_SALDOS_SERVER="$(echo "$PG_SALDOS_PLAN" | grep -oE 'Execution Time: [0-9.]+' | awk '{print $3}' | tail -1)"

MYSQL_MORA_MS="$(time_ms mysql_root -N -B -e 'SELECT * FROM vw_cartera_mora;')"
PG_MORA_WALL_MS="$(time_ms psql_admin -tAc 'SELECT * FROM vw_cartera_mora;')"
MYSQL_SALDOS_MS="$(time_ms mysql_root -N -B -e 'SELECT * FROM vw_resumen_saldos_socio;')"
PG_SALDOS_WALL_MS="$(time_ms psql_admin -tAc 'SELECT * FROM vw_resumen_saldos_socio;')"

echo ""
printf '%-30s %14s %12s %14s\n' "Consulta" "MySQL wall(ms)" "PG wall(ms)" "PG server(ms)"
printf '%-30s %14s %12s %14s\n' "------------------------------" "--------------" "------------" "--------------"
printf '%-30s %14s %12s %14s\n' "vw_cartera_mora" "$MYSQL_MORA_MS" "$PG_MORA_WALL_MS" "${PG_MORA_SERVER:-n/d}"
printf '%-30s %14s %12s %14s\n' "vw_resumen_saldos_socio" "$MYSQL_SALDOS_MS" "$PG_SALDOS_WALL_MS" "${PG_SALDOS_SERVER:-n/d}"
echo ""
echo "Nota: wall(ms) incluye el overhead de 'docker compose exec' en ambos motores;"
echo "      server(ms) es el 'Execution Time' de EXPLAIN ANALYZE en PostgreSQL."
echo ""

# ---------------------------------------------------------------------------
echo "============================================================"
echo "RESUMEN DE VERIFICACION"
echo "PASS: $PASS"
echo "FAIL: $FAIL"
echo "============================================================"
if [ "$FAIL" -eq 0 ]; then
  echo "RESULTADO: TODAS LAS PRUEBAS PASARON"
  exit 0
else
  echo "RESULTADO: $FAIL PRUEBAS FALLARON"
  exit 1
fi
