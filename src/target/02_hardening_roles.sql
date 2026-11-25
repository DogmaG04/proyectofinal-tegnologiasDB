-- ============================================================================
--  HARDENING DE ROLES - PostgreSQL 16
--  Cooperativa de Ahorro y Credito Horizonte PyME S.R.L.
--  Ejecutar DESPUES de 01_schema_target.sql (requiere las tablas creadas).
-- ============================================================================

SET TIME ZONE 'America/La_Paz';

-- ----------------------------------------------------------------------------
-- 1. Revocar privilegios de PUBLIC (minimo privilegio)
-- ----------------------------------------------------------------------------
REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
REVOKE CONNECT ON DATABASE coop_horizonte_core FROM PUBLIC;

-- ----------------------------------------------------------------------------
-- 2. Roles de minimo privilegio
--    admin_dba  : administracion (CREATEDB/CREATEROLE, sin SUPERUSER)
--    app_core_rw: aplicacion (DML, sin DDL)
--    auditor_ro : auditoria (solo lectura, sin datos sensibles directos)
--    nicolas, joaquin, david, gustavo: administradores del equipo
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  u text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'admin_dba') THEN
    EXECUTE format('CREATE ROLE admin_dba WITH LOGIN NOSUPERUSER CREATEDB CREATEROLE NOINHERIT PASSWORD %L', 'admin_dba_pass');
  ELSE
    EXECUTE format('ALTER ROLE admin_dba WITH LOGIN NOSUPERUSER CREATEDB CREATEROLE NOINHERIT PASSWORD %L', 'admin_dba_pass');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_core_rw') THEN
    EXECUTE format('CREATE ROLE app_core_rw WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT PASSWORD %L', 'app_core_rw_pass');
  ELSE
    EXECUTE format('ALTER ROLE app_core_rw WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT PASSWORD %L', 'app_core_rw_pass');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'auditor_ro') THEN
    EXECUTE format('CREATE ROLE auditor_ro WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT PASSWORD %L', 'auditor_ro_pass');
  ELSE
    EXECUTE format('ALTER ROLE auditor_ro WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT PASSWORD %L', 'auditor_ro_pass');
  END IF;

  -- Rol efimero de carga: solo puede operar sobre el schema de staging.
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'migration_loader') THEN
    EXECUTE format('CREATE ROLE migration_loader WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT PASSWORD %L', 'migration_loader_pass');
  ELSE
    EXECUTE format('ALTER ROLE migration_loader WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT PASSWORD %L', 'migration_loader_pass');
  END IF;

  -- Integrantes del equipo: perfil administrativo equivalente a admin_dba.
  -- Password unico de laboratorio acordado por el equipo.
  FOREACH u IN ARRAY ARRAY['nicolas', 'joaquin', 'david', 'gustavo']
  LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = u) THEN
      EXECUTE format('CREATE ROLE %I WITH LOGIN NOSUPERUSER CREATEDB CREATEROLE NOINHERIT PASSWORD %L', u, 'sudoers123');
    ELSE
      EXECUTE format('ALTER ROLE %I WITH LOGIN NOSUPERUSER CREATEDB CREATEROLE NOINHERIT PASSWORD %L', u, 'sudoers123');
    END IF;
    EXECUTE format('COMMENT ON ROLE %I IS %L', u,
                   'Administrador del equipo (perfil equivalente a admin_dba)');
  END LOOP;
END
$$;

-- El loader no debe resolver nombres contra public ni heredar privilegios.
ALTER ROLE migration_loader SET search_path = 'stg';

