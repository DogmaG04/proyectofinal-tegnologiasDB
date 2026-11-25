#!/usr/bin/env bash
# Auditoria del sistema origen MySQL 5.7 -> evidence/01_inventario_origen.txt
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

mkdir -p "$EVIDENCE_DIR"
OUT="$EVIDENCE_DIR/01_inventario_origen.txt"

{
  echo "============================================================"
  echo "INVENTARIO DEL SISTEMA ORIGEN - MySQL 5.7"
  echo "Cooperativa de Ahorro y Credito Horizonte PyME S.R.L."
  echo "Generado: $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "============================================================"
  echo ""

  log "Esperando MySQL ..."
  wait_healthy db-origen

  echo "== Version del motor =="
  mysql_root -e "SELECT VERSION() AS mysql_version;"
  echo ""

  echo "== Tamano de la base de datos =="
  mysql_root -e "SELECT table_schema AS db, ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS size_mb FROM information_schema.tables WHERE table_schema = 'coop_horizonte_legacy' GROUP BY table_schema;"
  echo ""

  echo "== Tamano por tabla =="
  mysql_root -e "SELECT table_name AS tabla, ROUND((data_length + index_length) / 1024 / 1024, 2) AS mb, table_rows AS filas_aprox FROM information_schema.tables WHERE table_schema = 'coop_horizonte_legacy' AND table_type = 'BASE TABLE' ORDER BY (data_length + index_length) DESC;"
  echo ""

  echo "== Tablas =="
  mysql_root -e "SELECT table_name AS tabla, engine AS motor, table_rows AS filas_aprox FROM information_schema.tables WHERE table_schema = 'coop_horizonte_legacy' AND table_type = 'BASE TABLE' ORDER BY table_name;"
  echo ""

  echo "== Vistas =="
  mysql_root -e "SELECT table_name AS vista FROM information_schema.views WHERE table_schema = 'coop_horizonte_legacy' ORDER BY table_name;"
  echo ""

  echo "== Indices =="
  mysql_root -e "SELECT table_name AS tabla, index_name AS indice, non_unique AS no_unico, column_name AS columna FROM information_schema.statistics WHERE table_schema = 'coop_horizonte_legacy' ORDER BY table_name, index_name, seq_in_index;"
  echo ""

  echo "== Usuarios =="
  mysql_root -e "SELECT user, host FROM mysql.user WHERE user NOT IN ('root', 'mysql.sys', 'mysql.session') ORDER BY user;"
  echo ""

  echo "== Privilegios de app_legacy_user =="
  mysql_root -e "SHOW GRANTS FOR 'app_legacy_user'@'%';"
  echo ""

  echo "== Conteos exactos por tabla =="
  printf '%-24s %8s\n' "Tabla" "Filas"
  printf '%-24s %8s\n' "------------------------" "--------"
  for tabla in "${TABLES[@]}"; do
    filas="$(count_mysql "$tabla")"
    printf '%-24s %8s\n' "$tabla" "$filas"
  done
  echo ""

  echo "== Juego de caracteres y collation =="
  mysql_root -e "SELECT default_character_set_name AS charset, default_collation_name AS collation FROM information_schema.schemata WHERE schema_name = 'coop_horizonte_legacy';"
  echo ""

  echo "== Columnas ENUM (incompatibilidad con PostgreSQL) =="
  mysql_root -e "SELECT table_name AS tabla, column_name AS columna, column_type AS tipo FROM information_schema.columns WHERE table_schema = 'coop_horizonte_legacy' AND column_type LIKE 'enum%' AND table_name IN (SELECT table_name FROM information_schema.tables WHERE table_schema = 'coop_horizonte_legacy' AND table_type = 'BASE TABLE') ORDER BY table_name, ordinal_position;"
  echo ""

  echo "== Columnas DATETIME (sin zona horaria) =="
  mysql_root -e "SELECT table_name AS tabla, column_name AS columna, column_type AS tipo FROM information_schema.columns WHERE table_schema = 'coop_horizonte_legacy' AND column_type LIKE 'datetime%' AND table_name IN (SELECT table_name FROM information_schema.tables WHERE table_schema = 'coop_horizonte_legacy' AND table_type = 'BASE TABLE') ORDER BY table_name, ordinal_position;"
  echo ""

  echo "== Columnas TINYINT(1) (booleanos) =="
  mysql_root -e "SELECT table_name AS tabla, column_name AS columna, column_type AS tipo FROM information_schema.columns WHERE table_schema = 'coop_horizonte_legacy' AND column_type LIKE 'tinyint(1)%' AND table_name IN (SELECT table_name FROM information_schema.tables WHERE table_schema = 'coop_horizonte_legacy' AND table_type = 'BASE TABLE') ORDER BY table_name, ordinal_position;"
  echo ""

  echo "== Resumen de incompatibilidades =="
  mysql_root -e "SELECT 'ENUM' AS tipo, COUNT(*) AS columnas FROM information_schema.columns WHERE table_schema = 'coop_horizonte_legacy' AND column_type LIKE 'enum%' AND table_name IN (SELECT table_name FROM information_schema.tables WHERE table_schema = 'coop_horizonte_legacy' AND table_type = 'BASE TABLE') UNION ALL SELECT 'DATETIME', COUNT(*) FROM information_schema.columns WHERE table_schema = 'coop_horizonte_legacy' AND column_type LIKE 'datetime%' AND table_name IN (SELECT table_name FROM information_schema.tables WHERE table_schema = 'coop_horizonte_legacy' AND table_type = 'BASE TABLE') UNION ALL SELECT 'TINYINT(1)', COUNT(*) FROM information_schema.columns WHERE table_schema = 'coop_horizonte_legacy' AND column_type LIKE 'tinyint(1)%' AND table_name IN (SELECT table_name FROM information_schema.tables WHERE table_schema = 'coop_horizonte_legacy' AND table_type = 'BASE TABLE') UNION ALL SELECT 'FOREIGN KEY existentes', COUNT(*) FROM information_schema.table_constraints WHERE table_schema = 'coop_horizonte_legacy' AND constraint_type = 'FOREIGN KEY';"
  echo ""

  echo "============================================================"
  echo "FIN DEL INVENTARIO"
  echo "============================================================"
} 2>&1 | tee "$OUT"

log "Inventario guardado en $OUT"
