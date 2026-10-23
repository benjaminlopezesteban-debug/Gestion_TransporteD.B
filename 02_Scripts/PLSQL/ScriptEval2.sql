-- *Proyecto Sistema de Transporte de Pasajeros*
-- *Script de Evaluación 2*


--Ojo los procedimientos tiene valores de salida con la definición out, y las funciones no. Las funciones devuelven un valor con RETURN.
-- Package -> package body -> package body

--Llamadas explicitas a otros package. PAra el cumpliemiento de las reglas de negocio que son las que guiaran las preguntas
--del profe. 
--Preguntara porque estamos ocupando ciertos tipos de excepciones. 

-- 0.- Limpiar el entorno de trabajo

DROP TABLE pasaje_estado_hist CASCADE CONSTRAINTS PURGE;
DROP TABLE pasaje             CASCADE CONSTRAINTS PURGE;
DROP TABLE venta              CASCADE CONSTRAINTS PURGE;
DROP TABLE tarifa             CASCADE CONSTRAINTS PURGE;
DROP TABLE pasajero           CASCADE CONSTRAINTS PURGE;
DROP TABLE viaje_conductor    CASCADE CONSTRAINTS PURGE;
DROP TABLE viaje              CASCADE CONSTRAINTS PURGE;
DROP TABLE conductor          CASCADE CONSTRAINTS PURGE;
DROP TABLE asiento            CASCADE CONSTRAINTS PURGE;
DROP TABLE bus                CASCADE CONSTRAINTS PURGE;
DROP TABLE ruta               CASCADE CONSTRAINTS PURGE;
DROP TABLE estado_pasaje      CASCADE CONSTRAINTS PURGE;
DROP TABLE tipo_asiento       CASCADE CONSTRAINTS PURGE;
DROP TABLE terminal           CASCADE CONSTRAINTS PURGE;


-- 2.- Crear las tablas

-- TERMINAL

CREATE TABLE terminal (
    id_terminal        NUMBER(6)          NOT NULL,
    nombre_terminal    VARCHAR2(60 CHAR)  NOT NULL,
    ciudad             VARCHAR2(60 CHAR)  NOT NULL,
    direccion          VARCHAR2(120 CHAR) NOT NULL,
    CONSTRAINT pk_terminal        PRIMARY KEY (id_terminal),
    CONSTRAINT uk_terminal_nombre UNIQUE      (nombre_terminal, ciudad)
);



-- TIPO_ASIENTO
-- Habilita el precio diferenciado por tipo (semi cama, salon cama, premium).
CREATE TABLE tipo_asiento (
    id_tipo_asiento    NUMBER(4)          NOT NULL,
    codigo             VARCHAR2(5 CHAR)   NOT NULL,
    nombre             VARCHAR2(40 CHAR)  NOT NULL,
    CONSTRAINT pk_tipo_asiento     PRIMARY KEY (id_tipo_asiento),
    CONSTRAINT uk_tipo_asiento_cod UNIQUE      (codigo)
);


-- ESTADO_PASAJE
-- ocupa_asiento = 'S' / SI , 'N' / NO.
CREATE TABLE estado_pasaje (
    id_estado          NUMBER(4)          NOT NULL,
    codigo             VARCHAR2(5 CHAR)   NOT NULL,
    nombre             VARCHAR2(40 CHAR)  NOT NULL,
    ocupa_asiento      CHAR(1 CHAR)       NOT NULL,
    CONSTRAINT pk_estado_pasaje     PRIMARY KEY (id_estado),
    CONSTRAINT uk_estado_pasaje_cod UNIQUE      (codigo),
    CONSTRAINT ck_estado_ocupa      CHECK       (ocupa_asiento IN ('S','N'))
);


-- RUTA
-- Origen y destino son FK a TERMINAL, no texto libre.
CREATE TABLE ruta (
    id_ruta                NUMBER(6)      NOT NULL,
    id_terminal_origen     NUMBER(6)      NOT NULL,
    id_terminal_destino    NUMBER(6)      NOT NULL,
    distancia_km           NUMBER(6)      NOT NULL,
    duracion_estimada_min  NUMBER(6)      NOT NULL,
    CONSTRAINT pk_ruta           PRIMARY KEY (id_ruta),
    CONSTRAINT uk_ruta_od        UNIQUE      (id_terminal_origen, id_terminal_destino),
    CONSTRAINT fk_ruta_origen    FOREIGN KEY (id_terminal_origen)
                                 REFERENCES  terminal (id_terminal),
    CONSTRAINT fk_ruta_destino   FOREIGN KEY (id_terminal_destino)
                                 REFERENCES  terminal (id_terminal),
    CONSTRAINT ck_ruta_od_distin CHECK       (id_terminal_origen <> id_terminal_destino),
    CONSTRAINT ck_ruta_distancia CHECK       (distancia_km > 0),
    CONSTRAINT ck_ruta_duracion  CHECK       (duracion_estimada_min > 0)
);


