--------------------------------------------------------------------------------
-- Modelo_GestionTransporte  |  Script PL/SQL - Parte 4
-- PROCEDIMIENTOS DE NEGOCIO
--
-- Los dos procesos centrales del sistema: programar un viaje y vender pasajes.
-- Son el nivel 3 -validan y escriben- e invocan a las funciones del nivel 1.
--
-- Requisito : DDL cargado, mas 01_Calculos.sql y 03_Consultas_Cursores.sql.
--             05_Triggers.sql debe existir antes de EJECUTAR la venta.
--------------------------------------------------------------------------------
-- TRAZABILIDAD
--   Informe : 8.2 (procedimientos), 7.2 (excepciones)   |   Anexo : Tabla 28
--   Rubrica : IE1.1.1 RECORD y VARRAY | IE1.2.1 cursores
--             IE1.3.1 excepciones     | IE1.4.1 procedimientos y funciones
--
-- QUE ELEMENTO APORTA CADA PROCEDIMIENTO
--   4.1 programacion : cursor explicito OPEN/FETCH/CLOSE, 3 funciones de calculo
--   4.2 venta        : RECORD, VARRAY, cursor parametrizado, trigger
--------------------------------------------------------------------------------
-- DOS DECISIONES QUE ATRAVIESAN EL ARCHIVO
--
-- NO HAY COMMIT NI ROLLBACK. El procedimiento no sabe si es la operacion
-- completa o un paso de una transaccion mayor; quien lo llama si lo sabe. El
-- menu debe confirmar tras el exito y revertir tras un rechazo.
--
-- LOS ID SE CALCULAN CON NVL(MAX)+1. Sirve para este proyecto pero no es seguro
-- con sesiones concurrentes: dos llamadas simultaneas obtendrian el mismo
-- numero. En produccion corresponde una SEQUENCE.
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON SIZE UNLIMITED


--------------------------------------------------------------------------------
-- TIPO DE ESQUEMA: tv_asientos
--
-- Es el UNICO objeto nuevo que agrega este archivo, y es inevitable. Un VARRAY
-- declarado dentro de un procedimiento -o de un bloque anonimo, como en el 2.3-
-- muere con el; para que sea un PARAMETRO tiene que existir en el diccionario.
-- Es el mismo limite que hizo falta resolver con los tipos RECORD.
--
-- El 6 no es arbitrario: es el maximo de asientos por transaccion de mostrador
-- que define la politica comercial. El limite queda EN EL TIPO y no depende de
-- una validacion que alguien pueda olvidar.
--
-- Va NUMBER(4) y no asiento.nro_asiento%TYPE porque un tipo de esquema es SQL,
-- no PL/SQL, y ahi el anclaje %TYPE no existe. NUMBER(4) es la definicion real
-- de la columna; si esta cambiara, hay que actualizar el tipo a mano.
--------------------------------------------------------------------------------
CREATE OR REPLACE TYPE tv_asientos AS VARRAY(6) OF NUMBER(4);
/


