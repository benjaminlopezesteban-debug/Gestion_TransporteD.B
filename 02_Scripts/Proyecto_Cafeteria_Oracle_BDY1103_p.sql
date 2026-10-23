-- =====================================================================
-- BDY1103 - PROYECTO CAFETERIA EN ORACLE
--
-- DECISION DE DISEÑO IMPORTANTE:
-- El descuento de stock es EXPLICITO.
-- NO existe un trigger que descuente stock.
-- PKG_VENTAS llama a PKG_INVENTARIO.DESCONTAR_STOCK.
-- =====================================================================

SET SERVEROUTPUT ON;

-- =====================================================================
-- 0. LIMPIEZA OPCIONAL
-- Ejecutar solo si desea reconstruir todo el proyecto.
-- =====================================================================
BEGIN EXECUTE IMMEDIATE 'DROP TRIGGER TR_AUDITAR_PRODUCTO'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP PACKAGE PKG_VENTAS'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP PACKAGE PKG_INVENTARIO'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE AUDITORIA_PRODUCTO CASCADE CONSTRAINTS'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE MOVIMIENTO_STOCK CASCADE CONSTRAINTS'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE DETALLE_VENTA CASCADE CONSTRAINTS'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE VENTA CASCADE CONSTRAINTS'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE PRODUCTO CASCADE CONSTRAINTS'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE CATEGORIA CASCADE CONSTRAINTS'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE EMPLEADO CASCADE CONSTRAINTS'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE CLIENTE CASCADE CONSTRAINTS'; EXCEPTION WHEN OTHERS THEN NULL; END;
/

-- =====================================================================
-- 1. TABLAS
-- =====================================================================

CREATE TABLE CLIENTE (
    cliente_id      NUMBER PRIMARY KEY,
    nombre          VARCHAR2(100) NOT NULL,
    email           VARCHAR2(120),
    telefono        VARCHAR2(20),
    estado          VARCHAR2(10) DEFAULT 'ACTIVO' NOT NULL,
    CONSTRAINT ck_cliente_estado CHECK (estado IN ('ACTIVO','INACTIVO')),
    CONSTRAINT uq_cliente_email UNIQUE (email)
);

CREATE TABLE EMPLEADO (
    empleado_id     NUMBER PRIMARY KEY,
    nombre          VARCHAR2(100) NOT NULL,
    cargo           VARCHAR2(50) NOT NULL,
    estado          VARCHAR2(10) DEFAULT 'ACTIVO' NOT NULL,
    CONSTRAINT ck_empleado_estado CHECK (estado IN ('ACTIVO','INACTIVO'))
);

CREATE TABLE CATEGORIA (
    categoria_id    NUMBER PRIMARY KEY,
    nombre          VARCHAR2(60) NOT NULL,
    CONSTRAINT uq_categoria_nombre UNIQUE (nombre)
);

CREATE TABLE PRODUCTO (
    producto_id     NUMBER PRIMARY KEY,
    categoria_id    NUMBER NOT NULL,
    nombre          VARCHAR2(100) NOT NULL,
    precio          NUMBER(10,2) NOT NULL,
    stock           NUMBER(10) DEFAULT 0 NOT NULL,
    estado          VARCHAR2(10) DEFAULT 'ACTIVO' NOT NULL,
    CONSTRAINT fk_producto_categoria
        FOREIGN KEY (categoria_id) REFERENCES CATEGORIA(categoria_id),
    CONSTRAINT ck_producto_precio CHECK (precio > 0),
    CONSTRAINT ck_producto_stock CHECK (stock >= 0),
    CONSTRAINT ck_producto_estado CHECK (estado IN ('ACTIVO','INACTIVO'))
);

