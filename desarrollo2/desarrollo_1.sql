CREATE TABLE cuentas (
    id_cuenta INT PRIMARY KEY,
    titular VARCHAR(100),
    saldo DECIMAL(10,2)
);

CREATE TABLE historial_transferencias (
    id_transferencia INT AUTO_INCREMENT PRIMARY KEY,
    cuenta_origen INT,
    cuenta_destino INT,
    monto DECIMAL(10,2),
    fecha TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO cuentas (id_cuenta, titular, saldo) VALUES
(1, 'Ana López', 5000.00),
(2, 'Carlos Pérez', 3000.00);

DELIMITER $$

CREATE PROCEDURE TransferirFondos (
    IN  p_origen INT,
    IN  p_destino INT,
    IN  p_monto DECIMAL(10,2),
    OUT p_codigo_respuesta INT
)
BEGIN

    DECLARE v_saldo_origen DECIMAL(10,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_codigo_respuesta = 500;
    END;

    START TRANSACTION;

        SELECT saldo INTO v_saldo_origen
        FROM cuentas
        WHERE id_cuenta = p_origen
        FOR UPDATE;

        IF v_saldo_origen >= p_monto THEN

            UPDATE cuentas
            SET saldo = saldo - p_monto
            WHERE id_cuenta = p_origen;

            UPDATE cuentas
            SET saldo = saldo + p_monto
            WHERE id_cuenta = p_destino;

            INSERT INTO historial_transferencias (cuenta_origen, cuenta_destino, monto)
            VALUES (p_origen, p_destino, p_monto);

            COMMIT;

            SET p_codigo_respuesta = 200;

        ELSE
            ROLLBACK;
            SET p_codigo_respuesta = 400;
        END IF;

END$$

DELIMITER ;

CALL TransferirFondos(1, 2, 1000, @codigo);
SELECT @codigo AS codigo_respuesta;     

SELECT * FROM cuentas;

SELECT * FROM historial_transferencias;

CALL TransferirFondos(1, 2, 10000, @codigo);
SELECT @codigo AS codigo_respuesta;    

SELECT * FROM cuentas;

ALTER TABLE historial_transferencias
    ADD COLUMN usuario_responsable VARCHAR(100);

DELIMITER $$

CREATE PROCEDURE TransferirFondosV2 (
    IN  p_origen INT,
    IN  p_destino INT,
    IN  p_monto DECIMAL(10,2),
    IN  p_usuario VARCHAR(100),
    OUT p_codigo_respuesta INT,
    OUT p_titular_origen VARCHAR(100)
)
BEGIN
    DECLARE v_saldo_origen DECIMAL(10,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_codigo_respuesta = 500;
    END;

    SELECT titular INTO p_titular_origen
    FROM cuentas
    WHERE id_cuenta = p_origen;

    IF p_monto <= 0 THEN
        SET p_codigo_respuesta = 401;
    ELSE
        START TRANSACTION;

            SELECT saldo INTO v_saldo_origen
            FROM cuentas
            WHERE id_cuenta = p_origen
            FOR UPDATE;

            IF v_saldo_origen >= p_monto THEN
                UPDATE cuentas
                SET saldo = saldo - p_monto
                WHERE id_cuenta = p_origen;

                UPDATE cuentas
                SET saldo = saldo + p_monto
                WHERE id_cuenta = p_destino;

                INSERT INTO historial_transferencias
                    (cuenta_origen, cuenta_destino, monto, usuario_responsable)
                VALUES
                    (p_origen, p_destino, p_monto, p_usuario);

                COMMIT;
                SET p_codigo_respuesta = 200;
            ELSE
                ROLLBACK;
                SET p_codigo_respuesta = 400;
            END IF;
    END IF;

END$$

DELIMITER ;

-- Pruebas del procedimiento extendido
CALL TransferirFondosV2(2, 1, 500, 'admin_juan', @codigo2, @titular2);
SELECT @codigo2 AS codigo_respuesta, @titular2 AS titular_origen; 

CALL TransferirFondosV2(2, 1, -50, 'admin_juan', @codigo3, @titular3);
SELECT @codigo3 AS codigo_respuesta, @titular3 AS titular_origen; 

SELECT * FROM historial_transferencias;