--------------------------------------------------------------------------------
-- 4.1  PROGRAMACION DE VIAJES
-- Sirve a : RF-03     Implementa : RN-03, RN-04, RN-10
--
-- Recibe ruta, salida y bus. Calcula la llegada, verifica que no haya conflictos
-- y ASIGNA los conductores que la jornada exija.
--
-- COMO SE GARANTIZA QUE EL RELEVO SEA DISTINTO DEL TITULAR
--
-- No hace falta ninguna logica de exclusion. Los dos conductores salen de DOS
-- FETCH CONSECUTIVOS sobre el mismo cursor, y un cursor no devuelve dos veces la
-- misma fila: el segundo FETCH entrega necesariamente otro conductor. Por eso
-- tampoco hay una excepcion "conductor repetido": el caso no puede ocurrir.
--
-- RN-10 tambien queda cubierta por el cursor: si la ruta exige dos conductores y
-- solo hay uno libre, el segundo FETCH no encuentra fila y el viaje se rechaza.
--------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_programacion_viajes (
    p_id_ruta  IN ruta.id_ruta%TYPE,
    p_salida   IN viaje.salida_prog%TYPE,
    p_id_bus   IN bus.id_bus%TYPE
)
IS
    -- CURSOR parametrizado: los conductores sin compromiso en esa ventana.
    -- Invoca fn_recurso_ocupado, que puede ir dentro del WHERE porque devuelve
    -- NULL -un valor legitimo- y no una excepcion cuando el recurso esta libre.
    CURSOR c_conductores_libres (cp_salida  viaje.salida_prog%TYPE,
                                 cp_llegada viaje.llegada_prog%TYPE) IS
        SELECT c.id_conductor
        FROM   conductor c
        WHERE  fn_recurso_ocupado(cp_salida, cp_llegada,
                                  p_id_conductor => c.id_conductor) IS NULL
        ORDER  BY c.id_conductor;

    -- VARIABLES
    v_id_viaje    viaje.id_viaje%TYPE;          -- local: no se devuelve al menu
    v_llegada     viaje.llegada_prog%TYPE;
    v_requeridos  PLS_INTEGER;
    v_id_titular  conductor.id_conductor%TYPE;
    v_id_relevo   conductor.id_conductor%TYPE;  -- queda NULL si basta uno
    v_conflicto   viaje.id_viaje%TYPE;
    v_duplicados  PLS_INTEGER;

    -- EXCEPCIONES DE USUARIO
    e_ruta_inexistente EXCEPTION;
    e_salida_en_pasado EXCEPTION;
    e_viaje_duplicado  EXCEPTION;
    e_bus_ocupado      EXCEPTION;   -- RN-04
    e_sin_conductores  EXCEPTION;   -- RN-03 y RN-10
BEGIN
    -- 1. La ruta debe existir. Las dos funciones la leen, asi que se agrupan
    --    para dar un mensaje propio en vez de un ORA-01403 suelto.
    BEGIN
        v_llegada    := fn_llegada_estimada(p_id_ruta, p_salida);
        v_requeridos := fn_conductores_requeridos(p_id_ruta);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RAISE e_ruta_inexistente;
    END;

    -- 2. No se programa hacia el pasado.
    IF p_salida <= SYSTIMESTAMP THEN
        RAISE e_salida_en_pasado;
    END IF;

    -- 3. No repetir un viaje ya programado para la misma ruta y salida.
    SELECT COUNT(*)
    INTO   v_duplicados
    FROM   viaje v
    WHERE  v.id_ruta      = p_id_ruta
    AND    v.salida_prog  = p_salida
    AND    v.estado_viaje IN ('PRO','ENC');

    IF v_duplicados > 0 THEN
        RAISE e_viaje_duplicado;
    END IF;

    -- 4. RN-04: el bus elegido no puede estar en un viaje que se solape.
    v_conflicto := fn_recurso_ocupado(p_salida, v_llegada, p_id_bus => p_id_bus);
    IF v_conflicto IS NOT NULL THEN
        RAISE e_bus_ocupado;
    END IF;

    -- 5. RN-03 y RN-10: el sistema asigna la tripulacion.
    --    Se usa la forma extendida OPEN/FETCH/CLOSE porque hacen falta filas
    --    SUELTAS -una o dos-, no recorrer el conjunto completo. Un FOR obligaria
    --    a contar vueltas y salir a mitad de camino.
    OPEN c_conductores_libres(p_salida, v_llegada);

    FETCH c_conductores_libres INTO v_id_titular;
    IF c_conductores_libres%NOTFOUND THEN
        CLOSE c_conductores_libres;
        RAISE e_sin_conductores;
    END IF;

    IF v_requeridos > 1 THEN
        FETCH c_conductores_libres INTO v_id_relevo;   -- distinto por definicion
        IF c_conductores_libres%NOTFOUND THEN
            CLOSE c_conductores_libres;
            RAISE e_sin_conductores;
        END IF;
    END IF;

    CLOSE c_conductores_libres;

    -- 6. Recien aqui se escribe: ninguna validacion dejo filas a medias.
    SELECT NVL(MAX(v.id_viaje), 0) + 1 INTO v_id_viaje FROM viaje v;

    INSERT INTO viaje (id_viaje, id_ruta, id_bus,
                       salida_prog, llegada_prog, estado_viaje)
    VALUES (v_id_viaje, p_id_ruta, p_id_bus, p_salida, v_llegada, 'PRO');

    -- UNA fila por conductor. Aqui queda registrado el relevo: dos conductores
    -- no son dos viajes, son dos asignaciones del mismo viaje.
    INSERT INTO viaje_conductor (id_viaje, id_conductor, rol)
    VALUES (v_id_viaje, v_id_titular, 'TIT');

    IF v_id_relevo IS NOT NULL THEN
        INSERT INTO viaje_conductor (id_viaje, id_conductor, rol)
        VALUES (v_id_viaje, v_id_relevo, 'REL');
    END IF;

    DBMS_OUTPUT.PUT_LINE('  Viaje ' || v_id_viaje || ' programado | ruta ' ||
        p_id_ruta || ' | bus ' || p_id_bus || ' | ' ||
        TO_CHAR(p_salida,  'DD-MM-YYYY HH24:MI') || ' -> ' ||
        TO_CHAR(v_llegada, 'DD-MM-YYYY HH24:MI') || ' | ' ||
        CASE WHEN v_id_relevo IS NULL
             THEN 'conductor ' || v_id_titular
             ELSE 'titular ' || v_id_titular || ', relevo ' || v_id_relevo
        END);

