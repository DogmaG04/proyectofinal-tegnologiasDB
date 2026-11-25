# Resumen del proyecto — Migración MySQL 5.7 → PostgreSQL 16

> **Propósito de este archivo:** servir de contexto completo para iniciar una nueva sesión
> de trabajo y continuar desde el estado actual sin necesidad de reexplicar nada.
> Copia este archivo (o pídelo) al empezar una sesión nueva.

---

## 1. Objetivo general

Reemplazar el ETL Python artesanal (`src/migration/migrate.py`) por una solución basada en
**pgloader + SQL declarativo**, tratando la base de datos como un sistema real: consistencia,
validación, rollback, seguridad y realismo operativo.

Estado de la documentación: **`README.md` y este `resumen.md` ya están actualizados**.
La documentación LaTeX ya está actualizada (`docs/contenido/05-plan-migracion.tex`,
`06-ejecucion.tex`).

---

## 2. Estado actual (verificado)

| Ítem | Resultado |
|---|---|
| Build de la imagen `migrador` | OK (pgloader 3.6.10 sobre `postgres:16`) |
| Migración completa | OK — 1.469 filas, 0 rechazos, 0 errores |
| `PRECHECK` / `POSTCHECK` / `SECUENCIAS` / `ANALYZE` | Todos OK |
| `scripts/03_verify_all.sh` | **75 PASS / 0 FAIL** |
| Roles de los 4 integrantes del equipo | OK (16 checks en `03_verify_all.sh`) |
| Evidencia | `evidence/01_inventario_origen.txt`, `02_ejecucion_migracion.txt`, `03_pruebas_y_hardening.txt` |
| Stack | Levantado (`docker compose up -d`), con datos migrados y respaldos nuevos en `backups/` |

Camino de fallo también probado: al corromper una fila en `stg`, el precheck aborta
(`PRECHECK FALLIDO: transacciones.monto no positivo (1 filas)`) y un marcador insertado en
`public` sobrevivió al `TRUNCATE` + error forzado → **rollback transaccional confirmado**.

### 2.1 Estado de ejecución: YA ESTÁ TODO CORRIDO (no es solo "listo para ejecutar")

Este punto es clave para retomar el proyecto: **no queda pendiente levantar nada ni correr
la migración por primera vez**. Todo lo siguiente se hizo realmente, varias veces, y el
entorno quedó funcionando:

1. **Contenedores ejecutándose**: `coop_horizonte_legacy` (MySQL 5.7),
   `coop_horizonte_core` (PostgreSQL 16) y `coop_horizonte_migrador` (pgloader), todos
   `healthy`. Se levantaron con `docker compose down -v` + `up -d --build` (volúmenes
   nuevos) para validar la provisión completa desde cero.
2. **Migración ejecutada de punta a punta**: `scripts/02_migrate_and_backup.sh` cargó
   1.469 filas de 8 tablas con 0 rechazos, pasó `PRECHECK`, `POSTCHECK` (comparación
   fila a fila `to_jsonb` + `EXCEPT ALL` bidireccional), `SECUENCIAS` y `ANALYZE`, y
   generó el respaldo cifrado más su prueba de restauración (55 socios). Se repitió
   para comprobar **idempotencia**.
3. **Verificación ejecutada**: `scripts/03_verify_all.sh` → 75 PASS / 0 FAIL.
4. **Evidencia real**, no plantillas: los tres archivos en `evidence/` son la salida
   capturada de esas corridas, y `backups/` contiene los respaldos generados.
5. **Pruebas negativas ejecutadas**: fila corrupta en `stg` → precheck aborta sin tocar
   `public`; error forzado dentro de la transacción → `ROLLBACK` confirmado con marcador.
6. **Usuarios del equipo verificados**: los 4 roles admin se crean con el stack y pasan
   sus 16 checks en `03_verify_all.sh` (login, no superusuario, privilegios y conexión TLS).

Consecuencia operativa:

- Si el usuario quiere **ver el resultado**, solo debe mirar `evidence/` y `backups/`
  o conectarse al PostgreSQL ya levantado.
- Si quiere **repetir la migración**, basta `./scripts/02_migrate_and_backup.sh` y
  `./scripts/03_verify_all.sh` (sin `down -v`).
- Si hace `docker compose down -v`, ahí sí se borran los volúmenes y hay que volver a
  ejecutar las tres fases (`01` → `02` → `03`) en orden.

> Matiz de realismo: los datos son los generados por el propio proyecto (semilla
> `seed=42`), no una base de producción real.

---

## 3. Arquitectura de la migración

