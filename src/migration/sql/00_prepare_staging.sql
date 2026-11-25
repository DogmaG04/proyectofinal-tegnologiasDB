-- ============================================================================
--  Preparacion del schema de staging
--
--  Se ejecuta como postgres por socket local (provision de esquema).
--  Idempotente: elimina cualquier resto de una corrida anterior.
-- ============================================================================
\set ON_ERROR_STOP on

SET client_min_messages = warning;

DROP SCHEMA IF EXISTS stg CASCADE;
CREATE SCHEMA stg AUTHORIZATION migration_loader;

-- admin_dba valida y carga desde stg: solo necesita leer.
GRANT USAGE ON SCHEMA stg TO admin_dba;

-- Las tablas las crea pgloader como migration_loader; admin_dba debe poder
-- leerlas sin recibir privilegios de escritura sobre el staging.
ALTER DEFAULT PRIVILEGES FOR ROLE migration_loader IN SCHEMA stg
  GRANT SELECT ON TABLES TO admin_dba;