EXCEPTION
    WHEN e_ruta_inexistente THEN
        DBMS_OUTPUT.PUT_LINE('  Rechazado: la ruta ' || p_id_ruta || ' no existe.');

    WHEN e_salida_en_pasado THEN
        DBMS_OUTPUT.PUT_LINE('  Rechazado: la salida ' ||
            TO_CHAR(p_salida,'DD-MM-YYYY HH24:MI') || ' ya paso.');

    WHEN e_viaje_duplicado THEN
        DBMS_OUTPUT.PUT_LINE('  Rechazado: ya hay un viaje programado para la ruta ' ||
            p_id_ruta || ' a las ' || TO_CHAR(p_salida,'DD-MM-YYYY HH24:MI') || '.');

    WHEN e_bus_ocupado THEN
        DBMS_OUTPUT.PUT_LINE('  Rechazado por RN-04: el bus ' || p_id_bus ||
            ' ya esta comprometido en el viaje ' || v_conflicto || '.');
        -- El bus lo eligio el usuario, asi que se le muestran las alternativas.
        sp_buscar_bus_libre(p_salida, v_llegada);

    WHEN e_sin_conductores THEN
        DBMS_OUTPUT.PUT_LINE('  Rechazado por RN-10: la ruta exige ' || v_requeridos ||
            ' conductor(es) y no hay tantos libres en esa ventana.');
END sp_programacion_viajes;
/


