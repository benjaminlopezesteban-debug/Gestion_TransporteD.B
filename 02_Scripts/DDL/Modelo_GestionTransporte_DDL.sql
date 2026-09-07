--------------------------------------------------------------------------------
-- Modelo_GestionTransporte  |  DDL + poblamiento
-- Motor.......: Oracle Database
-- Modelo......: 14 entidades en 3ra forma normal
-- Reglas......: RN-01 a RN-10 (ver informe, seccion 2.4)
--
-- Estructura de este script:
--   1. DROPS
--   2. TABLAS con sus PK, FK, UK y CHECK
--   3. INDICES que implementan reglas de negocio
--   4. POBLAMIENTO de prueba


--------------------------------------------------------------------------------
-- TRAZABILIDAD CON LA DOCUMENTACION
--
--   Informe  : DP_Informe_Requerimiento.docx
--                3.1 Datos que deben almacenarse -> seccion 2, las 14 tablas
--                4.1 Modelo de datos             -> claves foraneas y compuestas
--                4.2 Trazabilidad regla-mecanismo-> que regla implementa cada objeto
--                2.4 Reglas de negocio           -> RN-01 a RN-10
--   Anexo    : ANEXO_Tablas_de_Referencia.docx
--                Tablas 10 a 23 - Diccionario de datos, una por entidad
--                Tabla  24      - Relaciones entre entidades
--                Tabla  25      - Claves foraneas compuestas de PASAJE
--                Tabla   6      - Trazabilidad entre reglas y mecanismos
--
--   Reglas que este script garantiza por ESTRUCTURA, sin codigo:
--     RN-01  capacidad del bus = filas en ASIENTO (PK compuesta)
--     RN-02  origen distinto de destino en RUTA (FK + CHECK)
--     RN-05  pasajero y viaje obligatorios en PASAJE
--     RN-06  indice unico parcial ux_pasaje_asiento_vigente (seccion 3)
--     RN-07  TARIFA por ruta, tipo de asiento y vigencia
--     RN-08  catalogo ESTADO_PASAJE + PASAJE_ESTADO_HIST
--     RN-09  el indice unico ignora los estados que no ocupan asiento
--   Reglas que requieren PL/SQL (ver 02_Scripts/PLSQL/):
--     RN-03, RN-04  no superposicion de conductor y de bus
--     RN-10         jornada maxima de conduccion
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- 1. DROPS
--    Orden inverso al de dependencias. CASCADE CONSTRAINTS elimina tambien
--    las FK que apuntan a la tabla desde otras tablas.
--------------------------------------------------------------------------------

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


--------------------------------------------------------------------------------
-- 2. TABLAS
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- TERMINAL
--------------------------------------------------------------------------------
CREATE TABLE terminal (
    id_terminal        NUMBER(6)          NOT NULL,
    nombre_terminal    VARCHAR2(60 CHAR)  NOT NULL,
    ciudad             VARCHAR2(60 CHAR)  NOT NULL,
    direccion          VARCHAR2(120 CHAR) NOT NULL,
    CONSTRAINT pk_terminal        PRIMARY KEY (id_terminal),
    CONSTRAINT uk_terminal_nombre UNIQUE      (nombre_terminal, ciudad)
);

--------------------------------------------------------------------------------
-- TIPO_ASIENTO
-- Habilita el precio diferenciado por tipo (semi cama, salon cama, premium).
--------------------------------------------------------------------------------
CREATE TABLE tipo_asiento (
    id_tipo_asiento    NUMBER(4)          NOT NULL,
    codigo             VARCHAR2(5 CHAR)   NOT NULL,
    nombre             VARCHAR2(40 CHAR)  NOT NULL,
    CONSTRAINT pk_tipo_asiento     PRIMARY KEY (id_tipo_asiento),
    CONSTRAINT uk_tipo_asiento_cod UNIQUE      (codigo)
);

--------------------------------------------------------------------------------
-- ESTADO_PASAJE
-- ocupa_asiento = 'S' cuando el estado mantiene el asiento tomado.
-- Es el dato que convierte "la anulacion libera el asiento" en catalogo
-- en vez de una regla escondida en codigo.
--------------------------------------------------------------------------------
CREATE TABLE estado_pasaje (
    id_estado          NUMBER(4)          NOT NULL,
    codigo             VARCHAR2(5 CHAR)   NOT NULL,
    nombre             VARCHAR2(40 CHAR)  NOT NULL,
    ocupa_asiento      CHAR(1 CHAR)       NOT NULL,
    CONSTRAINT pk_estado_pasaje     PRIMARY KEY (id_estado),
    CONSTRAINT uk_estado_pasaje_cod UNIQUE      (codigo),
    CONSTRAINT ck_estado_ocupa      CHECK       (ocupa_asiento IN ('S','N'))
);