CREATE TABLE VENTA (
    venta_id        NUMBER PRIMARY KEY,
    cliente_id      NUMBER,
    empleado_id     NUMBER NOT NULL,
    fecha_venta     DATE DEFAULT SYSDATE NOT NULL,
    estado          VARCHAR2(12) DEFAULT 'ABIERTA' NOT NULL,
    CONSTRAINT fk_venta_cliente
        FOREIGN KEY (cliente_id) REFERENCES CLIENTE(cliente_id),
    CONSTRAINT fk_venta_empleado
        FOREIGN KEY (empleado_id) REFERENCES EMPLEADO(empleado_id),
    CONSTRAINT ck_venta_estado
        CHECK (estado IN ('ABIERTA','CONFIRMADA','ANULADA'))
);

CREATE TABLE DETALLE_VENTA (
    detalle_id      NUMBER PRIMARY KEY,
    venta_id        NUMBER NOT NULL,
    producto_id     NUMBER NOT NULL,
    cantidad        NUMBER(8) NOT NULL,
    precio_unitario NUMBER(10,2) NOT NULL,
    CONSTRAINT fk_detalle_venta
        FOREIGN KEY (venta_id) REFERENCES VENTA(venta_id),
    CONSTRAINT fk_detalle_producto
        FOREIGN KEY (producto_id) REFERENCES PRODUCTO(producto_id),
    CONSTRAINT ck_detalle_cantidad CHECK (cantidad > 0),
    CONSTRAINT ck_detalle_precio CHECK (precio_unitario > 0)
);

CREATE TABLE MOVIMIENTO_STOCK (
    movimiento_id   NUMBER PRIMARY KEY,
    producto_id     NUMBER NOT NULL,
    fecha_movimiento DATE DEFAULT SYSDATE NOT NULL,
    tipo_movimiento VARCHAR2(10) NOT NULL,
    cantidad        NUMBER(8) NOT NULL,
    venta_id        NUMBER,
    observacion     VARCHAR2(200),
    CONSTRAINT fk_mov_producto
        FOREIGN KEY (producto_id) REFERENCES PRODUCTO(producto_id),
    CONSTRAINT fk_mov_venta
        FOREIGN KEY (venta_id) REFERENCES VENTA(venta_id),
    CONSTRAINT ck_mov_tipo CHECK (tipo_movimiento IN ('ENTRADA','SALIDA')),
    CONSTRAINT ck_mov_cantidad CHECK (cantidad > 0)
);

CREATE TABLE AUDITORIA_PRODUCTO (
    auditoria_id    NUMBER PRIMARY KEY,
    producto_id     NUMBER NOT NULL,
    fecha_cambio    DATE DEFAULT SYSDATE NOT NULL,
    usuario_bd      VARCHAR2(128) NOT NULL,
    campo_modificado VARCHAR2(30) NOT NULL,
    valor_anterior  VARCHAR2(100),
    valor_nuevo     VARCHAR2(100)
);

-- =====================================================================
-- 2. SECUENCIAS
-- =====================================================================

CREATE SEQUENCE SEQ_CLIENTE START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE SEQ_EMPLEADO START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE SEQ_CATEGORIA START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE SEQ_PRODUCTO START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE SEQ_VENTA START WITH 1001 INCREMENT BY 1;
CREATE SEQUENCE SEQ_DETALLE START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE SEQ_MOVIMIENTO START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE SEQ_AUDITORIA START WITH 1 INCREMENT BY 1;

-- =====================================================================
-- 3. DATOS DE PRUEBA
-- =====================================================================

INSERT INTO CATEGORIA VALUES (SEQ_CATEGORIA.NEXTVAL, 'Cafes');
INSERT INTO CATEGORIA VALUES (SEQ_CATEGORIA.NEXTVAL, 'Pasteleria');
INSERT INTO CATEGORIA VALUES (SEQ_CATEGORIA.NEXTVAL, 'Bebidas');

INSERT INTO CLIENTE VALUES
(SEQ_CLIENTE.NEXTVAL, 'Ana Perez', 'ana@correo.cl', '912345678', 'ACTIVO');

