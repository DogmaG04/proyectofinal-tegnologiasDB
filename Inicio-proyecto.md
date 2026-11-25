# Inicio del proyecto — ejecución manual por fases

**Proyecto:** Migración MySQL 5.7 → PostgreSQL 16  
**Cliente del caso:** Cooperativa de Ahorro y Crédito Horizonte PyME S.R.L.  
**Repositorio:** `~/Proyectos/proyectofinal-tegnologiasDB`  
**Objetivo de este documento:** poder levantar y recorrer el proyecto **desde cero, a mano**, fase por fase, entendiendo qué se ejecuta en el anfitrión (Docker) y qué se ejecuta dentro de cada contenedor (cliente de base de datos).

---

## 0. Reglas de trabajo y preparación de la terminal

### 0.1 Dos contextos que no se mezclan

| Contexto | Qué se ejecuta | Dónde |
|---|---|---|
| **ANFITRIÓN** | `docker`, `docker compose`, `ss`, `openssl`, `gzip`, `tar`, `sha256sum` | Terminal normal de Linux, en la raíz del proyecto |
| **CONTENEDOR** | `mysql`, `psql`, `pgloader`, `pg_dump`, `pg_restore` | Dentro del contenedor, con `docker compose exec` |

**Regla:** para orquestar contenedores se usa el anfitrión. Para hablar con MySQL o PostgreSQL se entra al contenedor y se usa su cliente. La única excepción es pasar un archivo `.sql` por entrada estándar (`< archivo.sql`): el archivo lo lee el shell del anfitrión, pero `psql` se ejecuta dentro del contenedor.

> No se necesita MySQL, PostgreSQL, Python  instalados en el anfitrión. Todo vive en Docker.

### 0.2 Variables de entorno

El archivo `.env` de la raíz contiene las credenciales de laboratorio. Las variables que se usan en este documento son:

| Variable | Para qué sirve |
|---|---|
| `MYSQL_ROOT_PASSWORD` | Entrar a MySQL como `root` |
| `MYSQL_APP_PASSWORD` | Usuario legado `app_legacy_user` (solo contexto) |
| `POSTGRES_PASSWORD` | Superusuario `postgres` de PostgreSQL (solo socket local) |
| `ADMIN_DBA_PASSWORD` | Rol administrador `admin_dba` |
| `MIGRATION_LOADER_PASSWORD` | Rol de carga `migration_loader` |
| `APP_CORE_RW_PASSWORD` | Rol de aplicación `app_core_rw` |
| `AUDITOR_RO_PASSWORD` | Rol de auditoría `auditor_ro` |
| `ADMIN_TEAM_PASSWORD` | Roles `nicolas`, `joaquin`, `david`, `gustavo` |
| `BACKUP_PASSPHRASE` | Cifrado AES-256-CBC de los respaldos |
| `TZ` | Zona horaria (`America/La_Paz`) |

### 0.3 Preparar la terminal del anfitrión

```bash
cd ~/Proyectos/proyectofinal-tegnologiasDB

# Cargar .env en la sesión actual del anfitrión (para respaldos y openssl)
set -a
. ./.env
set +a

# Comprobar que las variables están disponibles
echo "$MYSQL_ROOT_PASSWORD" >/dev/null && echo "variables cargadas"
```

> Si abres otra terminal, vuelve a ejecutar `set -a; . ./.env; set +a`.

### 0.4 Advertencia importante

- `docker compose down -v` **borra los volúmenes**: se pierden los datos de origen y destino.
- `DROP DATABASE`, `TRUNCATE` y `down -v` son destructivos. Úsalos solo cuando quieras reiniciar el laboratorio.
- Los datos son sintéticos y deterministas (`seed=42`); no hay información personal real.

### 0.5 Estado esperado al final de todo

- 8 tablas migradas con **1.469 filas** en total.
- 0 filas rechazadas.
- 9 claves foráneas sin huérfanos.
- Secuencias alineadas con `MAX(id)`.
- 75 pruebas en `PASS` y 0 en `FAIL`.
- Respaldo cifrado y restauración verificada.

---

## Fase 1 — Inicio de contenedores Docker

**Meta:** tener los tres servicios activos y saludables, sin tocar todavía las bases de datos.

### 1.1 Qué se levanta

`docker-compose.yml` define cuatro servicios:

| Servicio | Contenedor | Imagen | Puerto en el anfitrión |
|---|---|---|---|
| `db-origen` | `coop_horizonte_legacy` | `mysql:5.7` | `127.0.0.1:3306` |
| `db-destino` | `coop_horizonte_core` | `postgres:16` | `127.0.0.1:5432` |
| `migrador` | `coop_horizonte_migrador` | build de `src/migration` (PostgreSQL 16 + pgloader) | ninguno |
| `docs` | perfil opcional | `texlive/texlive` | ninguno |

Los tres primeros comparten la red `red_cooperativa`. Los puertos están publicados **solo en `127.0.0.1`**, no en `0.0.0.0`.

### 1.2 Comandos en el ANFITRIÓN

```bash
cd ~/Proyectos/proyectofinal-tegnologiasDB

# 1. Verificar que Docker está disponible
docker --version
docker compose version

# 2. Crear .env solo si no existe
test -f .env || cp .env.example .env

# 3. Validar la configuración sin levantar nada
docker compose config --quiet && echo "compose OK"

# 4. Construir la imagen del migrador y levantar todo
docker compose up -d --build

# 5. Ver estado y salud
docker compose ps
docker compose ps --format 'table {{.Name}}\t{{.Status}}'
```

Resultado esperado:

```text
coop_horizonte_legacy     Up (healthy)
coop_horizonte_core       Up (healthy)
coop_horizonte_migrador   Up
```

### 1.3 Verificación desde el ANFITRIÓN

```bash
# Logs de arranque (útil si algo no queda healthy)
docker compose logs --tail=40 db-origen
docker compose logs --tail=40 db-destino

# Los puertos deben estar en 127.0.0.1, nunca en 0.0.0.0
ss -ltnp | grep -E '3306|5432' || true

# Red creada por Compose
docker network ls | grep red_cooperativa
```

### 1.4 Entrar a los contenedores