-- BUS
-- Sin nro_asientos_totales: la capacidad es COUNT(*) sobre ASIENTO y asi
-- nunca puede contradecir a los asientos que realmente existen.
CREATE TABLE bus (
    id_bus             NUMBER(6)          NOT NULL,
    patente            VARCHAR2(8 CHAR)   NOT NULL,
    modelo             VARCHAR2(60 CHAR)  NOT NULL,
    anio_fabricacion   NUMBER(4)          NOT NULL,
    fecha_compra       DATE               NOT NULL,
    CONSTRAINT pk_bus         PRIMARY KEY (id_bus),
    CONSTRAINT uk_bus_patente UNIQUE      (patente),
    CONSTRAINT ck_bus_anio    CHECK       (anio_fabricacion BETWEEN 1980 AND 2100)
);


-- ASIENTO
-- El asiento pertenece al BUS, no al viaje. PK compuesta natural.

CREATE TABLE asiento (
    id_bus             NUMBER(6)          NOT NULL,
    nro_asiento        NUMBER(4)          NOT NULL,
    id_tipo_asiento    NUMBER(4)          NOT NULL,
    piso               NUMBER(1)          NOT NULL,
    CONSTRAINT pk_asiento      PRIMARY KEY (id_bus, nro_asiento),
    CONSTRAINT fk_asiento_bus  FOREIGN KEY (id_bus)
                               REFERENCES  bus (id_bus),
    CONSTRAINT fk_asiento_tipo FOREIGN KEY (id_tipo_asiento)
                               REFERENCES  tipo_asiento (id_tipo_asiento),
    CONSTRAINT ck_asiento_nro  CHECK       (nro_asiento > 0),
    CONSTRAINT ck_asiento_piso CHECK       (piso IN (1,2))
);


-- CONDUCTOR
CREATE TABLE conductor (
    id_conductor       NUMBER(6)          NOT NULL,
    run                NUMBER(8)          NOT NULL,
    dv                 CHAR(1 CHAR)       NOT NULL,
    pnombre            VARCHAR2(40 CHAR)  NOT NULL,
    snombre            VARCHAR2(40 CHAR),
    papellido          VARCHAR2(40 CHAR)  NOT NULL,
    sapellido          VARCHAR2(40 CHAR),
    nro_licencia       VARCHAR2(20 CHAR)  NOT NULL,
    fecha_contrato     DATE               NOT NULL,
    CONSTRAINT pk_conductor          PRIMARY KEY (id_conductor),
    CONSTRAINT uk_conductor_run      UNIQUE      (run),
    CONSTRAINT uk_conductor_licencia UNIQUE      (nro_licencia),
    CONSTRAINT ck_conductor_dv       CHECK       (dv IN ('0','1','2','3','4','5','6','7','8','9','K'))
);


-- VIAJE  
-- es lo que permite comparar intervalos y detectar superposiciones.
-- uk_viaje_bus es aparentemente redundante, pero es el destino de la FK
-- compuesta de PASAJE que ata el asiento al bus correcto.

CREATE TABLE viaje (
    id_viaje           NUMBER(10)         NOT NULL,
    id_ruta            NUMBER(6)          NOT NULL,
    id_bus             NUMBER(6)          NOT NULL,
    salida_prog        TIMESTAMP          NOT NULL,
    llegada_prog       TIMESTAMP          NOT NULL,
    estado_viaje       VARCHAR2(3 CHAR)   DEFAULT 'PRO' NOT NULL,
    CONSTRAINT pk_viaje           PRIMARY KEY (id_viaje),
    CONSTRAINT uk_viaje_bus       UNIQUE      (id_viaje, id_bus),
    CONSTRAINT fk_viaje_ruta      FOREIGN KEY (id_ruta)
                                  REFERENCES  ruta (id_ruta),
    CONSTRAINT fk_viaje_bus       FOREIGN KEY (id_bus)
                                  REFERENCES  bus (id_bus),
    CONSTRAINT ck_viaje_intervalo CHECK       (llegada_prog > salida_prog),
    CONSTRAINT ck_viaje_estado    CHECK       (estado_viaje IN ('PRO','ENC','FIN','CAN'))
);


-- VIAJE_CONDUCTOR
-- rol: TIT = titular, REL = relevo.

CREATE TABLE viaje_conductor (
    id_viaje           NUMBER(10)         NOT NULL,
    id_conductor       NUMBER(6)          NOT NULL,
    rol                VARCHAR2(3 CHAR)   DEFAULT 'TIT' NOT NULL,
    CONSTRAINT pk_viaje_conductor   PRIMARY KEY (id_viaje, id_conductor),
    CONSTRAINT fk_vc_viaje          FOREIGN KEY (id_viaje)
                                    REFERENCES  viaje (id_viaje),
    CONSTRAINT fk_vc_conductor      FOREIGN KEY (id_conductor)
                                    REFERENCES  conductor (id_conductor),
    CONSTRAINT ck_vc_rol            CHECK       (rol IN ('TIT','REL'))
);