INSERT INTO CLIENTE VALUES
(SEQ_CLIENTE.NEXTVAL, 'Carlos Soto', 'carlos@correo.cl', '923456789', 'ACTIVO');

INSERT INTO EMPLEADO VALUES
(SEQ_EMPLEADO.NEXTVAL, 'Maria Gonzalez', 'CAJERO', 'ACTIVO');

INSERT INTO EMPLEADO VALUES
(SEQ_EMPLEADO.NEXTVAL, 'Pedro Rojas', 'ADMINISTRADOR', 'ACTIVO');

INSERT INTO PRODUCTO VALUES
(SEQ_PRODUCTO.NEXTVAL, 1, 'Cafe Americano', 2200, 30, 'ACTIVO');

INSERT INTO PRODUCTO VALUES
(SEQ_PRODUCTO.NEXTVAL, 1, 'Cafe Latte', 2800, 20, 'ACTIVO');

INSERT INTO PRODUCTO VALUES
(SEQ_PRODUCTO.NEXTVAL, 2, 'Cheesecake', 3500, 12, 'ACTIVO');

INSERT INTO PRODUCTO VALUES
(SEQ_PRODUCTO.NEXTVAL, 3, 'Agua Mineral', 1500, 25, 'ACTIVO');

COMMIT;

-- =====================================================================
-- 4. FUNCIONES INDEPENDIENTES
-- =====================================================================

CREATE OR REPLACE FUNCTION FN_STOCK_DISPONIBLE (
    p_producto_id IN NUMBER
) RETURN NUMBER
IS
    v_stock PRODUCTO.stock%TYPE;
BEGIN
    SELECT stock
      INTO v_stock
      FROM PRODUCTO
     WHERE producto_id = p_producto_id;

    RETURN v_stock;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20001, 'Producto inexistente.');
END;
/

CREATE OR REPLACE FUNCTION FN_TOTAL_VENTA (
    p_venta_id IN NUMBER
) RETURN NUMBER
IS
    v_total NUMBER(12,2);
BEGIN
    SELECT NVL(SUM(cantidad * precio_unitario), 0)
      INTO v_total
      FROM DETALLE_VENTA
     WHERE venta_id = p_venta_id;

    RETURN v_total;
END;
/

CREATE OR REPLACE FUNCTION FN_CANTIDAD_PRODUCTOS (
    p_venta_id IN NUMBER
) RETURN NUMBER
IS
    v_cantidad NUMBER;
BEGIN
    SELECT NVL(SUM(cantidad), 0)
      INTO v_cantidad
      FROM DETALLE_VENTA
     WHERE venta_id = p_venta_id;

    RETURN v_cantidad;
END;
/

-- =====================================================================
-- 5. RECORD
-- Agrupa temporalmente datos relacionados de una venta.
-- =====================================================================

DECLARE
    TYPE t_venta_resumen IS RECORD (
        venta_id    VENTA.venta_id%TYPE,
        fecha_venta VENTA.fecha_venta%TYPE,
        estado      VENTA.estado%TYPE,
        total       NUMBER(12,2)
    );

    v_resumen t_venta_resumen;
BEGIN
    -- Este bloque se ejecutara cuando exista la venta 1001.
    -- Se deja como ejemplo para ejecutar despues de las pruebas.
    NULL;
END;
/

-- =====================================================================
-- 6. VARRAY
-- NO se utiliza para almacenar DETALLE_VENTA.
-- El detalle es una relacion persistente y variable.
-- =====================================================================

DECLARE
    TYPE t_productos IS VARRAY(5) OF NUMBER;
    v_productos t_productos := t_productos(1, 2, 3);
BEGIN
    DBMS_OUTPUT.PUT_LINE('Productos temporales en VARRAY: ' || v_productos.COUNT);
END;
/

-- =====================================================================
-- 7. PACKAGE DE INVENTARIO
-- RESPONSABILIDAD: consultar, descontar y devolver stock.
-- =====================================================================