```bash
# MySQL: se entra como root del contenedor; el cliente mysql está dentro
docker compose exec db-origen bash

# PostgreSQL: entrar COMO USUARIO postgres (necesario por autenticación peer)
docker compose exec -u postgres db-destino bash

# Migrador: tiene pgloader, psql y las variables PGHOST/PGUSER/PGPASSWORD
docker compose exec migrador bash
```

Para salir de cualquier contenedor:

```bash
exit
```

### 1.5 Apagar, reiniciar y reiniciar desde cero

```bash
# Apagar conservando los datos
docker compose stop

# Volver a encender
docker compose start

# Bajar contenedores y red, conservando volúmenes
docker compose down

# REINICIO TOTAL: borra mysql_data y postgres_data (destructivo)
docker compose down -v --remove-orphans
docker compose up -d --build
```

> En el primer arranque con volúmenes vacíos, Docker ejecuta automáticamente los scripts de inicialización:
> - MySQL: `src/origin/01_schema_origin.sql` y `src/origin/02_seed_origin.sql`.
> - PostgreSQL: `src/target/01_schema_target.sql` y `src/target/02_hardening_roles.sql`.
>
> Por eso, al terminar la fase 1, el origen ya tiene datos y el destino ya tiene el esquema (pero sin filas). En la fase 2 se comprueba y, si se quiere, se repite la inyección a mano.

### 1.6 Evidencia de la fase

```bash
docker compose ps > evidence/00_contenedores.txt
ss -ltnp | grep -E '3306|5432' >> evidence/00_contenedores.txt 2>&1 || true
```

---

## Fase 2 — Inyección de datos en la BD origen y comprobación

**Meta:** confirmar que MySQL tiene el esquema, las 8 tablas, las 2 vistas y exactamente las filas esperadas. Opcionalmente, volver a inyectar el seed a mano.

### 2.1 Cómo se inyectan los datos

La inyección está automatizada por el montaje de `docker-compose.yml`:

```yaml
volumes:
  - ./src/origin:/docker-entrypoint-initdb.d:ro
```

MySQL ejecuta, **solo cuando el volumen `mysql_data` está vacío**:

1. `01_schema_origin.sql`: crea la base `coop_horizonte_legacy`, las 8 tablas, las 2 vistas, los índices y el usuario legado con `GRANT ALL`.
2. `02_seed_origin.sql`: inserta los datos generados por `src/origin/generate_seed.py` con `seed=42`.

Si el volumen ya existe, esos scripts **no se vuelven a ejecutar**. Para repetir la inyección hay dos caminos: el manual de 2.4 o un `down -v` desde el anfitrión.

### 2.2 Comprobación DENTRO del contenedor origen

Entrar al contenedor:

```bash
docker compose exec db-origen bash
```

Conectarse a MySQL usando la variable de entorno que ya está definida dentro del contenedor:

```bash
MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot coop_horizonte_legacy
```

Si prefieres que te pida la contraseña:

```bash
mysql -uroot -p coop_horizonte_legacy
# escribe el valor de MYSQL_ROOT_PASSWORD del .env
```

Ya dentro del cliente `mysql>`, ejecutar:

```sql
-- 1. Bases y tablas
SHOW DATABASES;
SELECT DATABASE();
SHOW TABLES;
SHOW FULL TABLES WHERE Table_type = 'VIEW';

-- 2. Estructura de una tabla representativa
SHOW CREATE TABLE socios\G
DESCRIBE socios;

-- 3. Conteos exactos de las 8 tablas
SELECT 'sucursales'          AS tabla, COUNT(*) AS filas FROM sucursales
UNION ALL SELECT 'socios',              COUNT(*) FROM socios
UNION ALL SELECT 'cuentas_ahorro',      COUNT(*) FROM cuentas_ahorro
UNION ALL SELECT 'tipos_credito',       COUNT(*) FROM tipos_credito
UNION ALL SELECT 'solicitudes_credito', COUNT(*) FROM solicitudes_credito
UNION ALL SELECT 'prestamos',           COUNT(*) FROM prestamos
UNION ALL SELECT 'cuotas_amortizacion', COUNT(*) FROM cuotas_amortizacion
UNION ALL SELECT 'transacciones',       COUNT(*) FROM transacciones;

-- 4. Muestras de datos
SELECT id, nombre_completo, numero_identificacion, genero, estado
FROM socios ORDER BY id LIMIT 5;

SELECT * FROM cuentas_ahorro ORDER BY id LIMIT 5;
SELECT * FROM prestamos ORDER BY id LIMIT 5;

-- 5. Vistas del origen
SELECT * FROM vw_cartera_mora LIMIT 5;
SELECT * FROM vw_resumen_saldos_socio LIMIT 5;

-- 6. Usuarios y privilegios (hallazgo de auditoría)
SELECT user, host FROM mysql.user;
SHOW GRANTS FOR 'app_legacy_user'@'%';

-- 7. Charset, motor y tamaño
SELECT table_name, engine, table_rows
FROM information_schema.tables
WHERE table_schema = 'coop_horizonte_legacy'
ORDER BY table_name;

SHOW VARIABLES LIKE 'character_set%';
SHOW VARIABLES LIKE 'collation%';

-- 8. Integridad física de una tabla
CHECK TABLE socios;
```

Salir del cliente y del contenedor:

```sql
exit
```

```bash
exit
```

### 2.3 Comprobación desde el ANFITRIÓN (una sola línea)

Esto no reemplaza la revisión interna, solo sirve para evidencias rápidas:

```bash
docker compose exec -T -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" db-origen \
  mysql -uroot -N -B coop_horizonte_legacy \
  -e "SELECT 'socios' AS tabla, COUNT(*) FROM socios
      UNION ALL SELECT 'transacciones', COUNT(*) FROM transacciones;"
```

### 2.4 Reinyección manual del seed (destructivo, opcional)

Úsalo solo si quieres demostrar la inyección "desde cero" sin borrar el volumen. **Borra y recrea la base de origen.**

Dentro del contenedor `db-origen`:

```bash
docker compose exec db-origen bash
MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot
```

En el cliente `mysql>`:

```sql
DROP DATABASE IF EXISTS coop_horizonte_legacy;

SOURCE /docker-entrypoint-initdb.d/01_schema_origin.sql;
SOURCE /docker-entrypoint-initdb.d/02_seed_origin.sql;

USE coop_horizonte_legacy;
SHOW TABLES;
SELECT COUNT(*) AS socios FROM socios;
```

