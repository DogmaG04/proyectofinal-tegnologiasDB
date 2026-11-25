#!/usr/bin/env python3
"""Genera src/origin/02_seed_origin.sql de forma determinista (seed=42).

Uso:
    python3 src/origin/generate_seed.py > src/origin/02_seed_origin.sql

Datos ficticios pero realistas para la Cooperativa Horizonte PyME S.R.L.
"""
from __future__ import annotations

import random
import unicodedata
from datetime import date, datetime, time, timedelta
from decimal import Decimal, ROUND_HALF_UP

RNG = random.Random(42)
TODAY = date(2026, 11, 20)

NOMBRES = [
    "Maria", "Juan", "Carlos", "Ana", "Luis", "Laura", "Pedro", "Sofia",
    "Miguel", "Patricia", "Fernando", "Rocio", "Jorge", "Valeria", "Andres",
    "Camila", "Diego", "Lucia", "Ricardo", "Gabriela", "Alberto", "Daniela",
    "Raul", "Elena", "Sergio", "Monica", "Pablo", "Silvia", "Oscar", "Teresa",
]
APELLIDOS = [
    "Gonzalez", "Rodriguez", "Mendez", "Fernandez", "Torres", "Sanchez",
    "Martinez", "Lopez", "Jimenez", "Diaz", "Vargas", "Rojas", "Quispe",
    "Mamani", "Choque", "Flores", "Cruz", "Ramos", "Castillo", "Vega",
    "Herrera", "Medina", "Paredes", "Salazar", "Cordero", "Aguilar",
    "Navarro", "Cabrera", "Reyes", "Molina",
]
CIUDADES = ["La Paz", "Santa Cruz", "Cochabamba", "Oruro", "Potosi", "Sucre", "Tarija", "El Alto"]
EXTENSIONES = ["LP", "SC", "CB", "OR", "PT", "CH", "TJ", "EX"]
CALLES = ["Av. Arce", "Calle Potosi", "Av. 6 de Agosto", "Calle Murillo", "Av. Busch",
          "Calle Sucre", "Av. America", "Calle Bolivar", "Av. Villazon", "Calle Junin"]