--------------------------------------------------------------------------------
-- RUTA
-- Origen y destino son FK a TERMINAL, no texto libre.
--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
-- BUS
-- Sin nro_asientos_totales: la capacidad es COUNT(*) sobre ASIENTO y asi
-- nunca puede contradecir a los asientos que realmente existen.
--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
-- ASIENTO
-- El asiento pertenece al BUS, no al viaje. PK compuesta natural.
--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
-- CONDUCTOR
--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
-- VIAJE   (reemplaza SERVICIO + HORARIO)
-- salida_prog y llegada_prog son TIMESTAMP, no fecha + hora separadas:
-- es lo que permite comparar intervalos y detectar superposiciones.
-- uk_viaje_bus es aparentemente redundante, pero es el destino de la FK
-- compuesta de PASAJE que ata el asiento al bus correcto.
--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
-- VIAJE_CONDUCTOR
-- Tabla puente porque en largo recorrido van dos conductores que se relevan.
-- rol: TIT = titular, REL = relevo.
--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
-- PASAJERO
--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
-- TARIFA
-- Las tres dimensiones del requisito de precio: ruta, tipo de asiento y
-- condicion comercial (la vigencia). Una tarifa nueva es una fila nueva,
-- nunca un UPDATE sobre la anterior.
--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
-- VENTA
-- Cabecera comercial. Sin precio_total (es SUM sobre PASAJE) y sin id_viaje:
-- el viaje vive en cada pasaje, que es donde corresponde.
--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
-- PASAJE
-- La entidad central: un pasajero, un viaje, un asiento, un estado.
--
-- id_bus aparece aqui a proposito. Con las dos FK compuestas
--   (id_viaje, id_bus)      -> VIAJE   (uk_viaje_bus)
--   (id_bus, nro_asiento)   -> ASIENTO (pk_asiento)
-- queda garantizado de forma declarativa que el asiento vendido existe en el
-- bus que efectivamente hace ese viaje. Sin trigger.
--
-- precio_aplicado NO es redundante con TARIFA: es el precio congelado en el
-- instante de la venta. Si manana sube la tarifa, el pasaje emitido no cambia.
--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
-- PASAJE_ESTADO_HIST
-- Cada transicion deja rastro. Sin esto una anulacion es indistinguible de
-- una venta que nunca ocurrio, y el negocio no puede auditar quien anulo que.
--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
-- 3. INDICES QUE IMPLEMENTAN REGLAS DE NEGOCIO
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- RN-06: un asiento no puede ser vendido dos veces para el mismo viaje.
-- RN-09: la anulacion de un pasaje libera el asiento correspondiente.
--
-- Ambas reglas se resuelven con un unico indice, y conviene entender por que no
-- basta un UNIQUE corriente. Un UNIQUE (id_viaje, id_bus, nro_asiento) impediria
-- revender un asiento despues de anularlo, porque el pasaje anulado seguiria
-- ocupando la clave. Se necesita que la unicidad aplique solo a los pasajes
-- vigentes.
--
-- Oracle no ofrece indices unicos parciales como otros motores, pero un indice
-- unico ignora las filas cuyas columnas indexadas son TODAS nulas. Ese es el
-- mecanismo: las expresiones CASE devuelven el valor real cuando el estado ocupa
-- el asiento (PEN=1, VEN=2, UTI=3) y NULL cuando no lo ocupa (ANU=4).
--
-- Consecuencia: al anular, el pasaje sale del indice y su asiento vuelve a estar
-- disponible sin borrar el registro. Y al intentar vender un asiento ya tomado,
-- el motor levanta DUP_VAL_ON_INDEX por si solo: la regla no se programa, se
-- disena.
--
-- Limitacion asumida: los codigos de estado quedan fijos en la definicion del
-- indice, porque un indice basado en funcion no puede consultar ESTADO_PASAJE.
-- Es aceptable porque los cuatro estados son parte del enunciado del caso.
--------------------------------------------------------------------------------
CREATE UNIQUE INDEX ux_pasaje_asiento_vigente ON pasaje (
    CASE WHEN id_estado IN (1,2,3) THEN id_viaje    END,
    CASE WHEN id_estado IN (1,2,3) THEN id_bus      END,
    CASE WHEN id_estado IN (1,2,3) THEN nro_asiento END
);


