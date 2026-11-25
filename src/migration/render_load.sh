#!/usr/bin/env bash
# Renderiza la plantilla pgloader sustituyendo solo las variables conocidas.
# Evita que envsubst reemplace cualquier ${...} que aparezca en el DSL.
#
# Uso: render_load.sh [archivo-destino]
set -euo pipefail

template=/app/src/migration/pgloader/mysql_to_stage.load
dest="${1:-/tmp/mysql_to_stage.load}"

: "${MYSQL_USER:?variable MYSQL_USER no definida}"
: "${MYSQL_PASSWORD:?variable MYSQL_PASSWORD no definida}"
: "${MYSQL_HOST:?variable MYSQL_HOST no definida}"
: "${MYSQL_PORT:?variable MYSQL_PORT no definida}"
: "${MYSQL_DB:?variable MYSQL_DB no definida}"
: "${MIGRATION_LOADER_USER:?variable MIGRATION_LOADER_USER no definida}"
: "${MIGRATION_LOADER_PASSWORD:?variable MIGRATION_LOADER_PASSWORD no definida}"
: "${PGHOST:?variable PGHOST no definida}"
: "${PGPORT:?variable PGPORT no definida}"
: "${PGDATABASE:?variable PGDATABASE no definida}"

umask 077
envsubst '${MYSQL_USER} ${MYSQL_PASSWORD} ${MYSQL_HOST} ${MYSQL_PORT} ${MYSQL_DB} ${MIGRATION_LOADER_USER} ${MIGRATION_LOADER_PASSWORD} ${PGHOST} ${PGPORT} ${PGDATABASE}' \
  < "$template" > "$dest"
chmod 600 "$dest"