--------------------------------------------------------------------------------
-- 4.2  VENTA DE PASAJES
-- Sirve a : RF-01     Implementa : RN-05, RN-06, RN-07
--
-- Recibe el viaje, el comprador y los asientos solicitados en un VARRAY. Emite
-- una venta y un pasaje por asiento.
--
-- POR QUE EL PASAJERO VA EN EL PASAJE Y NO EN LA VENTA (RN-05)
--
-- Aqui el comprador es el titular de los tres pasajes por simplicidad, pero el
-- modelo permite que cada pasaje tenga un pasajero distinto porque id_pasajero
-- cuelga de PASAJE, no de VENTA.
--
-- EL HISTORIAL NO SE ESCRIBE AQUI
--
-- Cada INSERT en PASAJE dispara trg_pasaje_historial, que registra la transicion
-- por si solo. Si el procedimiento tambien insertara en PASAJE_ESTADO_HIST, cada
-- venta quedaria registrada dos veces.
--------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_venta_pasajes (
    p_id_viaje     IN viaje.id_viaje%TYPE,
    p_id_comprador IN pasajero.id_pasajero%TYPE,
    p_asientos     IN tv_asientos,
    p_canal        IN venta.canal%TYPE      DEFAULT 'TER',
    p_medio_pago   IN venta.medio_pago%TYPE DEFAULT 'EFE'
)
IS
    -- RECORD: la misma estructura del bloque 2.4. Agrupa los cinco datos que
    -- describen un pasaje en formacion; sin el habria que arrastrar cuatro
    -- variables sueltas por todo el bucle.
    TYPE tr_pasaje IS RECORD (
        nro_asiento      asiento.nro_asiento%TYPE,
        -- El campo NO puede llamarse tipo_asiento: colisionaria con la tabla
        -- homonima y PL/SQL lo resolveria contra el campo (PLS-00320).
        nombre_tipo      tipo_asiento.nombre%TYPE,
        id_tarifa        tarifa.id_tarifa%TYPE,
        precio_aplicado  pasaje.precio_aplicado%TYPE
    );

    -- CURSOR parametrizado: describe UN asiento del viaje con su tarifa vigente.
    -- El JOIN con TARIFA cumple dos papeles: trae el precio y, por ser INNER,
    -- deja fuera los asientos cuyo tipo no tiene tarifa en esa ruta. Un asiento
    -- sin precio no es vendible, y asi el cursor no lo ofrece.
    --
    -- La vigencia va escrita aqui y no se resuelve con obtener_precio_tarifa:
    -- esa funcion devuelve el PRECIO pero PASAJE necesita ademas el id_tarifa,
    -- y ambos deben salir de la MISMA fila. Tomarlos del mismo JOIN es una sola
    -- verdad; llamar a la funcion seria leer dos veces la misma tarifa.
    CURSOR c_asiento (cp_id_viaje viaje.id_viaje%TYPE,
                      cp_nro      asiento.nro_asiento%TYPE) IS
        SELECT a.nro_asiento, ta.nombre, tf.id_tarifa, tf.precio
        FROM   viaje v
        JOIN   asiento a       ON a.id_bus           = v.id_bus
        JOIN   tipo_asiento ta ON ta.id_tipo_asiento = a.id_tipo_asiento
        JOIN   tarifa tf       ON tf.id_ruta         = v.id_ruta
                              AND tf.id_tipo_asiento = a.id_tipo_asiento
                              AND tf.vigencia_desde <= TRUNC(SYSDATE)
                              AND (tf.vigencia_hasta IS NULL
                                   OR tf.vigencia_hasta >= TRUNC(SYSDATE))
        WHERE  v.id_viaje    = cp_id_viaje
        AND    a.nro_asiento = cp_nro;

    -- VARIABLES
    r_pasaje     tr_pasaje;
    v_id_venta   venta.id_venta%TYPE;
    v_id_pasaje  pasaje.id_pasaje%TYPE;
    v_id_bus     viaje.id_bus%TYPE;
    v_estado     viaje.estado_viaje%TYPE;
    v_ocupados   PLS_INTEGER;
    v_total      NUMBER := 0;
    -- Guarda el asiento en curso: el indice del FOR no existe en el manejador.
    v_solicitado asiento.nro_asiento%TYPE;

    c_estado_vendido CONSTANT estado_pasaje.id_estado%TYPE := 2;   -- VEN

    -- EXCEPCIONES DE USUARIO
    e_viaje_no_vendible   EXCEPTION;   -- no existe o ya no admite venta
    e_asiento_no_vendible EXCEPTION;   -- no esta en el bus o no tiene tarifa
    e_asiento_ocupado     EXCEPTION;   -- RN-06