--------------------------------------------------------------------------------
-- 4. POBLAMIENTO
--
-- Los datos reflejan el contexto de negocio declarado en el informe: una empresa
-- que opera 7 rutas desde Santiago hacia Rancagua, Talca, Linares, Cauquenes,
-- Chillan, Bulnes y Concepcion, con una flota de buses interurbanos.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- TERMINAL
-- Santiago es el origen de las 7 rutas; los demas son los destinos del negocio.
--------------------------------------------------------------------------------
INSERT INTO terminal (id_terminal, nombre_terminal, ciudad, direccion) VALUES (1, 'Terminal Alameda',   'Santiago',   'Av. Libertador Bernardo O''Higgins 3750');
INSERT INTO terminal (id_terminal, nombre_terminal, ciudad, direccion) VALUES (2, 'Terminal Rancagua',  'Rancagua',   'Av. O''Carrol 1039');
INSERT INTO terminal (id_terminal, nombre_terminal, ciudad, direccion) VALUES (3, 'Terminal Talca',     'Talca',      '12 Oriente 1055');
INSERT INTO terminal (id_terminal, nombre_terminal, ciudad, direccion) VALUES (4, 'Terminal Linares',   'Linares',    'Av. Leon Bustos 200');
INSERT INTO terminal (id_terminal, nombre_terminal, ciudad, direccion) VALUES (5, 'Terminal Cauquenes', 'Cauquenes',  'Claudina Urrutia 550');
INSERT INTO terminal (id_terminal, nombre_terminal, ciudad, direccion) VALUES (6, 'Terminal Chillan',   'Chillan',    'Av. Brasil 560');
INSERT INTO terminal (id_terminal, nombre_terminal, ciudad, direccion) VALUES (7, 'Terminal Bulnes',    'Bulnes',     'Av. Manuel Bulnes 320');
INSERT INTO terminal (id_terminal, nombre_terminal, ciudad, direccion) VALUES (8, 'Terminal Collao',    'Concepcion', 'Av. General Bonilla 1855');

--------------------------------------------------------------------------------
-- TIPO_ASIENTO
--------------------------------------------------------------------------------
INSERT INTO tipo_asiento (id_tipo_asiento, codigo, nombre) VALUES (1, 'SEM', 'Semi Cama');
INSERT INTO tipo_asiento (id_tipo_asiento, codigo, nombre) VALUES (2, 'SAL', 'Salon Cama');
INSERT INTO tipo_asiento (id_tipo_asiento, codigo, nombre) VALUES (3, 'PRE', 'Premium Suite');

--------------------------------------------------------------------------------
-- ESTADO_PASAJE
-- Solo ANU libera el asiento.
--------------------------------------------------------------------------------
INSERT INTO estado_pasaje (id_estado, codigo, nombre, ocupa_asiento) VALUES (1, 'PEN', 'Pendiente de pago', 'S');
INSERT INTO estado_pasaje (id_estado, codigo, nombre, ocupa_asiento) VALUES (2, 'VEN', 'Vendido',           'S');
INSERT INTO estado_pasaje (id_estado, codigo, nombre, ocupa_asiento) VALUES (3, 'UTI', 'Utilizado',         'S');
INSERT INTO estado_pasaje (id_estado, codigo, nombre, ocupa_asiento) VALUES (4, 'ANU', 'Anulado',           'N');

--------------------------------------------------------------------------------
-- RUTA
-- Las 7 rutas del negocio, todas con origen en Santiago (terminal 1).
-- La duracion determina cuantos conductores exige RN-10 (maximo 5 h por conductor):
--   solo Concepcion (6,5 h) supera el limite y obliga a llevar relevo.
--   Bulnes (5,00 h) queda justo en el limite y se cubre con un solo conductor.
--------------------------------------------------------------------------------
INSERT INTO ruta (id_ruta, id_terminal_origen, id_terminal_destino, distancia_km, duracion_estimada_min) VALUES (1, 1, 2,  87,  75);
INSERT INTO ruta (id_ruta, id_terminal_origen, id_terminal_destino, distancia_km, duracion_estimada_min) VALUES (2, 1, 3, 255, 180);
INSERT INTO ruta (id_ruta, id_terminal_origen, id_terminal_destino, distancia_km, duracion_estimada_min) VALUES (3, 1, 4, 305, 210);
INSERT INTO ruta (id_ruta, id_terminal_origen, id_terminal_destino, distancia_km, duracion_estimada_min) VALUES (4, 1, 5, 360, 270);
INSERT INTO ruta (id_ruta, id_terminal_origen, id_terminal_destino, distancia_km, duracion_estimada_min) VALUES (5, 1, 6, 400, 285);
INSERT INTO ruta (id_ruta, id_terminal_origen, id_terminal_destino, distancia_km, duracion_estimada_min) VALUES (6, 1, 7, 425, 300);
INSERT INTO ruta (id_ruta, id_terminal_origen, id_terminal_destino, distancia_km, duracion_estimada_min) VALUES (7, 1, 8, 500, 390);

