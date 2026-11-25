#!/bin/sh
# Copia los certificados montados en solo-lectura a una ruta escribible,
# ajusta propietario/permisos y delega en el entrypoint oficial de postgres.
set -e

SRC_DIR=/etc/postgresql/ssl
DST_DIR=/var/lib/postgresql/ssl

mkdir -p "$DST_DIR"
cp "$SRC_DIR/server.crt" "$DST_DIR/server.crt"
cp "$SRC_DIR/server.key" "$DST_DIR/server.key"
chown -R postgres:postgres "$DST_DIR"
chmod 644 "$DST_DIR/server.crt"
chmod 600 "$DST_DIR/server.key"

exec docker-entrypoint.sh "$@"