BEGIN
    -- 1. El viaje debe existir y seguir admitiendo venta.
    BEGIN
        SELECT v.id_bus, v.estado_viaje
        INTO   v_id_bus, v_estado
        FROM   viaje v WHERE v.id_viaje = p_id_viaje;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RAISE e_viaje_no_vendible;
    END;

    IF v_estado <> 'PRO' THEN
        RAISE e_viaje_no_vendible;
    END IF;

    -- 2. Sin asientos no hay venta. Se comprueba antes de crear la cabecera
    --    para no dejar una venta vacia.
    IF p_asientos IS NULL OR p_asientos.COUNT = 0 THEN
        RAISE_APPLICATION_ERROR(-20030, 'La venta no incluye ningun asiento.');
    END IF;

    -- 3. Cabecera de la venta. Si algo falla mas adelante el procedimiento no
    --    confirma nada, y el ROLLBACK del llamador se lleva tambien esta fila.
    SELECT NVL(MAX(id_venta), 0) + 1 INTO v_id_venta FROM venta;

    INSERT INTO venta (id_venta, id_pasajero_comprador, canal, medio_pago)
    VALUES (v_id_venta, p_id_comprador, p_canal, p_medio_pago);

    -- 4. Un pasaje por cada asiento del VARRAY.
    FOR i IN 1 .. p_asientos.COUNT LOOP
        v_solicitado := p_asientos(i);

        -- El cursor llena el RECORD completo de una vez: la estructura del
        -- SELECT y la del RECORD coinciden campo a campo.
        OPEN  c_asiento(p_id_viaje, v_solicitado);
        FETCH c_asiento INTO r_pasaje;

        IF c_asiento%NOTFOUND THEN
            CLOSE c_asiento;
            RAISE e_asiento_no_vendible;
        END IF;
        CLOSE c_asiento;

        -- RN-06: el asiento debe estar libre. El criterio sale del catalogo
        -- -ESTADO_PASAJE.ocupa_asiento- y no de ids escritos a mano, que es la
        -- misma condicion que aplica el indice unico parcial del DDL.
        -- Tambien detecta un asiento repetido dentro del propio VARRAY, porque
        -- ve los INSERT ya hechos en esta misma transaccion.
        SELECT COUNT(*)
        INTO   v_ocupados
        FROM   pasaje p
        JOIN   estado_pasaje ep ON ep.id_estado = p.id_estado
        WHERE  p.id_viaje       = p_id_viaje
        AND    p.id_bus         = v_id_bus
        AND    p.nro_asiento    = r_pasaje.nro_asiento
        AND    ep.ocupa_asiento = 'S';

        IF v_ocupados > 0 THEN
            RAISE e_asiento_ocupado;
        END IF;

        SELECT NVL(MAX(id_pasaje), 0) + 1 INTO v_id_pasaje FROM pasaje;

        INSERT INTO pasaje (id_pasaje, id_venta, id_viaje, id_bus, nro_asiento,
                            id_pasajero, id_tarifa, precio_aplicado, id_estado)
        VALUES (v_id_pasaje, v_id_venta, p_id_viaje, v_id_bus, r_pasaje.nro_asiento,
                p_id_comprador, r_pasaje.id_tarifa, r_pasaje.precio_aplicado,
                c_estado_vendido);
        -- Este INSERT dispara trg_pasaje_historial, que escribe la transicion.

        v_total := v_total + r_pasaje.precio_aplicado;

        DBMS_OUTPUT.PUT_LINE('    pasaje ' || v_id_pasaje ||
            ' | asiento ' || LPAD(r_pasaje.nro_asiento, 2) ||
            ' | ' || RPAD(r_pasaje.nombre_tipo, 14) ||
            ' | $' || TO_CHAR(r_pasaje.precio_aplicado, 'FM999G999'));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('  Venta ' || v_id_venta || ' | viaje ' || p_id_viaje ||
        ' | ' || p_asientos.COUNT || ' pasaje(s) | total $' ||
        TO_CHAR(v_total, 'FM999G999'));

EXCEPTION
    WHEN e_viaje_no_vendible THEN
        DBMS_OUTPUT.PUT_LINE('  Rechazado: el viaje ' || p_id_viaje ||
            ' no existe o ya no admite venta.');

    WHEN e_asiento_no_vendible THEN
        DBMS_OUTPUT.PUT_LINE('  Rechazado: el asiento ' || v_solicitado ||
            ' no existe en el bus del viaje o su tipo no tiene tarifa vigente.');

    WHEN e_asiento_ocupado THEN
        DBMS_OUTPUT.PUT_LINE('  Rechazado por RN-06: el asiento ' ||
            r_pasaje.nro_asiento || ' ya esta vendido en este viaje.');
END sp_venta_pasajes;
/