--------------------------------------------------------------------------------
-- BUS
--------------------------------------------------------------------------------
INSERT INTO bus (id_bus, patente, modelo, anio_fabricacion, fecha_compra) VALUES (1, 'JKLM45', 'Mercedes-Benz O500RSD', 2021, DATE '2021-03-15');
INSERT INTO bus (id_bus, patente, modelo, anio_fabricacion, fecha_compra) VALUES (2, 'PQRS78', 'Volvo 9800',            2019, DATE '2019-11-02');
INSERT INTO bus (id_bus, patente, modelo, anio_fabricacion, fecha_compra) VALUES (3, 'TUVW12', 'Scania K410',           2023, DATE '2023-07-20');

--------------------------------------------------------------------------------
-- ASIENTO
-- Bus 1: 12 asientos | Bus 2: 10 asientos | Bus 3: 10 asientos
-- La capacidad de cada bus es exactamente esta cantidad de filas (RN-01).
--------------------------------------------------------------------------------
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (1,  1, 2, 1);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (1,  2, 2, 1);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (1,  3, 2, 1);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (1,  4, 2, 1);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (1,  5, 1, 2);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (1,  6, 1, 2);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (1,  7, 1, 2);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (1,  8, 1, 2);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (1,  9, 1, 2);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (1, 10, 1, 2);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (1, 11, 1, 2);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (1, 12, 1, 2);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (2,  1, 2, 1);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (2,  2, 2, 1);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (2,  3, 2, 1);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (2,  4, 2, 1);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (2,  5, 1, 2);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (2,  6, 1, 2);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (2,  7, 1, 2);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (2,  8, 1, 2);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (2,  9, 1, 2);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (2, 10, 1, 2);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (3,  1, 3, 1);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (3,  2, 3, 1);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (3,  3, 2, 1);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (3,  4, 2, 1);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (3,  5, 1, 2);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (3,  6, 1, 2);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (3,  7, 1, 2);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (3,  8, 1, 2);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (3,  9, 1, 2);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (3, 10, 1, 2);

--------------------------------------------------------------------------------
-- CONDUCTOR
--------------------------------------------------------------------------------
INSERT INTO conductor (id_conductor, run, dv, pnombre, snombre, papellido, sapellido, nro_licencia, fecha_contrato) VALUES (1, 12345678, '9', 'Juan',  'Carlos',  'Perez',   'Soto',   'A3-118422', DATE '2018-04-02');
INSERT INTO conductor (id_conductor, run, dv, pnombre, snombre, papellido, sapellido, nro_licencia, fecha_contrato) VALUES (2,  9876543, '1', 'Maria', 'Elena',   'Rojas',   'Munoz',  'A3-224901', DATE '2020-01-13');
INSERT INTO conductor (id_conductor, run, dv, pnombre, snombre, papellido, sapellido, nro_licencia, fecha_contrato) VALUES (3, 15678234, 'K', 'Pedro', 'Antonio', 'Silva',   'Cortes', 'A3-330755', DATE '2019-08-26');
INSERT INTO conductor (id_conductor, run, dv, pnombre, snombre, papellido, sapellido, nro_licencia, fecha_contrato) VALUES (4, 17234567, '2', 'Ana',   'Isabel',  'Fuentes', 'Vera',   'A3-401238', DATE '2022-05-09');

