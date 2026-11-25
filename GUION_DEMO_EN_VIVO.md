# Guion de demostración en vivo

**Proyecto:** Migración MySQL 5.7 → PostgreSQL 16  
**Cliente:** Cooperativa de Ahorro y Crédito Horizonte PyME S.R.L.  
**Equipo:** Sudoers  
**Duración objetivo:** 15–20 minutos  
**Modalidad:** demostración técnica con terminal y navegador de archivos

---

## 1. Antes de empezar (checklist de 2 minutos)

Ejecutar desde la raíz del proyecto:

```bash
cd ~/Proyectos/proyectofinal-tegnologiasDB

# 1. Archivo de entorno
test -f .env && echo ".env OK" || cp .env.example .env

# 2. Servicios activos
docker compose ps

# 3. Verificar que los tres contenedores estén healthy/running
docker compose ps --format 'table {{.Name}}\t{{.Status}}'
```

Resultado esperado:

```text
coop_horizonte_legacy     Up (healthy)
coop_horizonte_core       Up (healthy)
coop_horizonte_migrador   Up
```

Si algo no está levantado:

```bash
docker compose up -d --build
```

Tener abiertas dos pestañas o ventanas:

1. Terminal en la raíz del proyecto.
2. Visor de PDF en `docs/main.pdf` (se compila al final o se abre el ya generado).

> **Regla de oro de la demo:** no improvisar comandos destructivos
> (`down -v`, `DROP DATABASE`, `TRUNCATE`) frente al público. Todo lo que se
> muestra ya está automatizado en `scripts/`.

---

## 2. Guion cronometrado

| Minuto | Bloque | Qué se muestra |
|--------|--------|----------------|
| 0:00–1:30 | Apertura | Cliente, problema y objetivo |
| 1:30–3:30 | Arquitectura | `docker compose ps`, servicios y red |
| 3:30–6:00 | Diagnóstico | Script `01_audit_origin.sh` y hallazgos |
| 6:00–9:00 | Migración | Script `02_migrate_and_backup.sh` y ETL |
| 9:00–12:00 | Hardening en vivo | SSL rechazado y `auditor_ro` bloqueado |
| 12:00–15:00 | Verificación | Script `03_verify_all.sh` (75 PASS) |
| 15:00–17:00 | Respaldo y restauración | Cifrado AES y 55 socios restaurados |
| 17:00–19:00 | Informe y cierre | PDF, anexos y conclusiones |

---

## 3. Apertura (0:00–1:30)

**Mensaje sugerido:**

> “La Cooperativa Horizonte PyME S.R.L. opera su core financiero sobre MySQL
> 5.7, un motor sin soporte desde octubre de 2023. El usuario de la aplicación
> tiene `GRANT ALL`, no hay TLS obligatorio, no existen claves foráneas y los
> respaldos viajan sin cifrar. Nuestro proyecto migra esa base a PostgreSQL 16
> con Docker Compose, aplicando hardening, roles de mínimo privilegio,
> enmascaramiento de datos y respaldos cifrados. Todo el trabajo es
> reproducible y está respaldado por evidencias reales.”

Mostrar la estructura del proyecto:

```bash
ls -1
```

Resultado esperado:

```text
backups/
docker-compose.yml
docs/
evidence/
scripts/
src/
```

---

## 4. Arquitectura y servicios (1:30–3:30)

```bash
docker compose ps
docker compose config --services
```

Explicar:

- `db-origen`: MySQL 5.7.44, puerto `127.0.0.1:3306`.
- `db-destino`: PostgreSQL 16, puerto `127.0.0.1:5432`.
- `migrador`: Python + `pymysql` + `psycopg2`, sin puerto publicado.
- `docs`: perfil opcional con TeX Live.

Verificar que los puertos no están expuestos a la red:

```bash
ss -ltnp 2>/dev/null | grep -E '3306|5432' || true
```

Resultado esperado: las direcciones deben ser `127.0.0.1:3306` y
`127.0.0.1:5432`, nunca `0.0.0.0`.

---

## 5. Diagnóstico del origen (3:30–6:00)

```bash
./scripts/01_audit_origin.sh
```

Mientras corre, señalar:

- Versión MySQL `5.7.44`.
- 8 tablas, 2 vistas, 19 entradas de índice.
- `app_legacy_user` con `GRANT ALL PRIVILEGES`.
- Tipos incompatibles: `TINYINT(1)`, `ENUM`, `DATETIME`, `INT UNSIGNED`.

Al terminar:

```bash
sed -n '1,60p' evidence/01_inventario_origen.txt
```

Resultado esperado (extracto):

```text
== Version del motor ==
5.7.44

== Tablas ==
cuentas_ahorro    InnoDB   66
socios            InnoDB   55
solicitudes_credito InnoDB 50
...

== Privilegios de app_legacy_user ==
GRANT ALL PRIVILEGES ON `coop_horizonte_legacy`.* TO 'app_legacy_user'@'%'
```

**Frase de transición:**

> “Este inventario no es decorativo: cada riesgo que vemos aquí tiene una
> contramedida concreta en el destino.”