--------------------------------------------------------------------------------
-- 4.3  ANULACION DE PASAJE
-- Sirve a : RF-02     Implementa : RN-08, RN-09
--
-- La anulacion NO borra el pasaje: le cambia el estado. Esa decision es la que
-- hace posible auditar despues quien anulo que y cuando, y es tambien la que
-- convierte a RN-09 en una consecuencia y no en una tarea: el indice unico
-- parcial deja de incluir a los pasajes cuyo estado no ocupa asiento, de modo
-- que el asiento se libera solo, sin que este procedimiento lo toque.
--
-- COMO LLEGA EL MOTIVO HASTA EL TRIGGER
--
-- Un trigger no recibe parametros, y el motivo solo lo conoce quien ejecuta la
-- operacion. Se resuelve por el contexto de la sesion: el procedimiento lo
-- declara con DBMS_APPLICATION_INFO.SET_CLIENT_INFO antes del UPDATE y
-- trg_pasaje_historial lo lee con SYS_CONTEXT. No es una variable global del
-- programa sino un dato de sesion, que Oracle mantiene aislado entre sesiones
-- concurrentes.
--
-- El contexto se limpia SIEMPRE, tambien cuando la operacion falla: si quedara
-- cargado con el motivo de una anulacion fallida, el trigger lo adjuntaria a la
-- proxima transicion que ocurriera en esta misma sesion.
--
-- No calcula devolucion de dinero: el pago esta fuera del alcance del proyecto.
--------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_anular_pasaje (
    p_id_pasaje IN pasaje.id_pasaje%TYPE,
    p_motivo    IN VARCHAR2
)
IS
    -- CONSTANTES
    c_ventana  CONSTANT NUMBER := 4;                              -- horas
    c_anulado  CONSTANT estado_pasaje.id_estado%TYPE := 4;        -- ANU

    -- VARIABLES
    v_id_estado  pasaje.id_estado%TYPE;
    v_nro        pasaje.nro_asiento%TYPE;
    v_salida     viaje.salida_prog%TYPE;
    v_horas      NUMBER;

    -- EXCEPCIONES DE USUARIO
    e_pasaje_inexistente EXCEPTION;
    e_ya_anulado         EXCEPTION;   -- RN-08
    e_fuera_de_plazo     EXCEPTION;   -- precondicion de RF-02
BEGIN
    -- 1. El pasaje debe existir. Se trae junto con la salida de su viaje, que es
    --    lo que define el plazo.
    BEGIN
        SELECT p.id_estado, p.nro_asiento, v.salida_prog
        INTO   v_id_estado, v_nro, v_salida
        FROM   pasaje p
        JOIN   viaje  v ON v.id_viaje = p.id_viaje
        WHERE  p.id_pasaje = p_id_pasaje;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RAISE e_pasaje_inexistente;
    END;

    -- 2. RN-08: anular dos veces no es una transicion. Ademas trg_pasaje_no_revive
    --    impide el camino inverso, de modo que la regla se cumple por los dos lados.
    IF v_id_estado = c_anulado THEN
        RAISE e_ya_anulado;
    END IF;

    -- 3. La ventana de 4 horas. El calculo excluye por si solo los viajes que ya
    --    partieron: si la salida quedo atras, las horas restantes son negativas.
    v_horas := (CAST(v_salida AS DATE) - SYSDATE) * 24;
    IF v_horas < c_ventana THEN
        RAISE e_fuera_de_plazo;
    END IF;

    -- 4. El motivo viaja por el contexto de sesion; el UPDATE dispara el trigger.
    DBMS_APPLICATION_INFO.SET_CLIENT_INFO(p_motivo);
    UPDATE pasaje SET id_estado = c_anulado WHERE id_pasaje = p_id_pasaje;
    DBMS_APPLICATION_INFO.SET_CLIENT_INFO(NULL);
    -- Sin COMMIT: confirmar es decision de quien invoca.

    DBMS_OUTPUT.PUT_LINE('  Pasaje ' || p_id_pasaje || ' anulado | el asiento ' ||
        v_nro || ' vuelve a estar disponible (RN-09).');

EXCEPTION
    WHEN e_pasaje_inexistente THEN
        DBMS_OUTPUT.PUT_LINE('  Rechazado: el pasaje ' || p_id_pasaje || ' no existe.');

    WHEN e_ya_anulado THEN
        DBMS_OUTPUT.PUT_LINE('  Rechazado por RN-08: el pasaje ' || p_id_pasaje ||
            ' ya estaba anulado.');

    WHEN e_fuera_de_plazo THEN
        DBMS_OUTPUT.PUT_LINE('  Rechazado: solo se anula hasta ' || c_ventana ||
            ' horas antes de la salida; faltan ' ||
            TO_CHAR(ROUND(v_horas, 1)) || ' h.');

    WHEN OTHERS THEN
        -- La limpieza del contexto no puede quedar solo en el camino de exito.
        DBMS_APPLICATION_INFO.SET_CLIENT_INFO(NULL);
        RAISE;
END sp_anular_pasaje;
/
