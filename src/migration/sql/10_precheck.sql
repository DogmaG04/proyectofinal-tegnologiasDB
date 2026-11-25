-- ============================================================================
--  PRECHECK: valida el contenido de stg ANTES de tocar public.
--
--  Cualquier violacion aborta con una excepcion. Como este archivo se ejecuta
--  fuera de la transaccion de carga, public queda intacto.
--
--  Ejecutar como admin_dba (solo lectura sobre stg).
-- ============================================================================
\set ON_ERROR_STOP on

SET TIME ZONE 'America/La_Paz';
SET client_min_messages = warning;

CREATE OR REPLACE FUNCTION pg_temp.assert_no_rows(p_label text, p_sql text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  n bigint;
BEGIN
  EXECUTE p_sql INTO n;
  IF n > 0 THEN
    RAISE EXCEPTION 'PRECHECK FALLIDO: % (% filas)', p_label, n;
  END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- 1. Columnas NOT NULL del esquema destino
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  r record;
  n bigint;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('sucursales','id'),
      ('sucursales','nombre'),
      ('sucursales','fecha_creacion'),
      ('sucursales','estatus'),
      ('socios','id'),
      ('socios','nombre_completo'),
      ('socios','genero'),
      ('socios','estado'),
      ('socios','fecha_ingreso'),
      ('socios','fecha_ultima_actualizacion'),
      ('socios','estatus'),
      ('cuentas_ahorro','id'),
      ('cuentas_ahorro','socio_id'),
      ('cuentas_ahorro','saldo_inicial'),
      ('cuentas_ahorro','tasa_interes_anual'),
      ('cuentas_ahorro','fecha_apertura'),
      ('cuentas_ahorro','estatus'),
      ('tipos_credito','id'),
      ('tipos_credito','nombre'),
      ('tipos_credito','monto_maximo'),
      ('tipos_credito','tasa_interes_anual'),
      ('tipos_credito','plazo_maximo_dias'),
      ('tipos_credito','estado'),
      ('solicitudes_credito','id'),
      ('solicitudes_credito','socio_id'),
      ('solicitudes_credito','tipo_credito_id'),
      ('solicitudes_credito','monto_solicitado'),
      ('solicitudes_credito','plazo_dias'),
      ('solicitudes_credito','fecha_solicitud'),
      ('solicitudes_credito','status'),
      ('prestamos','id'),
      ('prestamos','solicitud_id'),
      ('prestamos','socio_id'),
      ('prestamos','monto_prestado'),
      ('prestamos','tasa_interes_anual'),
      ('prestamos','fecha_desembolso'),
      ('prestamos','fecha_fin_plazo'),
      ('prestamos','estado'),
      ('prestamos','total_cuotas'),
      ('prestamos','pagado_total'),
      ('cuotas_amortizacion','id'),
      ('cuotas_amortizacion','prestamo_id'),
      ('cuotas_amortizacion','numero_cuota'),
      ('cuotas_amortizacion','monto_cuota'),
      ('cuotas_amortizacion','fecha_vencimiento'),
      ('cuotas_amortizacion','estatus'),
      ('cuotas_amortizacion','monto_pagado'),
      ('transacciones','id'),
      ('transacciones','tipo'),
      ('transacciones','monto'),
      ('transacciones','fecha_transaccion')
    ) AS t(tabla, columna)
  LOOP
    EXECUTE format('SELECT count(*) FROM stg.%I WHERE %I IS NULL', r.tabla, r.columna)
      INTO n;
    IF n > 0 THEN
      RAISE EXCEPTION 'PRECHECK FALLIDO: %.% tiene % valores nulos', r.tabla, r.columna, n;
    END IF;
  END LOOP;
END;
$$;

-- ----------------------------------------------------------------------------
-- 2. Dominios ENUM (en staging pueden ser tipo enum o text segun pgloader)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  r record;
  n bigint;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('socios',                'genero',  ARRAY['M','F','O']),
      ('socios',                'estado',  ARRAY['activo','inactivo','suspendido']),
      ('tipos_credito',         'estado',  ARRAY['activo','inactivo','suspendido']),
      ('solicitudes_credito',   'status',  ARRAY['pendiente','aprobada','rechazada','cancelada']),
      ('prestamos',             'estado',  ARRAY['activo','pagado','moroso','cancelado']),
      ('cuotas_amortizacion',   'estatus', ARRAY['pendiente','pagada','atrasada']),
      ('transacciones',         'tipo',    ARRAY['deposito','retiro','pago_cuota','desembolso','transferencia'])
    ) AS t(tabla, columna, permitidos)
  LOOP
    EXECUTE format('SELECT count(*) FROM stg.%I WHERE %I::text <> ALL($1)', r.tabla, r.columna)
      INTO n USING r.permitidos;
    IF n > 0 THEN
      RAISE EXCEPTION 'PRECHECK FALLIDO: %.% tiene % valores fuera de dominio', r.tabla, r.columna, n;
    END IF;
  END LOOP;
