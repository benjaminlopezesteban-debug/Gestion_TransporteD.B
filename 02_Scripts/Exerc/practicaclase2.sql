

/* Borrado de las tablas en la base de datos */

DROP TABLE cliente CASCADE CONSTRAINT;
DROP TABLE producto CASCADE CONSTRAINT;
DROP TABLE venta CASCADE CONSTRAINT;
DROP TABLE detalle_venta CASCADE CONSTRAINT;


/* Creación de las tablas en la base de datos */

CREATE TABLE cliente (
    id_cliente NUMBER PRIMARY KEY,
    nombre     VARCHAR2(100),
    ciudad     VARCHAR2(50),
    email      VARCHAR2(100)
);

INSERT INTO cliente VALUES(1, 'Juan Perez', 'Santiago', 'juan@gmail.com');
INSERT INTO cliente VALUES(2, 'Maria Gonzalez', 'Valparaiso', 'maria@gmail.com');
INSERT INTO cliente VALUES(3, 'Carlos Soto', 'Concepcion', 'carlos@gmail.com');
INSERT INTO cliente VALUES(4, 'Ana Morales', 'Santiago', 'ana@gmail.com');
INSERT INTO cliente VALUES(5, 'Pedro Rojas', 'La Serena', 'pedro@gmail.com');
COMMIT;


CREATE TABLE producto (
    id_producto NUMBER PRIMARY KEY,
    nombre      VARCHAR2(100),
    categoria   VARCHAR2(50),
    precio      NUMBER(10,2),
    stock       NUMBER
);

INSERT INTO producto VALUES(101, 'Notebook Lenovo', 'Computadores', 750000, 15);
INSERT INTO producto VALUES(102, 'Mouse Logitech', 'Accesorios', 25000, 50);
INSERT INTO producto VALUES(103, 'Teclado Logitech', 'Accesorios', 35000, 40);
INSERT INTO producto VALUES(104, 'Monitor Samsung 24', 'Monitores', 180000, 20);
INSERT INTO producto VALUES(105, 'Impresora HP', 'Impresoras', 120000, 10);
INSERT INTO producto VALUES(106, 'Disco SSD 1TB', 'Almacenamiento', 85000, 25);
INSERT INTO producto VALUES(107, 'Memoria RAM 16GB', 'Componentes', 55000, 30);
INSERT INTO producto VALUES(108, 'Webcam Logitech', 'Accesorios', 45000, 35);
COMMIT;


CREATE TABLE venta (
    id_venta      NUMBER PRIMARY KEY,
    id_cliente    NUMBER,
    fecha_venta   DATE,
    total         NUMBER(12,2),
    CONSTRAINT fk_venta_cliente
        FOREIGN KEY (id_cliente)
        REFERENCES cliente(id_cliente)
);

INSERT INTO venta VALUES(1001, 1, DATE '2026-08-01', 800000);
INSERT INTO venta VALUES(1002, 2, DATE '2026-08-02', 215000);
INSERT INTO venta VALUES(1003, 3, DATE '2026-08-03', 300000);
INSERT INTO venta VALUES(1004, 1, DATE '2026-08-04', 120000);
INSERT INTO venta VALUES(1005, 4, DATE '2026-08-05', 265000);
COMMIT;

CREATE TABLE detalle_venta (
    id_detalle  NUMBER PRIMARY KEY,
    id_venta    NUMBER,
    id_producto NUMBER,
    cantidad    NUMBER,
    precio      NUMBER(10,2),


    CONSTRAINT fk_detalle_venta FOREIGN KEY (id_venta) REFERENCES venta(id_venta),
    CONSTRAINT fk_detalle_producto FOREIGN KEY (id_producto) REFERENCES producto(id_producto)
);


