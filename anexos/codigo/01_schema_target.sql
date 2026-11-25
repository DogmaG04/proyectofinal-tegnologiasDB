-- ============================================================================
--  DESTINO: PostgreSQL 16 - Cooperativa Horizonte PyME S.R.L.
--  Esquema migrado con tipos nativos, integridad referencial y CHECK.
--  Equivalencias respecto de MySQL 5.7:
--    TINYINT(1)              -> BOOLEAN
--    ENUM                    -> VARCHAR + CHECK
--    DATETIME                -> TIMESTAMPTZ (zona America/La_Paz)
--    INT UNSIGNED AUTO_INC   -> BIGINT GENERATED ALWAYS AS IDENTITY
--    utf8_general_ci         -> UTF-8 nativo (collation del cluster)
-- ============================================================================

SET TIME ZONE 'America/La_Paz';

-- ----------------------------------------------------------------------------
-- Tabla: sucursales
-- ----------------------------------------------------------------------------
CREATE TABLE sucursales (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre VARCHAR(100) NOT NULL,
  direccion VARCHAR(200),
  telefono VARCHAR(20),
  fecha_creacion TIMESTAMPTZ NOT NULL,
  estatus BOOLEAN NOT NULL DEFAULT TRUE
);

-- ----------------------------------------------------------------------------
-- Tabla: socios
-- ----------------------------------------------------------------------------
CREATE TABLE socios (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre_completo VARCHAR(150) NOT NULL,
  numero_identificacion VARCHAR(20) UNIQUE,
  fecha_nacimiento DATE,
  genero VARCHAR(1) NOT NULL DEFAULT 'M'
    CHECK (genero IN ('M', 'F', 'O')),
  estado VARCHAR(10) NOT NULL DEFAULT 'activo'
    CHECK (estado IN ('activo', 'inactivo', 'suspendido')),
  fecha_ingreso DATE NOT NULL,
  telefono VARCHAR(20),
  email VARCHAR(100),
  direccion_residencia TEXT,
  fecha_ultima_actualizacion TIMESTAMPTZ NOT NULL DEFAULT now(),
  estatus BOOLEAN NOT NULL DEFAULT TRUE
);

-- ----------------------------------------------------------------------------
-- Tabla: cuentas_ahorro
-- ----------------------------------------------------------------------------
CREATE TABLE cuentas_ahorro (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  socio_id BIGINT NOT NULL REFERENCES socios(id),
  num_cuenta VARCHAR(30) UNIQUE,
  saldo_inicial NUMERIC(12,2) NOT NULL DEFAULT 0.00 CHECK (saldo_inicial >= 0),
  tasa_interes_anual NUMERIC(5,2) NOT NULL DEFAULT 0.05 CHECK (tasa_interes_anual >= 0),
  fecha_apertura TIMESTAMPTZ NOT NULL,
  fecha_cierre TIMESTAMPTZ,
  estatus BOOLEAN NOT NULL DEFAULT TRUE
);

-- ----------------------------------------------------------------------------
-- Tabla: tipos_credito
-- ----------------------------------------------------------------------------
CREATE TABLE tipos_credito (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre VARCHAR(80) NOT NULL,
  descripcion TEXT,
  monto_maximo NUMERIC(12,2) NOT NULL CHECK (monto_maximo > 0),
  tasa_interes_anual NUMERIC(5,2) NOT NULL CHECK (tasa_interes_anual >= 0),
  plazo_maximo_dias BIGINT NOT NULL CHECK (plazo_maximo_dias > 0),
  estado VARCHAR(10) NOT NULL DEFAULT 'activo'
    CHECK (estado IN ('activo', 'inactivo', 'suspendido'))
);

-- ----------------------------------------------------------------------------
-- Tabla: solicitudes_credito
-- ----------------------------------------------------------------------------
CREATE TABLE solicitudes_credito (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  socio_id BIGINT NOT NULL REFERENCES socios(id),
  tipo_credito_id BIGINT NOT NULL REFERENCES tipos_credito(id),
  monto_solicitado NUMERIC(12,2) NOT NULL CHECK (monto_solicitado > 0),
  plazo_dias BIGINT NOT NULL CHECK (plazo_dias > 0),
  fecha_solicitud TIMESTAMPTZ NOT NULL,
  fecha_aprobacion TIMESTAMPTZ,
  fecha_desembolso TIMESTAMPTZ,
  status VARCHAR(10) NOT NULL DEFAULT 'pendiente'
    CHECK (status IN ('pendiente', 'aprobada', 'rechazada', 'cancelada')),
  observaciones TEXT
);