-- PASAJERO

CREATE TABLE pasajero (
    id_pasajero        NUMBER(10)         NOT NULL,
    run                NUMBER(8)          NOT NULL,
    dv                 CHAR(1 CHAR)       NOT NULL,
    pnombre            VARCHAR2(40 CHAR)  NOT NULL,
    snombre            VARCHAR2(40 CHAR),
    papellido          VARCHAR2(40 CHAR)  NOT NULL,
    sapellido          VARCHAR2(40 CHAR),
    mail               VARCHAR2(80 CHAR),
    telefono           VARCHAR2(20 CHAR),
    CONSTRAINT pk_pasajero     PRIMARY KEY (id_pasajero),
    CONSTRAINT uk_pasajero_run UNIQUE      (run),
    CONSTRAINT ck_pasajero_dv  CHECK       (dv IN ('0','1','2','3','4','5','6','7','8','9','K'))
);


-- TARIFA
-- Condicion comercial es la vigencia. Una tarifa nueva es una fila nueva,
-- nunca un UPDATE sobre la anterior.

CREATE TABLE tarifa (
    id_tarifa          NUMBER(10)         NOT NULL,
    id_ruta            NUMBER(6)          NOT NULL,
    id_tipo_asiento    NUMBER(4)          NOT NULL,
    vigencia_desde     DATE               NOT NULL,
    vigencia_hasta     DATE,
    precio             NUMBER(10,2)       NOT NULL,
    CONSTRAINT pk_tarifa          PRIMARY KEY (id_tarifa),
    CONSTRAINT uk_tarifa_vigencia UNIQUE      (id_ruta, id_tipo_asiento, vigencia_desde),
    CONSTRAINT fk_tarifa_ruta     FOREIGN KEY (id_ruta)
                                  REFERENCES  ruta (id_ruta),
    CONSTRAINT fk_tarifa_tipo     FOREIGN KEY (id_tipo_asiento)
                                  REFERENCES  tipo_asiento (id_tipo_asiento),
    CONSTRAINT ck_tarifa_precio   CHECK       (precio >= 0),
    CONSTRAINT ck_tarifa_rango    CHECK       (vigencia_hasta IS NULL OR vigencia_hasta > vigencia_desde)
);


-- VENTA
-- Cabecera comercial. Sin precio_total (es SUM sobre PASAJE) y sin id_viaje:

CREATE TABLE venta (
    id_venta               NUMBER(10)     NOT NULL,
    id_pasajero_comprador  NUMBER(10)     NOT NULL,
    fecha_hora             TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    canal                  VARCHAR2(3 CHAR) NOT NULL,
    medio_pago             VARCHAR2(3 CHAR) NOT NULL,
    CONSTRAINT pk_venta            PRIMARY KEY (id_venta),
    CONSTRAINT fk_venta_comprador  FOREIGN KEY (id_pasajero_comprador)
                                   REFERENCES  pasajero (id_pasajero),
    CONSTRAINT ck_venta_canal      CHECK       (canal IN ('WEB','MOV','TER','AGE')),
    CONSTRAINT ck_venta_medio      CHECK       (medio_pago IN ('TDC','TDB','EFE','TRA'))
);


-- PASAJE
-- La entidad central: un pasajero, un viaje, un asiento, un estado.
--
-- id_bus aparece aqui a proposito. Con las dos FK compuestas
--   (id_viaje, id_bus)      -> VIAJE   (uk_viaje_bus)
--   (id_bus, nro_asiento)   -> ASIENTO (pk_asiento)
--
-- precio_aplicado es el precio congelado en el
-- instante de la venta. Si sube la tarifa, el pasaje emitido no cambia.

