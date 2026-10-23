--------------------------------------------------------------------------------
-- Modelo_GestionTransporte  |  Script PL/SQL - Parte 3
-- PKG_OPERACIONES: los procesos que escriben en la base
--
-- Requisito : DDL cargado y 01_Pkg_Calculos.sql ejecutado
-- Motor     : Oracle Database
--------------------------------------------------------------------------------
-- TRAZABILIDAD CON LA DOCUMENTACION
--
--   Informe  : 2.3 (RF-01, RF-02, RF-03), 5.1 y 5.2 (RECORD y VARRAY),
--              7.2 y 7.3 (excepciones de usuario y estrategia),
--              8.1 y 8.2 (procedimientos), 10 (packages)
--   Anexo    : Tabla 28 (procedimientos), Tabla 27 (excepciones de usuario),
--              Tabla 3 (requerimientos), Tabla 5 y 6 (reglas y mecanismos)
--   Reglas   : RN-02, RN-03, RN-04, RN-05, RN-06, RN-07, RN-08, RN-09, RN-10
--   Rubrica  : IE1.1.1 - RECORD y VARRAY (5% informe / 15% presentacion)
--              IE1.3.1 - excepciones de usuario (10% / 15%)
--              IE1.4.1 - procedimientos y packages (15% / 15%)
--
--------------------------------------------------------------------------------
-- LO QUE EL PACKAGE RESUELVE Y LOS BLOQUES ANONIMOS NO PODIAN
--
-- Hay dos cosas que solo aparecen al agrupar estos procesos en un package, y
-- ambas se ven en la especificacion de abajo:
--
--   1. LOS TIPOS COMPUESTOS SE VUELVEN COMPARTIBLES. Un TYPE declarado en un
--      bloque anonimo muere con el bloque: cada programa que quisiera pasar una
--      lista de solicitudes tenia que declarar su propio VARRAY identico. Aqui
--      tv_solicitudes se declara una vez y cualquier programa la usa.
--
--   2. LAS EXCEPCIONES DE USUARIO SE VUELVEN PARTE DE LA INTERFAZ. Una EXCEPTION
--      declarada dentro de un bloque anonimo no existe fuera de el: quien lo
--      invocara solo podia capturar OTHERS y leer el mensaje. Declaradas en la
--      especificacion, el invocador puede escribir
--          WHEN pkg_operaciones.e_asiento_no_disponible THEN ...
--      y reaccionar de forma distinta a cada regla incumplida. Esto es lo que
--      convierte "el procedimiento fallo" en "el procedimiento fallo POR ESTO".
--
-- CONTROL DE TRANSACCION: NINGUN PROCEDIMIENTO HACE COMMIT NI ROLLBACK
--
-- Una operacion no decide por su invocador cuando confirmar. Si sp_vender_pasaje
-- hiciera COMMIT, seria imposible componerla dentro de una transaccion mayor -por
-- ejemplo, vender y luego registrar un pago, todo o nada-. Los procedimientos
-- validan, escriben y levantan excepciones; quien los llama decide si confirma o
-- revierte. Los bloques de demostracion (05_Demostraciones.sql) hacen ROLLBACK.
--
-- EL HISTORIAL LO ESCRIBE EL TRIGGER
--
-- Ningun procedimiento de este package inserta en PASAJE_ESTADO_HIST. Lo hace
-- trg_pasaje_historial (04_Triggers.sql) al detectar el evento. Si un
-- procedimiento lo insertara ademas, cada transicion quedaria registrada dos
-- veces.
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 140
SET PAGESIZE 60