--------------------------------------------------------------------------------
-- VIAJE
-- El bus 1 realiza tres viajes distintos (1, 2 y 6): eso es lo que la relacion
-- 1:1 del modelo original hacia imposible. Ninguna asignacion de bus se superpone.
--------------------------------------------------------------------------------
INSERT INTO viaje (id_viaje, id_ruta, id_bus, salida_prog, llegada_prog, estado_viaje) VALUES (1, 7, 1, TIMESTAMP '2026-09-01 08:00:00', TIMESTAMP '2026-09-01 14:30:00', 'FIN');
INSERT INTO viaje (id_viaje, id_ruta, id_bus, salida_prog, llegada_prog, estado_viaje) VALUES (2, 1, 1, TIMESTAMP '2026-09-01 18:00:00', TIMESTAMP '2026-09-01 19:15:00', 'FIN');
INSERT INTO viaje (id_viaje, id_ruta, id_bus, salida_prog, llegada_prog, estado_viaje) VALUES (3, 5, 2, TIMESTAMP '2026-09-01 09:00:00', TIMESTAMP '2026-09-01 13:45:00', 'FIN');
INSERT INTO viaje (id_viaje, id_ruta, id_bus, salida_prog, llegada_prog, estado_viaje) VALUES (4, 6, 3, TIMESTAMP '2026-09-02 21:00:00', TIMESTAMP '2026-09-03 02:00:00', 'PRO');
INSERT INTO viaje (id_viaje, id_ruta, id_bus, salida_prog, llegada_prog, estado_viaje) VALUES (5, 2, 2, TIMESTAMP '2026-09-02 07:30:00', TIMESTAMP '2026-09-02 10:30:00', 'PRO');
INSERT INTO viaje (id_viaje, id_ruta, id_bus, salida_prog, llegada_prog, estado_viaje) VALUES (6, 7, 1, TIMESTAMP '2026-09-03 08:00:00', TIMESTAMP '2026-09-03 14:30:00', 'PRO');

--------------------------------------------------------------------------------
-- VIAJE_CONDUCTOR
-- RN-10: por ley un conductor no puede superar 5 horas de conduccion.
-- Los viajes 1 y 6 (Concepcion, 6,5 h) llevan relevo; el resto no lo requiere.
-- Ningun conductor queda asignado a dos viajes que se superpongan.
--------------------------------------------------------------------------------
INSERT INTO viaje_conductor (id_viaje, id_conductor, rol) VALUES (1, 1, 'TIT');
INSERT INTO viaje_conductor (id_viaje, id_conductor, rol) VALUES (1, 2, 'REL');
INSERT INTO viaje_conductor (id_viaje, id_conductor, rol) VALUES (2, 3, 'TIT');
INSERT INTO viaje_conductor (id_viaje, id_conductor, rol) VALUES (3, 4, 'TIT');
INSERT INTO viaje_conductor (id_viaje, id_conductor, rol) VALUES (4, 4, 'TIT');
INSERT INTO viaje_conductor (id_viaje, id_conductor, rol) VALUES (5, 1, 'TIT');
INSERT INTO viaje_conductor (id_viaje, id_conductor, rol) VALUES (6, 2, 'TIT');
INSERT INTO viaje_conductor (id_viaje, id_conductor, rol) VALUES (6, 3, 'REL');

--------------------------------------------------------------------------------
-- PASAJERO
--------------------------------------------------------------------------------
INSERT INTO pasajero (id_pasajero, run, dv, pnombre, snombre, papellido, sapellido, mail, telefono) VALUES (1, 11222333, '4', 'Camila',    'Andrea',  'Torres',  'Lagos',   'camila.torres@correo.cl', '+56911111111');
INSERT INTO pasajero (id_pasajero, run, dv, pnombre, snombre, papellido, sapellido, mail, telefono) VALUES (2, 13444555, '6', 'Rodrigo',   'Esteban', 'Munoz',   'Diaz',    'rmunoz@correo.cl',        '+56922222222');
INSERT INTO pasajero (id_pasajero, run, dv, pnombre, snombre, papellido, sapellido, mail, telefono) VALUES (3, 16555777, 'K', 'Valentina', 'Paz',     'Herrera', 'Nunez',   'vherrera@correo.cl',      '+56933333333');
INSERT INTO pasajero (id_pasajero, run, dv, pnombre, snombre, papellido, sapellido, mail, telefono) VALUES (4, 10111222, '3', 'Sebastian', NULL,      'Castro',  'Rivas',   'scastro@correo.cl',       '+56944444444');
INSERT INTO pasajero (id_pasajero, run, dv, pnombre, snombre, papellido, sapellido, mail, telefono) VALUES (5, 18999000, '1', 'Francisca', 'Belen',   'Alvarez', 'Soto',    'falvarez@correo.cl',      NULL);
INSERT INTO pasajero (id_pasajero, run, dv, pnombre, snombre, papellido, sapellido, mail, telefono) VALUES (6, 14333222, '8', 'Matias',    'Alonso',  'Vega',    'Fuentes', 'mvega@correo.cl',         '+56966666666');