> `SOURCE` es un comando del cliente `mysql`, no de SQL estándar. La ruta existe porque `./src/origin` está montado en `/docker-entrypoint-initdb.d`.

### 2.5 Resultado esperado

| Tabla | Filas |
|---|---:|
| `sucursales` | 5 |
| `socios` | 55 |
| `cuentas_ahorro` | 66 |
| `tipos_credito` | 5 |
| `solicitudes_credito` | 50 |
| `prestamos` | 32 |
| `cuotas_amortizacion` | 516 |
| `transacciones` | 740 |
| **Total** | **1.469** |

También deben existir 2 vistas (`vw_cartera_mora`, `vw_resumen_saldos_socio`) y el usuario `app_legacy_user` con `GRANT ALL PRIVILEGES` sobre la base.

### 2.6 Evidencia de la fase

Desde el anfitrión:

```bash
docker compose exec -T -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" db-origen \
  mysql -uroot coop_horizonte_legacy \
  -e "SHOW TABLES; SELECT COUNT(*) AS socios FROM socios;" \
  | tee evidence/01_fase2_origen.txt
```

---

## Fase 3 — Qué tenemos preparado para la migración (BD destino)

**Meta:** revisar el contenedor PostgreSQL, confirmar que el esquema está creado, que **no hay filas** y que los roles, SSL y reglas de acceso están listos.

### 3.1 Qué debe haber en el destino tras el primer arranque

| Elemento | Esperado |
|---|---|
| Base de datos | `coop_horizonte_core` |
| Tablas en `public` | 8 |
| Vistas | 3: `vw_cartera_mora`, `vw_resumen_saldos_socio`, `vw_socios_audit` |
| Filas en las 8 tablas | **0** |
| Schema `stg` | **no debe existir** todavía |
| Roles | `admin_dba`, `app_core_rw`, `auditor_ro`, `migration_loader`, `nicolas`, `joaquin`, `david`, `gustavo` |
| SSL | `on`, certificado en `/var/lib/postgresql/ssl/` |
| Autenticación TCP | solo `hostssl` + `scram-sha-256` |
| `postgres` remoto | prohibido; solo socket local con `peer` |

> Importante: "vacío" significa **0 filas**, no "sin tablas". El esquema se crea en el primer arranque con `01_schema_target.sql`; las tablas deben existir y estar sin datos.

### 3.2 Revisión DENTRO del contenedor destino

Entrar **como usuario `postgres`** (si entras como root, la autenticación `peer` falla):

```bash
docker compose exec -u postgres db-destino bash
psql -U postgres -d coop_horizonte_core
```

Dentro de `psql`:

```sql
-- 1. Contexto
SELECT current_user, current_database(), current_setting('TimeZone');
SHOW ssl;

-- 2. Esquemas, tablas y vistas
\dn
\dt+
\dv+

-- 3. Confirmar que no hay datos (todas deben dar 0)
SELECT 'sucursales'          AS tabla, COUNT(*) AS filas FROM sucursales
UNION ALL SELECT 'socios',              COUNT(*) FROM socios
UNION ALL SELECT 'cuentas_ahorro',      COUNT(*) FROM cuentas_ahorro
UNION ALL SELECT 'tipos_credito',       COUNT(*) FROM tipos_credito
UNION ALL SELECT 'solicitudes_credito', COUNT(*) FROM solicitudes_credito
UNION ALL SELECT 'prestamos',           COUNT(*) FROM prestamos
UNION ALL SELECT 'cuotas_amortizacion', COUNT(*) FROM cuotas_amortizacion
UNION ALL SELECT 'transacciones',       COUNT(*) FROM transacciones;

-- 4. El schema de staging todavía no debe existir (0 filas)
SELECT nspname FROM pg_namespace WHERE nspname = 'stg';

-- 5. Roles preparados
\du
SELECT rolname, rolsuper, rolcanlogin, rolcreatedb, rolcreaterole
FROM pg_roles
WHERE rolname IN ('admin_dba','app_core_rw','auditor_ro','migration_loader',
                  'nicolas','joaquin','david','gustavo')
ORDER BY rolname;

-- 6. Reglas efectivas de acceso
SELECT line_number, type, database, user_name, address, auth_method
FROM pg_hba_file_rules ORDER BY line_number;

-- 7. Claves foráneas ya definidas en el esquema
SELECT count(*) AS fk_total FROM pg_constraint WHERE contype = 'f';  -- 9

-- 8. Secuencias de identidad creadas
SELECT schemaname, sequencename
FROM pg_sequences WHERE schemaname = 'public' ORDER BY sequencename;
```

Salir:

```sql
\q
exit
```

### 3.3 Revisión de los archivos que preparan el destino (lectura en el anfitrión)

```bash
# Esquema, roles y configuración
sed -n '1,60p'  src/target/01_schema_target.sql
sed -n '1,80p'  src/target/02_hardening_roles.sql
cat             src/target/pg_hba.conf
grep -E 'ssl|listen|timezone|log_' src/target/postgresql.conf
```

### 3.4 Revisión del contenedor migrador (herramientas)

```bash
docker compose exec migrador bash
pgloader --version
psql --version
env | grep -E '^(MYSQL|PG|SSL_CERT_FILE)'
exit
```

Debe mostrar `pgloader 3.6.x`, `psql (PostgreSQL) 16.x` y las variables `PGHOST=db-destino`, `PGUSER=admin_dba`, `PGSSLMODE=verify-ca`.

### 3.5 Si el destino no está vacío

| Situación | Acción |
|---|---|
| Hay filas de una corrida anterior | Es normal si ya migraste; puedes recargar con el script (es idempotente) o hacer `down -v` |
| No existen las tablas | Los scripts de init no corrieron porque el volumen ya existía; revisa logs y, si hace falta, `down -v` |
| Existe el schema `stg` | Resto de una migración fallida; se elimina al volver a ejecutar `00_prepare_staging.sql` |
| Faltan roles | El volumen se creó con una versión anterior; recrea el volumen o ejecuta el hardening a mano |

Limpieza puntual de un staging huérfano (dentro de `psql` como `postgres`):