-- ----------------------------------------------------------------------------
-- 3. Vista enmascarada para auditoria (oculta digitos de CI/NIT y cuentas)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_socios_audit AS
SELECT
  s.id,
  s.nombre_completo,
  CASE WHEN s.numero_identificacion IS NULL THEN NULL
       ELSE '****' || right(s.numero_identificacion, 4) END AS ci_nit,
  s.fecha_nacimiento,
  s.genero,
  s.estado,
  s.fecha_ingreso,
  CASE WHEN s.telefono IS NULL THEN NULL
       ELSE '****' || right(s.telefono, 4) END AS telefono,
  CASE WHEN s.email IS NULL THEN NULL
       ELSE '****@' || split_part(s.email, '@', 2) END AS email,
  COALESCE(string_agg(CASE WHEN ca.num_cuenta IS NULL THEN NULL
                           ELSE '****' || right(ca.num_cuenta, 4) END,
                      ', ' ORDER BY ca.id), 'Sin cuenta') AS numero_cuenta,
  COUNT(ca.id) AS total_cuentas,
  COALESCE(SUM(CASE WHEN ca.estatus THEN ca.saldo_inicial ELSE 0 END), 0) AS saldo_total_activo
FROM socios s
LEFT JOIN cuentas_ahorro ca ON ca.socio_id = s.id
GROUP BY s.id, s.nombre_completo, s.numero_identificacion, s.fecha_nacimiento,
         s.genero, s.estado, s.fecha_ingreso, s.telefono, s.email;

COMMENT ON VIEW vw_socios_audit IS
  'Vista de auditoria con CI/NIT, telefono, email y numeros de cuenta enmascarados';

-- ----------------------------------------------------------------------------
-- 4. Grants por rol
-- ----------------------------------------------------------------------------
GRANT CONNECT ON DATABASE coop_horizonte_core TO admin_dba, app_core_rw, auditor_ro, migration_loader;
GRANT USAGE ON SCHEMA public TO admin_dba, app_core_rw, auditor_ro;

-- migration_loader: sin acceso al esquema endurecido. Solo opera sobre stg,
-- schema que se crea y destruye en cada corrida de migracion.
REVOKE ALL ON SCHEMA public FROM migration_loader;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM migration_loader;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM migration_loader;

-- admin_dba: administracion completa del esquema
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO admin_dba;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO admin_dba;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO admin_dba;

-- Integrantes del equipo: mismo perfil administrativo que admin_dba
GRANT CONNECT ON DATABASE coop_horizonte_core TO nicolas, joaquin, david, gustavo;
GRANT USAGE ON SCHEMA public TO nicolas, joaquin, david, gustavo;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO nicolas, joaquin, david, gustavo;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO nicolas, joaquin, david, gustavo;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO nicolas, joaquin, david, gustavo;

-- app_core_rw: DML, sin DDL ni TRUNCATE
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_core_rw;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_core_rw;

-- auditor_ro: lectura general...
GRANT SELECT ON ALL TABLES IN SCHEMA public TO auditor_ro;
-- ...pero sin acceso directo a datos sensibles ni a vistas que los expongan
REVOKE SELECT ON socios FROM auditor_ro;
REVOKE SELECT ON cuentas_ahorro FROM auditor_ro;
REVOKE SELECT ON vw_cartera_mora FROM auditor_ro;
GRANT SELECT ON vw_socios_audit TO auditor_ro;
GRANT SELECT ON vw_resumen_saldos_socio TO auditor_ro;

-- ----------------------------------------------------------------------------
-- 5. Privilegios por defecto para objetos futuros
-- ----------------------------------------------------------------------------
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO auditor_ro;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_core_rw;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO app_core_rw;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO admin_dba;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO admin_dba;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO nicolas, joaquin, david, gustavo;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO nicolas, joaquin, david, gustavo;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM PUBLIC;

-- ----------------------------------------------------------------------------
-- 6. Documentacion de roles
-- ----------------------------------------------------------------------------
COMMENT ON ROLE admin_dba IS 'Administracion de la base: CREATEDB/CREATEROLE, sin SUPERUSER';
COMMENT ON ROLE app_core_rw IS 'Aplicacion core: DML sobre schema public, sin DDL';
COMMENT ON ROLE auditor_ro IS 'Auditoria: lectura de tablas no sensibles y vista enmascarada';
COMMENT ON ROLE migration_loader IS 'Carga pgloader: solo schema stg, sin acceso a public';