--------------------------------------------------------------------------------
-- TARIFA
-- Precio por ruta y tipo de asiento. La tarifa 17 esta cerrada y convive con la
-- 14, que la reemplazo para la misma ruta y tipo: es la variacion por condicion
-- comercial que exige RN-07, sin sobrescribir el historico.
--------------------------------------------------------------------------------
INSERT INTO tarifa (id_tarifa, id_ruta, id_tipo_asiento, vigencia_desde, vigencia_hasta, precio) VALUES ( 1, 1, 1, DATE '2026-01-01', NULL,  3500);
INSERT INTO tarifa (id_tarifa, id_ruta, id_tipo_asiento, vigencia_desde, vigencia_hasta, precio) VALUES ( 2, 1, 2, DATE '2026-01-01', NULL,  5200);
INSERT INTO tarifa (id_tarifa, id_ruta, id_tipo_asiento, vigencia_desde, vigencia_hasta, precio) VALUES ( 3, 2, 1, DATE '2026-01-01', NULL,  9500);
INSERT INTO tarifa (id_tarifa, id_ruta, id_tipo_asiento, vigencia_desde, vigencia_hasta, precio) VALUES ( 4, 2, 2, DATE '2026-01-01', NULL, 14000);
INSERT INTO tarifa (id_tarifa, id_ruta, id_tipo_asiento, vigencia_desde, vigencia_hasta, precio) VALUES ( 5, 3, 1, DATE '2026-01-01', NULL, 11000);
INSERT INTO tarifa (id_tarifa, id_ruta, id_tipo_asiento, vigencia_desde, vigencia_hasta, precio) VALUES ( 6, 3, 2, DATE '2026-01-01', NULL, 16500);
INSERT INTO tarifa (id_tarifa, id_ruta, id_tipo_asiento, vigencia_desde, vigencia_hasta, precio) VALUES ( 7, 4, 1, DATE '2026-01-01', NULL, 12500);
INSERT INTO tarifa (id_tarifa, id_ruta, id_tipo_asiento, vigencia_desde, vigencia_hasta, precio) VALUES ( 8, 4, 2, DATE '2026-01-01', NULL, 18500);
INSERT INTO tarifa (id_tarifa, id_ruta, id_tipo_asiento, vigencia_desde, vigencia_hasta, precio) VALUES ( 9, 5, 1, DATE '2026-01-01', NULL, 14000);
INSERT INTO tarifa (id_tarifa, id_ruta, id_tipo_asiento, vigencia_desde, vigencia_hasta, precio) VALUES (10, 5, 2, DATE '2026-01-01', NULL, 21000);
INSERT INTO tarifa (id_tarifa, id_ruta, id_tipo_asiento, vigencia_desde, vigencia_hasta, precio) VALUES (11, 6, 1, DATE '2026-01-01', NULL, 15000);
INSERT INTO tarifa (id_tarifa, id_ruta, id_tipo_asiento, vigencia_desde, vigencia_hasta, precio) VALUES (12, 6, 2, DATE '2026-01-01', NULL, 22500);
INSERT INTO tarifa (id_tarifa, id_ruta, id_tipo_asiento, vigencia_desde, vigencia_hasta, precio) VALUES (13, 6, 3, DATE '2026-01-01', NULL, 30000);
INSERT INTO tarifa (id_tarifa, id_ruta, id_tipo_asiento, vigencia_desde, vigencia_hasta, precio) VALUES (14, 7, 1, DATE '2026-01-01', NULL, 18000);
INSERT INTO tarifa (id_tarifa, id_ruta, id_tipo_asiento, vigencia_desde, vigencia_hasta, precio) VALUES (15, 7, 2, DATE '2026-01-01', NULL, 27000);
INSERT INTO tarifa (id_tarifa, id_ruta, id_tipo_asiento, vigencia_desde, vigencia_hasta, precio) VALUES (16, 7, 3, DATE '2026-01-01', NULL, 36000);
INSERT INTO tarifa (id_tarifa, id_ruta, id_tipo_asiento, vigencia_desde, vigencia_hasta, precio) VALUES (17, 7, 1, DATE '2025-06-01', DATE '2025-12-31', 16000);