CREATE TABLE pasaje (
    id_pasaje          NUMBER(12)         NOT NULL,
    id_venta           NUMBER(10)         NOT NULL,
    id_viaje           NUMBER(10)         NOT NULL,
    id_bus             NUMBER(6)          NOT NULL,
    nro_asiento        NUMBER(4)          NOT NULL,
    id_pasajero        NUMBER(10)         NOT NULL,
    id_tarifa          NUMBER(10)         NOT NULL,
    precio_aplicado    NUMBER(10,2)       NOT NULL,
    descuento          NUMBER(10,2)       DEFAULT 0 NOT NULL,
    id_estado          NUMBER(4)          NOT NULL,
    fecha_emision      TIMESTAMP          DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_pasaje           PRIMARY KEY (id_pasaje),
    CONSTRAINT fk_pasaje_venta     FOREIGN KEY (id_venta)
                                   REFERENCES  venta (id_venta),
    CONSTRAINT fk_pasaje_viaje_bus FOREIGN KEY (id_viaje, id_bus)
                                   REFERENCES  viaje (id_viaje, id_bus),
    CONSTRAINT fk_pasaje_asiento   FOREIGN KEY (id_bus, nro_asiento)
                                   REFERENCES  asiento (id_bus, nro_asiento),
    CONSTRAINT fk_pasaje_pasajero  FOREIGN KEY (id_pasajero)
                                   REFERENCES  pasajero (id_pasajero),
    CONSTRAINT fk_pasaje_tarifa    FOREIGN KEY (id_tarifa)
                                   REFERENCES  tarifa (id_tarifa),
    CONSTRAINT fk_pasaje_estado    FOREIGN KEY (id_estado)
                                   REFERENCES  estado_pasaje (id_estado),
    CONSTRAINT ck_pasaje_precio    CHECK       (precio_aplicado >= 0),
    CONSTRAINT ck_pasaje_descuento CHECK       (descuento >= 0 AND descuento <= precio_aplicado)
);


-- PASAJE_ESTADO_HIST
-- Cada transicion deja rastro. Sin esto una anulacion es indistinguible de
-- una venta que nunca ocurrio, y el negocio no puede auditar quien anulo que.
CREATE TABLE pasaje_estado_hist (
    id_pasaje          NUMBER(12)         NOT NULL,
    secuencia          NUMBER(4)          NOT NULL,
    fecha_hora         TIMESTAMP          DEFAULT SYSTIMESTAMP NOT NULL,
    id_estado          NUMBER(4)          NOT NULL,
    usuario            VARCHAR2(40 CHAR)  NOT NULL,
    motivo             VARCHAR2(200 CHAR),
    CONSTRAINT pk_pasaje_hist        PRIMARY KEY (id_pasaje, secuencia),
    CONSTRAINT fk_hist_pasaje        FOREIGN KEY (id_pasaje)
                                     REFERENCES  pasaje (id_pasaje),
    CONSTRAINT fk_hist_estado        FOREIGN KEY (id_estado)
                                     REFERENCES  estado_pasaje (id_estado),
    CONSTRAINT ck_hist_secuencia     CHECK       (secuencia > 0)
);

-- 3.- Sequencias para las PKs de las tablas.

CREATE SEQUENCE seq_terminal        START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_tipo_asiento    START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_estado_pasaje   START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_ruta            START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_bus             START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_asiento         START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_conductor       START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_viaje           START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_viaje_conductor START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_pasajero        START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_tarifa          START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_venta           START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_pasaje          START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_pasaje_estado_hist START WITH 1 INCREMENT BY 1;

-- A.- Programación

-- A1.- Creación de Viajes. Asignación de Bus y Hora. 
CREATE OR REPLACE PACKAGE pkg_programacion_viaje IS

    -- Calcula la llegada a partir de la duración estimada de la ruta.
    FUNCTION fn_llegada_prog (
        p_id_ruta     IN ruta.id_ruta%TYPE,
        p_salida_prog IN viaje.salida_prog%TYPE
    ) RETURN viaje.llegada_prog%TYPE;

    -- Registro para representar el intervalo del viaje.
    TYPE tr_bloque IS RECORD (
        inicio_prog  viaje.salida_prog%TYPE,
        llegada_prog viaje.llegada_prog%TYPE
    );

    -- Registra un viaje y devuelve su identificador.
    PROCEDURE pr_registrar_viaje (
        p_id_ruta      IN  viaje.id_ruta%TYPE,
        p_id_bus       IN  viaje.id_bus%TYPE,
        p_salida_prog  IN  viaje.salida_prog%TYPE,
        p_llegada_prog IN  viaje.llegada_prog%TYPE DEFAULT NULL,
        p_estado_viaje IN  viaje.estado_viaje%TYPE DEFAULT 'PRO',
        p_id_viaje     OUT viaje.id_viaje%TYPE
    );

