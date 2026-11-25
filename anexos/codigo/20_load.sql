-- ============================================================================
--  CARGA: stg -> public
--
--  Se ejecuta con:  psql --single-transaction -f 20 -f 30 -f 35
--  Por lo tanto TRUNCATE, INSERT, POSTCHECK y setval forman una sola
--  transaccion: cualquier fallo revierte todo y public queda como estaba.
--
--  Se preservan los identificadores originales con OVERRIDING SYSTEM VALUE.
-- ============================================================================
\set ON_ERROR_STOP on

SET TIME ZONE 'America/La_Paz';
SET client_min_messages = warning;

-- TRUNCATE es transaccional en PostgreSQL. No se usa RESTART IDENTITY:
-- las secuencias se ajustan en 35_sequences.sql, despues del postcheck.
TRUNCATE TABLE
  transacciones,
  cuotas_amortizacion,
  prestamos,
  solicitudes_credito,
  cuentas_ahorro,
  tipos_credito,
  socios,
  sucursales
CASCADE;

-- ----------------------------------------------------------------------------
-- Orden de insercion respetando las 9 claves foraneas
-- ----------------------------------------------------------------------------
INSERT INTO sucursales
  (id, nombre, direccion, telefono, fecha_creacion, estatus)
OVERRIDING SYSTEM VALUE
SELECT
  id::bigint,
  nombre,
  direccion,
  telefono,
  fecha_creacion::timestamptz,
  estatus::boolean
FROM stg.sucursales
ORDER BY id;

INSERT INTO socios
  (id, nombre_completo, numero_identificacion, fecha_nacimiento, genero, estado,
   fecha_ingreso, telefono, email, direccion_residencia,
   fecha_ultima_actualizacion, estatus)
OVERRIDING SYSTEM VALUE
SELECT
  id::bigint,
  nombre_completo,
  numero_identificacion,
  fecha_nacimiento::date,
  genero::text,
  estado::text,
  fecha_ingreso::date,
  telefono,
  email,
  direccion_residencia,
  fecha_ultima_actualizacion::timestamptz,
  estatus::boolean
FROM stg.socios
ORDER BY id;

INSERT INTO cuentas_ahorro
  (id, socio_id, num_cuenta, saldo_inicial, tasa_interes_anual,
   fecha_apertura, fecha_cierre, estatus)
OVERRIDING SYSTEM VALUE
SELECT
  id::bigint,
  socio_id::bigint,
  num_cuenta,
  saldo_inicial::numeric(12,2),
  tasa_interes_anual::numeric(5,2),
  fecha_apertura::timestamptz,
  fecha_cierre::timestamptz,
  estatus::boolean
FROM stg.cuentas_ahorro
ORDER BY id;

INSERT INTO tipos_credito
  (id, nombre, descripcion, monto_maximo, tasa_interes_anual,
   plazo_maximo_dias, estado)
OVERRIDING SYSTEM VALUE
SELECT
  id::bigint,
  nombre,
  descripcion,
  monto_maximo::numeric(12,2),
  tasa_interes_anual::numeric(5,2),
  plazo_maximo_dias::bigint,
  estado::text
FROM stg.tipos_credito
ORDER BY id;

INSERT INTO solicitudes_credito
  (id, socio_id, tipo_credito_id, monto_solicitado, plazo_dias,
   fecha_solicitud, fecha_aprobacion, fecha_desembolso, status, observaciones)
OVERRIDING SYSTEM VALUE
SELECT
  id::bigint,
  socio_id::bigint,
  tipo_credito_id::bigint,
  monto_solicitado::numeric(12,2),
  plazo_dias::bigint,
  fecha_solicitud::timestamptz,
  fecha_aprobacion::timestamptz,
  fecha_desembolso::timestamptz,
  status::text,
  observaciones
FROM stg.solicitudes_credito
ORDER BY id;

INSERT INTO prestamos
  (id, solicitud_id, socio_id, monto_prestado, tasa_interes_anual,
   fecha_desembolso, fecha_fin_plazo, estado, total_cuotas, pagado_total)
OVERRIDING SYSTEM VALUE
SELECT
  id::bigint,
  solicitud_id::bigint,
  socio_id::bigint,
  monto_prestado::numeric(12,2),
  tasa_interes_anual::numeric(5,2),
  fecha_desembolso::timestamptz,
  fecha_fin_plazo::date,
  estado::text,
  total_cuotas::bigint,
  pagado_total::boolean
FROM stg.prestamos
ORDER BY id;

INSERT INTO cuotas_amortizacion
  (id, prestamo_id, numero_cuota, monto_cuota, fecha_vencimiento,
   fecha_pago, estatus, monto_pagado)
OVERRIDING SYSTEM VALUE
SELECT
  id::bigint,
  prestamo_id::bigint,
  numero_cuota::bigint,
  monto_cuota::numeric(12,2),
  fecha_vencimiento::date,
  fecha_pago::timestamptz,
  estatus::text,
  monto_pagado::numeric(12,2)
FROM stg.cuotas_amortizacion
ORDER BY id;

INSERT INTO transacciones
  (id, tipo, socio_id, cuenta_ahorro_id, prestamo_id, monto,
   fecha_transaccion, descripcion)
OVERRIDING SYSTEM VALUE
SELECT
  id::bigint,
  tipo::text,
  socio_id::bigint,
  cuenta_ahorro_id::bigint,
  prestamo_id::bigint,
  monto::numeric(12,2),
  fecha_transaccion::timestamptz,
  descripcion
FROM stg.transacciones
ORDER BY id;