--------------------------------------------------------------------------------
-- ESPECIFICACION
--------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_operaciones AS

    ----------------------------------------------------------------------------
    -- TIPOS COMPUESTOS PUBLICOS
    --
    -- RECORD agrupa atributos HETEROGENEOS de una misma entidad: una solicitud
    -- de pasaje tiene un asiento y un pasajero, de tipos distintos, que solo
    -- tienen sentido juntos.
    --
    -- VARRAY agrupa elementos HOMOGENEOS sobre los que se itera, con un limite
    -- conocido declarado EN EL TIPO. El 6 no es arbitrario: es el maximo de
    -- asientos por transaccion que fija la politica comercial. Una tabla anidada
    -- no impondria cota alguna, y la restriccion del negocio dejaria de estar
    -- expresada en la estructura de datos.
    ----------------------------------------------------------------------------
    TYPE tr_solicitud IS RECORD (
        nro_asiento  asiento.nro_asiento%TYPE,
        id_pasajero  pasajero.id_pasajero%TYPE
    );

    TYPE tv_solicitudes IS VARRAY(6) OF tr_solicitud;

    -- Tripulacion de un viaje: 4 es el maximo razonable incluso en el trayecto
    -- mas largo de la malla, que exige 2.
    TYPE tv_conductores IS VARRAY(4) OF conductor.id_conductor%TYPE;

    ----------------------------------------------------------------------------
    -- EXCEPCIONES DE USUARIO
    --
    -- Todas describen condiciones VALIDAS para Oracle pero INVALIDAS para el
    -- negocio: el motor no puede saber que un pasaje no se anula cuatro horas
    -- antes de la salida, ni que un conductor tiene un limite legal de jornada.
    -- Al estar aqui y no dentro de cada cuerpo, el invocador puede distinguirlas.
    ----------------------------------------------------------------------------
    e_bus_ocupado           EXCEPTION;   -- RN-04
    e_conductor_ocupado     EXCEPTION;   -- RN-03
    e_jornada_excedida      EXCEPTION;   -- RN-10
    e_viaje_no_programado   EXCEPTION;   -- precondicion de RF-01
    e_pasajero_inexistente  EXCEPTION;   -- precondicion de RF-01
    e_asiento_no_disponible EXCEPTION;   -- RN-06
    e_fuera_de_plazo        EXCEPTION;   -- precondicion de RF-02
    e_ya_anulado            EXCEPTION;   -- RN-08

    ----------------------------------------------------------------------------
    -- PROCEDIMIENTOS
    ----------------------------------------------------------------------------

    -- 3.1  Programa un viaje validando solapamiento de bus y de conductores, y
    --      que la tripulacion cubra la jornada legal. RF-03.
    --      Devuelve por OUT el identificador del viaje creado.
    PROCEDURE sp_programar_viaje (
        p_id_ruta      IN  ruta.id_ruta%TYPE,
        p_id_bus       IN  bus.id_bus%TYPE,
        p_salida       IN  TIMESTAMP,
        p_conductores  IN  tv_conductores,
        p_id_viaje     OUT viaje.id_viaje%TYPE
    );

    -- 3.2  Registra una venta con uno o mas pasajes, cada uno para un pasajero,
    --      viaje y asiento determinados. RF-01.
    --      Es completa o no ocurre: si un solo asiento no esta disponible, la
    --      venta entera se rechaza.
    PROCEDURE sp_vender_pasaje (
        p_id_viaje      IN  viaje.id_viaje%TYPE,
        p_id_comprador  IN  pasajero.id_pasajero%TYPE,
        p_solicitudes   IN  tv_solicitudes,
        p_id_venta      OUT venta.id_venta%TYPE
    );

    -- 3.3  Anula un pasaje dentro del plazo permitido, liberando su asiento.
    --      RF-02. El motivo se propaga al trigger por el contexto de sesion.
    PROCEDURE sp_anular_pasaje (
        p_id_pasaje IN pasaje.id_pasaje%TYPE,
        p_motivo    IN VARCHAR2
    );

END pkg_operaciones;
/
SHOW ERRORS