END pkg_programacion_viaje;
/
CREATE OR REPLACE PACKAGE BODY pkg_programacion_viaje IS

    ------------------------------------------------------------------
    -- FUNCIÓN: calcular la llegada programada
    ------------------------------------------------------------------
    FUNCTION fn_llegada_prog (
        p_id_ruta     IN ruta.id_ruta%TYPE,
        p_salida_prog IN viaje.salida_prog%TYPE
    ) RETURN viaje.llegada_prog%TYPE
    IS
        v_duracion_min ruta.duracion_estimada_min%TYPE;
    BEGIN
        IF p_salida_prog IS NULL THEN
            RAISE_APPLICATION_ERROR(
                -20001,
                'La fecha y hora de salida son obligatorias.'
            );
        END IF;

        SELECT duracion_estimada_min
        INTO v_duracion_min
        FROM ruta
        WHERE id_ruta = p_id_ruta;

        RETURN p_salida_prog
               + NUMTODSINTERVAL(v_duracion_min, 'MINUTE');

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(
                -20002,
                'La ruta ' || p_id_ruta || ' no existe.'
            );
    END fn_llegada_prog;


    ------------------------------------------------------------------
    -- PROCEDIMIENTO: registrar un viaje
    ------------------------------------------------------------------
    PROCEDURE pr_registrar_viaje (
        p_id_ruta      IN  viaje.id_ruta%TYPE,
        p_id_bus       IN  viaje.id_bus%TYPE,
        p_salida_prog  IN  viaje.salida_prog%TYPE,
        p_llegada_prog IN  viaje.llegada_prog%TYPE DEFAULT NULL,
        p_estado_viaje IN  viaje.estado_viaje%TYPE DEFAULT 'PRO',
        p_id_viaje     OUT viaje.id_viaje%TYPE
    )
    IS
        v_llegada     viaje.llegada_prog%TYPE;
        v_existe      NUMBER;
        v_bus_ocupado NUMBER;
    BEGIN
        p_id_viaje := NULL;

        --------------------------------------------------------------
        -- 1. Validar los datos básicos
        --------------------------------------------------------------
        IF p_salida_prog IS NULL THEN
            RAISE_APPLICATION_ERROR(
                -20003,
                'Debe indicar la fecha y hora de salida.'
            );
        END IF;

        --------------------------------------------------------------
        -- 2. Verificar que la ruta exista
        --------------------------------------------------------------
        SELECT COUNT(*)
        INTO v_existe
        FROM ruta
        WHERE id_ruta = p_id_ruta;

        IF v_existe = 0 THEN
            RAISE_APPLICATION_ERROR(
                -20010,
                'La ruta ' || p_id_ruta || ' no existe.'
            );
        END IF;

        --------------------------------------------------------------
        -- 3. Verificar que el bus exista
        --------------------------------------------------------------
        SELECT COUNT(*)
        INTO v_existe
        FROM bus
        WHERE id_bus = p_id_bus;

        IF v_existe = 0 THEN
            RAISE_APPLICATION_ERROR(
                -20011,
                'El bus ' || p_id_bus || ' no existe.'
            );
        END IF;

        --------------------------------------------------------------
        -- 4. Calcular o aceptar la llegada
        --------------------------------------------------------------
        IF p_llegada_prog IS NULL THEN
            v_llegada :=
                pkg_programacion_viaje.fn_llegada_prog(
                    p_id_ruta,
                    p_salida_prog
                );
        ELSE
            v_llegada := p_llegada_prog;
        END IF;

        --------------------------------------------------------------
        -- 5. Validar el intervalo
        --------------------------------------------------------------
        IF v_llegada <= p_salida_prog THEN
            RAISE_APPLICATION_ERROR(
                -20013,
                'La llegada debe ser posterior a la salida.'
            );
        END IF;

        --------------------------------------------------------------
        -- 6. Comprobar disponibilidad del bus
        -- Los viajes cancelados no bloquean el intervalo.
        --------------------------------------------------------------
        SELECT COUNT(*)
        INTO v_bus_ocupado
        FROM viaje v
        WHERE v.id_bus = p_id_bus
          AND v.estado_viaje <> 'CAN'
          AND v.salida_prog < v_llegada
          AND v.llegada_prog > p_salida_prog;

        IF v_bus_ocupado > 0 THEN
            RAISE_APPLICATION_ERROR(
                -20012,
                'El bus ' || p_id_bus ||
                ' ya tiene un viaje en ese intervalo.'
            );
        END IF;

        --------------------------------------------------------------
        -- 7. Generar el ID e insertar el viaje
        --------------------------------------------------------------
        SELECT seq_viaje.NEXTVAL
        INTO p_id_viaje
        FROM dual;

        INSERT INTO viaje (
            id_viaje,
            id_ruta,
            id_bus,
            salida_prog,
            llegada_prog,
            estado_viaje
        )
        VALUES (
            p_id_viaje,
            p_id_ruta,
            p_id_bus,
            p_salida_prog,
            v_llegada,
            p_estado_viaje
        );

        -- Sin COMMIT: la transacción queda bajo control del llamante.

    END pr_registrar_viaje;

END pkg_programacion_viaje;
/
SET SERVEROUTPUT ON;
--Listar
DECLARE
    r_bloque pkg_programacion_viaje.tr_bloque;

    v_ruta   ruta.id_ruta%TYPE := 7;
    v_inicio viaje.salida_prog%TYPE := TIMESTAMP '2026-11-10 08:00:00';
    v_fin viaje.llegada_prog%TYPE;

    CURSOR c_libres (
        p_ini viaje.salida_prog%TYPE,
        p_fin viaje.llegada_prog%TYPE
    )IS
        SELECT b.id_bus, b.patente, b.modelo
        FROM bus b
        WHERE NOT EXISTS (
            SELECT 1
            FROM viaje v
            WHERE v.id_bus = b.id_bus
              AND v.estado_viaje <> 'CAN'
              AND v.salida_prog < p_fin
              AND v.llegada_prog > p_ini
        )
        ORDER BY b.id_bus;

    v_cantidad PLS_INTEGER := 0;