**Staging + SQL**, con corte **big-bang controlado**:
1. Congelamiento de escrituras en MySQL (pgloader no tiene snapshot multi-tabla).
2. `mysqldump --single-transaction` del origen como respaldo.
3. `00_prepare_staging.sql` crea el schema `stg` (propiedad de `migration_loader`).
4. **pgloader** carga las 8 tablas desde MySQL directamente a `stg` (sin índices, sin FK, sin secuencias).
5. Conteos origen vs `stg`.
6. `10_precheck.sql` valida nulos, ENUM, huérfanos, rangos y fechas cero → aborta antes de tocar `public`.
7. **Una sola transacción** (`psql --single-transaction`):
   `20_load.sql` (casts + `OVERRIDING SYSTEM VALUE`) → `30_postcheck.sql` (`to_jsonb` + `EXCEPT ALL`
   bidireccional fila a fila) → `35_sequences.sql` (`setval`). Si falla, `ROLLBACK`.
8. `40_analyze.sql` como `postgres` por socket local.
9. `50_cleanup.sql` elimina `stg`.
10. Respaldo cifrado del destino (`pg_dump` + OpenSSL AES-256-CBC) y prueba de restauración.

No hay CDC (se descartó; se considera mejora futura).

---

## 4. Archivos creados

| Archivo | Contenido |
|---|---|
| `src/migration/Dockerfile` | `postgres:16` + `pgloader` + `gettext-base` + `tzdata` (sin Python) |
| `src/migration/render_load.sh` | Renderiza la plantilla `.load` con `envsubst` (lista explícita de variables) |
| `src/migration/pgloader/mysql_to_stage.load` | DSL de pgloader: 8 tablas, `ALTER SCHEMA '${MYSQL_DB}' RENAME TO 'stg'`, `on error stop`, sin índices/FK |
| `src/migration/sql/00_prepare_staging.sql` | Crea `stg` y default privileges |
| `src/migration/sql/10_precheck.sql` | Validaciones exactas; aborta con `PRECHECK FALLIDO` |
| `src/migration/sql/20_load.sql` | Casts (ENUM → `::text`, `tinyint` → boolean) e `INSERT ... OVERRIDING SYSTEM VALUE` |
| `src/migration/sql/30_postcheck.sql` | `to_jsonb` + `EXCEPT ALL` bidireccional por tabla |
| `src/migration/sql/35_sequences.sql` | `setval` de las 8 secuencias y verificación |
| `src/migration/sql/40_analyze.sql` | Estadísticas del planificador (como `postgres`) |
| `src/migration/sql/50_cleanup.sql` | `DROP SCHEMA stg CASCADE` |

## 5. Archivos modificados

| Archivo | Cambio |
|---|---|
| `scripts/02_migrate_and_backup.sh` | Reescrito por completo: flujo pgloader + precheck + transacción + ANALYZE + cleanup + respaldos. Conservative `stg` y rechazos en `/tmp/pgloader-work` si falla. |
| `scripts/03_verify_all.sh` | +18 checks (staging, loader, secuencias) y +16 checks de los 4 usuarios admin (75 en total). |
| `scripts/lib.sh` | `psql_admin` con `-X`, nuevo `psql_dba` (TLS `verify-ca`), `count_stage`. |
| `src/target/02_hardening_roles.sql` | Rol `migration_loader` + 4 roles de administradores del equipo. |
| `src/target/pg_hba.conf` | Reglas `hostssl` para `migration_loader` y los 4 administradores. |
| `docker-compose.yml` | Variables libpq estándar (`PGHOST/PGPORT/PGDATABASE/PGUSER/PGPASSWORD`), `MIGRATION_LOADER_*`, `SSL_CERT_FILE`. |
| `.env` / `.env.example` | `MIGRATION_LOADER_PASSWORD`, `ADMIN_TEAM_PASSWORD`. |

## 6. Archivos movidos / eliminados

- `src/migration/migrate.py` → **`src/migration/legacy/migrate.py`** (archivado como legado, no se ejecuta).
- No se eliminó ningún otro archivo.

### Variables de entorno nuevas

```ini
MIGRATION_LOADER_PASSWORD=migration_loader_pass   # .env ; en .env.example: cambiar_migration_loader
ADMIN_TEAM_PASSWORD=sudoers123                    # .env y .env.example
PGSSLMODE=verify-ca
PGSSLROOTCERT=/etc/postgresql/ssl/server.crt
SSL_CERT_FILE=/etc/postgresql/ssl/server.crt
```

---

## 7. Roles en PostgreSQL (estado final)

| Rol | Perfil |
|---|---|
| `admin_dba` | Administración: `CREATEDB`, `CREATEROLE`, sin `SUPERUSER`, `NOINHERIT`, password `admin_dba_pass` |
| `app_core_rw` | DML de aplicación, sin DDL ni TRUNCATE |
| `auditor_ro` | Solo lectura de vistas enmascaradas |
| `migration_loader` | NOSUPERUSER/NOCREATEDB/NOCREATEROLE/NOINHERIT, `search_path='stg'`, sin acceso a `public` |
| **`nicolas`, `joaquin`, `david`, `gustavo`** | **Perfil administrativo equivalente a `admin_dba`, password `sudoers123`** |