```sql
DROP SCHEMA IF EXISTS stg CASCADE;
```

### 3.6 Evidencia de la fase

```bash
docker compose exec -T -u postgres db-destino \
  psql -X -U postgres -d coop_horizonte_core \
  -c "\dt" -c "\dv" -c "SELECT count(*) FROM socios;" \
  | tee evidence/02_fase3_destino_vacio.txt
```

---

## Fase 4 — Desarrollo de la migración

**Meta:** ejecutar el pipeline completo y entender cada decisión. Esta es la fase más larga.

### 4.1 Decisiones que hay que tomar en cuenta

| Tema | Decisión del proyecto | Por qué |
|---|---|---|
| Ventana de migración | Congelar escrituras en el origen | pgloader lee cada tabla con un `SELECT` independiente; no hay snapshot consistente entre tablas |
| Respaldo previo | `mysqldump --single-transaction` + gzip | Poder volver atrás sin tocar el origen |
| Zona horaria | `DATETIME` → `TIMESTAMPTZ` con `America/La_Paz` | Evitar ambigüedad en fechas contables |
| Booleanos | `TINYINT(1)` → `BOOLEAN` | Tipo nativo |
| Enumeraciones | `ENUM` → `VARCHAR` + `CHECK` | Compatibilidad y validación |
| Identificadores | `INT UNSIGNED AUTO_INCREMENT` → `BIGINT GENERATED ALWAYS AS IDENTITY` | Conservar IDs con `OVERRIDING SYSTEM VALUE` |
| Integridad | Crear 9 claves foráneas en destino | El origen no las tiene |
| Carga | `stg` (staging) → validación → `public` | No tocar `public` hasta validar |
| Transacción | `20_load.sql` + `30_postcheck.sql` + `35_sequences.sql` en una sola transacción | Si algo falla, `public` queda como estaba |
| Seguridad | `migration_loader` solo puede escribir en `stg`; `admin_dba` carga por TLS | Mínimo privilegio |
| Idempotencia | `TRUNCATE` + recarga | Permite repetir la migración |
| Respaldo final | `pg_dump -Fc` + AES-256-CBC | Recuperación y confidencialidad |

### 4.2 Herramientas que se usan

- `pgloader 3.6.10`: carga MySQL → PostgreSQL.
- `psql`: precheck, carga, postcheck, secuencias, ANALYZE, limpieza.
- `pg_dump` / `pg_restore`: respaldo y prueba de restauración.
- `mysqldump`: respaldo del origen.
- `openssl`: cifrado AES-256-CBC con PBKDF2.
- `docker compose exec`: ejecutar todo dentro de los contenedores.
- `src/migration/legacy/migrate.py`: ETL Python original **archivado, no se ejecuta**.

### 4.3 Pipeline manual, paso a paso

Antes de empezar, en el anfitrión:

```bash
cd ~/Proyectos/proyectofinal-tegnologiasDB
set -a; . ./.env; set +a
mkdir -p backups
TS="$(date +%Y%m%d_%H%M%S)"
```

#### Paso 1 — Respaldo del origen (ANFITRIÓN + contenedor origen)

```bash
docker compose exec -T -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" db-origen \
  mysqldump -uroot --single-transaction --routines --triggers --events \
    --databases coop_horizonte_legacy \
  | gzip -9 > "backups/origin_manual_${TS}.sql.gz"

ls -lh "backups/origin_manual_${TS}.sql.gz"
sha256sum "backups/origin_manual_${TS}.sql.gz"
```

#### Paso 2 — Crear el schema de staging (DENTRO del destino, como `postgres`)

El archivo se lee desde el anfitrión, pero `psql` corre dentro del contenedor:

```bash
docker compose exec -T -u postgres db-destino \
  psql -X -v ON_ERROR_STOP=1 -U postgres -d coop_horizonte_core \
  < src/migration/sql/00_prepare_staging.sql
```

Comprobar dentro del destino:

```bash
docker compose exec -T -u postgres db-destino \
  psql -X -U postgres -d coop_horizonte_core \
  -c "SELECT nspname FROM pg_namespace WHERE nspname = 'stg';"
```

#### Paso 3 — Renderizar la plantilla de pgloader (DENTRO del migrador)

```bash
docker compose exec -T migrador bash /app/src/migration/render_load.sh /tmp/mysql_to_stage.load
```

Revisar que las credenciales se sustituyeron (sin mostrarlas en claro):

```bash
docker compose exec -T migrador bash -lc \
  "sed -E 's#(://[^:/@]+):[^@]*@#\\1:***@#g' /tmp/mysql_to_stage.load | head -n 20"
```

#### Paso 4 — Cargar MySQL → `stg` con pgloader (DENTRO del migrador)

```bash
docker compose exec -T migrador bash -lc \
  "rm -rf /tmp/pgloader-work && mkdir -p /tmp/pgloader-work"

docker compose exec -T migrador bash -lc \
  "exec pgloader --root-dir /tmp/pgloader-work /tmp/mysql_to_stage.load"
```

Comprobar que no hubo rechazos:

```bash
docker compose exec -T migrador bash -lc \
  "find /tmp/pgloader-work -name '*.dat' -print"
```

Si el comando anterior imprime rutas, hubo filas rechazadas: hay que revisarlas antes de continuar.

#### Paso 5 — Comparar conteos origen vs staging (lectura en el destino)

```bash
docker compose exec -T -u postgres db-destino \
  psql -X -U postgres -d coop_horizonte_core \
  -c "SELECT 'socios' AS tabla, count(*) FROM stg.socios
      UNION ALL SELECT 'transacciones', count(*) FROM stg.transacciones;"
```

Deben coincidir con los conteos del origen (55 y 740).

#### Paso 6 — PRECHECK sobre staging (DENTRO del migrador, como `admin_dba` y por TLS)

```bash
docker compose exec -T migrador \
  psql -X -v ON_ERROR_STOP=1 -f /app/src/migration/sql/10_precheck.sql
```

Resultado esperado: `PRECHECK OK: staging consistente con el esquema destino.`

#### Paso 7 — Carga transaccional `stg` → `public` (DENTRO del migrador)