BEGIN
    v_fin := pkg_programacion_viaje.fn_llegada_prog(
        v_ruta,
        v_inicio
    );

    r_bloque.inicio_prog  := v_inicio;
    r_bloque.llegada_prog := v_fin;

    DBMS_OUTPUT.PUT_LINE(
        'Intervalo: ' ||
        TO_CHAR(r_bloque.inicio_prog, 'YYYY-MM-DD HH24:MI') ||
        ' - ' ||
        TO_CHAR(r_bloque.llegada_prog, 'YYYY-MM-DD HH24:MI')
    );

    DBMS_OUTPUT.PUT_LINE('Buses disponibles:');

    FOR r IN c_libres(
        r_bloque.inicio_prog,
        r_bloque.llegada_prog
    ) LOOP
        v_cantidad := v_cantidad + 1;

        DBMS_OUTPUT.PUT_LINE(
            'ID: ' || r.id_bus ||
            ' | Patente: ' || r.patente ||
            ' | Modelo: ' || r.modelo
        );
    END LOOP;

    IF v_cantidad = 0 THEN
        DBMS_OUTPUT.PUT_LINE(
            'No hay buses disponibles para este intervalo.'
        );
    END IF;
END;
/
--Ejecutar Programación
DECLARE
    v_id_bus   bus.id_bus%TYPE := &id_bus;
    v_id_viaje viaje.id_viaje%TYPE;
    v_ruta   ruta.id_ruta%TYPE := 7;
    v_salida viaje.salida_prog%TYPE := TIMESTAMP '2026-11-10 08:00:00';

BEGIN


    pkg_programacion_viaje.pr_registrar_viaje(
        p_id_ruta     => v_ruta,
        p_id_bus      => v_id_bus,
        p_salida_prog => v_salida,
        p_id_viaje    => v_id_viaje
    );

    DBMS_OUTPUT.PUT_LINE(
        'Viaje programado correctamente. ID: ' || v_id_viaje
    );

    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;

        DBMS_OUTPUT.PUT_LINE(
            'No se pudo programar el viaje: ' || SQLERRM
        );

        RAISE;
END;
/
-- A2.- Asignación de Conductor. 
CREATE OR REPLACE PACKAGE pkg_programacion_conductor IS

    -- ¿Cuántos conductores exige un viaje de esta ruta? (RN-10)
    FUNCTION fn_conductores_requeridos (
        p_id_ruta IN ruta.id_ruta%TYPE
    ) RETURN PLS_INTEGER;

    -- ¿Está libre este conductor en el intervalo? (RN-03)
    FUNCTION fn_conductor_disponible (
        p_id_conductor IN conductor.id_conductor%TYPE,
        p_salida       IN viaje.salida_prog%TYPE,
        p_llegada      IN viaje.llegada_prog%TYPE,
        p_excluir      IN viaje.id_viaje%TYPE DEFAULT NULL
    ) RETURN BOOLEAN;

    -- Asignación manual de UN conductor (rol TIT o REL)
    PROCEDURE pr_asignar_conductor (
        p_id_viaje     IN viaje.id_viaje%TYPE,
        p_id_conductor IN conductor.id_conductor%TYPE,
        p_rol          IN viaje_conductor.rol%TYPE DEFAULT 'TIT'
    );