CREATE OR REPLACE PACKAGE PKG_INVENTARIO AS

    FUNCTION STOCK_DISPONIBLE (
        p_producto_id IN NUMBER
    ) RETURN NUMBER;

    PROCEDURE DESCONTAR_STOCK (
        p_producto_id IN NUMBER,
        p_cantidad    IN NUMBER,
        p_venta_id    IN NUMBER
    );

    PROCEDURE DEVOLVER_STOCK (
        p_producto_id IN NUMBER,
        p_cantidad    IN NUMBER,
        p_venta_id    IN NUMBER
    );

END PKG_INVENTARIO;
/

CREATE OR REPLACE PACKAGE BODY PKG_INVENTARIO AS

    FUNCTION STOCK_DISPONIBLE (
        p_producto_id IN NUMBER
    ) RETURN NUMBER
    IS
        v_stock PRODUCTO.stock%TYPE;
    BEGIN
        SELECT stock
          INTO v_stock
          FROM PRODUCTO
         WHERE producto_id = p_producto_id;

        RETURN v_stock;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20001, 'Producto inexistente.');
    END STOCK_DISPONIBLE;


    PROCEDURE DESCONTAR_STOCK (
        p_producto_id IN NUMBER,
        p_cantidad    IN NUMBER,
        p_venta_id    IN NUMBER
    )
    IS
        v_stock PRODUCTO.stock%TYPE;
        v_estado PRODUCTO.estado%TYPE;
    BEGIN
        IF p_cantidad <= 0 THEN
            RAISE_APPLICATION_ERROR(-20002, 'La cantidad debe ser mayor que cero.');
        END IF;

        -- FOR UPDATE bloquea la fila mientras se valida y modifica.
        SELECT stock, estado
          INTO v_stock, v_estado
          FROM PRODUCTO
         WHERE producto_id = p_producto_id
         FOR UPDATE;

        IF v_estado <> 'ACTIVO' THEN
            RAISE_APPLICATION_ERROR(-20003, 'El producto se encuentra inactivo.');
        END IF;

        IF v_stock < p_cantidad THEN
            RAISE_APPLICATION_ERROR(
                -20004,
                'Stock insuficiente. Disponible: ' || v_stock
            );
        END IF;

        -- =============================================================
        -- DESCUENTO EXPLICITO DE STOCK
        -- No se realiza mediante trigger.
        -- =============================================================
        UPDATE PRODUCTO
           SET stock = stock - p_cantidad
         WHERE producto_id = p_producto_id;

        INSERT INTO MOVIMIENTO_STOCK (
            movimiento_id,
            producto_id,
            fecha_movimiento,
            tipo_movimiento,
            cantidad,
            venta_id,
            observacion
        ) VALUES (
            SEQ_MOVIMIENTO.NEXTVAL,
            p_producto_id,
            SYSDATE,
            'SALIDA',
            p_cantidad,
            p_venta_id,
            'Salida por venta'
        );

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20001, 'Producto inexistente.');
    END DESCONTAR_STOCK;


    PROCEDURE DEVOLVER_STOCK (
        p_producto_id IN NUMBER,
        p_cantidad    IN NUMBER,
        p_venta_id    IN NUMBER
    )
    IS
    BEGIN
        UPDATE PRODUCTO
           SET stock = stock + p_cantidad
         WHERE producto_id = p_producto_id;

        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20001, 'Producto inexistente.');
        END IF;

        INSERT INTO MOVIMIENTO_STOCK (
            movimiento_id,
            producto_id,
            fecha_movimiento,
            tipo_movimiento,
            cantidad,
            venta_id,
            observacion
        ) VALUES (
            SEQ_MOVIMIENTO.NEXTVAL,
            p_producto_id,
            SYSDATE,
            'ENTRADA',
            p_cantidad,
            p_venta_id,
            'Devolucion por anulacion de venta'
        );
    END DEVOLVER_STOCK;