--------------------------------------------------------------------------------
-- VENTA
--------------------------------------------------------------------------------
INSERT INTO venta (id_venta, id_pasajero_comprador, fecha_hora, canal, medio_pago) VALUES (1, 1, TIMESTAMP '2026-08-20 10:15:00', 'WEB', 'TDC');
INSERT INTO venta (id_venta, id_pasajero_comprador, fecha_hora, canal, medio_pago) VALUES (2, 4, TIMESTAMP '2026-08-22 16:40:00', 'MOV', 'TDB');
INSERT INTO venta (id_venta, id_pasajero_comprador, fecha_hora, canal, medio_pago) VALUES (3, 3, TIMESTAMP '2026-08-25 09:05:00', 'TER', 'EFE');
INSERT INTO venta (id_venta, id_pasajero_comprador, fecha_hora, canal, medio_pago) VALUES (4, 6, TIMESTAMP '2026-08-26 18:20:00', 'WEB', 'TDC');

--------------------------------------------------------------------------------
-- PASAJE
-- Casos que este poblamiento demuestra:
--   * Venta 2: un comprador (pasajero 4) adquiere tres pasajes para tres
--     viajeros distintos (4, 5 y 6). Esto era imposible en el modelo original.
--   * Pasaje 6 anulado y pasaje 7 sobre el MISMO asiento (viaje 3, bus 2,
--     asiento 7): la anulacion libero el asiento sin borrar la evidencia.
--   * Los cuatro estados aparecen representados.
--------------------------------------------------------------------------------
INSERT INTO pasaje (id_pasaje, id_venta, id_viaje, id_bus, nro_asiento, id_pasajero, id_tarifa, precio_aplicado, descuento, id_estado, fecha_emision) VALUES (1, 1, 1, 1,  3, 1, 15, 27000,    0, 3, TIMESTAMP '2026-08-20 10:15:00');
INSERT INTO pasaje (id_pasaje, id_venta, id_viaje, id_bus, nro_asiento, id_pasajero, id_tarifa, precio_aplicado, descuento, id_estado, fecha_emision) VALUES (2, 1, 1, 1,  4, 2, 15, 27000, 2700, 3, TIMESTAMP '2026-08-20 10:15:00');
INSERT INTO pasaje (id_pasaje, id_venta, id_viaje, id_bus, nro_asiento, id_pasajero, id_tarifa, precio_aplicado, descuento, id_estado, fecha_emision) VALUES (3, 2, 4, 3,  1, 4, 13, 30000,    0, 2, TIMESTAMP '2026-08-22 16:40:00');
INSERT INTO pasaje (id_pasaje, id_venta, id_viaje, id_bus, nro_asiento, id_pasajero, id_tarifa, precio_aplicado, descuento, id_estado, fecha_emision) VALUES (4, 2, 4, 3,  2, 5, 13, 30000, 3000, 2, TIMESTAMP '2026-08-22 16:40:00');
INSERT INTO pasaje (id_pasaje, id_venta, id_viaje, id_bus, nro_asiento, id_pasajero, id_tarifa, precio_aplicado, descuento, id_estado, fecha_emision) VALUES (5, 2, 4, 3,  6, 6, 11, 15000,    0, 2, TIMESTAMP '2026-08-22 16:40:00');
INSERT INTO pasaje (id_pasaje, id_venta, id_viaje, id_bus, nro_asiento, id_pasajero, id_tarifa, precio_aplicado, descuento, id_estado, fecha_emision) VALUES (6, 3, 3, 2,  7, 3,  9, 14000,    0, 4, TIMESTAMP '2026-08-25 09:05:00');
INSERT INTO pasaje (id_pasaje, id_venta, id_viaje, id_bus, nro_asiento, id_pasajero, id_tarifa, precio_aplicado, descuento, id_estado, fecha_emision) VALUES (7, 4, 3, 2,  7, 6,  9, 14000,    0, 2, TIMESTAMP '2026-08-26 18:20:00');
INSERT INTO pasaje (id_pasaje, id_venta, id_viaje, id_bus, nro_asiento, id_pasajero, id_tarifa, precio_aplicado, descuento, id_estado, fecha_emision) VALUES (8, 4, 5, 2,  5, 6,  3,  9500,    0, 1, TIMESTAMP '2026-08-26 18:20:00');