END pkg_programacion_conductor;
/
CREATE OR REPLACE PACKAGE BODY pkg_programacion_conductor IS
    ----------------------------------------------------------------------------
    -- 1. Cantidad de conductores requeridos (RN-10)
    ----------------------------------------------------------------------------
    FUNCTION fn_conductores_requeridos (
        p_id_ruta IN ruta.id_ruta%TYPE
    ) RETURN PLS_INTEGER
    IS
        c_max_horas    CONSTANT NUMBER := 5;
        v_duracion_min ruta.duracion_estimada_min%TYPE;
    BEGIN
        SELECT r.duracion_estimada_min INTO v_duracion_min
        FROM   ruta r WHERE r.id_ruta = p_id_ruta;

        RETURN CEIL(v_duracion_min / 60 / c_max_horas);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20030, 'Ruta ' || p_id_ruta || ' no existe.');
    END fn_conductores_requeridos;
    ----------------------------------------------------------------------------
    -- 2. Disponibilidad: conductor libre en el intervalo
    ----------------------------------------------------------------------------
    FUNCTION fn_conductor_disponible (
        p_id_conductor IN conductor.id_conductor%TYPE,
        p_salida       IN viaje.salida_prog%TYPE,
        p_llegada      IN viaje.llegada_prog%TYPE,
        p_excluir      IN viaje.id_viaje%TYPE DEFAULT NULL
    ) RETURN BOOLEAN
    IS
        v_ocupado NUMBER;
    BEGIN
        SELECT COUNT(*)
        INTO   v_ocupado
        FROM   viaje_conductor vc
        JOIN   viaje v ON v.id_viaje = vc.id_viaje
        WHERE  vc.id_conductor = p_id_conductor
        AND    v.estado_viaje <> 'CAN'
        AND    (p_excluir IS NULL OR v.id_viaje <> p_excluir)
        AND    v.salida_prog  < p_llegada
        AND    v.llegada_prog > p_salida;

        RETURN v_ocupado = 0;
    END fn_conductor_disponible;
    ----------------------------------------------------------------------------
    -- 3. Asignación MANUAL de un conductor
    ----------------------------------------------------------------------------
    PROCEDURE pr_asignar_conductor (
        p_id_viaje     IN viaje.id_viaje%TYPE,
        p_id_conductor IN conductor.id_conductor%TYPE,
        p_rol          IN viaje_conductor.rol%TYPE DEFAULT 'TIT'
    )
    IS
        v_salida  viaje.salida_prog%TYPE;
        v_llegada viaje.llegada_prog%TYPE;
        v_existe  NUMBER;
    BEGIN
        -- Validar que el viaje exista
        BEGIN
            SELECT salida_prog, llegada_prog
            INTO   v_salida, v_llegada
            FROM   viaje WHERE id_viaje = p_id_viaje;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20035,
                    'Viaje ' || p_id_viaje || ' no existe.');
        END;

        -- Validar que el conductor exista
        SELECT COUNT(*) INTO v_existe
        FROM   conductor WHERE id_conductor = p_id_conductor;
        IF v_existe = 0 THEN
            RAISE_APPLICATION_ERROR(-20031,
                'Conductor ' || p_id_conductor || ' no existe.');
        END IF;

        -- Validar solapamiento (RN-03)
        IF NOT fn_conductor_disponible(p_id_conductor, v_salida, v_llegada, p_id_viaje) THEN
            RAISE_APPLICATION_ERROR(-20032,
                'Conductor ' || p_id_conductor ||
                ' ya tiene un viaje en ese intervalo.');
        END IF;

        INSERT INTO viaje_conductor (id_viaje, id_conductor, rol)
        VALUES (p_id_viaje, p_id_conductor, p_rol);
    END pr_asignar_conductor;

END pkg_programacion_conductor;
/
-- Listar Disponibilidad Y Ver conductores requeridos
DECLARE
    v_ruta       ruta.id_ruta%TYPE      := 7;
    v_salida     viaje.salida_prog%TYPE := TIMESTAMP '2026-11-10 08:00:00';
    v_llegada    viaje.llegada_prog%TYPE;
    v_requeridos PLS_INTEGER;
