#!/usr/bin/env python3
"""ETL MySQL 5.7 -> PostgreSQL 16 para Cooperativa Horizonte.

- Lee el origen con una transaccion consistente (InnoDB).
- Trunca el destino y carga en orden de claves foraneas.
- Convierte TINYINT(1) -> BOOLEAN y DATETIME -> TIMESTAMPTZ (America/La_Paz).
- Inserta IDs explicitos con OVERRIDING SYSTEM VALUE y reajusta secuencias.
- Verifica conteos origen vs destino y falla si no coinciden.
"""
from __future__ import annotations

import os
import sys
import time
from datetime import datetime
from decimal import Decimal
from zoneinfo import ZoneInfo

import pymysql
import psycopg2
from psycopg2.extras import execute_values

TZ = ZoneInfo("America/La_Paz")

# (tabla, columnas, columnas datetime, columnas boolean)
TABLE_SPECS = [
    (
        "tipos_credito",
        ["id", "nombre", "descripcion", "monto_maximo", "tasa_interes_anual",
         "plazo_maximo_dias", "estado"],
        set(),
        set(),
    ),
    (
        "sucursales",
        ["id", "nombre", "direccion", "telefono", "fecha_creacion", "estatus"],
        {"fecha_creacion"},
        {"estatus"},
    ),
    (
        "socios",
        ["id", "nombre_completo", "numero_identificacion", "fecha_nacimiento",
         "genero", "estado", "fecha_ingreso", "telefono", "email",
         "direccion_residencia", "fecha_ultima_actualizacion", "estatus"],
        {"fecha_ultima_actualizacion"},
        {"estatus"},
    ),
    (
        "cuentas_ahorro",
        ["id", "socio_id", "num_cuenta", "saldo_inicial", "tasa_interes_anual",
         "fecha_apertura", "fecha_cierre", "estatus"],
        {"fecha_apertura", "fecha_cierre"},
        {"estatus"},
    ),
    (
        "solicitudes_credito",
        ["id", "socio_id", "tipo_credito_id", "monto_solicitado", "plazo_dias",
         "fecha_solicitud", "fecha_aprobacion", "fecha_desembolso", "status",
         "observaciones"],
        {"fecha_solicitud", "fecha_aprobacion", "fecha_desembolso"},
        set(),
    ),
    (
        "prestamos",
        ["id", "solicitud_id", "socio_id", "monto_prestado", "tasa_interes_anual",
         "fecha_desembolso", "fecha_fin_plazo", "estado", "total_cuotas",
         "pagado_total"],
        {"fecha_desembolso"},
        {"pagado_total"},
    ),
    (
        "cuotas_amortizacion",
        ["id", "prestamo_id", "numero_cuota", "monto_cuota", "fecha_vencimiento",
         "fecha_pago", "estatus", "monto_pagado"],
        {"fecha_pago"},
        set(),
    ),
    (
        "transacciones",
        ["id", "tipo", "socio_id", "cuenta_ahorro_id", "prestamo_id", "monto",
         "fecha_transaccion", "descripcion"],
        {"fecha_transaccion"},
        set(),
    ),
]

TRUNCATE_ORDER = [
    "transacciones", "cuotas_amortizacion", "prestamos", "solicitudes_credito",
    "cuentas_ahorro", "socios", "tipos_credito", "sucursales",
]


def env(name: str, default: str | None = None) -> str:
    value = os.getenv(name, default)
    if value is None:
        raise SystemExit(f"Falta la variable de entorno {name}")
    return value


def log(message: str) -> None:
    print(message, flush=True)


def transform(value, is_bool: bool, is_datetime: bool):
    if value is None:
        return None
    if is_bool:
        return bool(int(value))
    if is_datetime and isinstance(value, datetime):
        return value.replace(tzinfo=TZ)
    return value


