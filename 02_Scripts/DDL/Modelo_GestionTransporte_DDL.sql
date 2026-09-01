--------------------------------------------------------------------------------
-- Modelo_GestionTransporte  |  DDL + poblamiento
-- Motor.......: Oracle Database
-- Modelo......: 14 entidades 3ra normal


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
-- 3. POBLAMIENTO
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- TERMINAL
--------------------------------------------------------------------------------
INSERT INTO terminal (id_terminal, nombre_terminal, ciudad, direccion) VALUES (1, 'Terminal Alameda',    'Santiago',    'Av. Libertador Bernardo O''Higgins 3750');
INSERT INTO terminal (id_terminal, nombre_terminal, ciudad, direccion) VALUES (2, 'Terminal Rodoviario', 'La Serena',   'Av. El Santo 400');
INSERT INTO terminal (id_terminal, nombre_terminal, ciudad, direccion) VALUES (3, 'Terminal Collao',     'Concepcion',  'Av. General Bonilla 1855');
INSERT INTO terminal (id_terminal, nombre_terminal, ciudad, direccion) VALUES (4, 'Terminal Valparaiso', 'Valparaiso',  'Av. Pedro Montt 2800');
INSERT INTO terminal (id_terminal, nombre_terminal, ciudad, direccion) VALUES (5, 'Terminal Rodoviario', 'Temuco',      'Vicente Perez Rosales 01609');

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
--------------------------------------------------------------------------------
INSERT INTO ruta (id_ruta, id_terminal_origen, id_terminal_destino, distancia_km, duracion_estimada_min) VALUES (1, 1, 2, 471, 390);
INSERT INTO ruta (id_ruta, id_terminal_origen, id_terminal_destino, distancia_km, duracion_estimada_min) VALUES (2, 2, 1, 471, 390);
INSERT INTO ruta (id_ruta, id_terminal_origen, id_terminal_destino, distancia_km, duracion_estimada_min) VALUES (3, 1, 3, 500, 420);
INSERT INTO ruta (id_ruta, id_terminal_origen, id_terminal_destino, distancia_km, duracion_estimada_min) VALUES (4, 3, 1, 500, 420);
INSERT INTO ruta (id_ruta, id_terminal_origen, id_terminal_destino, distancia_km, duracion_estimada_min) VALUES (5, 1, 5, 675, 540);
INSERT INTO ruta (id_ruta, id_terminal_origen, id_terminal_destino, distancia_km, duracion_estimada_min) VALUES (6, 1, 4, 120, 105);

--------------------------------------------------------------------------------
-- BUS
--------------------------------------------------------------------------------
INSERT INTO bus (id_bus, patente, modelo, anio_fabricacion, fecha_compra) VALUES (1, 'JKLM45', 'Mercedes-Benz O500RSD', 2021, DATE '2021-03-15');
INSERT INTO bus (id_bus, patente, modelo, anio_fabricacion, fecha_compra) VALUES (2, 'PQRS78', 'Volvo 9800',            2019, DATE '2019-11-02');
INSERT INTO bus (id_bus, patente, modelo, anio_fabricacion, fecha_compra) VALUES (3, 'TUVW12', 'Scania K410',           2023, DATE '2023-07-20');

--------------------------------------------------------------------------------
-- ASIENTO
-- Bus 1: 12 asientos | Bus 2: 10 asientos | Bus 3: 10 asientos
-- La capacidad de cada bus es exactamente esta cantidad de filas.
--------------------------------------------------------------------------------
-- Bus 1 - piso 1 salon cama
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (1,  1, 2, 1);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (1,  2, 2, 1);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (1,  3, 2, 1);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (1,  4, 2, 1);
-- Bus 1 - piso 2 semi cama
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (1,  5, 1, 2);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (1,  6, 1, 2);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (1,  7, 1, 2);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (1,  8, 1, 2);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (1,  9, 1, 2);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (1, 10, 1, 2);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (1, 11, 1, 2);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (1, 12, 1, 2);
-- Bus 2 - piso 1 salon cama
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (2,  1, 2, 1);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (2,  2, 2, 1);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (2,  3, 2, 1);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (2,  4, 2, 1);
-- Bus 2 - piso 2 semi cama
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (2,  5, 1, 2);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (2,  6, 1, 2);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (2,  7, 1, 2);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (2,  8, 1, 2);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (2,  9, 1, 2);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (2, 10, 1, 2);
-- Bus 3 - piso 1 premium + salon cama
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (3,  1, 3, 1);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (3,  2, 3, 1);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (3,  3, 2, 1);
INSERT INTO asiento (id_bus, nro_asiento, id_tipo_asiento, piso) VALUES (3,  4, 2, 1);
-- Bus 3 - piso 2 semi cama
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
-- El bus 1 hace tres viajes distintos (1, 2 y 6): eso es lo que la relacion
-- 1:1 del modelo original hacia imposible.
-- Ninguna asignacion de bus se superpone en el tiempo.
--------------------------------------------------------------------------------
INSERT INTO viaje (id_viaje, id_ruta, id_bus, salida_prog, llegada_prog, estado_viaje) VALUES (1, 1, 1, TIMESTAMP '2026-09-01 08:00:00', TIMESTAMP '2026-09-01 14:30:00', 'FIN');
INSERT INTO viaje (id_viaje, id_ruta, id_bus, salida_prog, llegada_prog, estado_viaje) VALUES (2, 2, 1, TIMESTAMP '2026-09-01 22:00:00', TIMESTAMP '2026-09-02 04:30:00', 'FIN');
INSERT INTO viaje (id_viaje, id_ruta, id_bus, salida_prog, llegada_prog, estado_viaje) VALUES (3, 3, 2, TIMESTAMP '2026-09-01 09:00:00', TIMESTAMP '2026-09-01 16:00:00', 'FIN');
INSERT INTO viaje (id_viaje, id_ruta, id_bus, salida_prog, llegada_prog, estado_viaje) VALUES (4, 5, 3, TIMESTAMP '2026-09-02 21:00:00', TIMESTAMP '2026-09-03 06:00:00', 'PRO');
INSERT INTO viaje (id_viaje, id_ruta, id_bus, salida_prog, llegada_prog, estado_viaje) VALUES (5, 6, 2, TIMESTAMP '2026-09-02 07:30:00', TIMESTAMP '2026-09-02 09:15:00', 'PRO');
INSERT INTO viaje (id_viaje, id_ruta, id_bus, salida_prog, llegada_prog, estado_viaje) VALUES (6, 1, 1, TIMESTAMP '2026-09-03 08:00:00', TIMESTAMP '2026-09-03 14:30:00', 'PRO');