```bash
docker compose exec -T migrador \
  psql -X -v ON_ERROR_STOP=1 --single-transaction \
    -f /app/src/migration/sql/20_load.sql \
    -f /app/src/migration/sql/30_postcheck.sql \
    -f /app/src/migration/sql/35_sequences.sql
```

Resultado esperado: avisos `POSTCHECK OK` por tabla y `SECUENCIAS OK`.

#### Paso 8 — `ANALYZE` (DENTRO del destino, como `postgres`)

En PostgreSQL 16 `ANALYZE` exige ser dueño de la tabla, por eso se ejecuta como `postgres`:

```bash
docker compose exec -T -u postgres db-destino \
  psql -X -v ON_ERROR_STOP=1 -U postgres -d coop_horizonte_core \
  < src/migration/sql/40_analyze.sql
```

#### Paso 9 — Limpieza del staging (DENTRO del destino)

```bash
docker compose exec -T -u postgres db-destino \
  psql -X -v ON_ERROR_STOP=1 -U postgres -d coop_horizonte_core \
  < src/migration/sql/50_cleanup.sql
```

Comprobar que `stg` ya no existe:

```bash
docker compose exec -T -u postgres db-destino \
  psql -X -U postgres -d coop_horizonte_core \
  -c "SELECT count(*) FROM pg_namespace WHERE nspname = 'stg';"   -- 0
```

#### Paso 10 — Respaldo cifrado del destino (ANFITRIÓN + contenedor destino)

```bash
docker compose exec -T -u postgres db-destino \
  pg_dump -U postgres -d coop_horizonte_core -Fc \
  | openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt \
      -pass env:BACKUP_PASSPHRASE \
      -out "backups/target_manual_${TS}.dump.enc"

ls -lh "backups/target_manual_${TS}.dump.enc"
sha256sum "backups/target_manual_${TS}.dump.enc"
```

#### Paso 11 — Prueba de restauración (ANFITRIÓN + contenedor destino)

```bash
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
  -pass env:BACKUP_PASSPHRASE \
  -in "backups/target_manual_${TS}.dump.enc" \
  -out /tmp/coop_restore.dump

docker compose exec -T -u postgres db-destino \
  psql -X -U postgres -d postgres \
  -c "DROP DATABASE IF EXISTS coop_horizonte_restore;"

docker compose exec -T -u postgres db-destino \
  psql -X -U postgres -d postgres \
  -c "CREATE DATABASE coop_horizonte_restore;"

docker compose exec -T -u postgres db-destino \
  pg_restore -U postgres -d coop_horizonte_restore --no-owner --no-privileges \
  < /tmp/coop_restore.dump

docker compose exec -T -u postgres db-destino \
  psql -X -U postgres -d coop_horizonte_restore \
  -tAc "SELECT count(*) FROM socios;"

docker compose exec -T -u postgres db-destino \
  psql -X -U postgres -d postgres \
  -c "DROP DATABASE coop_horizonte_restore;"
```

El conteo restaurado debe ser `55`, igual que en el origen.

### 4.4 Ruta automatizada (equivalente a todo lo anterior)

```bash
./scripts/02_migrate_and_backup.sh
```

Este script hace exactamente el pipeline de 4.3, guarda la salida en `evidence/02_ejecucion_migracion.txt` y crea los respaldos en `backups/` con marca de tiempo.

### 4.5 Qué hacer si algo falla

| Falla en | Efecto | Recuperación |
|---|---|---|
| pgloader | `public` intacto; `stg` puede quedar a medias | Revisar rechazos en `/tmp/pgloader-work`, corregir y repetir desde el paso 2 |
| Precheck | `public` intacto | Corregir el dato en `stg` o en el origen y repetir |
| Carga / postcheck / secuencias | La transacción se revierte; `public` conserva lo anterior | Revisar el error y repetir desde el paso 6 |
| Respaldo o restauración | La migración ya está hecha | Revisar `BACKUP_PASSPHRASE`, espacio en disco y permisos |

> El `TRUNCATE` de `20_load.sql` es transaccional en PostgreSQL: si la transacción falla, no se pierde lo que había en `public`.

### 4.6 Evidencia de la fase

```bash
ls -lh backups/
grep -A 12 'Comparativa de conteos' evidence/02_ejecucion_migracion.txt 2>/dev/null || true
```

---

## Fase 5 — Análisis y revisión manual de la BD destino

**Meta:** entrar al destino con distintos usuarios, ver tablas, contenido, secuencias, integridad y roles; comprobar que los datos llegaron bien.

### 5.1 Revisión completa DENTRO del contenedor destino como `postgres`

```bash
docker compose exec -u postgres db-destino bash
psql -U postgres -d coop_horizonte_core
```

Dentro de `psql`:

