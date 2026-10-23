--------------------------------------------------------------------------------
-- Modelo_GestionTransporte  |  Script PL/SQL - Parte 1
-- PKG_CALCULOS: las funciones que el resto del proyecto reutiliza
--
-- Requisito : DDL cargado
-- Motor     : Oracle Database
--------------------------------------------------------------------------------
-- TRAZABILIDAD CON LA DOCUMENTACION
--
--   Informe  : 9.1 y 9.2 (funciones almacenadas), 10 (packages),
--              7.1 (excepciones predefinidas), 4.2 (regla -> mecanismo)
--   Anexo    : Tabla 29 (funciones), Tabla 26 (excepciones predefinidas),
--              Tabla 5 y 6 (reglas y mecanismos)
--   Reglas   : RN-01, RN-06, RN-07, RN-09, RN-10
--   Rubrica  : IE1.4.1 - funciones y packages (15% informe / 15% presentacion)
--              IE1.3.1 - excepciones predefinidas (10% / 15%)
--
--------------------------------------------------------------------------------
-- POR QUE UN PACKAGE Y NO CINCO FUNCIONES SUELTAS
--
-- Las cinco resuelven la misma clase de problema: obtener UN valor derivado del
-- estado de la base, sin modificar nada. Agruparlas tiene tres efectos que las
-- funciones sueltas no dan:
--
--   1. Dependencias. Quien necesita cualquiera de estos calculos depende de UN
--      objeto, no de cinco. Si manana se agrega un calculo nuevo, los programas
--      que ya usaban el package no cambian.
--   2. Encapsulamiento. El package puede tener miembros PRIVADOS, visibles solo
--      dentro de su propio body. Aqui eso permite que dos funciones publicas
--      compartan una consulta interna sin exponerla como parte de la interfaz.
--   3. Interfaz explicita. La especificacion es un contrato legible: dice que
--      ofrece el package sin obligar a leer como lo hace.
--
-- POR QUE NINGUNA FUNCION ATRAPA SUS PROPIAS EXCEPCIONES
--
-- NO_DATA_FOUND, TOO_MANY_ROWS y ZERO_DIVIDE se dejan propagar tal como las
-- produce el motor. Una funcion de calculo no sabe que quiere hacer su invocador
-- ante la ausencia de un dato: la venta necesita rechazar la operacion completa,
-- una consulta quiza solo quiera mostrar un guion. Decidir por el invocador
-- seria quitarle informacion.
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 140
SET PAGESIZE 60


--------------------------------------------------------------------------------
-- ESPECIFICACION
--
-- Solo declara QUE ofrece el package. Es lo unico que ven los demas programas, y
-- lo unico que deben leer para usarlo.
--------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_calculos AS

    -- Constante publica: el limite legal de conduccion por conductor (RN-10).
    -- Se expone porque los procedimientos de operacion la citan al explicar por
    -- que rechazan una programacion.
    c_max_horas_conduccion  CONSTANT NUMBER := 5;

    -- 1.1  Tarifa vigente para una ruta y tipo de asiento en una fecha (RN-07).
    --      Devuelve el id_tarifa, no el precio: PASAJE guarda la clave foranea,
    --      y obtener el precio desde el id es despues una lectura trivial.
    --      Propaga NO_DATA_FOUND si no hay tarifa y TOO_MANY_ROWS si el catalogo
    --      tiene vigencias solapadas.
    FUNCTION fn_tarifa_vigente (
        p_id_ruta         IN ruta.id_ruta%TYPE,
        p_id_tipo_asiento IN tipo_asiento.id_tipo_asiento%TYPE,
        p_fecha           IN DATE DEFAULT SYSDATE
    ) RETURN tarifa.id_tarifa%TYPE;

    -- 1.2  Conductores minimos que exige la duracion de un viaje (RN-10).
    --      Requiere un viaje ya creado, porque consulta su ruta.
    FUNCTION fn_conductores_requeridos (
        p_id_viaje IN viaje.id_viaje%TYPE
    ) RETURN PLS_INTEGER;

    -- 1.3  Asientos libres de un viaje (RN-01, RN-06).
    FUNCTION fn_asientos_disponibles (
        p_id_viaje IN viaje.id_viaje%TYPE
    ) RETURN PLS_INTEGER;

    -- 1.4  Porcentaje de ocupacion de un viaje. Propaga ZERO_DIVIDE si el bus
    --      no tiene asientos registrados, condicion que contradice RN-01.
    FUNCTION fn_porcentaje_ocupacion (
        p_id_viaje IN viaje.id_viaje%TYPE
    ) RETURN NUMBER;

    -- 1.5  Si UN asiento concreto esta tomado en un viaje (RN-06, RN-09).
    --      Devuelve 'S' u 'N', misma convencion que ESTADO_PASAJE.ocupa_asiento.
    FUNCTION fn_asiento_ocupado (
        p_id_viaje    IN pasaje.id_viaje%TYPE,
        p_id_bus      IN pasaje.id_bus%TYPE,
        p_nro_asiento IN pasaje.nro_asiento%TYPE
    ) RETURN VARCHAR2;