---

## 6. Migración y respaldo (6:00–9:00)

```bash
./scripts/02_migrate_and_backup.sh
```

Mientras corre, explicar el ETL:

1. Snapshot consistente en MySQL (`REPEATABLE READ` + `WITH CONSISTENT SNAPSHOT`).
2. Transformación: `TINYINT(1) → BOOLEAN`, `ENUM → VARCHAR + CHECK`,
   `DATETIME → TIMESTAMPTZ` en `America/La_Paz`.
3. Carga con `OVERRIDING SYSTEM VALUE` para conservar IDs.
4. Reajuste de secuencias con `setval`.
5. Verificación de conteos origen vs. destino.

Al terminar, mostrar el resumen:

```bash
grep -A 12 'Verificacion de conteos' evidence/02_ejecucion_migracion.txt
```

Resultado esperado:

```text
Tabla                      Origen  Destino   Estado
socios                         55       55       OK
cuentas_ahorro                 66       66       OK
prestamos                      32       32       OK
cuotas_amortizacion           516      516       OK
transacciones                 740      740       OK
```

Mostrar los respaldos:

```bash
ls -lh backups/
```

Resultado esperado:

```text
origin_20261120_080940.sql.gz       32K
target_20261120_080940.dump.enc     68K
```

**Frase clave:**

> “El respaldo del destino no queda en texto claro: se cifra con AES-256-CBC y
> PBKDF2, y se prueba restaurándolo en una base temporal.”

---

## 7. Hardening en vivo (9:00–12:00)

### 7.1 Demostración 1: conexión sin SSL rechazada

Primero, una conexión **sin** cifrado:

```bash
docker compose exec -T migrador psql \
  "host=db-destino port=5432 dbname=coop_horizonte_core \
   user=app_core_rw password=${APP_CORE_RW_PASSWORD} sslmode=disable" \
  -tAc 'SELECT 1;'
```

Resultado esperado:

```text
psql: error: connection ... failed: no pg_hba.conf entry ...
no encryption
```

Ahora, la misma conexión **con** SSL verificado:

```bash
docker compose exec -T migrador psql \
  "host=db-destino port=5432 dbname=coop_horizonte_core \
   user=app_core_rw password=${APP_CORE_RW_PASSWORD} \
   sslmode=verify-ca sslrootcert=/etc/postgresql/ssl/server.crt" \
  -tAc 'SELECT 1;'
```

Resultado esperado:

```text
1
```

**Mensaje:**

> “La política no es una recomendación: sin TLS, PostgreSQL ni siquiera evalúa
> la contraseña. El rechazo ocurre en `pg_hba.conf`, antes de la autenticación.”

### 7.2 Demostración 2: auditor no puede leer datos sensibles

Intentar leer la tabla base:

```bash
docker compose exec -T migrador psql \
  "host=db-destino port=5432 dbname=coop_horizonte_core \
   user=auditor_ro password=${AUDITOR_RO_PASSWORD} \
   sslmode=verify-ca sslrootcert=/etc/postgresql/ssl/server.crt" \
  -tAc 'SELECT numero_identificacion FROM socios LIMIT 1;'
```

Resultado esperado:

```text
ERROR: permission denied for table socios
```

Ahora, la vista enmascarada:

```bash
docker compose exec -T migrador psql \
  "host=db-destino port=5432 dbname=coop_horizonte_core \
   user=auditor_ro password=${AUDITOR_RO_PASSWORD} \
   sslmode=verify-ca sslrootcert=/etc/postgresql/ssl/server.crt" \
  -tAc 'SELECT ci_nit, numero_cuenta FROM vw_socios_audit LIMIT 3;'
```

Resultado esperado:

```text
****6-OR|****9292
****4-OR|****7514
****3-LP|****4895
```

**Mensaje:**

> “El auditor puede correlacionar registros por el sufijo, pero no ve el
> documento ni la cuenta completa. Y no puede saltarse la vista leyendo la
> tabla original: el privilegio no existe.”

### 7.3 Demostración 3 (opcional, 30 s): `app_core_rw` no puede truncar

```bash
docker compose exec -T migrador psql \
  "host=db-destino port=5432 dbname=coop_horizonte_core \
   user=app_core_rw password=${APP_CORE_RW_PASSWORD} \
   sslmode=require" -tAc 'TRUNCATE socios;'
```

Resultado esperado:

```text
ERROR: permission denied for table socios
```

---

## 8. Verificación integral (12:00–15:00)

```bash
./scripts/03_verify_all.sh | tail -40
```

Resultado esperado al final:

```text
============================================================
RESUMEN: 75 PASS, 0 FAIL
============================================================
```

Mostrar los grupos:

```bash
grep -E '^== [0-9]' evidence/03_pruebas_y_hardening.txt
```

Resultado esperado:

```text
== 1. Parametros de seguridad activos ==
== 2. Reglas efectivas de pg_hba.conf ==
== 3. Rechazo de conexiones sin SSL ==
== 4. Roles y privilegios de minimo privilegio ==
== 5. Enmascaramiento de datos sensibles ==
== 6. Conteos origen vs destino ==
== 7. Integridad referencial ==
== 8. Rendimiento de vistas ==
```