INSERT INTO detalle_venta VALUES(1, 1001, 101, 1, 750000);
INSERT INTO detalle_venta VALUES(2, 1001, 102, 2, 25000);
INSERT INTO detalle_venta VALUES(3, 1002, 104, 1, 180000);
INSERT INTO detalle_venta VALUES(4, 1002, 102, 1, 25000);
INSERT INTO detalle_venta VALUES(5, 1003, 105, 1, 120000);
INSERT INTO detalle_venta VALUES(6, 1003, 106, 2, 85000);
INSERT INTO detalle_venta VALUES(7, 1004, 105, 1, 120000);
INSERT INTO detalle_venta VALUES(8, 1005, 107, 2, 55000);
INSERT INTO detalle_venta VALUES(9, 1005, 108, 1, 45000);
INSERT INTO detalle_venta VALUES(10, 1005, 102, 1, 25000);
COMMIT;


SELECT * FROM cliente ;
SELECT * FROM producto;
SELECT * FROM venta;
SELECT * FROM detalle_venta;

/*
EJERCICIO 1 – RECORD de clientes
Enunciado

Crear un bloque PL/SQL que consulte la tabla CLIENTE utilizando una variable de tipo RECORD.

El programa debe buscar el cliente cuyo ID_CLIENTE sea 1 y mostrar:

ID del cliente.
Nombre.
Ciudad.
Correo electrónico.
*/

SET SERVEROUTPUT ON;

DECLARE

    TYPE cliente_record IS RECORD (
        id_cliente cliente.id_cliente%TYPE,
        nombre     cliente.nombre%TYPE,
        ciudad     cliente.ciudad%TYPE,
        email      cliente.email%TYPE
    );

    v_cliente cliente_record; --asignación de la variable de tipo RECORD. Es similar a una tabla temporal que almacena los datos de un cliente para manipulación

BEGIN

    SELECT id_cliente, nombre, ciudad, email
    INTO v_cliente
    FROM cliente
    WHERE id_cliente = 1;

    DBMS_OUTPUT.PUT_LINE('ID del cliente: ' || v_cliente.id_cliente);
    DBMS_OUTPUT.PUT_LINE('Nombre: ' || v_cliente.nombre);
    DBMS_OUTPUT.PUT_LINE('Ciudad: ' || v_cliente.ciudad);
    DBMS_OUTPUT.PUT_LINE('Correo electrónico: ' || v_cliente.email);

END;
/


/*
EJERCICIO 2 – RECORD para una venta
Enunciado

Crear un bloque PL/SQL que consulte la tabla VENTA y almacene en un RECORD la información correspondiente a la venta 1001.

Mostrar:

Número de venta.
Fecha.
ID del cliente.
Total.
*/

SET SERVEROUTPUT ON;
DECLARE

    TYPE venta_record IS RECORD (
        id_venta      venta.id_venta%TYPE,
        id_cliente    venta.id_cliente%TYPE,
        fecha_venta  venta.fecha_venta%TYPE,
        total   venta.total%TYPE
    );

    v_venta venta_record;

BEGIN

    SELECT id_venta, id_cliente, fecha_venta, total
    INTO v_venta
    FROM venta
    WHERE id_venta = 1001;

    DBMS_OUTPUT.PUT_LINE('Id de la venta : ' || v_venta.id_venta);
    DBMS_OUTPUT.PUT_LINE('Id del cliente : ' || v_venta.id_cliente);
    DBMS_OUTPUT.PUT_LINE('fecha de la venta : ' || v_venta.fecha_venta);
    DBMS_OUTPUT.PUT_LINE('Total: ' || v_venta.total);

END;
/ 






/*
EJERCICIO 3 – VARRAY de productos
Enunciado

Crear un bloque PL/SQL que consulte la tabla PRODUCTO y almacene en un VARRAY los nombres de los productos pertenecientes a la categoría Accesorios.

El VARRAY debe permitir almacenar como máximo 5 productos.

Mostrar todos los productos almacenados.
*/

SET SERVEROUTPUT ON;

