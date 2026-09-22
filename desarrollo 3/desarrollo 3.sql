CREATE DATABASE IF NOT EXISTS BancoBD;
USE BancoBD;

CREATE TABLE IF NOT EXISTS cuentas (
    id_cuenta INT PRIMARY KEY AUTO_INCREMENT,
    titular VARCHAR(100) NOT NULL,
    saldo DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    estado VARCHAR(20) DEFAULT 'Activa'
);

CREATE TABLE IF NOT EXISTS historial_transferencias (
    id_transferencia INT AUTO_INCREMENT PRIMARY KEY,
    cuenta_origen INT NOT NULL,
    cuenta_destino INT NOT NULL,
    monto DECIMAL(10, 2) NOT NULL,
    fecha TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (cuenta_origen) REFERENCES cuentas(id_cuenta),
    FOREIGN KEY (cuenta_destino) REFERENCES cuentas(id_cuenta)
);

INSERT INTO cuentas (titular, saldo, estado) VALUES
('Carlos Mendoza', 2500000.00, 'Activa'),
('Ana Gómez', 850000.00, 'Activa'),
('Roberto Silva', 120000.00, 'Bloqueada');

DROP USER IF EXISTS ''@'localhost';
DROP USER IF EXISTS ''@'%';

DROP USER IF EXISTS 'admin_banco'@'localhost';
DROP USER IF EXISTS 'cajero_app'@'localhost';
DROP USER IF EXISTS 'auditor_consulta'@'%';
DROP USER IF EXISTS 'app_backend'@'localhost';

CREATE USER 'admin_banco'@'localhost' IDENTIFIED BY 'AdminBank2026!#';
CREATE USER 'cajero_app'@'localhost' IDENTIFIED BY 'CajeroPass2026!';
CREATE USER 'auditor_consulta'@'%' IDENTIFIED BY 'AuditorPass2026!';
CREATE USER 'app_backend'@'localhost' IDENTIFIED BY 'AppBackend2026!Sec';

GRANT ALL PRIVILEGES ON BancoBD.* TO 'admin_banco'@'localhost' WITH GRANT OPTION;

GRANT SELECT, INSERT, UPDATE ON BancoBD.* TO 'app_backend'@'localhost';

GRANT SELECT (id_cuenta, titular, saldo), UPDATE (saldo) ON BancoBD.cuentas TO 'cajero_app'@'localhost';

GRANT SELECT ON BancoBD.* TO 'auditor_consulta'@'%';

FLUSH PRIVILEGES;

SHOW GRANTS FOR 'cajero_app'@'localhost';
SHOW GRANTS FOR 'app_backend'@'localhost';

REVOKE UPDATE ON BancoBD.cuentas FROM 'cajero_app'@'localhost';
FLUSH PRIVILEGES;

PREPARE stmt_buscar_cuenta FROM 
'SELECT id_cuenta, titular, saldo, estado FROM cuentas WHERE id_cuenta = ? AND estado = ?';

SET @id_busqueda = 1;
SET @estado_busqueda = 'Activa';

EXECUTE stmt_buscar_cuenta USING @id_busqueda, @estado_busqueda;

DEALLOCATE PREPARE stmt_buscar_cuenta;