**Mensaje:**

> “Las pruebas no imprimen valores y ya: comparan contra el valor esperado y
> cuentan fallos. Un solo FAIL haría que el script terminara en error.”

---

## 9. Respaldo cifrado y restauración (15:00–17:00)

Mostrar el archivo cifrado y su huella:

```bash
ls -lh backups/*.enc
sha256sum backups/*.enc
```

Verificar que el archivo no contiene texto legible:

```bash
file backups/target_*.dump.enc
```

Resultado esperado:

```text
data
```

Restauración (ya ejecutada por el script; se puede repetir el extracto):

```bash
grep -A 6 'Prueba de restauracion' evidence/02_ejecucion_migracion.txt
```

Resultado esperado:

```text
Descifrado OK: 68K
Filas de socios restauradas: 55
Restauracion: OK (coincide con el origen)
```

**Mensaje:**

> “Un respaldo que nunca se restaura no es un respaldo: es una esperanza.
> Nosotros lo desciframos, lo restauramos y contamos los 55 socios.”

---

## 10. Informe, anexos y cierre (17:00–19:00)

Abrir `docs/main.pdf` y recorrer:

1. Portada y datos del equipo.
2. Índice y tabla de trazabilidad de los 13 puntos.
3. Capítulo II: matriz de incompatibilidades y hardening.
4. Capítulo III: salidas reales del ETL y pruebas.
5. Anexos A–C: SQL, scripts y evidencias.

> **Capturas en el informe:** `docs/main.pdf` incluye nueve capturas reales en
> los apartados 2.1–2.3 (versión del origen, inventario y privilegios), 2.5
> (SSL, roles y vista enmascarada), 3.5 (ejecución del ETL y restauración) y
> 3.7 (resumen de pruebas). Están insertadas con la macro `\capturaAPA` de la
> plantilla: los integrantes deben guardar los PNG en `docs/figuras/` con los
> nombres que indica cada recuadro `CAPTURA PENDIENTE`; al recompilar, el
> recuadro se sustituye automáticamente por la imagen. Las capturas no se
> reemplazan por las salidas en texto: las complementan.

Si se necesita recompilar en vivo:

```bash
docker compose --profile docs run --rm docs make
ls -lh docs/main.pdf
```

**Cierre sugerido:**

> “El resultado es verificable: 1.469 filas migradas, 8 tablas con conteos
> idénticos, 9 claves foráneas sin huérfanos, 75 pruebas en PASS, TLS
> obligatorio, tres roles de mínimo privilegio, datos sensibles enmascarados y
> un respaldo cifrado que se restauró con éxito. No es una maqueta: es un
> entorno reproducible con evidencias.”

---

## 11. Preguntas frecuentes del jurado

| Pregunta | Respuesta breve |
|----------|-----------------|
| ¿Por qué no usaron pgloader? | El volumen es pequeño, pero las reglas de zona horaria, identidades y verificación requerían control explícito. El ETL propio es auditable. |
| ¿Por qué `TIMESTAMPTZ` y no `TIMESTAMP`? | Porque `DATETIME` de MySQL no guarda zona y un pago puede caer en otro día contable. `TIMESTAMPTZ` elimina la ambigüedad. |
| ¿Por qué `admin_dba` no es superusuario? | Para limitar el daño de un error o credencial comprometida. Puede administrar sin leer archivos del sistema ni eludir `pg_hba`. |
| ¿Qué pasa si falla la migración? | Se conserva el origen, se restaura el destino desde el respaldo cifrado y se repite. RTO estimado: 30 minutos. |
| ¿Cómo escalan? | PgBouncer, particionamiento de `transacciones`, índices parciales y réplicas de lectura. |
| ¿Cumplen alguna norma? | Se alinean con CIS PostgreSQL Benchmark, OWASP ASVS y NIST SP 800-53; no se certifica cumplimiento. |
| ¿Los datos son reales? | No. Son sintéticos y deterministas (`seed=42`), sin información personal real. |

---

## 12. Plan B si falla algo en vivo

| Síntoma | Acción inmediata |
|---------|------------------|
| Un contenedor no está `healthy` | `docker compose up -d`, esperar 20 s y reintentar. |
| El script falla por `.env` | `cp .env.example .env` y volver a ejecutar. |
| El PDF no está compilado | `docker compose --profile docs run --rm docs make`. |
| No hay red para descargar la imagen de TeX Live | Mostrar el PDF ya compilado y el código fuente en `docs/`. |
| Una conexión de demo falla por variable vacía | Usar `docker compose exec -T db-destino psql -U postgres` por socket local. |

**Consejo final:** ensayar la demo una vez completa antes de la presentación y
cronometrarla. Si el tiempo se acorta, omitir la demostración 7.3 y el bloque
de recompilación del PDF; nunca omitir las demostraciones 7.1 y 7.2, porque son
la evidencia visible del hardening.