END;
$$;

-- ----------------------------------------------------------------------------
-- 3. Unicidad e integridad que el origen no puede garantizar por si mismo
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('sucursales',           'SELECT count(*) FROM (SELECT id FROM stg.sucursales GROUP BY id HAVING count(*) > 1) d'),
      ('socios',               'SELECT count(*) FROM (SELECT id FROM stg.socios GROUP BY id HAVING count(*) > 1) d'),
      ('cuentas_ahorro',       'SELECT count(*) FROM (SELECT id FROM stg.cuentas_ahorro GROUP BY id HAVING count(*) > 1) d'),
      ('tipos_credito',        'SELECT count(*) FROM (SELECT id FROM stg.tipos_credito GROUP BY id HAVING count(*) > 1) d'),
      ('solicitudes_credito',  'SELECT count(*) FROM (SELECT id FROM stg.solicitudes_credito GROUP BY id HAVING count(*) > 1) d'),
      ('prestamos',            'SELECT count(*) FROM (SELECT id FROM stg.prestamos GROUP BY id HAVING count(*) > 1) d'),
      ('cuotas_amortizacion',  'SELECT count(*) FROM (SELECT id FROM stg.cuotas_amortizacion GROUP BY id HAVING count(*) > 1) d'),
      ('transacciones',        'SELECT count(*) FROM (SELECT id FROM stg.transacciones GROUP BY id HAVING count(*) > 1) d'),
      ('socios.numero_identificacion', 'SELECT count(*) FROM (SELECT lower(btrim(numero_identificacion)) FROM stg.socios WHERE numero_identificacion IS NOT NULL GROUP BY 1 HAVING count(*) > 1) d'),
      ('cuentas_ahorro.num_cuenta',    'SELECT count(*) FROM (SELECT lower(btrim(num_cuenta)) FROM stg.cuentas_ahorro WHERE num_cuenta IS NOT NULL GROUP BY 1 HAVING count(*) > 1) d'),
      ('prestamos.solicitud_id',       'SELECT count(*) FROM (SELECT solicitud_id FROM stg.prestamos GROUP BY solicitud_id HAVING count(*) > 1) d'),
      ('cuotas_amortizacion(prestamo_id,numero_cuota)', 'SELECT count(*) FROM (SELECT prestamo_id, numero_cuota FROM stg.cuotas_amortizacion GROUP BY 1, 2 HAVING count(*) > 1) d')
    ) AS t(etiqueta, sentencia)
  LOOP
    PERFORM pg_temp.assert_no_rows(r.etiqueta || ' duplicado', r.sentencia);
  END LOOP;
END;
$$;

-- ----------------------------------------------------------------------------
-- 4. Huerfanos de las 9 claves foraneas del destino
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  r record;
  n bigint;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('cuentas_ahorro',     'socio_id',          'socios',              'id'),
      ('solicitudes_credito','socio_id',          'socios',              'id'),
      ('solicitudes_credito','tipo_credito_id',   'tipos_credito',       'id'),
      ('prestamos',          'solicitud_id',      'solicitudes_credito', 'id'),
      ('prestamos',          'socio_id',          'socios',              'id'),
      ('cuotas_amortizacion','prestamo_id',       'prestamos',           'id'),
      ('transacciones',      'socio_id',          'socios',              'id'),
      ('transacciones',      'cuenta_ahorro_id',  'cuentas_ahorro',      'id'),
      ('transacciones',      'prestamo_id',       'prestamos',           'id')
    ) AS f(child, ccol, parent, pcol)
  LOOP
    EXECUTE format(
      'SELECT count(*) FROM stg.%I c LEFT JOIN stg.%I p ON c.%I = p.%I WHERE c.%I IS NOT NULL AND p.%I IS NULL',
      r.child, r.parent, r.ccol, r.pcol, r.ccol, r.pcol) INTO n;
    IF n > 0 THEN
      RAISE EXCEPTION 'PRECHECK FALLIDO: % huerfanos en %.%', n, r.child, r.ccol;
    END IF;
  END LOOP;
