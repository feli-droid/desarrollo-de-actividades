-- ==============================================================================
-- TALLER PRÁCTICO: OPTIMIZACIÓN DE CONSULTAS Y RENDIMIENTO EN MYSQL (BancoDB)
-- SOLUCIÓN COMPLETA - Ejercicios 1, 2 y 3
-- ==============================================================================

CREATE DATABASE IF NOT EXISTS BancoDB;
USE BancoDB;

-- ------------------------------------------------------------------------------
-- PARTE 0: ESTRUCTURA DE TABLAS Y POBLAMIENTO DE DATOS MASIVOS
-- ------------------------------------------------------------------------------

DROP TABLE IF EXISTS historial_transferencias;
DROP TABLE IF EXISTS cuentas;

CREATE TABLE cuentas (
    id_cuenta INT PRIMARY KEY AUTO_INCREMENT,
    titular VARCHAR(100) NOT NULL,
    tipo_cuenta VARCHAR(20) NOT NULL DEFAULT 'Ahorros',
    saldo DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    estado VARCHAR(20) NOT NULL DEFAULT 'Activa',
    fecha_apertura DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE historial_transferencias (
    id_transferencia INT AUTO_INCREMENT PRIMARY KEY,
    cuenta_origen INT NOT NULL,
    cuenta_destino INT NOT NULL,
    monto DECIMAL(12, 2) NOT NULL,
    estado_transferencia VARCHAR(20) NOT NULL DEFAULT 'Exitosa',
    fecha DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (cuenta_origen) REFERENCES cuentas(id_cuenta),
    FOREIGN KEY (cuenta_destino) REFERENCES cuentas(id_cuenta)
);

DELIMITER //
CREATE PROCEDURE CargarDatosPrueba()
BEGIN
    DECLARE i INT DEFAULT 1;

    WHILE i <= 1000 DO
        INSERT INTO cuentas (titular, tipo_cuenta, saldo, estado, fecha_apertura)
        VALUES (
            CONCAT('Cliente_', i),
            IF(i % 2 = 0, 'Ahorros', 'Corriente'),
            ROUND(RAND() * 10000000, 2),
            IF(i % 10 = 0, 'Bloqueada', 'Activa'),
            DATE_SUB(NOW(), INTERVAL FLOOR(RAND() * 365) DAY)
        );
        SET i = i + 1;
    END WHILE;

    SET i = 1;
    WHILE i <= 10000 DO
        INSERT INTO historial_transferencias (cuenta_origen, cuenta_destino, monto, estado_transferencia, fecha)
        VALUES (
            FLOOR(1 + RAND() * 999),
            FLOOR(1 + RAND() * 999),
            ROUND(1000 + RAND() * 500000, 2),
            IF(i % 15 = 0, 'Fallida', 'Exitosa'),
            DATE_SUB(NOW(), INTERVAL FLOOR(RAND() * 180) DAY)
        );
        SET i = i + 1;
    END WHILE;
END //
DELIMITER ;

CALL CargarDatosPrueba();
DROP PROCEDURE IF EXISTS CargarDatosPrueba;


-- ==============================================================================
-- PARTE 1: DEMOSTRACIÓN GUIADA (PROFESOR)
-- ==============================================================================

EXPLAIN ANALYZE
SELECT id_transferencia, cuenta_origen, monto, fecha
FROM historial_transferencias
WHERE estado_transferencia = 'Exitosa'
  AND fecha >= '2026-01-01 00:00:00';

CREATE INDEX idx_transf_estado_fecha ON historial_transferencias(estado_transferencia, fecha);

EXPLAIN ANALYZE
SELECT id_transferencia, cuenta_origen, monto, fecha
FROM historial_transferencias
WHERE estado_transferencia = 'Exitosa'
  AND fecha >= '2026-01-01 00:00:00';


-- ==============================================================================
-- PARTE 2: EJERCICIOS RESUELTOS
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- EJERCICIO 1: Diagnóstico de "Non-Sargable Query" (Uso de Funciones en WHERE)
-- ------------------------------------------------------------------------------

-- BASE INEFICIENTE:
EXPLAIN ANALYZE
SELECT *
FROM historial_transferencias
WHERE DATE(fecha) = '2026-02-15';

-- 1) ¿Por qué NO se usa el índice idx_transf_estado_fecha aquí?
--    Porque la consulta envuelve la columna indexada (fecha) dentro de la función
--    DATE(fecha). MySQL debe calcular DATE(fecha) para CADA fila de la tabla antes
--    de poder compararla con el literal '2026-02-15'. Al transformar la columna,
--    el optimizador ya no puede usar el árbol B-Tree del índice para saltar
--    directamente a los valores buscados (no puede hacer un "index seek"), por lo
--    que la consulta deja de ser "sargable" (Search ARGument ABLE) y MySQL recurre
--    a un recorrido completo de la tabla (Table Scan), sin importar que exista
--    un índice sobre la columna 'fecha'.

-- 2) Reescritura SARGABLE usando un rango de fechas (sin funciones sobre la columna):
EXPLAIN ANALYZE
SELECT *
FROM historial_transferencias
WHERE fecha >= '2026-02-15 00:00:00'
  AND fecha <  '2026-02-16 00:00:00';

