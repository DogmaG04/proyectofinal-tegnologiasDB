#!/usr/bin/env bash
# Utilidades compartidas por los scripts de automatizacion.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"
EVIDENCE_DIR="$ROOT_DIR/evidence"
BACKUP_DIR="$ROOT_DIR/backups"

if [ -f "$ROOT_DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$ROOT_DIR/.env"
  set +a
fi

TABLES=(sucursales socios cuentas_ahorro tipos_credito solicitudes_credito prestamos cuotas_amortizacion transacciones)

compose() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

wait_healthy() {
  local service="$1" cid status i
  cid="$(compose ps -q "$service")"
  if [ -z "$cid" ]; then
    log "ERROR: el servicio $service no esta corriendo"
    return 1
  fi
  for i in $(seq 1 90); do
    status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$cid" 2>/dev/null || echo starting)"
    if [ "$status" = "healthy" ]; then
      log "Servicio $service healthy"
      return 0
    fi
    sleep 2
  done
  log "ERROR: timeout esperando $service (estado: $status)"
  return 1
}

wait_running() {
  local service="$1" cid status i
  cid="$(compose ps -q "$service")"
  if [ -z "$cid" ]; then
    log "ERROR: el servicio $service no esta corriendo"
    return 1
  fi
  for i in $(seq 1 60); do
    status="$(docker inspect -f '{{.State.Status}}' "$cid" 2>/dev/null || echo missing)"
    if [ "$status" = "running" ]; then
      return 0
    fi
    sleep 1
  done
  log "ERROR: timeout esperando $service (estado: $status)"
  return 1
}

mysql_root() {
  compose exec -T -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" db-origen \
    mysql -uroot coop_horizonte_legacy "$@"
}

psql_admin() {
  compose exec -T -u postgres db-destino \
    psql -X -U postgres -d coop_horizonte_core -v ON_ERROR_STOP=1 "$@"
}

# Ejecuta SQL como admin_dba por TLS con verificacion de certificado.
# Las variables PGHOST/PGPORT/PGDATABASE/PGUSER/PGPASSWORD/PGSSLMODE/PGSSLROOTCERT
# ya estan definidas en el contenedor migrador.
psql_dba() {
  compose exec -T migrador psql -X -v ON_ERROR_STOP=1 "$@"
}

count_stage() {
  psql_dba -tAc "SELECT count(*) FROM stg.$1;" | tr -d '[:space:]'
}

psql_value() {
  psql_admin -tAc "$1" | tr -d '[:space:]'
}

count_mysql() {
  mysql_root -N -B -e "SELECT COUNT(*) FROM $1;" | tr -d '[:space:]'
}

count_pg() {
  psql_value "SELECT COUNT(*) FROM $1;"
}