END;
$$;

-- ----------------------------------------------------------------------------
-- 5. Rangos numericos
-- ----------------------------------------------------------------------------
SELECT pg_temp.assert_no_rows('cuentas_ahorro.saldo_inicial negativo',
  'SELECT count(*) FROM stg.cuentas_ahorro WHERE saldo_inicial < 0');
SELECT pg_temp.assert_no_rows('cuentas_ahorro.tasa_interes_anual negativa',
  'SELECT count(*) FROM stg.cuentas_ahorro WHERE tasa_interes_anual < 0');
SELECT pg_temp.assert_no_rows('tipos_credito.monto_maximo no positivo',
  'SELECT count(*) FROM stg.tipos_credito WHERE monto_maximo <= 0');
SELECT pg_temp.assert_no_rows('tipos_credito.tasa_interes_anual negativa',
  'SELECT count(*) FROM stg.tipos_credito WHERE tasa_interes_anual < 0');
SELECT pg_temp.assert_no_rows('tipos_credito.plazo_maximo_dias no positivo',
  'SELECT count(*) FROM stg.tipos_credito WHERE plazo_maximo_dias <= 0');
SELECT pg_temp.assert_no_rows('solicitudes_credito.monto_solicitado no positivo',
  'SELECT count(*) FROM stg.solicitudes_credito WHERE monto_solicitado <= 0');
SELECT pg_temp.assert_no_rows('solicitudes_credito.plazo_dias no positivo',
  'SELECT count(*) FROM stg.solicitudes_credito WHERE plazo_dias <= 0');
SELECT pg_temp.assert_no_rows('prestamos.monto_prestado no positivo',
  'SELECT count(*) FROM stg.prestamos WHERE monto_prestado <= 0');
SELECT pg_temp.assert_no_rows('prestamos.tasa_interes_anual negativa',
  'SELECT count(*) FROM stg.prestamos WHERE tasa_interes_anual < 0');
SELECT pg_temp.assert_no_rows('prestamos.total_cuotas no positivo',
  'SELECT count(*) FROM stg.prestamos WHERE total_cuotas <= 0');
SELECT pg_temp.assert_no_rows('cuotas_amortizacion.numero_cuota no positivo',
  'SELECT count(*) FROM stg.cuotas_amortizacion WHERE numero_cuota <= 0');
SELECT pg_temp.assert_no_rows('cuotas_amortizacion.monto_cuota no positivo',
  'SELECT count(*) FROM stg.cuotas_amortizacion WHERE monto_cuota <= 0');
SELECT pg_temp.assert_no_rows('cuotas_amortizacion.monto_pagado negativo',
  'SELECT count(*) FROM stg.cuotas_amortizacion WHERE monto_pagado < 0');
SELECT pg_temp.assert_no_rows('transacciones.monto no positivo',
  'SELECT count(*) FROM stg.transacciones WHERE monto <= 0');

-- ----------------------------------------------------------------------------
-- 6. Longitudes maximas del destino
-- ----------------------------------------------------------------------------
SELECT pg_temp.assert_no_rows('sucursales.nombre excede 100',
  'SELECT count(*) FROM stg.sucursales WHERE length(nombre) > 100');
SELECT pg_temp.assert_no_rows('sucursales.direccion excede 200',
  'SELECT count(*) FROM stg.sucursales WHERE length(direccion) > 200');
SELECT pg_temp.assert_no_rows('sucursales.telefono excede 20',
  'SELECT count(*) FROM stg.sucursales WHERE length(telefono) > 20');
SELECT pg_temp.assert_no_rows('socios.nombre_completo excede 150',
  'SELECT count(*) FROM stg.socios WHERE length(nombre_completo) > 150');
SELECT pg_temp.assert_no_rows('socios.numero_identificacion excede 20',
  'SELECT count(*) FROM stg.socios WHERE length(numero_identificacion) > 20');
SELECT pg_temp.assert_no_rows('socios.telefono excede 20',
  'SELECT count(*) FROM stg.socios WHERE length(telefono) > 20');
SELECT pg_temp.assert_no_rows('socios.email excede 100',
  'SELECT count(*) FROM stg.socios WHERE length(email) > 100');
