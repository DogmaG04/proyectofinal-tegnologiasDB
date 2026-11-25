-- ============================================================================
--  SECUENCIAS: alinea cada secuencia de identidad con MAX(id).
--
--  Se ejecuta despues del postcheck y dentro de la misma transaccion para que
--  un fallo previo no deje las secuencias avanzadas (setval no es transaccional).
-- ============================================================================
\set ON_ERROR_STOP on

SET client_min_messages = warning;

DO $$
DECLARE
  t text;
  m bigint;
  seq text;
  lv bigint;
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
    seq := pg_get_serial_sequence(format('public.%I', t), 'id');
    IF seq IS NULL THEN
      RAISE EXCEPTION 'SECUENCIAS FALLIDO: no hay secuencia de identidad para public.%', t;
    END IF;

    EXECUTE format('SELECT COALESCE(max(id), 0) FROM public.%I', t) INTO m;

    IF m > 0 THEN
      PERFORM setval(seq::regclass, m, true);
    ELSE
      PERFORM setval(seq::regclass, 1, false);
    END IF;

    EXECUTE format('SELECT last_value FROM %s', seq::regclass) INTO lv;
    IF lv <> GREATEST(m, 1) THEN
      RAISE EXCEPTION 'SECUENCIAS FALLIDO: % last_value=% esperado=%',
        t, lv, GREATEST(m, 1);
    END IF;

    RAISE NOTICE 'SECUENCIAS OK: % -> %', t, lv;
  END LOOP;
END;
$$;

\echo 'SECUENCIAS OK: todas alineadas con MAX(id).'