DECLARE 

    TYPE accesorios_varray IS VARRAY(5) 
        OF producto.nombre%TYPE;

    v_accesorios accesorios_varray;

    v_contador NUMBER := 0;
    v_productos accesorios_varray;

    FOR r in (
        SELECT nombre
        FROM producto
        WHERE categoria = 'Accesorios'
        ORDER BY id_producto
    ) LOOP

        v_contador := v_contador + 1;
        v_productos.extend; -- Extiende el VARRAY para agregar un nuevo elemento
        v_productos(v_contador) := r.nombre; -- Asigna el nombre del producto

    END LOOP;   

    DBMS_OUTPUT.PUT_LINE('Productos de Accesorios:');
    DBMS_OUTPUT.PUT_LINE('-----------------------');

    FOR i IN 1 .. v_productos.count LOOP
        DBMS_OUTPUT.PUT_LINE(v_productos(i));
    END LOOP;

END;
/SET SERVEROUTPUT ON;

DECLARE 

    TYPE accesorios_varray IS VARRAY(5) 
        OF producto.nombre%TYPE;

    v_accesorios accesorios_varray;

    v_contador NUMBER := 0;
    v_productos VARCHAR2;
BEGIN

    FOR r in (
        SELECT nombre
        FROM producto
        WHERE categoria = 'Accesorios'
        ORDER BY id_producto
    ) LOOP

        v_contador := v_contador + 1;
        v_productos.extend; -- Extiende el VARRAY para agregar un nuevo elemento
        v_productos(v_contador) := r.nombre; -- Asigna el nombre del producto

    END LOOP;   

    DBMS_OUTPUT.PUT_LINE('Productos de Accesorios:');
    DBMS_OUTPUT.PUT_LINE('-----------------------');

    FOR i IN 1 .. v_productos.count LOOP
        DBMS_OUTPUT.PUT_LINE(v_productos(i));
    END LOOP;

END;

/BER := 0;
BEGIN

    FOR r in (
        SELECT nombre
        FROM producto
        WHERE categoria = 'Accesorios'
        ORDER BY id_producto
    ) LOOP

        v_contador := v_contador + 1;
        v_productos.extend; -- Extiende el VARRAY para agregar un nuevo elemento
        v_productos(v_contador) := r.nombre; -- Asigna el nombre del producto

    END LOOP;   

    DBMS_OUTPUT.PUT_LINE('Productos de Accesorios:');
    DBMS_OUTPUT.PUT_LINE('-----------------------');

    FOR i IN 1 .. v_productos.count LOOP
        DBMS_OUTPUT.PUT_LINE(v_productos(i));
    END LOOP;

END;
/


/*
EJERCICIO 4 – VARRAY para descuentos

La empresa tiene diferentes porcentajes de descuento para sus clientes.

Crear un VARRAY que permita almacenar hasta 5 porcentajes de descuento.

Los valores serán:

5%
10%
15%
20%
25%

El programa debe consultar el total de la venta 1001 y calcular cuánto pagaría el cliente aplicando cada descuento.
*/



/*
EJERCICIO 5 – RECORD + VARRAY

Para la venta 1005, consultar los productos vendidos.

El programa debe utilizar:

Un RECORD para almacenar información de cada producto.
Un VARRAY para almacenar los nombres de los productos.

Por cada producto se debe mostrar:

Nombre.
Cantidad.
Precio.
Subtotal.
*/



/*
EJERCICIO 6 – INTEGRADOR: RECORD + VARRAY

La empresa necesita generar un pequeño resumen de una venta.

Crear un bloque PL/SQL que reciba el número de venta 1001 y:

Consulte la información de la venta.
Utilice un RECORD para almacenar:
Número de venta.
ID del cliente.
Nombre del cliente.
Fecha.
Total.
Utilice un VARRAY para almacenar los nombres de todos los productos vendidos.
Mostrar la información de la venta.
Mostrar los productos incluidos en la venta.
Calcular la cantidad de productos diferentes vendidos.
Mostrar el total de la venta.
*/

--iNTEGRADOR TOMA VARIABLES TIPO RECORD Y VARRAY PARA MOSTRAR INFORMACION DE LA VENTA
--Siempre la variable record es primera por que es el valor que se tiene que consultar
--posteriormente es el varray que es el que almacena los productos de la venta.