--------------------------------------------------------------------------------
-- VIAJE_CONDUCTOR
-- Ningun conductor queda asignado a dos viajes que se superpongan.
--------------------------------------------------------------------------------
INSERT INTO viaje_conductor (id_viaje, id_conductor, rol) VALUES (1, 1, 'TIT');
INSERT INTO viaje_conductor (id_viaje, id_conductor, rol) VALUES (1, 2, 'REL');
INSERT INTO viaje_conductor (id_viaje, id_conductor, rol) VALUES (2, 1, 'TIT');
INSERT INTO viaje_conductor (id_viaje, id_conductor, rol) VALUES (2, 2, 'REL');
INSERT INTO viaje_conductor (id_viaje, id_conductor, rol) VALUES (3, 3, 'TIT');
INSERT INTO viaje_conductor (id_viaje, id_conductor, rol) VALUES (4, 3, 'TIT');
INSERT INTO viaje_conductor (id_viaje, id_conductor, rol) VALUES (4, 4, 'REL');
INSERT INTO viaje_conductor (id_viaje, id_conductor, rol) VALUES (5, 4, 'TIT');
INSERT INTO viaje_conductor (id_viaje, id_conductor, rol) VALUES (6, 2, 'TIT');

--------------------------------------------------------------------------------
-- PASAJERO
--------------------------------------------------------------------------------
INSERT INTO pasajero (id_pasajero, run, dv, pnombre, snombre, papellido, sapellido, mail, telefono) VALUES (1, 11222333, '4', 'Camila',    'Andrea',  'Torres',  'Lagos',   'camila.torres@correo.cl',   '+56911111111');
INSERT INTO pasajero (id_pasajero, run, dv, pnombre, snombre, papellido, sapellido, mail, telefono) VALUES (2, 13444555, '6', 'Rodrigo',   'Esteban', 'Munoz',   'Diaz',    'rmunoz@correo.cl',          '+56922222222');
INSERT INTO pasajero (id_pasajero, run, dv, pnombre, snombre, papellido, sapellido, mail, telefono) VALUES (3, 16555777, 'K', 'Valentina', 'Paz',     'Herrera', 'Nunez',   'vherrera@correo.cl',        '+56933333333');
INSERT INTO pasajero (id_pasajero, run, dv, pnombre, snombre, papellido, sapellido, mail, telefono) VALUES (4, 10111222, '3', 'Sebastian', NULL,      'Castro',  'Rivas',   'scastro@correo.cl',         '+56944444444');
INSERT INTO pasajero (id_pasajero, run, dv, pnombre, snombre, papellido, sapellido, mail, telefono) VALUES (5, 18999000, '1', 'Francisca', 'Belen',   'Alvarez', 'Soto',    'falvarez@correo.cl',        NULL);
INSERT INTO pasajero (id_pasajero, run, dv, pnombre, snombre, papellido, sapellido, mail, telefono) VALUES (6, 14333222, '8', 'Matias',    'Alonso',  'Vega',    'Fuentes', 'mvega@correo.cl',           '+56966666666');