def money(value: float) -> Decimal:
    return Decimal(str(value)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def sql_str(value) -> str:
    if value is None:
        return "NULL"
    text = str(value).replace("\\", "\\\\").replace("'", "''")
    return f"'{text}'"


def sql_dt(value: datetime | None) -> str:
    return "NULL" if value is None else f"'{value:%Y-%m-%d %H:%M:%S}'"


def sql_date(value: date | None) -> str:
    return "NULL" if value is None else f"'{value:%Y-%m-%d}'"


def sql_num(value) -> str:
    return "NULL" if value is None else f"{value:.2f}"


def sql_bool(value: bool) -> str:
    return "1" if value else "0"


def rand_dt(start: date, end: date) -> datetime:
    delta = max((end - start).days, 1)
    d = start + timedelta(days=RNG.randint(0, delta))
    return datetime.combine(d, time(RNG.randint(8, 18), RNG.randint(0, 59), RNG.randint(0, 59)))


def ascii_slug(text: str) -> str:
    normalized = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    return normalized.lower().replace(" ", ".")


# ---------------------------------------------------------------------------
# Sucursales
# ---------------------------------------------------------------------------
sucursales = [
    (1, "Sucursal Central", "Av. 16 de Julio #123, La Paz", "+591-2-2201234", datetime(2015, 1, 15, 9, 0, 0), 1),
    (2, "Sucursal Norte", "Av. Banzer #456, Santa Cruz", "+591-3-3405678", datetime(2016, 3, 10, 9, 0, 0), 1),
    (3, "Sucursal Sur", "Calle Bolivar #789, Cochabamba", "+591-4-4508765", datetime(2017, 6, 20, 9, 0, 0), 1),
    (4, "Sucursal Este", "Av. Circunvalacion #321, Oruro", "+591-2-5204321", datetime(2018, 9, 5, 9, 0, 0), 1),
    (5, "Sucursal Oeste", "Calle Sucre #654, Tarija", "+591-4-6602121", datetime(2019, 11, 12, 9, 0, 0), 1),
]

# ---------------------------------------------------------------------------
# Tipos de credito
# ---------------------------------------------------------------------------
tipos_credito = [
    (1, "Personal", "Credito para necesidades personales y consumo", money(50000), money(18.50), 730, "activo"),
    (2, "Empresarial", "Capital de trabajo para pymes y emprendedores", money(150000), money(14.00), 1095, "activo"),
    (3, "Educativo", "Financiamiento de estudios tecnicos y universitarios", money(30000), money(12.00), 730, "activo"),
    (4, "Medico", "Gastos medicos, internaciones y tratamientos", money(25000), money(10.00), 365, "activo"),
    (5, "Agricola", "Insumos, maquinaria y capital de trabajo agricola", money(80000), money(11.50), 1095, "activo"),
]

# ---------------------------------------------------------------------------
# Socios (55)
# ---------------------------------------------------------------------------
socios = []
used_names: set[str] = set()
used_ci: set[str] = set()
for i in range(1, 56):
    while True:
        nombre = f"{RNG.choice(NOMBRES)} {RNG.choice(APELLIDOS)} {RNG.choice(APELLIDOS)}"
        if nombre not in used_names:
            used_names.add(nombre)
            break
    while True:
        ci = f"{RNG.randint(1000000, 9999999)}-{RNG.choice(EXTENSIONES)}"
        if ci not in used_ci:
            used_ci.add(ci)
            break
    genero = RNG.choices(["M", "F", "O"], weights=[48, 50, 2])[0]
    estado = RNG.choices(["activo", "inactivo", "suspendido"], weights=[82, 12, 6])[0]
    fecha_nacimiento = date(RNG.randint(1960, 2003), RNG.randint(1, 12), RNG.randint(1, 28))
    fecha_ingreso = date(RNG.randint(2018, 2025), RNG.randint(1, 12), RNG.randint(1, 28))
    ciudad = RNG.choice(CIUDADES)
    direccion = f"{RNG.choice(CALLES)} #{RNG.randint(1, 999)}, {ciudad}"
    telefono = f"+591-7{RNG.randint(1000000, 9999999)}"
    email = f"{ascii_slug(nombre).replace('.', '')}{i}@horizonte.pymes"
    actualizacion = rand_dt(fecha_ingreso, TODAY)
    estatus = 1 if estado == "activo" else 0
    socios.append((i, nombre, ci, fecha_nacimiento, genero, estado, fecha_ingreso,
                   telefono, email, direccion, actualizacion, estatus))

# ---------------------------------------------------------------------------
# Cuentas de ahorro (~65)
# ---------------------------------------------------------------------------
cuentas = []
cuenta_id = 1
used_accounts: set[str] = set()
for socio in socios:
    n_cuentas = 2 if RNG.random() < 0.18 else 1
    for _ in range(n_cuentas):
        while True:
            num = f"CTA-{RNG.randint(1000000000, 9999999999)}"
            if num not in used_accounts:
                used_accounts.add(num)
                break
        apertura = rand_dt(socio[6], TODAY)
        cerrada = RNG.random() < 0.15
        cierre = rand_dt(apertura.date() + timedelta(days=30), TODAY) if cerrada else None
        cuentas.append((cuenta_id, socio[0], num, money(RNG.uniform(0, 25000)),
                        money(RNG.uniform(0.50, 3.50)), apertura, cierre,
                        0 if cerrada else 1))
        cuenta_id += 1

# ---------------------------------------------------------------------------
# Solicitudes de credito (50)
# ---------------------------------------------------------------------------
solicitudes = []
statuses = ["aprobada"] * 35 + ["pendiente"] * 8 + ["rechazada"] * 4 + ["cancelada"] * 3
RNG.shuffle(statuses)
for i, status in enumerate(statuses, start=1):
    socio = RNG.choice(socios)
    tipo = RNG.choice(tipos_credito)
    monto = money(RNG.uniform(1000, float(tipo[3])))
    plazos = [p for p in [180, 365, 540, 730, 1095] if p <= tipo[5]]
    plazo = RNG.choice(plazos)
    fecha_solicitud = rand_dt(date(2023, 1, 1), date(2026, 9, 30))
    if status == "aprobada":
        fecha_aprobacion = fecha_solicitud + timedelta(days=RNG.randint(1, 10))
        fecha_desembolso = fecha_aprobacion + timedelta(days=RNG.randint(1, 5))
    else:
        fecha_aprobacion = None
        fecha_desembolso = None
    observaciones = {
        "aprobada": "Solicitud evaluada y aprobada por el comite de credito.",
        "pendiente": "Solicitud en revision documental.",
        "rechazada": "Solicitud rechazada por politica de riesgo.",
        "cancelada": "Solicitud cancelada a pedido del socio.",
    }[status]
    solicitudes.append((i, socio[0], tipo[0], monto, plazo, fecha_solicitud,
                        fecha_aprobacion, fecha_desembolso, status, observaciones))

# ---------------------------------------------------------------------------
# Prestamos (32)
# ---------------------------------------------------------------------------
aprobadas = [s for s in solicitudes if s[8] == "aprobada"][:32]
prestamos = []
cuotas = []
cuota_id = 1
for i, sol in enumerate(aprobadas, start=1):
    tipo = next(t for t in tipos_credito if t[0] == sol[2])
    estado = RNG.choices(["activo", "pagado", "moroso", "cancelado"], weights=[60, 25, 10, 5])[0]
    total_cuotas = min(24, max(6, sol[4] // 30))
    fecha_fin = sol[7].date() + timedelta(days=sol[4])
    prestamos.append((i, sol[0], sol[1], sol[3], tipo[4], sol[7], fecha_fin,
                      estado, total_cuotas, 1 if estado == "pagado" else 0))

    monto_cuota = money(float(sol[3]) * (1 + float(tipo[4]) / 100) / total_cuotas)
    for n in range(1, total_cuotas + 1):
        vencimiento = sol[7].date() + timedelta(days=30 * n)
        if estado == "pagado":
            pagada = True
        elif estado == "moroso":
            pagada = n <= int(total_cuotas * 0.6)
        elif estado == "cancelado":
            pagada = n <= int(total_cuotas * 0.3)
        else:
            if vencimiento < TODAY:
                pagada = RNG.random() < 0.8
            else:
                pagada = False
        if pagada:
            fecha_pago = datetime.combine(vencimiento + timedelta(days=RNG.randint(0, 5)),
                                          time(RNG.randint(9, 17), RNG.randint(0, 59)))
            estatus = "pagada"
            monto_pagado = monto_cuota
        elif vencimiento < TODAY:
            fecha_pago = None
            estatus = "atrasada"
            monto_pagado = money(0)
        else:
            fecha_pago = None
            estatus = "pendiente"
            monto_pagado = money(0)
        cuotas.append((cuota_id, i, n, monto_cuota, vencimiento, fecha_pago,
                       estatus, monto_pagado))
        cuota_id += 1

# ---------------------------------------------------------------------------
# Transacciones (>300)
# ---------------------------------------------------------------------------
transacciones = []
tx_id = 1
for p in prestamos:
    transacciones.append((tx_id, "desembolso", p[2], None, p[0], p[3], p[5],
                          f"Desembolso del prestamo #{p[0]}"))
    tx_id += 1

for c in cuotas:
    if c[6] == "pagada":
        p = next(x for x in prestamos if x[0] == c[1])
        transacciones.append((tx_id, "pago_cuota", p[2], None, p[0], c[7], c[5],
                              f"Pago de cuota {c[2]} del prestamo #{p[0]}"))
        tx_id += 1

for cuenta in cuentas:
    for _ in range(RNG.randint(3, 6)):
        tipo = RNG.choice(["deposito", "retiro"])
        fecha = rand_dt(cuenta[5].date(), TODAY)
        monto = money(RNG.uniform(100, 5000))
        transacciones.append((tx_id, tipo, cuenta[1], cuenta[0], None, monto, fecha,
                              f"{tipo.capitalize()} en cuenta {cuenta[2]}"))
        tx_id += 1

for _ in range(60):
    cuenta = RNG.choice(cuentas)
    fecha = rand_dt(cuenta[5].date(), TODAY)
    monto = money(RNG.uniform(100, 3000))
    transacciones.append((tx_id, "transferencia", cuenta[1], cuenta[0], None, monto, fecha,
                          f"Transferencia desde cuenta {cuenta[2]}"))
    tx_id += 1

transacciones.sort(key=lambda t: t[6])


def emit_insert(out, table: str, columns: list[str], rows: list[tuple], formatters) -> None:
    out.append(f"-- {table}: {len(rows)} filas")
    out.append(f"INSERT INTO {table} ({', '.join(columns)}) VALUES")
    for idx, row in enumerate(rows):
        values = ", ".join(fmt(val) for fmt, val in zip(formatters, row))
        suffix = "," if idx < len(rows) - 1 else ";"
        out.append(f"  ({values}){suffix}")
    out.append("")


def main() -> None:
    out: list[str] = []
    out.append("-- ============================================================================")
    out.append("--  SEED: MySQL 5.7 - Cooperativa Horizonte PyME S.R.L.")
    out.append("--  Generado por src/origin/generate_seed.py (seed=42, reproducible)")
    out.append(f"--  Socios: {len(socios)} | Cuentas: {len(cuentas)} | Solicitudes: {len(solicitudes)}")
    out.append(f"--  Prestamos: {len(prestamos)} | Cuotas: {len(cuotas)} | Transacciones: {len(transacciones)}")
    out.append("-- ============================================================================")
    out.append("")
    out.append("USE coop_horizonte_legacy;")
    out.append("SET NAMES utf8;")
    out.append("")

    emit_insert(out, "sucursales",
                ["id", "nombre", "direccion", "telefono", "fecha_creacion", "estatus"],
                sucursales,
                [str, sql_str, sql_str, sql_str, sql_dt, sql_bool])

    emit_insert(out, "tipos_credito",
                ["id", "nombre", "descripcion", "monto_maximo", "tasa_interes_anual",
                 "plazo_maximo_dias", "estado"],
                tipos_credito,
                [str, sql_str, sql_str, sql_num, sql_num, str, sql_str])

    emit_insert(out, "socios",
                ["id", "nombre_completo", "numero_identificacion", "fecha_nacimiento",
                 "genero", "estado", "fecha_ingreso", "telefono", "email",
                 "direccion_residencia", "fecha_ultima_actualizacion", "estatus"],
                socios,
                [str, sql_str, sql_str, sql_date, sql_str, sql_str, sql_date,
                 sql_str, sql_str, sql_str, sql_dt, sql_bool])

    emit_insert(out, "cuentas_ahorro",
                ["id", "socio_id", "num_cuenta", "saldo_inicial", "tasa_interes_anual",
                 "fecha_apertura", "fecha_cierre", "estatus"],
                cuentas,
                [str, str, sql_str, sql_num, sql_num, sql_dt, sql_dt, sql_bool])

    emit_insert(out, "solicitudes_credito",
                ["id", "socio_id", "tipo_credito_id", "monto_solicitado", "plazo_dias",
                 "fecha_solicitud", "fecha_aprobacion", "fecha_desembolso", "status",
                 "observaciones"],
                solicitudes,
                [str, str, str, sql_num, str, sql_dt, sql_dt, sql_dt, sql_str, sql_str])

    emit_insert(out, "prestamos",
                ["id", "solicitud_id", "socio_id", "monto_prestado", "tasa_interes_anual",
                 "fecha_desembolso", "fecha_fin_plazo", "estado", "total_cuotas",
                 "pagado_total"],
                prestamos,
                [str, str, str, sql_num, sql_num, sql_dt, sql_date, sql_str, str, sql_bool])

    emit_insert(out, "cuotas_amortizacion",
                ["id", "prestamo_id", "numero_cuota", "monto_cuota", "fecha_vencimiento",
                 "fecha_pago", "estatus", "monto_pagado"],
                cuotas,
                [str, str, str, sql_num, sql_date, sql_dt, sql_str, sql_num])

    emit_insert(out, "transacciones",
                ["id", "tipo", "socio_id", "cuenta_ahorro_id", "prestamo_id", "monto",
                 "fecha_transaccion", "descripcion"],
                transacciones,
                [str, sql_str, lambda v: "NULL" if v is None else str(v),
                 lambda v: "NULL" if v is None else str(v),
                 lambda v: "NULL" if v is None else str(v),
                 sql_num, sql_dt, sql_str])

    out.append("-- Fin del seed")
    print("\n".join(out))


if __name__ == "__main__":
    main()
