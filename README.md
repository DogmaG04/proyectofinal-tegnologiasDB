# Migración MySQL 5.7 → PostgreSQL 16 — Cooperativa Horizonte PyME S.R.L.

Proyecto final de **Tecnología de Base de Datos I**. Migración heterogénea,
endurecimiento de PostgreSQL y documentación reproducible, ejecutada
íntegramente con **Docker Compose** (sin instalar motores en el host).

La carga se hace con **pgloader 3.6.10 + SQL declarativo** (staging → validación →
`public` en una sola transacción). El ETL Python original quedó archivado en
`src/migration/legacy/migrate.py` como referencia histórica; **no se ejecuta**.

## Ramas del repositorio

| Rama | Contenido |
|------|-----------|
| `dev` | Rama principal: código, scripts, evidencias y configuración. **No incluye `docs/`.** |
| `docs` | Solo la documentación del informe (el contenido de `docs/`) y su README. |

Trabaja en `dev` para el entorno y la migración; cambia a `docs` para editar o
compilar el informe LaTeX.

## Requisitos

- Linux con Docker Engine y Docker Compose v2.
- 4 GB de RAM libres y ~12 GB de disco (incluye la imagen de TeX Live).
- No se necesitan MySQL, PostgreSQL, Python ni LaTeX en el anfitrión.

## Inicio rápido

```bash
cp .env.example .env
docker compose up -d --build

./scripts/01_audit_origin.sh
./scripts/02_migrate_and_backup.sh
./scripts/03_verify_all.sh

docker compose --profile docs run --rm docs make
```

Resultados esperados:

- 8 tablas, 2 vistas y 1.469 filas migradas, **0 rechazos**.
- `PRECHECK`, `POSTCHECK` (fila a fila con `EXCEPT ALL`), secuencias y `ANALYZE` OK.
- **75 pruebas en `PASS`, 0 en `FAIL`**.
- Respaldo cifrado en `backups/` y restauración verificada (55 socios).
- Informe compilado en `docs/main.pdf` (rama `docs`).
- Guion de demostración en `docs/GUION_DEMO_EN_VIVO.md` (rama `docs`).

Para reconstruir el entorno desde cero:

```bash
docker compose down -v
docker compose up -d --build
# vuelven a ejecutarse los tres scripts en el orden indicado arriba
```

## Estado actual del entorno

**El stack ya está levantado y la migración ya fue ejecutada**, no es solo una
instalación pendiente de correr por fases:

- Contenedores `coop_horizonte_legacy`, `coop_horizonte_core` y
  `coop_horizonte_migrador` activos y `healthy`.
- `coop_horizonte_core` contiene las 8 tablas de `public` cargadas, con sus
  secuencias alineadas y estadísticas actualizadas.
- `evidence/01_inventario_origen.txt`, `02_ejecucion_migracion.txt` y
  `03_pruebas_y_hardening.txt` son salidas reales de las corridas (75 PASS / 0 FAIL).
- `backups/` contiene el respaldo cifrado y el dump de la prueba de restauración.
- Se probó además el camino de fallo: una fila corrupta en `stg` hace abortar el
  precheck y un error forzado durante la carga confirma el `ROLLBACK` (el marcador
  en `public` sobrevive).

Si solo se quiere repetir la migración sobre el entorno ya levantado:

```bash
./scripts/02_migrate_and_backup.sh   # idempotente: trunca y recarga public
./scripts/03_verify_all.sh
```

> Los datos son los que genera el propio proyecto (semilla determinista `seed=42`),
> no datos reales de producción.

## Estructura

| Ruta | Contenido |
|------|-----------|
| `docker-compose.yml` | Orquestación de origen, destino, migrador y perfil de documentación. |
| `src/origin/` | Esquema MySQL 5.7, generador de datos y semilla determinista (`seed=42`). |
| `src/target/` | Esquema PostgreSQL 16, roles, `postgresql.conf`, `pg_hba.conf` y certificados. |
| `src/migration/` | Imagen del migrador (pgloader + `gettext-base`), DSL `.load` y SQL de staging/validación/carga. |
| `src/migration/legacy/` | ETL Python original (`pymysql` + `psycopg2`), archivado, **no se ejecuta**. |
| `scripts/` | Auditoría, migración/respaldo y verificación integral. |
| `evidence/` | Salidas reales de los tres scripts. |
| `backups/` | Respaldos cifrados (excluidos de git). |
| `resumen.md` | Contexto completo del estado del proyecto para retomar el trabajo. |

El informe LaTeX, sus anexos, las copias de evidencias y el guion de demo están
en la rama `docs` (equivalen al contenido local de `docs/`). La plantilla UPDS
original (`plantilla-latex/`) no se versiona.

### Flujo de migración

1. Congelamiento de escrituras en MySQL y `mysqldump --single-transaction`.
2. `00_prepare_staging.sql` crea el schema `stg` (propiedad de `migration_loader`).
3. pgloader carga las 8 tablas a `stg` (sin índices, sin FK, sin secuencias).
4. `10_precheck.sql` valida nulos, ENUM, huérfanos, rangos y fechas cero antes de tocar `public`.
5. Una sola transacción: `20_load.sql` → `30_postcheck.sql` → `35_sequences.sql`.
6. `40_analyze.sql`, `50_cleanup.sql` (elimina `stg`) y respaldo cifrado con prueba de restauración.

## Seguridad del destino

- TLS/SSL obligatorio (`hostssl`) con certificado autofirmado SAN `db-destino`.
- Autenticación `scram-sha-256`; `postgres` solo por socket local (`peer`).
- Roles:
  - `admin_dba` — administración, sin `SUPERUSER`.
  - `nicolas`, `joaquin`, `david`, `gustavo` — mismo perfil administrativo.
  - `migration_loader` — solo `stg`, sin acceso a `public`, `search_path='stg'`.
  - `app_core_rw` — solo DML, sin DDL ni `TRUNCATE`.
  - `auditor_ro` — solo vista enmascarada `vw_socios_audit`.
- `PUBLIC` sin privilegios; registro de conexiones, desconexiones y DDL.
- Respaldo lógico cifrado con AES-256-CBC + PBKDF2 (200.000 iteraciones).

## Variables de entorno

Además de las habituales (`MYSQL_*`, `POSTGRES_PASSWORD`, `BACKUP_PASSPHRASE`, `TZ`):

| Variable | Uso |
|---|---|
| `MIGRATION_LOADER_PASSWORD` | Carga a `stg`; debe coincidir con `02_hardening_roles.sql`. |
| `ADMIN_TEAM_PASSWORD` | Password de los cuatro administradores, usado por las verificaciones. |
| `PGSSLMODE` / `PGSSLROOTCERT` | TLS `verify-ca` para el SQL que escribe en `public`. |
| `SSL_CERT_FILE` | Certificado usado por pgloader (necesario aunque la URI diga `sslmode=require`). |

## Notas

- Los datos son sintéticos; no se usó información personal real.
- `.env` y `backups/` están excluidos del control de versiones.
- La plantilla original se conserva intacta en local; el informe se edita en la rama `docs`.
- La documentación LaTeX pendiente se detalla en `resumen.md` (sección 11).
