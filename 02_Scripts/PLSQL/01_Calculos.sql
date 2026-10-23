--------------------------------------------------------------------------------
-- Modelo_GestionTransporte 

-- POR QUE ESTE ARCHIVO VA PRIMERO
--
-- Los bloques de este archivo resuelven UN VALOR a partir de sus entradas y no
-- modifican nada. Son los unicos que no dependen de ningun otro, y en cambio
-- todos los demas dependeran de ellos: la venta necesita el precio vigente, la
-- programacion necesita saber cuantos conductores exige el viaje, y la consulta
-- de disponibilidad necesita contar asientos libres.

-- FRONTERA DE FUNCION Convertir los calculos en funciones almacenadas
--
-- SOBRE LAS EXCEPCIONES DE ESTE NIVEL
--
-- Aqui aparecen unicamente excepciones PREDEFINIDAS de Oracle
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 140
SET PAGESIZE 60 

--------------------------------------------------------------------------------
-- 1.1  Tarifa vigente ->  futura FUNCTION fn_tarifa_vigente
--
-- Entradas : p_id_ruta, p_id_tipo_asiento, p_fecha
-- Devuelve : precio que rige para esa combinacion en esa fecha
-- Sirve a  : RF-01 (venta)      Implementa : RN-07
--
-- Problema que resuelve: TARIFA conserva el historico completo de precios,
-- porque RN-07 exige que el precio varie segun la condicion comercial. 
--
-- Por que funcion devuelve un unico valor a partir de sus
-- parametros y no modifica estado. Esa condicion es la que permite ademas
-- invocarla desde una sentencia SQL, cosa que un procedimiento no admite.