END PKG_INVENTARIO;
/

-- =====================================================================
-- 8. TRIGGER
-- SOLO AUDITORIA. NO MODIFICA STOCK.
-- =====================================================================

CREATE OR REPLACE TRIGGER TR_AUDITAR_PRODUCTO
AFTER UPDATE OF precio, estado ON PRODUCTO
FOR EACH ROW
BEGIN
    IF NVL(:OLD.precio, -1) <> NVL(:NEW.precio, -1) THEN
        INSERT INTO AUDITORIA_PRODUCTO (
            auditoria_id,
            producto_id,
            fecha_cambio,
            usuario_bd,
            campo_modificado,
            valor_anterior,
            valor_nuevo
        ) VALUES (
            SEQ_AUDITORIA.NEXTVAL,
            :NEW.producto_id,
            SYSDATE,
            USER,
            'PRECIO',
            TO_CHAR(:OLD.precio),
            TO_CHAR(:NEW.precio)
        );
    END IF;

    IF NVL(:OLD.estado, 'X') <> NVL(:NEW.estado, 'X') THEN
        INSERT INTO AUDITORIA_PRODUCTO (
            auditoria_id,
            producto_id,
            fecha_cambio,
            usuario_bd,
            campo_modificado,
            valor_anterior,
            valor_nuevo
        ) VALUES (
            SEQ_AUDITORIA.NEXTVAL,
            :NEW.producto_id,
            SYSDATE,
            USER,
            'ESTADO',
            :OLD.estado,
            :NEW.estado
        );
    END IF;
END;
/

-- =====================================================================
-- 9. PACKAGE DE VENTAS
-- PKG_VENTAS coordina la operacion.
-- PKG_INVENTARIO realiza EXPLICITAMENTE el descuento de stock.
-- =====================================================================

CREATE OR REPLACE PACKAGE PKG_VENTAS AS

    PROCEDURE REGISTRAR_VENTA (
        p_cliente_id  IN NUMBER,
        p_empleado_id IN NUMBER,
        p_venta_id    OUT NUMBER
    );

    PROCEDURE AGREGAR_PRODUCTO (
        p_venta_id    IN NUMBER,
        p_producto_id IN NUMBER,
        p_cantidad    IN NUMBER
    );

    FUNCTION CALCULAR_TOTAL (
        p_venta_id IN NUMBER
    ) RETURN NUMBER;

    PROCEDURE CONFIRMAR_VENTA (
        p_venta_id IN NUMBER
    );

    PROCEDURE ANULAR_VENTA (
        p_venta_id IN NUMBER
    );

    PROCEDURE MOSTRAR_RESUMEN (
        p_venta_id IN NUMBER
    );

END PKG_VENTAS;
/