END pkg_calculos;
/
SHOW ERRORS


--------------------------------------------------------------------------------
-- BODY
--
-- Implementa lo declarado arriba y ademas contiene un miembro PRIVADO que la
-- especificacion no menciona: fn_ocupados_viaje. Es privado a proposito -no es
-- una omision-: cuenta los asientos tomados de un viaje, dato intermedio que
-- solo tiene sentido dentro de este package. Antes de existir, esa misma
-- consulta estaba escrita dos veces, una en cada funcion publica que la
-- necesitaba.
--------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE BODY pkg_calculos AS

    ----------------------------------------------------------------------------
    -- PRIVADA: no aparece en la especificacion, de modo que ningun programa
    -- externo puede invocarla ni depender de ella. Eso deja libertad para
    -- cambiarla sin afectar a nadie fuera del package.
    --
    -- El criterio de "ocupado" no se escribe a mano: se toma de
    -- ESTADO_PASAJE.ocupa_asiento, que es la misma condicion que aplica el
    -- indice unico parcial del DDL. Si manana se agrega un estado, el package
    -- lo respeta sin tocarlo.
    ----------------------------------------------------------------------------
    FUNCTION fn_ocupados_viaje (
        p_id_viaje IN viaje.id_viaje%TYPE
    ) RETURN PLS_INTEGER
    IS
        v_ocupados  PLS_INTEGER;
    BEGIN
        SELECT COUNT(*)
        INTO   v_ocupados
        FROM   pasaje p
        JOIN   estado_pasaje ep ON ep.id_estado = p.id_estado
        WHERE  p.id_viaje       = p_id_viaje
        AND    ep.ocupa_asiento = 'S';

        RETURN v_ocupados;
    END fn_ocupados_viaje;


    ----------------------------------------------------------------------------
    -- 1.1  Tarifa vigente
    --
    -- TARIFA conserva el historico completo de precios porque RN-07 exige que el
    -- precio varie segun la condicion comercial. Por eso una consulta directa
    -- puede devolver varias filas para la misma ruta y tipo: la vigente y las ya
    -- vencidas. Esta funcion aisla la que corresponde a una fecha.
    ----------------------------------------------------------------------------
    FUNCTION fn_tarifa_vigente (
        p_id_ruta         IN ruta.id_ruta%TYPE,
        p_id_tipo_asiento IN tipo_asiento.id_tipo_asiento%TYPE,
        p_fecha           IN DATE DEFAULT SYSDATE
    ) RETURN tarifa.id_tarifa%TYPE
    IS
        v_id_tarifa  tarifa.id_tarifa%TYPE;
    BEGIN
        -- Vigente si ya empezo y no ha vencido, o si no tiene fecha de termino.
        -- TRUNC elimina la hora para comparar solo por fecha.
        SELECT tf.id_tarifa
        INTO   v_id_tarifa
        FROM   tarifa tf
        WHERE  tf.id_ruta         = p_id_ruta
        AND    tf.id_tipo_asiento = p_id_tipo_asiento
        AND    tf.vigencia_desde <= TRUNC(p_fecha)
        AND   (tf.vigencia_hasta IS NULL OR tf.vigencia_hasta >= TRUNC(p_fecha));

        RETURN v_id_tarifa;
    END fn_tarifa_vigente;


    ----------------------------------------------------------------------------
    -- 1.2  Conductores requeridos
    --
    -- CEIL redondea hacia arriba porque la fraccion sobrante tambien necesita
    -- quien la conduzca: 6,5 h dividido en 5 da 1,3, y eso significa 2
    -- conductores. Una ruta de 5,00 h exactas queda en el limite y se cubre con
    -- uno solo.
    ----------------------------------------------------------------------------
    FUNCTION fn_conductores_requeridos (
        p_id_viaje IN viaje.id_viaje%TYPE
    ) RETURN PLS_INTEGER
    IS
        v_duracion_min  ruta.duracion_estimada_min%TYPE;
    BEGIN
        -- La duracion es atributo de la ruta; el viaje solo la hereda.
        SELECT r.duracion_estimada_min
        INTO   v_duracion_min
        FROM   viaje v
        JOIN   ruta  r ON r.id_ruta = v.id_ruta
        WHERE  v.id_viaje = p_id_viaje;

        RETURN CEIL(v_duracion_min / 60 / c_max_horas_conduccion);
    END fn_conductores_requeridos;


    ----------------------------------------------------------------------------
    -- 1.3  Asientos disponibles
    --
    -- La disponibilidad no esta almacenada y no debe estarlo: guardarla como
    -- columna obligaria a sincronizarla con cada venta y cada anulacion, y
    -- bastaria un fallo para que el dato mintiera.
    --
    -- El GROUP BY no es decorativo: si el viaje no existe, o su bus no tiene
    -- asientos, la consulta no devuelve filas y se propaga NO_DATA_FOUND. Es la
    -- forma de distinguir "cero disponibles" de "no hay nada que contar".
    ----------------------------------------------------------------------------
    FUNCTION fn_asientos_disponibles (
        p_id_viaje IN viaje.id_viaje%TYPE
    ) RETURN PLS_INTEGER
    IS
        v_capacidad  PLS_INTEGER;
    BEGIN
        SELECT COUNT(a.nro_asiento)
        INTO   v_capacidad
        FROM   viaje v
        JOIN   asiento a ON a.id_bus = v.id_bus
        WHERE  v.id_viaje = p_id_viaje
        GROUP  BY v.id_bus;

        RETURN v_capacidad - fn_ocupados_viaje(p_id_viaje);
    END fn_asientos_disponibles;


    ----------------------------------------------------------------------------
    -- 1.4  Porcentaje de ocupacion
    --
    -- La cantidad de asientos libres no permite comparar viajes entre si, porque
    -- los buses tienen capacidades distintas. Cinco libres en un bus de 10 y en
    -- uno de 40 describen situaciones opuestas; el porcentaje normaliza eso.
    --
    -- Aqui la capacidad se cuenta SIN GROUP BY, a diferencia de 1.3: asi un bus
    -- sin asientos devuelve 0 y la division levanta ZERO_DIVIDE, que es el
    -- diagnostico correcto para esa anomalia. Las dos funciones cuentan lo mismo
    -- pero con distinta forma porque cada una necesita una senal de error
    -- distinta.
    ----------------------------------------------------------------------------
    FUNCTION fn_porcentaje_ocupacion (
        p_id_viaje IN viaje.id_viaje%TYPE
    ) RETURN NUMBER
    IS
        v_capacidad  PLS_INTEGER;
    BEGIN
        SELECT COUNT(a.nro_asiento)
        INTO   v_capacidad
        FROM   viaje v
        JOIN   asiento a ON a.id_bus = v.id_bus
        WHERE  v.id_viaje = p_id_viaje;

        RETURN ROUND(fn_ocupados_viaje(p_id_viaje) * 100 / v_capacidad, 1);
    END fn_porcentaje_ocupacion;


    ----------------------------------------------------------------------------
    -- 1.5  Asiento ocupado
    --
    -- Contraparte de 1.3 a nivel de UN asiento. Existe porque el VARRAY de una
    -- venta no pregunta "cuantos quedan" sino, para cada asiento pedido, si ESE
    -- esta libre.
    --
    -- Con COUNT(*) siempre vuelve exactamente una fila, asi que esta funcion
    -- nunca lanza NO_DATA_FOUND. Asume que el asiento existe en el bus: esa es
    -- otra regla (RN-01) y la valida quien invoca.
    ----------------------------------------------------------------------------
    FUNCTION fn_asiento_ocupado (
        p_id_viaje    IN pasaje.id_viaje%TYPE,
        p_id_bus      IN pasaje.id_bus%TYPE,
        p_nro_asiento IN pasaje.nro_asiento%TYPE
    ) RETURN VARCHAR2
    IS
        v_ocupado  PLS_INTEGER;
    BEGIN
        SELECT COUNT(*)
        INTO   v_ocupado
        FROM   pasaje p
        JOIN   estado_pasaje ep ON ep.id_estado = p.id_estado
        WHERE  p.id_viaje       = p_id_viaje
        AND    p.id_bus         = p_id_bus
        AND    p.nro_asiento    = p_nro_asiento
        AND    ep.ocupa_asiento = 'S';

        RETURN CASE WHEN v_ocupado > 0 THEN 'S' ELSE 'N' END;
    END fn_asiento_ocupado;

END pkg_calculos;
/
SHOW ERRORS
