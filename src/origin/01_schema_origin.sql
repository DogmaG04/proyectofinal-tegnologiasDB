-- ============================================================================
--  ORIGEN: MySQL 5.7 - Cooperativa de Ahorro y Credito Horizonte PyME S.R.L.
--  Esquema legacy con incompatibilidades deliberadas para la migracion:
--    - TINYINT(1) como booleanos
--    - ENUM para estados
--    - DATETIME sin zona horaria
--    - INT UNSIGNED AUTO_INCREMENT
--    - collation utf8_general_ci (utf8mb3)
--    - usuario de aplicacion con GRANT ALL (permisos excesivos)
--    - ausencia de FOREIGN KEY (deuda tecnica del sistema legado)
-- ============================================================================

CREATE DATABASE IF NOT EXISTS coop_horizonte_legacy
  CHARACTER SET utf8 COLLATE utf8_general_ci;

USE coop_horizonte_legacy;

SET NAMES utf8;

-- ----------------------------------------------------------------------------
-- Tabla: sucursales
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sucursales (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(100) NOT NULL,
  direccion VARCHAR(200),
  telefono VARCHAR(20),
  fecha_creacion DATETIME NOT NULL,
  estatus TINYINT(1) NOT NULL DEFAULT 1 COMMENT '1=activo, 0=inactivo'
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci;

-- ----------------------------------------------------------------------------
-- Tabla: socios
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS socios (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre_completo VARCHAR(150) NOT NULL,
  numero_identificacion VARCHAR(20) UNIQUE KEY,
  fecha_nacimiento DATE,
  genero ENUM('M', 'F', 'O') NOT NULL DEFAULT 'M',
  estado ENUM('activo', 'inactivo', 'suspendido') NOT NULL DEFAULT 'activo',
  fecha_ingreso DATE NOT NULL,
  telefono VARCHAR(20),
  email VARCHAR(100),
  direccion_residencia TEXT,
  fecha_ultima_actualizacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  estatus TINYINT(1) NOT NULL DEFAULT 1 COMMENT '1=activo, 0=inactivo'
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci;

-- ----------------------------------------------------------------------------
-- Tabla: cuentas_ahorro
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cuentas_ahorro (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  socio_id INT UNSIGNED NOT NULL,
  num_cuenta VARCHAR(30) UNIQUE KEY,
  saldo_inicial DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  tasa_interes_anual DECIMAL(5,2) NOT NULL DEFAULT 0.05,
  fecha_apertura DATETIME NOT NULL,
  fecha_cierre DATETIME,
  estatus TINYINT(1) NOT NULL DEFAULT 1 COMMENT '1=activa, 0=cerrada'
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci;

-- ----------------------------------------------------------------------------
-- Tabla: tipos_credito
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tipos_credito (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(80) NOT NULL,
  descripcion TEXT,
  monto_maximo DECIMAL(12,2) NOT NULL,
  tasa_interes_anual DECIMAL(5,2) NOT NULL,
  plazo_maximo_dias INT UNSIGNED NOT NULL,
  estado ENUM('activo', 'inactivo', 'suspendido') NOT NULL DEFAULT 'activo'
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci;

-- ----------------------------------------------------------------------------
-- Tabla: solicitudes_credito
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS solicitudes_credito (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  socio_id INT UNSIGNED NOT NULL,
  tipo_credito_id INT UNSIGNED NOT NULL,
  monto_solicitado DECIMAL(12,2) NOT NULL,
  plazo_dias INT UNSIGNED NOT NULL,
  fecha_solicitud DATETIME NOT NULL,
  fecha_aprobacion DATETIME,
  fecha_desembolso DATETIME,
  status ENUM('pendiente', 'aprobada', 'rechazada', 'cancelada') NOT NULL DEFAULT 'pendiente',
  observaciones TEXT,
  INDEX idx_socio_credito (socio_id, tipo_credito_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci;

-- ----------------------------------------------------------------------------
-- Tabla: prestamos
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS prestamos (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  solicitud_id INT UNSIGNED NOT NULL UNIQUE KEY,
  socio_id INT UNSIGNED NOT NULL,
  monto_prestado DECIMAL(12,2) NOT NULL,
  tasa_interes_anual DECIMAL(5,2) NOT NULL,
  fecha_desembolso DATETIME NOT NULL,
  fecha_fin_plazo DATE NOT NULL,
  estado ENUM('activo', 'pagado', 'moroso', 'cancelado') NOT NULL DEFAULT 'activo',
  total_cuotas INT UNSIGNED NOT NULL,
  pagado_total TINYINT(1) NOT NULL DEFAULT 0 COMMENT 'TINYINT(1) - incompatibilidad para migracion'
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci;

-- ----------------------------------------------------------------------------
-- Tabla: cuotas_amortizacion
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cuotas_amortizacion (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  prestamo_id INT UNSIGNED NOT NULL,
  numero_cuota INT UNSIGNED NOT NULL,
  monto_cuota DECIMAL(12,2) NOT NULL,
  fecha_vencimiento DATE NOT NULL,
  fecha_pago DATETIME,
  estatus ENUM('pendiente', 'pagada', 'atrasada') NOT NULL DEFAULT 'pendiente',
  monto_pagado DECIMAL(12,2) NOT NULL DEFAULT 0.00
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci;

-- ----------------------------------------------------------------------------
-- Tabla: transacciones
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS transacciones (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tipo ENUM('deposito', 'retiro', 'pago_cuota', 'desembolso', 'transferencia') NOT NULL,
  socio_id INT UNSIGNED,
  cuenta_ahorro_id INT UNSIGNED,
  prestamo_id INT UNSIGNED,
  monto DECIMAL(12,2) NOT NULL,
  fecha_transaccion DATETIME NOT NULL,
  descripcion VARCHAR(255)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci;

-- ----------------------------------------------------------------------------
-- Vistas
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
  SUM(CASE WHEN ca.estatus = 1 THEN ca.saldo_inicial ELSE 0 END) AS saldo_total_activo,
  SUM(CASE WHEN ca.estatus = 0 THEN ca.saldo_inicial ELSE 0 END) AS saldo_total_cerrado,
  COUNT(DISTINCT p.id) AS total_prestamos,
  SUM(CASE WHEN p.estado = 'activo' THEN p.monto_prestado ELSE 0 END) AS monto_prestamos_activos
FROM socios s
LEFT JOIN cuentas_ahorro ca ON s.id = ca.socio_id
LEFT JOIN prestamos p ON s.id = p.socio_id
GROUP BY s.id, s.estado;

-- ----------------------------------------------------------------------------
-- Indices adicionales (ademas de los generados por PRIMARY/UNIQUE)
-- ----------------------------------------------------------------------------
CREATE INDEX idx_socio_identificacion ON socios(numero_identificacion);
CREATE INDEX idx_cuenta_ahorro_socio ON cuentas_ahorro(socio_id);
CREATE INDEX idx_solicitud_tipo ON solicitudes_credito(tipo_credito_id);
CREATE INDEX idx_transaccion_fecha ON transacciones(fecha_transaccion);
CREATE INDEX idx_prestado_estado ON prestamos(estado);
CREATE INDEX idx_cuota_prestamo ON cuotas_amortizacion(prestamo_id);

-- ----------------------------------------------------------------------------
-- Usuario legacy con permisos excesivos (hallazgo de auditoria)
-- ----------------------------------------------------------------------------
CREATE USER IF NOT EXISTS 'app_legacy_user'@'%' IDENTIFIED BY 'legacypass123';
ALTER USER 'app_legacy_user'@'%' IDENTIFIED BY 'legacypass123';
GRANT ALL PRIVILEGES ON coop_horizonte_legacy.* TO 'app_legacy_user'@'%';
FLUSH PRIVILEGES;