CREATE OR REPLACE PACKAGE BODY PKG_VENTAS AS

    PROCEDURE REGISTRAR_VENTA (
        p_cliente_id  IN NUMBER,
        p_empleado_id IN NUMBER,
        p_venta_id    OUT NUMBER
    )
    IS
        v_existe NUMBER;
    BEGIN
        IF p_cliente_id IS NOT NULL THEN
            SELECT COUNT(*)
              INTO v_existe
              FROM CLIENTE
             WHERE cliente_id = p_cliente_id
               AND estado = 'ACTIVO';

            IF v_existe = 0 THEN
                RAISE_APPLICATION_ERROR(-20010, 'Cliente inexistente o inactivo.');
            END IF;
        END IF;

        SELECT COUNT(*)
          INTO v_existe
          FROM EMPLEADO
         WHERE empleado_id = p_empleado_id
           AND estado = 'ACTIVO';

        IF v_existe = 0 THEN
            RAISE_APPLICATION_ERROR(-20011, 'Empleado inexistente o inactivo.');
        END IF;

        p_venta_id := SEQ_VENTA.NEXTVAL;

        INSERT INTO VENTA (
            venta_id, cliente_id, empleado_id, fecha_venta, estado
        ) VALUES (
            p_venta_id, p_cliente_id, p_empleado_id, SYSDATE, 'ABIERTA'
        );

        DBMS_OUTPUT.PUT_LINE('Venta creada: ' || p_venta_id);
    END REGISTRAR_VENTA;


    PROCEDURE AGREGAR_PRODUCTO (
        p_venta_id    IN NUMBER,
        p_producto_id IN NUMBER,
        p_cantidad    IN NUMBER
    )
    IS
        v_estado VENTA.estado%TYPE;
        v_precio PRODUCTO.precio%TYPE;
    BEGIN
        SELECT estado
          INTO v_estado
          FROM VENTA
         WHERE venta_id = p_venta_id;

        IF v_estado <> 'ABIERTA' THEN
            RAISE_APPLICATION_ERROR(
                -20012,
                'Solo se pueden agregar productos a una venta ABIERTA.'
            );
        END IF;

        SELECT precio
          INTO v_precio
          FROM PRODUCTO
         WHERE producto_id = p_producto_id;

        -- =============================================================
        -- LLAMADA EXPLICITA AL INVENTARIO
        -- Aqui se observa claramente cuando se descuenta el stock.
        -- =============================================================
        PKG_INVENTARIO.DESCONTAR_STOCK(
            p_producto_id => p_producto_id,
            p_cantidad    => p_cantidad,
            p_venta_id    => p_venta_id
        );

        INSERT INTO DETALLE_VENTA (
            detalle_id,
            venta_id,
            producto_id,
            cantidad,
            precio_unitario
        ) VALUES (
            SEQ_DETALLE.NEXTVAL,
            p_venta_id,
            p_producto_id,
            p_cantidad,
            v_precio
        );

        DBMS_OUTPUT.PUT_LINE(
            'Producto ' || p_producto_id ||
            ' agregado. Stock descontado explicitamente.'
        );

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20013, 'Venta o producto inexistente.');
    END AGREGAR_PRODUCTO;


    FUNCTION CALCULAR_TOTAL (
        p_venta_id IN NUMBER
    ) RETURN NUMBER
    IS
        v_total NUMBER(12,2);
    BEGIN
        SELECT NVL(SUM(cantidad * precio_unitario), 0)
          INTO v_total
          FROM DETALLE_VENTA
         WHERE venta_id = p_venta_id;

        RETURN v_total;
    END CALCULAR_TOTAL;


    PROCEDURE CONFIRMAR_VENTA (
        p_venta_id IN NUMBER
    )
    IS
        v_estado VENTA.estado%TYPE;
        v_items NUMBER;
    BEGIN
        SELECT estado
          INTO v_estado
          FROM VENTA
         WHERE venta_id = p_venta_id;

        IF v_estado <> 'ABIERTA' THEN
            RAISE_APPLICATION_ERROR(-20014, 'La venta no se encuentra ABIERTA.');
        END IF;

        SELECT COUNT(*)
          INTO v_items
          FROM DETALLE_VENTA
         WHERE venta_id = p_venta_id;

        IF v_items = 0 THEN
            RAISE_APPLICATION_ERROR(
                -20015,
                'No se puede confirmar una venta sin productos.'
            );
        END IF;

        UPDATE VENTA
           SET estado = 'CONFIRMADA'
         WHERE venta_id = p_venta_id;

        DBMS_OUTPUT.PUT_LINE(
            'Venta confirmada. Total: $' ||
            TO_CHAR(CALCULAR_TOTAL(p_venta_id), 'FM999G999G990D00')
        );
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20016, 'Venta inexistente.');
    END CONFIRMAR_VENTA;


    PROCEDURE ANULAR_VENTA (
        p_venta_id IN NUMBER
    )
    IS
        v_estado VENTA.estado%TYPE;

        -- Cursor parametrizado: obtiene los productos de una venta.
        CURSOR c_detalle (cp_venta_id NUMBER) IS
            SELECT producto_id, cantidad
              FROM DETALLE_VENTA
             WHERE venta_id = cp_venta_id;
    BEGIN
        SELECT estado
          INTO v_estado
          FROM VENTA
         WHERE venta_id = p_venta_id
         FOR UPDATE;

        IF v_estado = 'ANULADA' THEN
            RAISE_APPLICATION_ERROR(-20017, 'La venta ya se encuentra anulada.');
        END IF;

        -- La devolucion de stock tambien es EXPLICITA.
        FOR r IN c_detalle(p_venta_id) LOOP
            PKG_INVENTARIO.DEVOLVER_STOCK(
                p_producto_id => r.producto_id,
                p_cantidad    => r.cantidad,
                p_venta_id    => p_venta_id
            );
        END LOOP;

        UPDATE VENTA
           SET estado = 'ANULADA'
         WHERE venta_id = p_venta_id;

        DBMS_OUTPUT.PUT_LINE(
            'Venta anulada. El stock fue devuelto explicitamente.'
        );

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20016, 'Venta inexistente.');
    END ANULAR_VENTA;


    PROCEDURE MOSTRAR_RESUMEN (
        p_venta_id IN NUMBER
    )
    IS
        -- RECORD aplicado dentro del proyecto.
        TYPE t_venta_resumen IS RECORD (
            venta_id    VENTA.venta_id%TYPE,
            cliente     VARCHAR2(100),
            fecha_venta VENTA.fecha_venta%TYPE,
            estado      VENTA.estado%TYPE,
            total       NUMBER(12,2)
        );

        v_resumen t_venta_resumen;
    BEGIN
        SELECT v.venta_id,
               NVL(c.nombre, 'Consumidor final'),
               v.fecha_venta,
               v.estado,
               CALCULAR_TOTAL(v.venta_id)
          INTO v_resumen.venta_id,
               v_resumen.cliente,
               v_resumen.fecha_venta,
               v_resumen.estado,
               v_resumen.total
          FROM VENTA v
          LEFT JOIN CLIENTE c
            ON c.cliente_id = v.cliente_id
         WHERE v.venta_id = p_venta_id;

        DBMS_OUTPUT.PUT_LINE('-------------------------------');
        DBMS_OUTPUT.PUT_LINE('VENTA   : ' || v_resumen.venta_id);
        DBMS_OUTPUT.PUT_LINE('CLIENTE : ' || v_resumen.cliente);
        DBMS_OUTPUT.PUT_LINE('FECHA   : ' || TO_CHAR(v_resumen.fecha_venta,'DD-MM-YYYY HH24:MI'));
        DBMS_OUTPUT.PUT_LINE('ESTADO  : ' || v_resumen.estado);
        DBMS_OUTPUT.PUT_LINE('TOTAL   : $' || v_resumen.total);
        DBMS_OUTPUT.PUT_LINE('-------------------------------');

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20016, 'Venta inexistente.');
    END MOSTRAR_RESUMEN;