Los cuatro usuarios nuevos:
- Se crean/actualizan en un bloque `DO $$ ... FOREACH ...` en `src/target/02_hardening_roles.sql`
  al levantar el stack, igual que el resto de los roles.
- Tienen `GRANT CONNECT`, `USAGE` en `public` y `ALL` sobre tablas, secuencias y funciones.
- `ALTER DEFAULT PRIVILEGES` para objetos futuros.
- Reglas `hostssl ... scram-sha-256` (IPv4 e IPv6) en `src/target/pg_hba.conf`.
- 16 checks en `03_verify_all.sh` (login, no superusuario, privilegio de admin, conexión TLS real).

> Estos usuarios existen para que cada integrante, al correr el proyecto en **su propia
> laptop** desde el `.zip`, pueda acceder al PostgreSQL de su entorno después de la
> migración y verificar los resultados. **No se documenta acceso remoto**: cada copia
> del stack corre de forma local y el puerto queda publicado en `127.0.0.1`.

---

## 8. Decisiones tomadas

- pgloader **3.6.x estable**, no v4 pre-release.
- Staging + SQL en vez de carga directa.
- Big-bang controlado con freeze de escrituras; **sin CDC**.
- `migrate.py` archivado como legado.
- Validación **SQL exacta**: conteos, `EXCEPT ALL` bidireccional, FK y secuencias.
- **Extras rechazados explícitamente:** `migration_reader` en MySQL, índices case-insensitive,
  trigger de `fecha_ultima_actualizacion`, `04_test_rollback.sh`.
- `app_legacy_user` (con `GRANT ALL`) se sigue usando para lectura del origen: **deuda técnica**.

---

## 9. Hallazgos técnicos que obligaron a ajustar el plan

1. **`postgres:16` hoy es Debian 13 (trixie)**: paquete disponible es `pgloader 3.6.10`, no 3.6.9.
   Misma rama estable 3.6.x.
2. **`sslmode=require` en pgloader 3.6.10 sí verifica el certificado** y `--no-ssl-cert-verification`
   no lo desactiva. Solución real: `SSL_CERT_FILE=/etc/postgresql/ssl/server.crt`. No se degradó a `prefer`.
3. **`create no schema` no existe para MySQL**: pgloader crea un schema con el nombre de la base origen.
   Se resolvió con `ALTER SCHEMA '${MYSQL_DB}' RENAME TO 'stg'` (en memoria). No hace falta dar
   `CREATE` sobre la base a `migration_loader`.
4. **`ANALYZE` exige ser dueño en PostgreSQL 16** (`MAINTAIN` recién aparece en 17): se ejecuta
   como `postgres` por socket local. El resto del camino de datos va como `admin_dba` por TLS.
5. pgloader escribe rechazos en `/tmp/pgloader/` por defecto → se usa `--root-dir /tmp/pgloader-work`.
6. Tags flotantes (`postgres:16`, `mysql:5.7`) sin fijar por digest.

---

## 10. Cómo ejecutar y validar

```bash
cd /home/dogma/Proyectos/proyectofinal-tegnologiasDB

# Reinicio limpio (borra volúmenes)
docker compose down -v --remove-orphans
docker compose up -d --build

# Auditoría del origen
./scripts/01_audit_origin.sh

# Migración + respaldo cifrado + prueba de restauración
./scripts/02_migrate_and_backup.sh

# Verificación completa (75 checks)
./scripts/03_verify_all.sh
```

Evidencia en `evidence/`. Respaldo cifrado y dump de prueba en `backups/`.

---

## 11. Pendiente / próximos pasos

1. **Documentación** (completada):
   - ✅ `docs/contenido/05-plan-migracion.tex`: capítulo reescrito con la arquitectura
     pgloader + staging + validación + rollback.
   - ✅ `docs/contenido/06-ejecucion.tex`: evidencia actualizada (1.469 filas, 0 rechazos, 75 PASS).
   - ✅ `docs/anexos/codigo/Dockerfile` y `docs/anexos/codigo/docker-compose.yml.txt`: actualizados
     a la herramienta y variables vigentes.
   - ✅ `README.md` y `resumen.md`: actualizados con la herramienta actual, variables
     nuevas, `migrate.py` en `legacy/`, los 4 usuarios admin y el estado de ejecución real.
2. Reducir privilegios de `app_legacy_user` en MySQL (deuda técnica acordada).

> Cada integrante ejecutará su propia copia del proyecto desde el `.zip`, en su laptop,
> sin acceso remoto a una instancia compartida.