BEGIN
    v_llegada    := pkg_programacion_viaje.fn_llegada_prog(v_ruta, v_salida);
    v_requeridos := pkg_programacion_conductor.fn_conductores_requeridos(v_ruta);

    DBMS_OUTPUT.PUT_LINE(
        'Ventana: ' || TO_CHAR(v_salida, 'YYYY-MM-DD HH24:MI') ||
        ' - '       || TO_CHAR(v_llegada, 'YYYY-MM-DD HH24:MI')
    );
    DBMS_OUTPUT.PUT_LINE(
        'Ruta ' || v_ruta || ' requiere ' || v_requeridos || ' conductor(es)'
    );
    DBMS_OUTPUT.PUT_LINE('Conductores disponibles:');

    FOR r IN (
        SELECT c.id_conductor,
               c.pnombre || ' ' || c.papellido AS nombre
        FROM   conductor c
        WHERE  NOT EXISTS (
            SELECT 1 FROM viaje_conductor vc
            JOIN   viaje v ON v.id_viaje = vc.id_viaje
            WHERE  vc.id_conductor = c.id_conductor
            AND    v.estado_viaje <> 'CAN'
            AND    v.salida_prog  < v_llegada
            AND    v.llegada_prog > v_salida
        )
        ORDER BY c.id_conductor
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('  ID: ' || r.id_conductor || ' | ' || r.nombre);
    END LOOP;
END;
/
--Asginación Manual
DECLARE
    v_id_viaje viaje.id_viaje%TYPE         := &id_viaje;
    v_id_tit   conductor.id_conductor%TYPE := &id_titular;
    v_id_rel   conductor.id_conductor%TYPE := &id_relevo;  -- dejar vacío si es 1
    v_requeridos PLS_INTEGER;
    v_id_ruta  viaje.id_ruta%TYPE;
BEGIN
    SELECT id_ruta INTO v_id_ruta FROM viaje WHERE id_viaje = v_id_viaje;
    v_requeridos := pkg_programacion_conductor.fn_conductores_requeridos(v_id_ruta);

    -- Titular (siempre obligatorio)
    pkg_programacion_conductor.pr_asignar_conductor(v_id_viaje, v_id_tit, 'TIT');

    -- Relevo solo si la ruta lo exige
    IF v_requeridos > 1 AND v_id_rel IS NOT NULL THEN
        pkg_programacion_conductor.pr_asignar_conductor(v_id_viaje, v_id_rel, 'REL');
    END IF;

    IF v_requeridos > 1 AND v_id_rel IS NULL THEN
        RAISE_APPLICATION_ERROR(-20036,
            'La ruta requiere ' || v_requeridos || ' conductores; falta el relevo.');
    END IF;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Conductores asignados manualmente.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        RAISE;
END;
/


-- Parte B. Vichin, La venta del pasaje y el trigger en el packete. 

-- 5.- Creación de funciones independientes


CREATE OR REPLACE FUNCTION FN_obtener_precio_tarifa (
    p_id_ruta         IN ruta.id_ruta%TYPE,
    p_id_tipo_asiento IN tipo_asiento.id_tipo_asiento%TYPE,
    p_fecha           IN DATE DEFAULT SYSDATE   -- Si no se especifica, usa la fecha actual
) RETURN NUMBER
IS
    v_precio tarifa.precio%TYPE;
BEGIN
    -- Consulta la tarifa vigente para la combinación dada en la fecha especificada.
    -- TRUNC elimina la hora para comparar solo por fecha.
    SELECT tf.precio
    INTO   v_precio
    FROM   tarifa tf
    WHERE  tf.id_ruta          = p_id_ruta
    AND    tf.id_tipo_asiento  = p_id_tipo_asiento
    AND    tf.vigencia_desde  <= TRUNC(p_fecha)
    AND   (tf.vigencia_hasta IS NULL OR tf.vigencia_hasta >= TRUNC(p_fecha));

    DBMS_OUTPUT.PUT_LINE('1.1 Tarifa vigente' || '    ruta ' || p_id_ruta || ' tipo ' || p_id_tipo_asiento || ' al ' || TO_CHAR(p_fecha,'DD-MM-YYYY') ||
                         '  ->  $' || TO_CHAR(v_precio,'FM999G999'));
    RETURN v_precio;

EXCEPTION
    -- No existe tarifa para esa combinación en esa fecha
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('1.1 Sin tarifa vigente para ruta ' || p_id_ruta || ' al ' || TO_CHAR(p_fecha,'DD-MM-YYYY'));

END obtener_precio_tarifa;
/

CREATE OR REPLACE FUNCTION FN_asientos_disponibles (
    p_id_viaje IN viaje.id_viaje%TYPE
) RETURN PLS_INTEGER
IS
    -- PARAMETRO de la futura funcion
    p_id_viaje  CONSTANT viaje.id_viaje%TYPE := 1;   -- Concepcion del 01-09

    -- RETORNO
    v_disponibles  PLS_INTEGER; --Asientos disponibles

    -- Auxiliares
    v_capacidad  PLS_INTEGER; -- Capacidad del bus
    v_ocupados   PLS_INTEGER; -- Asientos ocupados
    v_id_bus     bus.id_bus%TYPE; -- ID del bus 

BEGIN
    -- consulta capacidad del bus y la cantidad de asientos registrados para el.
    SELECT v.id_bus, COUNT(a.nro_asiento)
    INTO   v_id_bus, v_capacidad
    FROM   viaje v
    JOIN   asiento a ON a.id_bus = v.id_bus
    WHERE  v.id_viaje = p_id_viaje
    GROUP  BY v.id_bus;

    -- Consulta los asientos ocupados: los pasajes de ese viaje cuyo estado mantiene el asiento tomado.
    SELECT COUNT(*)
    INTO   v_ocupados
    FROM   pasaje p
    JOIN   estado_pasaje ep ON ep.id_estado = p.id_estado
    WHERE  p.id_viaje       = p_id_viaje
    AND    ep.ocupa_asiento = 'S';

    v_disponibles := v_capacidad - v_ocupados;

    DBMS_OUTPUT.PUT_LINE('1.3 Asientos disponibles' ||'    viaje ' || p_id_viaje || ' (bus ' || v_id_bus || ')' || '  capacidad ' || v_capacidad ||
                         ' - ocupados ' || v_ocupados ||
                         '  ->  ' || v_disponibles || ' disponibles');
EXCEPTION
    -- Excepción a bus sin asientos disponibles o que no exista  el viaje
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('1.3 El viaje ' || p_id_viaje || ' no existe o su bus no tiene asientos registrados.');
END;
/