END PKG_VENTAS;
/

-- =====================================================================
-- 10. CURSOR SIN PARAMETROS
-- =====================================================================

DECLARE
    CURSOR c_stock_bajo IS
        SELECT producto_id, nombre, stock
          FROM PRODUCTO
         WHERE stock <= 15
         ORDER BY stock;

BEGIN
    DBMS_OUTPUT.PUT_LINE('PRODUCTOS CON STOCK BAJO');

    FOR r IN c_stock_bajo LOOP
        DBMS_OUTPUT.PUT_LINE(
            r.producto_id || ' - ' ||
            r.nombre || ' - Stock: ' ||
            r.stock
        );
    END LOOP;
END;
/

-- =====================================================================
-- 11. PRUEBA COMPLETA: REGISTRAR UNA VENTA
-- Observe que NO se hace COMMIT dentro de los packages.
-- La transaccion queda bajo control del bloque llamador/aplicacion.
-- =====================================================================

DECLARE
    v_venta_id NUMBER;
BEGIN
    PKG_VENTAS.REGISTRAR_VENTA(
        p_cliente_id  => 1,
        p_empleado_id => 1,
        p_venta_id    => v_venta_id
    );

    PKG_VENTAS.AGREGAR_PRODUCTO(
        p_venta_id    => v_venta_id,
        p_producto_id => 1,
        p_cantidad    => 2
    );

    PKG_VENTAS.AGREGAR_PRODUCTO(
        p_venta_id    => v_venta_id,
        p_producto_id => 3,
        p_cantidad    => 1
    );

    PKG_VENTAS.CONFIRMAR_VENTA(v_venta_id);
    PKG_VENTAS.MOSTRAR_RESUMEN(v_venta_id);

    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
        RAISE;