def main() -> int:
    mysql_host = env("MYSQL_HOST", "db-origen")
    mysql_port = int(env("MYSQL_PORT", "3306"))
    mysql_db = env("MYSQL_DB", "coop_horizonte_legacy")
    mysql_user = env("MYSQL_USER", "app_legacy_user")
    mysql_password = env("MYSQL_PASSWORD")

    pg_host = env("PG_HOST", "db-destino")
    pg_port = int(env("PG_PORT", "5432"))
    pg_db = env("PG_DB", "coop_horizonte_core")
    pg_user = env("PG_USER", "admin_dba")
    pg_password = env("PG_PASSWORD")
    pg_sslmode = env("PGSSLMODE", "verify-ca")
    pg_sslrootcert = env("PGSSLROOTCERT", "/etc/postgresql/ssl/server.crt")

    log("[ETL] Conectando a MySQL ...")
    mysql_conn = pymysql.connect(
        host=mysql_host,
        port=mysql_port,
        user=mysql_user,
        password=mysql_password,
        database=mysql_db,
        charset="utf8mb4",
        autocommit=False,
        cursorclass=pymysql.cursors.Cursor,
    )
    mysql_cur = mysql_conn.cursor()
    mysql_cur.execute("SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ")
    mysql_cur.execute("START TRANSACTION WITH CONSISTENT SNAPSHOT")
    log("[ETL] Snapshot consistente de MySQL iniciado")

    log(f"[ETL] Conectando a PostgreSQL (sslmode={pg_sslmode}) ...")
    pg_conn = psycopg2.connect(
        host=pg_host,
        port=pg_port,
        dbname=pg_db,
        user=pg_user,
        password=pg_password,
        sslmode=pg_sslmode,
        sslrootcert=pg_sslrootcert,
        connect_timeout=15,
    )
    pg_cur = pg_conn.cursor()
    pg_cur.execute("SET TIME ZONE 'America/La_Paz'")

    try:
        log("[ETL] Truncando tablas destino ...")
        pg_cur.execute(
            "TRUNCATE " + ", ".join(TRUNCATE_ORDER) + " CASCADE"
        )

        total_rows = 0
        log("")
        log(f"{'Tabla':<24} {'Filas':>8} {'Tiempo(s)':>10}")
        log("-" * 46)
        for table, columns, datetime_cols, bool_cols in TABLE_SPECS:
            started = time.perf_counter()
            select_cols = ", ".join(columns)
            mysql_cur.execute(f"SELECT {select_cols} FROM {table} ORDER BY id")
            raw_rows = mysql_cur.fetchall()

            rows = []
            for raw in raw_rows:
                rows.append(tuple(
                    transform(value, col in bool_cols, col in datetime_cols)
                    for col, value in zip(columns, raw)
                ))

            if rows:
                insert_sql = (
                    f"INSERT INTO {table} ({select_cols}) "
                    f"OVERRIDING SYSTEM VALUE VALUES %s"
                )
                execute_values(pg_cur, insert_sql, rows, page_size=500)

            elapsed = time.perf_counter() - started
            total_rows += len(rows)
            log(f"{table:<24} {len(rows):>8} {elapsed:>10.3f}")

        log("-" * 46)
        log(f"{'TOTAL':<24} {total_rows:>8}")

        log("")
        log("[ETL] Reajustando secuencias de identidad ...")
        for table, _, _, _ in TABLE_SPECS:
            pg_cur.execute(
                f"SELECT setval(pg_get_serial_sequence(%s, 'id'), "
                f"COALESCE(MAX(id), 1), MAX(id) IS NOT NULL) FROM {table}",
                (table,),
            )

        pg_conn.commit()
        log("[ETL] Commit aplicado")

        log("")
        log("[ETL] Verificacion de conteos origen vs destino")
        log(f"{'Tabla':<24} {'Origen':>8} {'Destino':>8} {'Estado':>8}")
        log("-" * 52)
        mismatches = 0
        for table, _, _, _ in TABLE_SPECS:
            mysql_cur.execute(f"SELECT COUNT(*) FROM {table}")
            source_count = mysql_cur.fetchone()[0]
            pg_cur.execute(f"SELECT COUNT(*) FROM {table}")
            target_count = pg_cur.fetchone()[0]
            status = "OK" if source_count == target_count else "ERROR"
            if source_count != target_count:
                mismatches += 1
            log(f"{table:<24} {source_count:>8} {target_count:>8} {status:>8}")
        log("-" * 52)

        mysql_conn.rollback()

        if mismatches:
            log(f"[ETL] ERROR: {mismatches} tablas con conteos distintos")
            return 1

        log("[ETL] Migracion completada correctamente")
        return 0
    except Exception as exc:  # noqa: BLE001
        pg_conn.rollback()
        log(f"[ETL] ERROR: {exc}")
        return 1
    finally:
        mysql_cur.close()
        mysql_conn.close()
        pg_cur.close()
        pg_conn.close()


if __name__ == "__main__":
    sys.exit(main())