-- ----------------------------------------------------------------------------
-- Tabla: prestamos
-- ----------------------------------------------------------------------------
CREATE TABLE prestamos (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  solicitud_id BIGINT NOT NULL UNIQUE REFERENCES solicitudes_credito(id),
  socio_id BIGINT NOT NULL REFERENCES socios(id),
  monto_prestado NUMERIC(12,2) NOT NULL CHECK (monto_prestado > 0),
  tasa_interes_anual NUMERIC(5,2) NOT NULL CHECK (tasa_interes_anual >= 0),
  fecha_desembolso TIMESTAMPTZ NOT NULL,
  fecha_fin_plazo DATE NOT NULL,
  estado VARCHAR(10) NOT NULL DEFAULT 'activo'
    CHECK (estado IN ('activo', 'pagado', 'moroso', 'cancelado')),
  total_cuotas BIGINT NOT NULL CHECK (total_cuotas > 0),
  pagado_total BOOLEAN NOT NULL DEFAULT FALSE
);

-- ----------------------------------------------------------------------------
-- Tabla: cuotas_amortizacion
-- ----------------------------------------------------------------------------
CREATE TABLE cuotas_amortizacion (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  prestamo_id BIGINT NOT NULL REFERENCES prestamos(id) ON DELETE CASCADE,
  numero_cuota BIGINT NOT NULL CHECK (numero_cuota > 0),
  monto_cuota NUMERIC(12,2) NOT NULL CHECK (monto_cuota > 0),
  fecha_vencimiento DATE NOT NULL,
  fecha_pago TIMESTAMPTZ,
  estatus VARCHAR(10) NOT NULL DEFAULT 'pendiente'
    CHECK (estatus IN ('pendiente', 'pagada', 'atrasada')),
  monto_pagado NUMERIC(12,2) NOT NULL DEFAULT 0.00 CHECK (monto_pagado >= 0),
  UNIQUE (prestamo_id, numero_cuota)
);

-- ----------------------------------------------------------------------------
-- Tabla: transacciones
-- ----------------------------------------------------------------------------
CREATE TABLE transacciones (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tipo VARCHAR(15) NOT NULL
    CHECK (tipo IN ('deposito', 'retiro', 'pago_cuota', 'desembolso', 'transferencia')),
  socio_id BIGINT REFERENCES socios(id) ON DELETE SET NULL,
  cuenta_ahorro_id BIGINT REFERENCES cuentas_ahorro(id) ON DELETE SET NULL,
  prestamo_id BIGINT REFERENCES prestamos(id) ON DELETE SET NULL,
  monto NUMERIC(12,2) NOT NULL CHECK (monto > 0),
  fecha_transaccion TIMESTAMPTZ NOT NULL,
  descripcion VARCHAR(255)
);

-- ----------------------------------------------------------------------------
-- Indices para reportes y claves foraneas
-- ----------------------------------------------------------------------------
CREATE INDEX idx_socio_estado ON socios(estado);
CREATE INDEX idx_cuenta_ahorro_socio ON cuentas_ahorro(socio_id);
CREATE INDEX idx_solicitud_tipo ON solicitudes_credito(tipo_credito_id);
CREATE INDEX idx_solicitud_socio ON solicitudes_credito(socio_id);
CREATE INDEX idx_transaccion_fecha ON transacciones(fecha_transaccion);
CREATE INDEX idx_transaccion_socio ON transacciones(socio_id);
CREATE INDEX idx_prestamo_estado ON prestamos(estado);
CREATE INDEX idx_prestamo_socio ON prestamos(socio_id);
CREATE INDEX idx_cuota_prestamo ON cuotas_amortizacion(prestamo_id);
CREATE INDEX idx_cuota_estatus ON cuotas_amortizacion(estatus);

-- ----------------------------------------------------------------------------
-- Vistas equivalentes a las del origen
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_cartera_mora AS
SELECT
  s.id,
  s.nombre_completo,
  s.numero_identificacion,
  p.estado AS estado_prestamo,
  p.monto_prestado,
  p.fecha_desembolso,
  COUNT(c.id) AS total_cuotas,
  SUM(CASE WHEN c.estatus = 'atrasada' THEN 1 ELSE 0 END) AS cuotas_atrasadas,
  SUM(c.monto_cuota) AS total_cuota_mora
FROM socios s
JOIN prestamos p ON s.id = p.socio_id
LEFT JOIN cuotas_amortizacion c ON p.id = c.prestamo_id
WHERE p.estado = 'moroso'
GROUP BY s.id, p.id;

CREATE OR REPLACE VIEW vw_resumen_saldos_socio AS
SELECT
  s.id,
  s.nombre_completo,
  s.estado AS socio_estado,
  COUNT(ca.id) AS total_cuentas,
  SUM(CASE WHEN ca.estatus THEN ca.saldo_inicial ELSE 0 END) AS saldo_total_activo,
  SUM(CASE WHEN NOT ca.estatus THEN ca.saldo_inicial ELSE 0 END) AS saldo_total_cerrado,
  COUNT(DISTINCT p.id) AS total_prestamos,
  SUM(CASE WHEN p.estado = 'activo' THEN p.monto_prestado ELSE 0 END) AS monto_prestamos_activos
FROM socios s
LEFT JOIN cuentas_ahorro ca ON s.id = ca.socio_id
LEFT JOIN prestamos p ON s.id = p.socio_id
GROUP BY s.id, s.estado;