--------------------------------------------------------------------------------
-- BODY
--------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE BODY pkg_operaciones AS

    -- Ventana minima de antelacion para anular, en horas (RF-02). Es PRIVADA:
    -- forma parte de como se implementa la regla, no de lo que el package
    -- ofrece. Si manana la empresa la cambia a 6 horas, ningun programa externo
    -- se entera ni necesita recompilarse.
    c_ventana_anulacion  CONSTANT NUMBER := 4;


    ----------------------------------------------------------------------------
    -- 3.1  Programacion de viajes
    --
    -- Va antes que la venta porque la venta necesita viajes ya programados.
    --
    -- Las dos validaciones de solapamiento usan la misma condicion canonica:
    --     a.inicio < b.fin  AND  b.inicio < a.fin
    -- Trata correctamente los viajes que se tocan en el extremo, que no se
    -- superponen. La llegada no se pide como parametro sino que se deriva de la
    -- duracion de la ruta, para que no pueda declararse una distinta de la que
    -- el catalogo define.
    --
    -- El numero de conductores requeridos se calcula aqui con CEIL y NO con
    -- pkg_calculos.fn_conductores_requeridos, aunque es la misma formula: esa
    -- funcion recibe un id_viaje y lo usa para buscar su ruta, y en este punto
    -- el viaje TODAVIA NO EXISTE -es justamente lo que se esta por crear-. La
    -- duracion ya se obtuvo para calcular la llegada, asi que no hay consulta
    -- adicional.
    ----------------------------------------------------------------------------
    PROCEDURE sp_programar_viaje (
        p_id_ruta      IN  ruta.id_ruta%TYPE,
        p_id_bus       IN  bus.id_bus%TYPE,
        p_salida       IN  TIMESTAMP,
        p_conductores  IN  tv_conductores,
        p_id_viaje     OUT viaje.id_viaje%TYPE
    )
    IS
        CURSOR c_solape_bus (cp_id_bus  bus.id_bus%TYPE,
                             cp_salida  TIMESTAMP,
                             cp_llegada TIMESTAMP) IS
            SELECT v.id_viaje
            FROM   viaje v
            WHERE  v.id_bus        = cp_id_bus
            AND    v.estado_viaje <> 'CAN'          -- un viaje cancelado libera el bus
            AND    v.salida_prog   < cp_llegada
            AND    cp_salida       < v.llegada_prog;

        CURSOR c_solape_conductor (cp_id_conductor conductor.id_conductor%TYPE,
                                   cp_salida  TIMESTAMP,
                                   cp_llegada TIMESTAMP) IS
            SELECT v.id_viaje
            FROM   viaje v
            JOIN   viaje_conductor vc ON vc.id_viaje = v.id_viaje
            WHERE  vc.id_conductor = cp_id_conductor
            AND    v.estado_viaje <> 'CAN'
            AND    v.salida_prog   < cp_llegada
            AND    cp_salida       < v.llegada_prog;

        v_duracion_min  ruta.duracion_estimada_min%TYPE;
        v_llegada       TIMESTAMP;
        v_requeridos    PLS_INTEGER;
        v_conflicto     viaje.id_viaje%TYPE;
    BEGIN
        -- La duracion la define la ruta; la llegada se deriva, no se declara.
        SELECT duracion_estimada_min INTO v_duracion_min
        FROM   ruta WHERE id_ruta = p_id_ruta;

        v_llegada    := p_salida + NUMTODSINTERVAL(v_duracion_min, 'MINUTE');
        v_requeridos := CEIL(v_duracion_min / 60 / pkg_calculos.c_max_horas_conduccion);

        -- VALIDACION 1 (RN-10): la tripulacion debe cubrir la jornada legal
        IF p_conductores IS NULL OR p_conductores.COUNT < v_requeridos THEN
            RAISE e_jornada_excedida;
        END IF;

        -- VALIDACION 2 (RN-04): el bus no puede estar en otro viaje superpuesto
        OPEN c_solape_bus(p_id_bus, p_salida, v_llegada);
        FETCH c_solape_bus INTO v_conflicto;
        IF c_solape_bus%FOUND THEN
            CLOSE c_solape_bus;
            RAISE e_bus_ocupado;
        END IF;
        CLOSE c_solape_bus;

        -- VALIDACION 3 (RN-03): ningun conductor en otro viaje superpuesto
        FOR i IN 1 .. p_conductores.COUNT LOOP
            OPEN c_solape_conductor(p_conductores(i), p_salida, v_llegada);
            FETCH c_solape_conductor INTO v_conflicto;
            IF c_solape_conductor%FOUND THEN
                CLOSE c_solape_conductor;
                RAISE e_conductor_ocupado;
            END IF;
            CLOSE c_solape_conductor;
        END LOOP;

        -- ESCRITURA: recien aqui, con todas las reglas verificadas
        SELECT NVL(MAX(id_viaje),0) + 1 INTO p_id_viaje FROM viaje;

        INSERT INTO viaje (id_viaje, id_ruta, id_bus, salida_prog, llegada_prog, estado_viaje)
        VALUES (p_id_viaje, p_id_ruta, p_id_bus, p_salida, v_llegada, 'PRO');

        FOR i IN 1 .. p_conductores.COUNT LOOP
            INSERT INTO viaje_conductor (id_viaje, id_conductor, rol)
            VALUES (p_id_viaje, p_conductores(i),
                    CASE WHEN i = 1 THEN 'TIT' ELSE 'REL' END);
        END LOOP;
        -- Sin COMMIT: la decision de confirmar es del invocador.
    END sp_programar_viaje;


    ----------------------------------------------------------------------------
    -- 3.2  Venta de pasajes
    --
    -- Es la operacion donde convergen las dos estructuras compuestas:
    --   VARRAY  aporta QUE asientos procesar y para quien, con limite conocido
    --   RECORD  describe la solicitud de cada pasajero como una unidad
    --
    -- Un detalle de PL/SQL: los tipos RECORD no tienen constructor, a diferencia
    -- de los tipos objeto. Por eso quien arma la coleccion la llena con EXTEND y
    -- asignacion campo a campo, no con tr_solicitud(3, 1).
    --
    -- ATOMICIDAD: se valida el conjunto COMPLETO antes de escribir nada. Vender
    -- los disponibles y omitir el resto dejaria al cliente con un grupo separado
    -- sin avisarle.
    ----------------------------------------------------------------------------
    PROCEDURE sp_vender_pasaje (
        p_id_viaje      IN  viaje.id_viaje%TYPE,
        p_id_comprador  IN  pasajero.id_pasajero%TYPE,
        p_solicitudes   IN  tv_solicitudes,
        p_id_venta      OUT venta.id_venta%TYPE
    )
    IS
        v_id_bus     viaje.id_bus%TYPE;
        v_id_ruta    viaje.id_ruta%TYPE;
        v_estado     viaje.estado_viaje%TYPE;
        v_id_tipo    tipo_asiento.id_tipo_asiento%TYPE;
        v_id_tarifa  tarifa.id_tarifa%TYPE;
        v_precio     tarifa.precio%TYPE;
        v_existe     PLS_INTEGER;
        v_id_pasaje  pasaje.id_pasaje%TYPE;
    BEGIN
        IF p_solicitudes IS NULL OR p_solicitudes.COUNT = 0 THEN
            RAISE e_asiento_no_disponible;
        END IF;

        -- VALIDACION 1: el viaje debe existir y estar programado
        SELECT id_bus, id_ruta, estado_viaje
        INTO   v_id_bus, v_id_ruta, v_estado
        FROM   viaje WHERE id_viaje = p_id_viaje;

        IF v_estado <> 'PRO' THEN
            RAISE e_viaje_no_programado;
        END IF;

        -- VALIDACION 2: recorre TODA la coleccion antes de escribir nada
        FOR i IN 1 .. p_solicitudes.COUNT LOOP

            -- el pasajero debe estar registrado (precondicion de RF-01)
            SELECT COUNT(*) INTO v_existe
            FROM   pasajero WHERE id_pasajero = p_solicitudes(i).id_pasajero;
            IF v_existe = 0 THEN
                RAISE e_pasajero_inexistente;
            END IF;

            -- el asiento debe existir en el bus de ESE viaje (RN-01)
            SELECT COUNT(*) INTO v_existe
            FROM   asiento
            WHERE  id_bus = v_id_bus AND nro_asiento = p_solicitudes(i).nro_asiento;
            IF v_existe = 0 THEN
                RAISE e_asiento_no_disponible;
            END IF;

            -- y debe estar libre (RN-06), segun el criterio del catalogo
            IF pkg_calculos.fn_asiento_ocupado(p_id_viaje, v_id_bus,
                                               p_solicitudes(i).nro_asiento) = 'S' THEN
                RAISE e_asiento_no_disponible;
            END IF;
        END LOOP;

        -- ESCRITURA: cabecera de la venta
        SELECT NVL(MAX(id_venta),0) + 1 INTO p_id_venta FROM venta;
        INSERT INTO venta (id_venta, id_pasajero_comprador, fecha_hora, canal, medio_pago)
        VALUES (p_id_venta, p_id_comprador, SYSTIMESTAMP, 'TER', 'EFE');

        SELECT NVL(MAX(id_pasaje),0) INTO v_id_pasaje FROM pasaje;

        FOR i IN 1 .. p_solicitudes.COUNT LOOP
            v_id_pasaje := v_id_pasaje + 1;

            SELECT a.id_tipo_asiento INTO v_id_tipo
            FROM   asiento a
            WHERE  a.id_bus = v_id_bus
            AND    a.nro_asiento = p_solicitudes(i).nro_asiento;

            -- El precio no se inventa: la funcion aplica RN-07 y devuelve la
            -- tarifa vigente; el precio es una lectura por clave primaria.
            v_id_tarifa := pkg_calculos.fn_tarifa_vigente(v_id_ruta, v_id_tipo, SYSDATE);
            SELECT precio INTO v_precio FROM tarifa WHERE id_tarifa = v_id_tarifa;

            -- id_bus viaja en el pasaje a proposito: las dos FK compuestas
            -- garantizan que el asiento pertenece al bus que hace este viaje.
            INSERT INTO pasaje (id_pasaje, id_venta, id_viaje, id_bus, nro_asiento,
                                id_pasajero, id_tarifa, precio_aplicado, descuento,
                                id_estado, fecha_emision)
            VALUES (v_id_pasaje, p_id_venta, p_id_viaje, v_id_bus,
                    p_solicitudes(i).nro_asiento, p_solicitudes(i).id_pasajero,
                    v_id_tarifa, v_precio, 0, 1, SYSTIMESTAMP);
            -- estado inicial 1 (PEN); el historial lo escribe el trigger
        END LOOP;
        -- Sin COMMIT: la decision de confirmar es del invocador.
    END sp_vender_pasaje;


    ----------------------------------------------------------------------------
    -- 3.3  Anulacion de pasaje
    --
    -- La anulacion no borra el pasaje: cambia su estado. Esa decision es la que
    -- hace posible auditar despues quien anulo que y cuando. El asiento se libera
    -- solo, porque el indice unico parcial deja de incluir a los pasajes cuyo
    -- estado no ocupa asiento (RN-09).
    --
    -- El motivo se declara en el contexto de la sesion antes del UPDATE, para
    -- que el trigger pueda recogerlo: un trigger no recibe parametros.
    --
    -- No calcula devolucion de dinero: el pago esta fuera del alcance del
    -- proyecto, segun la seccion 1.5 del informe.
    ----------------------------------------------------------------------------
    PROCEDURE sp_anular_pasaje (
        p_id_pasaje IN pasaje.id_pasaje%TYPE,
        p_motivo    IN VARCHAR2
    )
    IS
        v_id_estado  pasaje.id_estado%TYPE;
        v_salida     viaje.salida_prog%TYPE;
        v_horas      NUMBER;
    BEGIN
        SELECT p.id_estado, v.salida_prog
        INTO   v_id_estado, v_salida
        FROM   pasaje p JOIN viaje v ON v.id_viaje = p.id_viaje
        WHERE  p.id_pasaje = p_id_pasaje;

        -- Anular dos veces no es una transicion (RN-08)
        IF v_id_estado = 4 THEN
            RAISE e_ya_anulado;
        END IF;

        -- La ventana excluye por si sola los pasajes utilizados y los viajes ya
        -- salidos: si el viaje ya partio, las horas restantes son negativas.
        v_horas := (CAST(v_salida AS DATE) - SYSDATE) * 24;
        IF v_horas < c_ventana_anulacion THEN
            RAISE e_fuera_de_plazo;
        END IF;

        DBMS_APPLICATION_INFO.SET_CLIENT_INFO(p_motivo);
        UPDATE pasaje SET id_estado = 4 WHERE id_pasaje = p_id_pasaje;
        DBMS_APPLICATION_INFO.SET_CLIENT_INFO(NULL);
        -- Sin COMMIT: la decision de confirmar es del invocador.
    EXCEPTION
        WHEN OTHERS THEN
            -- El contexto de sesion se limpia siempre: si quedara con el motivo
            -- de una anulacion fallida, el trigger lo adjuntaria a la proxima
            -- transicion que ocurriera en esta sesion.
            DBMS_APPLICATION_INFO.SET_CLIENT_INFO(NULL);
            RAISE;
    END sp_anular_pasaje;

END pkg_operaciones;
/
SHOW ERRORS