END;
/

-- =====================================================================
-- 12. CONSULTAS DE COMPROBACION
-- =====================================================================

SELECT producto_id, nombre, precio, stock, estado
FROM PRODUCTO
ORDER BY producto_id;

SELECT *
FROM VENTA
ORDER BY venta_id;

SELECT *
FROM DETALLE_VENTA
ORDER BY detalle_id;

SELECT *
FROM MOVIMIENTO_STOCK
ORDER BY movimiento_id;

-- =====================================================================
-- 13. PRUEBA DE AUDITORIA
-- El trigger registra precio/estado, NO STOCK.
-- =====================================================================

UPDATE PRODUCTO
   SET precio = 2300
 WHERE producto_id = 1;

COMMIT;

SELECT *
FROM AUDITORIA_PRODUCTO
ORDER BY auditoria_id;

-- =====================================================================
-- 14. PRUEBA CONTROLADA: STOCK INSUFICIENTE
-- Ejecutar separadamente durante la clase.
-- =====================================================================
/*
DECLARE
    v_venta_id NUMBER;
BEGIN
    PKG_VENTAS.REGISTRAR_VENTA(1, 1, v_venta_id);

    PKG_VENTAS.AGREGAR_PRODUCTO(
        v_venta_id,
        1,
        999
    );

    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('ERROR CONTROLADO: ' || SQLERRM);
END;
/
*/

-- =====================================================================
-- 15. PRUEBA DE ANULACION
-- Cambiar 1001 si la secuencia genero otro ID.
-- =====================================================================
/*
BEGIN
    PKG_VENTAS.ANULAR_VENTA(1001);
    COMMIT;
END;
/

SELECT producto_id, nombre, stock
FROM PRODUCTO
ORDER BY producto_id;

SELECT *
FROM MOVIMIENTO_STOCK
ORDER BY movimiento_id;
*/

-- =====================================================================
-- 16. EJERCICIOS PROPUESTOS
-- =====================================================================
-- 1) Crear FN_VENTAS_CLIENTE que reciba cliente_id y retorne la cantidad
--    de ventas realizadas.
--
-- 2) Crear PR_CAMBIAR_ESTADO_PRODUCTO para activar/inactivar productos.
--
-- 3) Modificar PKG_INVENTARIO para incorporar una entrada manual de stock.
--
-- 4) Explicar por que DESCONTAR_STOCK es un procedimiento y no una funcion.
--
-- 5) Explicar por que el descuento de stock NO se implemento con trigger.
--
-- 6) Incorporar una excepcion si se intenta confirmar una venta cuyo total
--    sea cero.
--
-- 7) Crear un cursor parametrizado que liste los productos de una venta.
--
-- 8) Proponer otro caso del proyecto donde RECORD aporte claridad.
--
-- 9) Evaluar si existe algun caso real del proyecto que justifique VARRAY.
--
-- 10) Crear una consulta que reconstruya la trazabilidad de stock por producto.

-- =====================================================================
-- FIN
-- =====================================================================
