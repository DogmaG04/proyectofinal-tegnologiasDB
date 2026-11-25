-- ============================================================================
--  Estadisticas para el planificador tras una carga completa.
--
--  Se ejecuta como postgres por socket local: en PostgreSQL 16 ANALYZE exige
--  ser dueno de la tabla (MAINTAIN recien aparece en PostgreSQL 17).
-- ============================================================================
\set ON_ERROR_STOP on

SET client_min_messages = warning;

ANALYZE public.sucursales;
ANALYZE public.socios;
ANALYZE public.cuentas_ahorro;
ANALYZE public.tipos_credito;
ANALYZE public.solicitudes_credito;
ANALYZE public.prestamos;
ANALYZE public.cuotas_amortizacion;
ANALYZE public.transacciones;

\echo 'ANALYZE OK.'