SELECT pg_temp.assert_no_rows('cuentas_ahorro.num_cuenta excede 30',
  'SELECT count(*) FROM stg.cuentas_ahorro WHERE length(num_cuenta) > 30');
SELECT pg_temp.assert_no_rows('tipos_credito.nombre excede 80',
  'SELECT count(*) FROM stg.tipos_credito WHERE length(nombre) > 80');
SELECT pg_temp.assert_no_rows('transacciones.descripcion excede 255',
  'SELECT count(*) FROM stg.transacciones WHERE length(descripcion) > 255');

-- ----------------------------------------------------------------------------
-- 7. Coherencia temporal (incluye fechas cero y orden logico)
-- ----------------------------------------------------------------------------
SELECT pg_temp.assert_no_rows('sucursales.fecha_creacion anterior a 1900',
  'SELECT count(*) FROM stg.sucursales WHERE fecha_creacion < TIMESTAMPTZ ''1900-01-01''');
SELECT pg_temp.assert_no_rows('socios.fecha_nacimiento fuera de rango',
  'SELECT count(*) FROM stg.socios WHERE fecha_nacimiento IS NOT NULL AND (fecha_nacimiento < DATE ''1900-01-01'' OR fecha_nacimiento > CURRENT_DATE)');
SELECT pg_temp.assert_no_rows('socios.fecha_ingreso anterior a 1900',
  'SELECT count(*) FROM stg.socios WHERE fecha_ingreso < DATE ''1900-01-01''');
SELECT pg_temp.assert_no_rows('socios.fecha_ultima_actualizacion anterior a 1900',
  'SELECT count(*) FROM stg.socios WHERE fecha_ultima_actualizacion < TIMESTAMPTZ ''1900-01-01''');
SELECT pg_temp.assert_no_rows('cuentas_ahorro.fecha_apertura anterior a 1900',
  'SELECT count(*) FROM stg.cuentas_ahorro WHERE fecha_apertura < TIMESTAMPTZ ''1900-01-01''');
SELECT pg_temp.assert_no_rows('cuentas_ahorro.fecha_cierre anterior a fecha_apertura',
  'SELECT count(*) FROM stg.cuentas_ahorro WHERE fecha_cierre IS NOT NULL AND fecha_cierre < fecha_apertura');
SELECT pg_temp.assert_no_rows('solicitudes_credito.fecha_solicitud anterior a 1900',
  'SELECT count(*) FROM stg.solicitudes_credito WHERE fecha_solicitud < TIMESTAMPTZ ''1900-01-01''');
SELECT pg_temp.assert_no_rows('solicitudes_credito.fecha_aprobacion anterior a fecha_solicitud',
  'SELECT count(*) FROM stg.solicitudes_credito WHERE fecha_aprobacion IS NOT NULL AND fecha_aprobacion < fecha_solicitud');
SELECT pg_temp.assert_no_rows('solicitudes_credito.fecha_desembolso anterior a fecha_solicitud',
  'SELECT count(*) FROM stg.solicitudes_credito WHERE fecha_desembolso IS NOT NULL AND fecha_desembolso < fecha_solicitud');
SELECT pg_temp.assert_no_rows('prestamos.fecha_desembolso anterior a 1900',
  'SELECT count(*) FROM stg.prestamos WHERE fecha_desembolso < TIMESTAMPTZ ''1900-01-01''');
SELECT pg_temp.assert_no_rows('prestamos.fecha_fin_plazo anterior a fecha_desembolso',
  'SELECT count(*) FROM stg.prestamos WHERE fecha_fin_plazo < fecha_desembolso::date');
SELECT pg_temp.assert_no_rows('cuotas_amortizacion.fecha_vencimiento anterior a 1900',
  'SELECT count(*) FROM stg.cuotas_amortizacion WHERE fecha_vencimiento < DATE ''1900-01-01''');
SELECT pg_temp.assert_no_rows('cuotas_amortizacion.fecha_pago anterior a 1900',
  'SELECT count(*) FROM stg.cuotas_amortizacion WHERE fecha_pago IS NOT NULL AND fecha_pago < TIMESTAMPTZ ''1900-01-01''');
SELECT pg_temp.assert_no_rows('transacciones.fecha_transaccion anterior a 1900',
  'SELECT count(*) FROM stg.transacciones WHERE fecha_transaccion < TIMESTAMPTZ ''1900-01-01''');

\echo 'PRECHECK OK: staging consistente con el esquema destino.'