```sql
-- 1. Tablas, vistas y tamaño
\dt+
\dv+
\di+

-- 2. Conteos finales (deben coincidir con la fase 2)
SELECT 'sucursales'          AS tabla, COUNT(*) AS filas FROM sucursales
UNION ALL SELECT 'socios',              COUNT(*) FROM socios
UNION ALL SELECT 'cuentas_ahorro',      COUNT(*) FROM cuentas_ahorro
UNION ALL SELECT 'tipos_credito',       COUNT(*) FROM tipos_credito
UNION ALL SELECT 'solicitudes_credito', COUNT(*) FROM solicitudes_credito
UNION ALL SELECT 'prestamos',           COUNT(*) FROM prestamos
UNION ALL SELECT 'cuotas_amortizacion', COUNT(*) FROM cuotas_amortizacion
UNION ALL SELECT 'transacciones',       COUNT(*) FROM transacciones;

-- 3. Contenido de muestra
SELECT * FROM socios ORDER BY id LIMIT 5;
SELECT * FROM cuentas_ahorro ORDER BY id LIMIT 5;
SELECT * FROM prestamos ORDER BY id LIMIT 5;
SELECT * FROM cuotas_amortizacion ORDER BY id LIMIT 5;
SELECT * FROM transacciones ORDER BY id LIMIT 5;

-- 4. Vistas de negocio y de auditoría
SELECT * FROM vw_cartera_mora LIMIT 5;
SELECT * FROM vw_resumen_saldos_socio LIMIT 5;
SELECT id, nombre_completo, ci_nit, numero_cuenta
FROM vw_socios_audit ORDER BY id LIMIT 5;

-- 5. Secuencias alineadas con MAX(id)
SELECT 'socios' AS tabla,
       pg_get_serial_sequence('public.socios','id') AS secuencia,
       (SELECT last_value FROM public.socios_id_seq) AS ultimo,
       (SELECT MAX(id) FROM public.socios) AS max_id;

-- Repetir el patrón para las 8 tablas, o confiar en 35_sequences.sql

-- 6. Integridad referencial: 9 claves foráneas, 0 huérfanos
SELECT count(*) AS total_fk FROM pg_constraint WHERE contype = 'f';

SELECT 'cuentas_ahorro.socio_id -> socios.id' AS fk, COUNT(*) AS huerfanos
FROM cuentas_ahorro c LEFT JOIN socios p ON c.socio_id = p.id
WHERE c.socio_id IS NOT NULL AND p.id IS NULL
UNION ALL
SELECT 'solicitudes_credito.socio_id -> socios.id', COUNT(*)
FROM solicitudes_credito c LEFT JOIN socios p ON c.socio_id = p.id
WHERE c.socio_id IS NOT NULL AND p.id IS NULL
UNION ALL
SELECT 'solicitudes_credito.tipo_credito_id -> tipos_credito.id', COUNT(*)
FROM solicitudes_credito c LEFT JOIN tipos_credito p ON c.tipo_credito_id = p.id
WHERE c.tipo_credito_id IS NOT NULL AND p.id IS NULL
UNION ALL
SELECT 'prestamos.solicitud_id -> solicitudes_credito.id', COUNT(*)
FROM prestamos c LEFT JOIN solicitudes_credito p ON c.solicitud_id = p.id
WHERE c.solicitud_id IS NOT NULL AND p.id IS NULL
UNION ALL
SELECT 'prestamos.socio_id -> socios.id', COUNT(*)
FROM prestamos c LEFT JOIN socios p ON c.socio_id = p.id
WHERE c.socio_id IS NOT NULL AND p.id IS NULL
UNION ALL
SELECT 'cuotas_amortizacion.prestamo_id -> prestamos.id', COUNT(*)
FROM cuotas_amortizacion c LEFT JOIN prestamos p ON c.prestamo_id = p.id
WHERE c.prestamo_id IS NOT NULL AND p.id IS NULL
UNION ALL
SELECT 'transacciones.socio_id -> socios.id', COUNT(*)
FROM transacciones c LEFT JOIN socios p ON c.socio_id = p.id
WHERE c.socio_id IS NOT NULL AND p.id IS NULL
UNION ALL
SELECT 'transacciones.cuenta_ahorro_id -> cuentas_ahorro.id', COUNT(*)
FROM transacciones c LEFT JOIN cuentas_ahorro p ON c.cuenta_ahorro_id = p.id
WHERE c.cuenta_ahorro_id IS NOT NULL AND p.id IS NULL
UNION ALL
SELECT 'transacciones.prestamo_id -> prestamos.id', COUNT(*)
FROM transacciones c LEFT JOIN prestamos p ON c.prestamo_id = p.id
WHERE c.prestamo_id IS NOT NULL AND p.id IS NULL;
```

Salir:

```sql
\q
exit
```

### 5.2 Entrar a la BD destino con el usuario `admin_dba`

`admin_dba` **no** puede usar el socket local (la regla `local ... peer` solo permite al usuario del sistema `postgres`). Hay que conectarse por TCP, que obliga a TLS:

```bash
docker compose exec db-destino bash

export PGPASSWORD='<ADMIN_DBA_PASSWORD>'   # valor de .env
export PGSSLMODE=verify-ca
export PGSSLROOTCERT=/var/lib/postgresql/ssl/server.crt

psql -h 127.0.0.1 -U admin_dba -d coop_horizonte_core
```

Dentro de `psql`:

```sql
SELECT current_user, current_database();
SHOW ssl;

\dt
SELECT COUNT(*) FROM socios;
SELECT COUNT(*) FROM transacciones;

-- Verificar que admin_dba no es superusuario
SELECT rolname, rolsuper FROM pg_roles WHERE rolname = 'admin_dba';
```

> Si `verify-ca` falla, usa `PGSSLMODE=require`. El certificado es autofirmado y `verify-ca` valida la CA, no el nombre del host.

### 5.3 Pruebas de roles y seguridad (DENTRO del contenedor destino)

Sin SSL debe ser rechazado:

```bash
PGPASSWORD='<APP_CORE_RW_PASSWORD>' PGSSLMODE=disable \
  psql -h 127.0.0.1 -U app_core_rw -d coop_horizonte_core \
  -c "SELECT 1;"
# ERROR: no pg_hba.conf entry ... no encryption
```

Con SSL como `app_core_rw` (puede leer y escribir, no puede truncar):

```bash
PGPASSWORD='<APP_CORE_RW_PASSWORD>' PGSSLMODE=require \
  psql -h 127.0.0.1 -U app_core_rw -d coop_horizonte_core \
  -c "SELECT COUNT(*) FROM socios;"

PGPASSWORD='<APP_CORE_RW_PASSWORD>' PGSSLMODE=require \
  psql -h 127.0.0.1 -U app_core_rw -d coop_horizonte_core \
  -c "TRUNCATE socios;"
# ERROR: permission denied for table socios
```

Como `auditor_ro` (no lee la tabla base, sí la vista enmascarada):

```bash
PGPASSWORD='<AUDITOR_RO_PASSWORD>' PGSSLMODE=require \
  psql -h 127.0.0.1 -U auditor_ro -d coop_horizonte_core \
  -c "SELECT * FROM socios LIMIT 1;"
# ERROR: permission denied for table socios

PGPASSWORD='<AUDITOR_RO_PASSWORD>' PGSSLMODE=require \
  psql -h 127.0.0.1 -U auditor_ro -d coop_horizonte_core \
  -c "SELECT ci_nit, numero_cuenta FROM vw_socios_audit LIMIT 3;"
# ****6-OR | ****9292
```

Como `migration_loader` (no debe leer `public`):

```bash
PGPASSWORD='<MIGRATION_LOADER_PASSWORD>' PGSSLMODE=require \
  psql -h 127.0.0.1 -U migration_loader -d coop_horizonte_core \
  -c "SELECT COUNT(*) FROM public.socios;"
# ERROR: permission denied for schema public
```

