-- ============================================================================
--  POSTCHECK: compara public contra stg dentro de la misma transaccion.
--
--  Se comparan filas completas como jsonb: evita problemas de orden de
--  columnas y de tipos (enum en staging vs varchar en public).
--  Cualquier diferencia aborta la transaccion y public vuelve a su estado
--  anterior.
-- ============================================================================
\set ON_ERROR_STOP on

SET TIME ZONE 'America/La_Paz';
SET client_min_messages = warning;

DO $$
DECLARE
  t text;
  n_public bigint;
  n_stg bigint;
  n_diff bigint;
  tablas text[] := ARRAY[
    'sucursales',
    'socios',
    'cuentas_ahorro',
    'tipos_credito',
    'solicitudes_credito',
    'prestamos',
    'cuotas_amortizacion',
    'transacciones'
  ];
BEGIN
  FOREACH t IN ARRAY tablas LOOP
    EXECUTE format('SELECT count(*) FROM public.%I', t) INTO n_public;
    EXECUTE format('SELECT count(*) FROM stg.%I', t) INTO n_stg;

    IF n_public <> n_stg THEN
      RAISE EXCEPTION 'POSTCHECK FALLIDO: % tiene % filas en public y % en stg',
        t, n_public, n_stg;
    END IF;

    EXECUTE format($f$
      SELECT count(*) FROM (
        (SELECT to_jsonb(x) FROM public.%1$I x
         EXCEPT ALL
         SELECT to_jsonb(y) FROM stg.%1$I y)
        UNION ALL
        (SELECT to_jsonb(x) FROM stg.%1$I x
         EXCEPT ALL
         SELECT to_jsonb(y) FROM public.%1$I y)
      ) d
    $f$, t) INTO n_diff;

    IF n_diff <> 0 THEN
      RAISE EXCEPTION 'POSTCHECK FALLIDO: % tiene % filas con diferencias de valor',
        t, n_diff;
    END IF;

    RAISE NOTICE 'POSTCHECK OK: % (% filas identicas)', t, n_public;
  END LOOP;
END;
$$;

-- ----------------------------------------------------------------------------
-- Integridad referencial sobre el destino ya cargado
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  r record;
  n bigint;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('cuentas_ahorro',     'socio_id',         'socios',              'id'),
      ('solicitudes_credito','socio_id',         'socios',              'id'),
      ('solicitudes_credito','tipo_credito_id',  'tipos_credito',       'id'),
      ('prestamos',          'solicitud_id',     'solicitudes_credito', 'id'),
      ('prestamos',          'socio_id',         'socios',              'id'),
      ('cuotas_amortizacion','prestamo_id',      'prestamos',           'id'),
      ('transacciones',      'socio_id',         'socios',              'id'),
      ('transacciones',      'cuenta_ahorro_id', 'cuentas_ahorro',      'id'),
      ('transacciones',      'prestamo_id',      'prestamos',           'id')
    ) AS f(child, ccol, parent, pcol)
  LOOP
    EXECUTE format(
      'SELECT count(*) FROM public.%I c LEFT JOIN public.%I p ON c.%I = p.%I
       WHERE c.%I IS NOT NULL AND p.%I IS NULL',
      r.child, r.parent, r.ccol, r.pcol, r.ccol, r.pcol) INTO n;
    IF n > 0 THEN
      RAISE EXCEPTION 'POSTCHECK FALLIDO: % huerfanos en public.%.%', n, r.child, r.ccol;
    END IF;
  END LOOP;
END;
$$;

\echo 'POSTCHECK OK: public y stg son identicos.'