--------------------------------------------------------------------------------
-- TARIFA
-- La tarifa 11 esta cerrada (vigencia_hasta) y convive con la 1, que la
-- reemplazo para la misma ruta y tipo de asiento: precio por condicion
-- comercial sin sobrescribir el historico.
--------------------------------------------------------------------------------
INSERT INTO tarifa (id_tarifa, id_ruta, id_tipo_asiento, vigencia_desde, vigencia_hasta, precio) VALUES ( 1, 1, 1, DATE '2026-01-01', NULL, 18900);
INSERT INTO tarifa (id_tarifa, id_ruta, id_tipo_asiento, vigencia_desde, vigencia_hasta, precio) VALUES ( 2, 1, 2, DATE '2026-01-01', NULL, 27500);
INSERT INTO tarifa (id_tarifa, id_ruta, id_tipo_asiento, vigencia_desde, vigencia_hasta, precio) VALUES ( 3, 2, 1, DATE '2026-01-01', NULL, 18900);
INSERT INTO tarifa (id_tarifa, id_ruta, id_tipo_asiento, vigencia_desde, vigencia_hasta, precio) VALUES ( 4, 2, 2, DATE '2026-01-01', NULL, 27500);
INSERT INTO tarifa (id_tarifa, id_ruta, id_tipo_asiento, vigencia_desde, vigencia_hasta, precio) VALUES ( 5, 3, 1, DATE '2026-01-01', NULL, 21000);
INSERT INTO tarifa (id_tarifa, id_ruta, id_tipo_asiento, vigencia_desde, vigencia_hasta, precio) VALUES ( 6, 3, 2, DATE '2026-01-01', NULL, 31000);
INSERT INTO tarifa (id_tarifa, id_ruta, id_tipo_asiento, vigencia_desde, vigencia_hasta, precio) VALUES ( 7, 5, 1, DATE '2026-01-01', NULL, 26500);
INSERT INTO tarifa (id_tarifa, id_ruta, id_tipo_asiento, vigencia_desde, vigencia_hasta, precio) VALUES ( 8, 5, 2, DATE '2026-01-01', NULL, 39900);
INSERT INTO tarifa (id_tarifa, id_ruta, id_tipo_asiento, vigencia_desde, vigencia_hasta, precio) VALUES ( 9, 5, 3, DATE '2026-01-01', NULL, 52000);
INSERT INTO tarifa (id_tarifa, id_ruta, id_tipo_asiento, vigencia_desde, vigencia_hasta, precio) VALUES (10, 6, 1, DATE '2026-01-01', NULL,  4500);
INSERT INTO tarifa (id_tarifa, id_ruta, id_tipo_asiento, vigencia_desde, vigencia_hasta, precio) VALUES (11, 1, 1, DATE '2025-06-01', DATE '2025-12-31', 16500);

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
INSERT INTO pasaje (id_pasaje, id_venta, id_viaje, id_bus, nro_asiento, id_pasajero, id_tarifa, precio_aplicado, descuento, id_estado, fecha_emision) VALUES (1, 1, 1, 1,  3, 1,  2, 27500,    0, 3, TIMESTAMP '2026-08-20 10:15:00');
INSERT INTO pasaje (id_pasaje, id_venta, id_viaje, id_bus, nro_asiento, id_pasajero, id_tarifa, precio_aplicado, descuento, id_estado, fecha_emision) VALUES (2, 1, 1, 1,  4, 2,  2, 27500, 2750, 3, TIMESTAMP '2026-08-20 10:15:00');
INSERT INTO pasaje (id_pasaje, id_venta, id_viaje, id_bus, nro_asiento, id_pasajero, id_tarifa, precio_aplicado, descuento, id_estado, fecha_emision) VALUES (3, 2, 4, 3,  1, 4,  9, 52000,    0, 2, TIMESTAMP '2026-08-22 16:40:00');
INSERT INTO pasaje (id_pasaje, id_venta, id_viaje, id_bus, nro_asiento, id_pasajero, id_tarifa, precio_aplicado, descuento, id_estado, fecha_emision) VALUES (4, 2, 4, 3,  2, 5,  9, 52000, 5200, 2, TIMESTAMP '2026-08-22 16:40:00');
INSERT INTO pasaje (id_pasaje, id_venta, id_viaje, id_bus, nro_asiento, id_pasajero, id_tarifa, precio_aplicado, descuento, id_estado, fecha_emision) VALUES (5, 2, 4, 3,  6, 6,  7, 26500,    0, 2, TIMESTAMP '2026-08-22 16:40:00');
INSERT INTO pasaje (id_pasaje, id_venta, id_viaje, id_bus, nro_asiento, id_pasajero, id_tarifa, precio_aplicado, descuento, id_estado, fecha_emision) VALUES (6, 3, 3, 2,  7, 3,  5, 21000,    0, 4, TIMESTAMP '2026-08-25 09:05:00');
INSERT INTO pasaje (id_pasaje, id_venta, id_viaje, id_bus, nro_asiento, id_pasajero, id_tarifa, precio_aplicado, descuento, id_estado, fecha_emision) VALUES (7, 4, 3, 2,  7, 6,  5, 21000,    0, 2, TIMESTAMP '2026-08-26 18:20:00');
INSERT INTO pasaje (id_pasaje, id_venta, id_viaje, id_bus, nro_asiento, id_pasajero, id_tarifa, precio_aplicado, descuento, id_estado, fecha_emision) VALUES (8, 4, 5, 2,  5, 6, 10,  4500,    0, 1, TIMESTAMP '2026-08-26 18:20:00');

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