--------------------------------------------------------------------------------
-- PASAJE_ESTADO_HIST
-- El ultimo estado de cada pasaje coincide con PASAJE.id_estado.
--------------------------------------------------------------------------------
INSERT INTO pasaje_estado_hist (id_pasaje, secuencia, fecha_hora, id_estado, usuario, motivo) VALUES (1, 1, TIMESTAMP '2026-08-20 10:15:00', 1, 'WEB_CHECKOUT',    NULL);
INSERT INTO pasaje_estado_hist (id_pasaje, secuencia, fecha_hora, id_estado, usuario, motivo) VALUES (1, 2, TIMESTAMP '2026-08-20 10:17:00', 2, 'PASARELA_PAGO',   NULL);
INSERT INTO pasaje_estado_hist (id_pasaje, secuencia, fecha_hora, id_estado, usuario, motivo) VALUES (1, 3, TIMESTAMP '2026-09-01 07:42:00', 3, 'VALIDADOR_AND12', NULL);
INSERT INTO pasaje_estado_hist (id_pasaje, secuencia, fecha_hora, id_estado, usuario, motivo) VALUES (2, 1, TIMESTAMP '2026-08-20 10:15:00', 1, 'WEB_CHECKOUT',    NULL);
INSERT INTO pasaje_estado_hist (id_pasaje, secuencia, fecha_hora, id_estado, usuario, motivo) VALUES (2, 2, TIMESTAMP '2026-08-20 10:17:00', 2, 'PASARELA_PAGO',   NULL);
INSERT INTO pasaje_estado_hist (id_pasaje, secuencia, fecha_hora, id_estado, usuario, motivo) VALUES (2, 3, TIMESTAMP '2026-09-01 07:44:00', 3, 'VALIDADOR_AND12', NULL);
INSERT INTO pasaje_estado_hist (id_pasaje, secuencia, fecha_hora, id_estado, usuario, motivo) VALUES (3, 1, TIMESTAMP '2026-08-22 16:40:00', 1, 'APP_MOVIL',       NULL);
INSERT INTO pasaje_estado_hist (id_pasaje, secuencia, fecha_hora, id_estado, usuario, motivo) VALUES (3, 2, TIMESTAMP '2026-08-22 16:41:00', 2, 'PASARELA_PAGO',   NULL);
INSERT INTO pasaje_estado_hist (id_pasaje, secuencia, fecha_hora, id_estado, usuario, motivo) VALUES (4, 1, TIMESTAMP '2026-08-22 16:40:00', 1, 'APP_MOVIL',       NULL);
INSERT INTO pasaje_estado_hist (id_pasaje, secuencia, fecha_hora, id_estado, usuario, motivo) VALUES (4, 2, TIMESTAMP '2026-08-22 16:41:00', 2, 'PASARELA_PAGO',   NULL);
INSERT INTO pasaje_estado_hist (id_pasaje, secuencia, fecha_hora, id_estado, usuario, motivo) VALUES (5, 1, TIMESTAMP '2026-08-22 16:40:00', 1, 'APP_MOVIL',       NULL);
INSERT INTO pasaje_estado_hist (id_pasaje, secuencia, fecha_hora, id_estado, usuario, motivo) VALUES (5, 2, TIMESTAMP '2026-08-22 16:41:00', 2, 'PASARELA_PAGO',   NULL);
INSERT INTO pasaje_estado_hist (id_pasaje, secuencia, fecha_hora, id_estado, usuario, motivo) VALUES (6, 1, TIMESTAMP '2026-08-25 09:05:00', 1, 'CAJA_ALAMEDA',    NULL);
INSERT INTO pasaje_estado_hist (id_pasaje, secuencia, fecha_hora, id_estado, usuario, motivo) VALUES (6, 2, TIMESTAMP '2026-08-25 09:06:00', 2, 'CAJA_ALAMEDA',    NULL);
INSERT INTO pasaje_estado_hist (id_pasaje, secuencia, fecha_hora, id_estado, usuario, motivo) VALUES (6, 3, TIMESTAMP '2026-08-26 11:30:00', 4, 'CALL_CENTER',     'Solicitud del pasajero, cambio de fecha de viaje');
INSERT INTO pasaje_estado_hist (id_pasaje, secuencia, fecha_hora, id_estado, usuario, motivo) VALUES (7, 1, TIMESTAMP '2026-08-26 18:20:00', 1, 'WEB_CHECKOUT',    NULL);
INSERT INTO pasaje_estado_hist (id_pasaje, secuencia, fecha_hora, id_estado, usuario, motivo) VALUES (7, 2, TIMESTAMP '2026-08-26 18:22:00', 2, 'PASARELA_PAGO',   NULL);
INSERT INTO pasaje_estado_hist (id_pasaje, secuencia, fecha_hora, id_estado, usuario, motivo) VALUES (8, 1, TIMESTAMP '2026-08-26 18:20:00', 1, 'WEB_CHECKOUT',    NULL);

COMMIT;