-- 3) Comparación:
--    - Versión con DATE(fecha) = '...'  -> Table scan, MySQL evalúa la función en
--      cada una de las 10,000 filas.
--    - Versión con rango (>= y <)       -> MySQL puede usar idx_transf_estado_fecha
--      (o un índice creado solo sobre 'fecha') para ubicar directamente el rango
--      de filas mediante un recorrido de índice (Index Range Scan), reduciendo
--      drásticamente las filas examinadas y el costo estimado que muestra
--      EXPLAIN ANALYZE.


-- ------------------------------------------------------------------------------
-- EJERCICIO 2: Optimización mediante Índices Cubrientes (Covering Index)
-- ------------------------------------------------------------------------------

-- BASE INEFICIENTE:
EXPLAIN ANALYZE
SELECT titular, saldo, tipo_cuenta
FROM cuentas
WHERE estado = 'Activa';

-- 1) SELECT * vs seleccionar solo los campos necesarios:
--    SELECT * obliga a MySQL a traer TODAS las columnas de cada fila (incluyendo
--    fecha_apertura, id_cuenta, etc.), lo cual aumenta el volumen de datos leídos
--    desde disco/memoria y el tráfico de red hacia el cliente, incluso cuando la
--    aplicación solo necesita 2 o 3 columnas. Seleccionar únicamente los campos
--    estrictamente necesarios reduce el trabajo de E/S y hace posible que un
--    índice cubriente resuelva toda la consulta.

-- 2) Índice cubriente: incluye la columna del WHERE (estado) primero, y luego
--    las columnas que se retornan en el SELECT (titular, saldo, tipo_cuenta),
--    para que MySQL pueda resolver la consulta leyendo ÚNICAMENTE el índice,
--    sin ir a buscar las filas en la tabla base:
CREATE INDEX idx_cuentas_estado_cubriente
    ON cuentas (estado, titular, saldo, tipo_cuenta);

-- 3) Verificación: la salida debe mostrar "Using index" (covering index),
--    en lugar de acceder a la tabla base fila por fila:
EXPLAIN ANALYZE
SELECT titular, saldo, tipo_cuenta
FROM cuentas
WHERE estado = 'Activa';


-- ------------------------------------------------------------------------------
-- EJERCICIO 3: Optimización de Filtros Combinados y JOINs
-- ------------------------------------------------------------------------------

-- BASE INEFICIENTE:
EXPLAIN ANALYZE
SELECT c.id_cuenta, c.titular, ht.id_transferencia, ht.monto, ht.fecha
FROM cuentas c
JOIN historial_transferencias ht ON c.id_cuenta = ht.cuenta_origen
WHERE c.estado = 'Activa'
  AND ht.monto > 300000.00;

-- 1) Diagnóstico:
--    Sin índices adecuados, MySQL tiende a hacer un recorrido completo de la
--    tabla más grande (historial_transferencias, 10,000 filas) para evaluar
--    ht.monto > 300000.00 y, por cada fila coincidente, buscar la cuenta
--    correspondiente. También puede escanear 'cuentas' por completo para
--    filtrar estado = 'Activa'. En EXPLAIN ANALYZE esto se ve como
--    "Table scan on ht" (o "on c") con un costo/tiempo alto.

-- 2) Índices necesarios:

--    a) En 'cuentas': índice sobre la columna de filtro (estado) que además
--       cubra la columna usada en el JOIN (id_cuenta ya es PK, así que el
--       JOIN por ese lado ya es eficiente); igual se indexa el filtro:
CREATE INDEX idx_cuentas_estado ON cuentas (estado);

--    b) En 'historial_transferencias': índice compuesto que soporte el JOIN
--       (cuenta_origen) y el filtro de rango (monto) en un solo índice:
CREATE INDEX idx_transf_origen_monto
    ON historial_transferencias (cuenta_origen, monto);

-- 3) Justificación del orden de columnas en idx_transf_origen_monto:
--    - 'cuenta_origen' va primero porque es la columna usada en la condición
--      de igualdad del JOIN (c.id_cuenta = ht.cuenta_origen); las columnas de
--      igualdad deben ir antes que las de rango en un índice compuesto, ya
--      que permiten que MySQL "salte" directamente al grupo de filas de cada
--      cuenta.
--    - 'monto' va segundo porque se usa en una condición de RANGO (> 300000).
--      Una vez posicionado en el grupo de una cuenta_origen específica, MySQL
--      puede recorrer solo el sub-rango de valores de monto mayores a 300000
--      dentro de ese grupo, sin necesidad de leer filas adicionales.
--    - Regla general: en un índice compuesto, columnas de IGUALDAD primero,
--      columnas de RANGO al final (regla "equality before range").

-- Re-evaluación tras crear los índices:
EXPLAIN ANALYZE
SELECT c.id_cuenta, c.titular, ht.id_transferencia, ht.monto, ht.fecha
FROM cuentas c
JOIN historial_transferencias ht ON c.id_cuenta = ht.cuenta_origen
WHERE c.estado = 'Activa'
  AND ht.monto > 300000.00;

-- ==============================================================================
-- FIN DEL TALLER
-- ==============================================================================