### 5.4 Lo mismo desde el ANFITRIÓN (una línea por prueba)

```bash
# admin_dba por TLS desde el migrador (que ya tiene las variables)
docker compose exec -T migrador psql -tAc "SELECT current_user, COUNT(*) FROM socios;"

# auditor_ro: tabla base (debe fallar)
docker compose exec -T migrador psql \
  "host=db-destino port=5432 dbname=coop_horizonte_core \
   user=auditor_ro password=${AUDITOR_RO_PASSWORD} sslmode=require" \
  -tAc "SELECT * FROM socios LIMIT 1;"

# auditor_ro: vista enmascarada (debe funcionar)
docker compose exec -T migrador psql \
  "host=db-destino port=5432 dbname=coop_horizonte_core \
   user=auditor_ro password=${AUDITOR_RO_PASSWORD} sslmode=require" \
  -tAc "SELECT ci_nit, numero_cuenta FROM vw_socios_audit LIMIT 3;"
```

### 5.5 Verificación automatizada integral

```bash
./scripts/03_verify_all.sh
```

Al final debe imprimir:

```text
PASS: 75
FAIL: 0
RESULTADO: TODAS LAS PRUEBAS PASARON
```

Guardar la evidencia:

```bash
grep -c '^PASS' evidence/03_pruebas_y_hardening.txt   # 75
grep -c '^FAIL' evidence/03_pruebas_y_hardening.txt   # 0
```

### 5.6 Evidencia de la fase 5 (revisión manual)

```bash
docker compose exec -T -u postgres db-destino \
  psql -X -U postgres -d coop_horizonte_core \
  -c "\dt" \
  -c "SELECT count(*) AS socios FROM socios;" \
  -c "SELECT count(*) AS transacciones FROM transacciones;" \
  | tee evidence/04_fase5_destino_manual.txt
```

---

## Anexo A — Scripts y su fase

| Archivo | Qué hace | Fase |
|---|---|---|
| `scripts/lib.sh` | Utilidades compartidas: carga `.env`, arreglo `TABLES`, `compose()`, `wait_healthy()`, `mysql_root()`, `psql_admin()`, `psql_dba()`, `count_mysql()`, `count_pg()` | 1–5 |
| `scripts/01_audit_origin.sh` | Inventario del origen MySQL: versión, tamaño, tablas, vistas, índices, usuarios, privilegios, ENUM/DATETIME/TINYINT, conteos. Guarda en `evidence/01_inventario_origen.txt` | 2 y 3 (diagnóstico) |
| `scripts/02_migrate_and_backup.sh` | Pipeline completo: respaldo del origen, staging, pgloader, precheck, carga transaccional, ANALYZE, limpieza, respaldo cifrado y restauración de prueba. Guarda en `evidence/02_ejecucion_migracion.txt` | 4 |
| `scripts/03_verify_all.sh` | 75 pruebas: SSL, `pg_hba`, roles, privilegios, enmascaramiento, conteos, secuencias, 9 FKs y rendimiento. Guarda en `evidence/03_pruebas_y_hardening.txt` | 5 |
| `src/origin/01_schema_origin.sql` | Crea la base MySQL, 8 tablas, 2 vistas, índices y usuario legado con `GRANT ALL` | 1 y 2 |
| `src/origin/02_seed_origin.sql` | Inserta 1.469 filas deterministas (`seed=42`) | 1 y 2 |
| `src/origin/generate_seed.py` | Genera la semilla reproducible (no se ejecuta en el flujo) | 2 (referencia) |
| `src/target/01_schema_target.sql` | Crea las 8 tablas PostgreSQL, 2 vistas de negocio, índices, CHECK y 9 FKs | 1 y 3 |
| `src/target/02_hardening_roles.sql` | Crea roles, revoca `PUBLIC`, define grants y la vista `vw_socios_audit` | 1 y 3 |
| `src/target/postgresql.conf` | SSL, `listen_addresses`, logging, zona horaria | 1 y 3 |
| `src/target/pg_hba.conf` | Solo `hostssl` + `scram-sha-256`; `postgres` solo por socket local | 1 y 3 |
| `src/target/docker/entrypoint.sh` | Copia certificados a una ruta escribible y delega en el entrypoint oficial | 1 |
| `src/migration/Dockerfile` | Imagen del migrador: `postgres:16` + `pgloader` + `gettext-base` | 1 |
| `src/migration/render_load.sh` | Sustituye solo las variables conocidas en la plantilla `.load` | 4 |
| `src/migration/pgloader/mysql_to_stage.load` | DSL de pgloader: 8 tablas, sin índices, sin FKs, schema `stg` | 4 |
| `src/migration/sql/00_prepare_staging.sql` | Crea `stg` y lo asigna a `migration_loader` | 4 |
| `src/migration/sql/10_precheck.sql` | Valida nulos, ENUM, duplicados, huérfanos, rangos, longitudes y fechas antes de tocar `public` | 4 |
| `src/migration/sql/20_load.sql` | `TRUNCATE` + 8 `INSERT ... OVERRIDING SYSTEM VALUE` dentro de una transacción | 4 |
| `src/migration/sql/30_postcheck.sql` | Compara `public` vs `stg` fila a fila con `EXCEPT ALL` y valida FKs | 4 |
| `src/migration/sql/35_sequences.sql` | Alinea cada secuencia de identidad con `MAX(id)` | 4 |
| `src/migration/sql/40_analyze.sql` | `ANALYZE` de las 8 tablas | 4 |
| `src/migration/sql/50_cleanup.sql` | `DROP SCHEMA stg CASCADE` | 4 |
| `src/migration/legacy/migrate.py` | ETL Python histórico, **archivado y no ejecutado** | — |

### Cómo se lee `02_migrate_and_backup.sh`