--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION obtener_precio_tarifa (
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

    -- Inconsistencia en el catálogo: más de una tarifa vigente solapada
    WHEN TOO_MANY_ROWS THEN
        DBMS_OUTPUT.PUT_LINE('1.1 Catalogo inconsistente: mas de una tarifa vigente para ruta ' || p_id_ruta );
END obtener_precio_tarifa;
/




--------------------------------------------------------------------------------
-- 1.2  Conductores requeridos  
--
-- Entradas : p_id_viaje
-- Devuelve : cantidad minima de conductores que exige la duracion del viaje
-- Sirve a  : RF-03 (programacion)      Implementa : RN-10
--
-- Problema que resuelve: la ley impide que un conductor supere las 5 horas de
-- conduccion, de modo que un viaje largo debe repartirse entre varios. El
-- calculo traduce esa regla a un numero verificable.
--
-- CEIL redondea hacia arriba porque la fraccion sobrante tambien necesita quien
-- la conduzca: 6,5 h dividido en 5 da 1,3, y eso significa 2 conductores. Una
-- ruta de 5,00 h exactas queda en el limite y se cubre con uno solo.
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_conductores_requeridos (
    p_id_ruta IN ruta.id_ruta%TYPE          -- antes recibia p_id_viaje
) RETURN PLS_INTEGER
IS
    c_max_horas    CONSTANT NUMBER := 5;    -- RN-10
    v_duracion_min ruta.duracion_estimada_min%TYPE;
BEGIN
    SELECT r.duracion_estimada_min INTO v_duracion_min
    FROM   ruta r WHERE r.id_ruta = p_id_ruta;

    RETURN CEIL(v_duracion_min / 60 / c_max_horas);
END fn_conductores_requeridos;
/

--------------------------------------------------------------------------------
-- 1.3  Asientos disponibles    ->  futura FUNCTION fn_asientos_disponibles
--
-- Entradas : p_id_viaje
-- Devuelve : cantidad de asientos libres del viaje
-- Sirve a  : RF-01 (venta), RF-04 (disponibilidad)   Implementa : RN-01, RN-06
--
-- Problema que resuelve: la disponibilidad no esta almacenada en ninguna parte
-- y no debe estarlo. Guardarla como columna obligaria a mantenerla sincronizada
-- con cada venta y cada anulacion, y bastaria un fallo para que el dato mintiera.
-- Se calcula: asientos del bus asignado menos los que tienen pasaje vigente.
--
-- El criterio de "ocupado" no se escribe a mano. Se toma de ESTADO_PASAJE, en su
-- columna ocupa_asiento, que es la misma condicion que aplica el indice unico
-- parcial del DDL. Asi la regla vive en un solo lugar: si manana se agrega un
-- estado nuevo, este calculo lo respeta sin tocarlo.
--------------------------------------------------------------------------------
DECLARE
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


--------------------------------------------------------------------------------
-- 1.4  Porcentaje de ocupacion ->  futura FUNCTION fn_porcentaje_ocupacion
--
-- Entradas : p_id_viaje
-- Devuelve : porcentaje de asientos ocupados del viaje
-- Sirve a  : RF-04 (disponibilidad)
--
-- Problema que resuelve: la cantidad de asientos libres no permite comparar
-- viajes entre si, porque los buses tienen capacidades distintas. Cinco asientos
-- libres en un bus de 10 y en uno de 40 describen situaciones opuestas. El
-- porcentaje normaliza esa medida.
--

--------------------------------------------------------------------------------
DECLARE
    -- PARAMETRO de la futura funcion
    p_id_viaje  CONSTANT viaje.id_viaje%TYPE := 4;   -- Bulnes del 02-09

    -- RETORNO
    v_porcentaje  NUMBER; --Porcentaje de ocupacion

    -- Auxiliares
    v_capacidad  PLS_INTEGER;
    v_ocupados   PLS_INTEGER;

BEGIN
    -- Consulta la capacidad del bus y la cantidad de asientos registrados para el.
    SELECT COUNT(a.nro_asiento)
    INTO   v_capacidad
    FROM   viaje v
    JOIN   asiento a ON a.id_bus = v.id_bus
    WHERE  v.id_viaje = p_id_viaje;

    -- Consulta los asientos ocupados: los pasajes de ese viaje cuyo estado mantiene el asiento tomado.
    SELECT COUNT(*)
    INTO   v_ocupados
    FROM   pasaje p
    JOIN   estado_pasaje ep ON ep.id_estado = p.id_estado
    WHERE  p.id_viaje       = p_id_viaje
    AND    ep.ocupa_asiento = 'S';

    v_porcentaje := ROUND(v_ocupados * 100 / v_capacidad, 1);

    DBMS_OUTPUT.PUT_LINE('1.4 Porcentaje de ocupacion' || '    viaje ' || p_id_viaje ||
                         '  ' || v_ocupados || ' de ' || v_capacidad ||
                         '  ->  ' || v_porcentaje || '%');
EXCEPTION
    -- Excepción a bus sin asientos disponibles o que no exista  el viaje.
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('1.4 El viaje ' || p_id_viaje || ' no existe.');
END;
/

---------------------------------------------------------------------------------
-- 1.5 Evaluar si un recurso esta ocupado fn_recurso_ocupado
-- Evaluar si un recurso esta ocupado en un intervalo de tiempo


CREATE OR REPLACE FUNCTION fn_recurso_ocupado (
      p_salida       IN viaje.salida_prog%TYPE, --inicio del intervalo de tiempo a evaluar
      p_llegada      IN viaje.llegada_prog%TYPE, --fin del intervalo de tiempo a evaluar
      p_id_bus       IN viaje.id_bus%TYPE            DEFAULT NULL,
      p_id_conductor IN conductor.id_conductor%TYPE  DEFAULT NULL,
      p_excluir      IN viaje.id_viaje%TYPE          DEFAULT NULL
  ) RETURN viaje.id_viaje%TYPE -- devuelve el id del viaje que ocupa el recurso, o NULL si esta libre
  IS
      v_conflicto viaje.id_viaje%TYPE; -- id del viaje que ocupa el recurso en ese intervalo, o NULL si esta libre
  BEGIN
        -- Esta funcion evalua un recurso (bus o conductor) en un intervalo de tiempo. Devuelve el id del viaje que lo ocupa, o NULL si esta libre.

      IF (p_id_bus IS NULL     AND p_id_conductor IS NULL) -- Si no se indica recurso, no se puede evaluar ocupacion
      OR (p_id_bus IS NOT NULL AND p_id_conductor IS NOT NULL)  -- O si se indican ambos, tampoco se puede evaluar ocupacion
      THEN
          RAISE_APPLICATION_ERROR(-20020,'Indique exactamente un recurso.');
      END IF;

      SELECT MIN(v.id_viaje) -- MIN para devolver un solo valor, aunque haya varios viajes que ocupen el recurso en ese intervalo
      INTO v_conflicto
      FROM   viaje v
      WHERE  v.estado_viaje IN ('PRO','ENC') -- Solo se consideran viajes programados o en curso, no los finalizados ni cancelados
      AND    (p_excluir IS NULL OR v.id_viaje <> p_excluir) -- Excluye el viaje que se esta programando, si se indica
      AND    p_salida      < v.llegada_prog -- El viaje que ocupa el recurso debe solaparse con el intervalo indicado
      AND    v.salida_prog < p_llegada      --
      AND    (  (p_id_bus IS NOT NULL AND v.id_bus = p_id_bus)
             OR (p_id_conductor IS NOT NULL AND EXISTS (
                    SELECT 1 FROM viaje_conductor vc
                    WHERE vc.id_viaje=v.id_viaje AND vc.id_conductor=p_id_conductor)) );
      RETURN v_conflicto;
END;
/


-- fn_llegada_estimada
-- Sirve a: RF-03   |   Informe: seccion 9.2
--
-- El operador indica ruta y salida; la llegada NO se le pide, se deriva. Pedirla
-- como parametro abriria la puerta a que contradiga la duracion de la ruta, y
-- entonces habria dos versiones del mismo hecho.
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_llegada_estimada (
    p_id_ruta IN ruta.id_ruta%TYPE,
    p_salida  IN viaje.salida_prog%TYPE
) RETURN viaje.llegada_prog%TYPE
IS
    v_duracion_min ruta.duracion_estimada_min%TYPE;
BEGIN
    SELECT r.duracion_estimada_min
    INTO   v_duracion_min
    FROM   ruta r
    WHERE  r.id_ruta = p_id_ruta;

    -- NUMTODSINTERVAL y no p_salida + v_duracion_min/1440: sumar un NUMBER a un
    -- TIMESTAMP lo degrada a DATE y pierde la fraccion de segundo. Comprobado:
    --   NUMTODSINTERVAL  -> 03-09-2026 14:30:00.123456
    --   dividir por 1440 -> 03-09-2026 14:30:00.000000
    RETURN p_salida + NUMTODSINTERVAL(v_duracion_min, 'MINUTE');
END fn_llegada_estimada;
/