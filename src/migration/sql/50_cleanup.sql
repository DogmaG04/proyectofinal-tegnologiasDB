-- ============================================================================
--  Limpieza del staging. Solo se ejecuta si la carga y el postcheck pasaron.
--  Se ejecuta como postgres por socket local.
-- ============================================================================
\set ON_ERROR_STOP on

DROP SCHEMA IF EXISTS stg CASCADE;