1. Carga `lib.sh` y exige las variables críticas con `require_var`.
2. Espera a que origen y destino estén `healthy` (`wait_healthy`).
3. Cuenta filas en el origen.
4. Respalda el origen con `mysqldump --single-transaction | gzip`.
5. Ejecuta `00_prepare_staging.sql` como `postgres`.
6. Renderiza la plantilla de pgloader con `render_load.sh`.
7. Ejecuta pgloader y detecta archivos de rechazo.
8. Compara conteos origen vs `stg`.
9. Ejecuta el precheck; si falla, aborta sin tocar `public`.
10. Ejecuta `20`, `30` y `35` en **una sola transacción**.
11. Ejecuta `ANALYZE` y elimina `stg`.
12. Respalda el destino con `pg_dump -Fc | openssl`, y prueba la restauración en `coop_horizonte_restore`.
13. Compara conteos origen vs destino y devuelve código de error si hay diferencias.
14. Un `trap cleanup EXIT` elimina archivos temporales y la base de restauración.

### Cómo se lee `lib.sh`

- `ROOT_DIR`, `COMPOSE_FILE`, `EVIDENCE_DIR`, `BACKUP_DIR`: rutas absolutas.
- Carga `.env` automáticamente.
- `TABLES=(...)`: las 8 tablas del dominio.
- `compose()`: envuelve `docker compose -f ...`.
- `wait_healthy()`: consulta `docker inspect` hasta 90 veces.
- `mysql_root()`: `docker compose exec` a MySQL con `MYSQL_PWD`.
- `psql_admin()`: `psql` como `postgres` por socket local.
- `psql_dba()`: `psql` como `admin_dba` por TLS desde el migrador.
- `count_stage()`, `count_mysql()`, `count_pg()`, `psql_value()`: conteos y valores escalares.

---

## Anexo B — Orden recomendado de una ejecución desde cero

```bash
# ANFITRIÓN
cd ~/Proyectos/proyectofinal-tegnologiasDB
set -a; . ./.env; set +a

# Fase 1
docker compose down -v --remove-orphans     # solo si quieres partir de cero
docker compose up -d --build
docker compose ps

# Fase 2: revisar origen
docker compose exec db-origen bash
#   MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot coop_horizonte_legacy
#   ... consultas de la fase 2 ...
#   exit

# Fase 3: revisar destino
docker compose exec -u postgres db-destino bash
#   psql -U postgres -d coop_horizonte_core
#   ... consultas de la fase 3 ...
#   \q
#   exit

# Fase 4: migrar
./scripts/02_migrate_and_backup.sh

# Fase 5: verificar
./scripts/03_verify_all.sh

# Documento (opcional)
docker compose --profile docs run --rm docs make
```

---

## Anexo C — Checklist de avance

- [ ] **Fase 1:** `docker compose up -d --build` sin errores.
- [ ] **Fase 1:** los tres contenedores `Up`/`healthy`.
- [ ] **Fase 1:** puertos solo en `127.0.0.1`.
- [ ] **Fase 2:** 8 tablas y 2 vistas en MySQL.
- [ ] **Fase 2:** 1.469 filas totales.
- [ ] **Fase 2:** `app_legacy_user` con `GRANT ALL` (hallazgo).
- [ ] **Fase 3:** 8 tablas y 3 vistas en PostgreSQL.
- [ ] **Fase 3:** 0 filas en las 8 tablas.
- [ ] **Fase 3:** `stg` no existe.
- [ ] **Fase 3:** roles y `pg_hba` correctos; SSL `on`.
- [ ] **Fase 3:** `pgloader --version` funciona en el migrador.
- [ ] **Fase 4:** respaldo del origen creado.
- [ ] **Fase 4:** pgloader sin rechazos.
- [ ] **Fase 4:** precheck OK.
- [ ] **Fase 4:** postcheck OK y secuencias OK.
- [ ] **Fase 4:** `stg` eliminado.
- [ ] **Fase 4:** respaldo cifrado + restauración con 55 socios.
- [ ] **Fase 5:** conteos origen = destino.
- [ ] **Fase 5:** 9 FKs sin huérfanos.
- [ ] **Fase 5:** `admin_dba` entra por TLS.
- [ ] **Fase 5:** `auditor_ro` no lee `socios`, sí la vista enmascarada.
- [ ] **Fase 5:** `03_verify_all.sh` con 75 PASS / 0 FAIL.

---

## Anexo D — Problemas comunes

| Síntoma | Causa probable | Solución |
|---|---|---|
| `Cannot connect to the Docker daemon` | Docker no está iniciado | `sudo systemctl start docker` |
| `no such file or directory: .env` | Falta el archivo | `cp .env.example .env` |
| MySQL arranca pero no hay tablas | El volumen ya existía y los init scripts no corrieron | `docker compose down -v` y volver a levantar |
| `Table 'coop_horizonte_legacy.socios' doesn't exist` | Igual que arriba | Revisar `docker compose logs db-origen` |
| `Peer authentication failed for user "postgres"` | Entraste como `root` al contenedor | Usa `docker compose exec -u postgres db-destino ...` |
| `no pg_hba.conf entry ... no encryption` | Conexión TCP sin SSL | Usa `sslmode=require` o `verify-ca` |
| `password authentication failed for user "admin_dba"` | Contraseña distinta a la de `.env` | Verifica `ADMIN_DBA_PASSWORD` y que `02_hardening_roles.sql` se haya ejecutado |
| pgloader termina con rechazos | Dato incompatible con el esquema destino | Revisar `/tmp/pgloader-work/*.dat` y el log |
| `PRECHECK FALLIDO` | Dato nulo, duplicado, huérfano o fuera de rango | Leer el mensaje; `public` sigue intacto |
| `stg` ya existe | Corrida anterior fallida | Volver a ejecutar `00_prepare_staging.sql` |
| Secuencias desfasadas | No se ejecutó `35_sequences.sql` | Ejecutarlo o correr el script completo |
| `port is already allocated` | Hay un MySQL/PostgreSQL local en 3306/5432 | Detener el servicio local o cambiar el puerto en `docker-compose.yml` |
| El PDF no compila | Falta la imagen TeX Live o hay un error LaTeX | `docker compose --profile docs run --rm docs make` |

---

## Anexo E — Nota sobre la documentación existente

El `README.md` y los scripts describen la migración con **pgloader + SQL declarativo**. El `docs/GUION_DEMO_EN_VIVO.md`, en algunos pasajes, todavía habla del ETL Python (`pymysql` + `psycopg2`). El ETL real está archivado en `src/migration/legacy/migrate.py` y **no se ejecuta**. Para la ejecución manual y la demo, la fuente de verdad es este documento y los scripts de `scripts/`.
