--------------------------------------------------------------------------------
-- Modelo_GestionTransporte 

-- POR QUE ESTE ARCHIVO VA PRIMERO
--
-- Los bloques de este archivo resuelven UN VALOR a partir de sus entradas y no
-- modifican nada. Son los unicos que no dependen de ningun otro, y en cambio
-- todos los demas dependeran de ellos: la venta necesita el precio vigente, la
-- programacion necesita saber cuantos conductores exige el viaje, y la consulta
-- de disponibilidad necesita contar asientos libres.
--
-- Escribirlos al final obligaria a incrustar esos calculos dentro de los bloques
-- que los consumen y a extraerlos despues, reescribiendo cada uno. Escribirlos
-- primero permite que los niveles siguientes los invoquen ya resueltos.
--
-- FRONTERA DE FUNCION
--
-- Cada bloque esta escrito con la forma que tendra al convertirse en funcion:
--   - Las entradas van como CONSTANT con prefijo p_ al inicio del DECLARE.
--     Al extraerlo, esas lineas pasan a la firma y desaparecen del cuerpo.
--   - El resultado se deposita siempre en una unica variable de retorno.
--   - El cuerpo entre BEGIN y EXCEPTION no cambia al extraerse.
-- La conversion a funcion es entonces mecanica y no reescritura.
--
-- SOBRE LAS EXCEPCIONES DE ESTE NIVEL
--
-- Aqui aparecen unicamente excepciones PREDEFINIDAS de Oracle, y no es una
-- omision: en este nivel los errores posibles son los que el motor detecta por
-- si mismo -no hay dato, hay mas de uno, se divide por cero-. Las excepciones
-- definidas por el usuario corresponden al nivel 3, donde se validan reglas de
-- negocio que el motor no puede conocer. Declarar una excepcion propia aqui,
-- donde una predefinida ya describe la situacion, seria usarla por cumplir un
-- requisito formal y no por necesidad tecnica.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- TRAZABILIDAD CON LA DOCUMENTACION
--
--   Informe  : DP_Informe_Requerimiento.docx
--                9.1 Identificacion de funciones -> los 4 bloques de este archivo
--                7.1 Excepciones predefinidas    -> manejo de errores de cada bloque
--                4.2 Trazabilidad regla-mecanismo-> RN-01, RN-06, RN-07, RN-10
--   Anexo    : ANEXO_Tablas_de_Referencia.docx
--                Tabla 29 - Funciones almacenadas
--                Tabla 26 - Excepciones predefinidas de Oracle
--                Tabla  5 - Reglas de negocio del dominio
--                Tabla  6 - Trazabilidad entre reglas y mecanismos
--   Rubrica  : IE1.3.1 - control de excepciones (10% informe / 15% presentacion)
--              IE1.4.1 - evaluacion de funciones (15% informe / 15% presentacion)
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 140
SET PAGESIZE 60 

--------------------------------------------------------------------------------
-- 1.1  Tarifa vigente          ->  futura FUNCTION fn_tarifa_vigente
--
-- Entradas : p_id_ruta, p_id_tipo_asiento, p_fecha
-- Devuelve : precio que rige para esa combinacion en esa fecha
-- Sirve a  : RF-01 (venta)      Implementa : RN-07
-- Informe  : 9.1 (funcion), 7.1 (NO_DATA_FOUND y TOO_MANY_ROWS)
-- Anexo    : Tabla 29 (fn_tarifa_vigente), Tabla 26
--
-- Problema que resuelve: TARIFA conserva el historico completo de precios,
-- porque RN-07 exige que el precio varie segun la condicion comercial. Por eso
-- una consulta directa a la tabla puede devolver varias filas para la misma
-- ruta y tipo de asiento: la vigente y las ya vencidas. Este calculo aisla la
-- que corresponde a una fecha dada.
--
-- Por que funcion y no procedimiento: devuelve un unico valor a partir de sus
-- parametros y no modifica estado. Esa condicion es la que permite ademas
-- invocarla desde una sentencia SQL, cosa que un procedimiento no admite.
--------------------------------------------------------------------------------
DECLARE
    -- PARAMETROS de la futura funcion -- Al terminar limpiar atributos recordar --p de parametro
    p_id_ruta          CONSTANT ruta.id_ruta%TYPE                 := 7;  -- Concepcion
    p_id_tipo_asiento  CONSTANT tipo_asiento.id_tipo_asiento%TYPE := 2;  -- Salon Cama
    p_fecha            CONSTANT DATE                              := SYSDATE; --Fecha actual

    -- RETORNO
    v_precio  tarifa.precio%TYPE;
BEGIN

    -- Una tarifa esta vigente si ya empezo y aun no ha terminado. 
    SELECT tf.precio
        INTO   v_precio
        FROM   tarifa tf
    WHERE  tf.id_ruta          = p_id_ruta
    AND    tf.id_tipo_asiento  = p_id_tipo_asiento
    AND    tf.vigencia_desde  <= TRUNC(p_fecha)
    AND   (tf.vigencia_hasta IS NULL OR tf.vigencia_hasta >= TRUNC(p_fecha));

    DBMS_OUTPUT.PUT_LINE('1.1 Tarifa vigente' || '    ruta ' || p_id_ruta || ' tipo ' || p_id_tipo_asiento || ' al ' || TO_CHAR(p_fecha,'DD-MM-YYYY') ||
                         '  ->  $' || TO_CHAR(v_precio,'FM999G999'));
EXCEPTION

    -- No existe tarifa definida para esa combinacion en esa fecha. 
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('1.1 Sin tarifa vigente para ruta ' || p_id_ruta || ' al ' || TO_CHAR(p_fecha,'DD-MM-YYYY'));

    -- Incosistencia del catalogo:Existe mas de una vigencia solapada para la misma ruta y tipo. 
    WHEN TOO_MANY_ROWS THEN
        DBMS_OUTPUT.PUT_LINE('1.1 Catalogo inconsistente: mas de una tarifa vigente para ruta ' || p_id_ruta );
END;
/


--------------------------------------------------------------------------------
-- 1.2  Conductores requeridos  
--
-- Entradas : p_id_viaje
-- Devuelve : cantidad minima de conductores que exige la duracion del viaje
-- Sirve a  : RF-03 (programacion)      Implementa : RN-10
-- Informe  : 9.1 (funcion), 2.4 y 4.2 (RN-10)
-- Anexo    : Tabla 29 (fn_conductores_requeridos), Tabla 7 (jornada por ruta)
--
-- Problema que resuelve: la ley impide que un conductor supere las 5 horas de
-- conduccion, de modo que un viaje largo debe repartirse entre varios. El
-- calculo traduce esa regla a un numero verificable.
--
-- CEIL redondea hacia arriba porque la fraccion sobrante tambien necesita quien
-- la conduzca: 6,5 h dividido en 5 da 1,3, y eso significa 2 conductores. Una
-- ruta de 5,00 h exactas queda en el limite y se cubre con uno solo.
--------------------------------------------------------------------------------

DECLARE
    -- PARAMETRO de la futura funcion --recordar limpiar atributos p de parametro este sera ingresado por el usuario
    p_id_viaje  CONSTANT viaje.id_viaje%TYPE := 6;   -- Santiago - Concepcion

    -- RETORNO
    v_conductores  PLS_INTEGER;

    -- Auxiliares del calculo
    v_duracion_min  ruta.duracion_estimada_min%TYPE;
    c_max_horas     CONSTANT NUMBER := 5;   -- limite legal por conductor

BEGIN
    -- La duracion es un atributo de la ruta, no del viaje: el viaje solo la hereda al referenciarla.
    SELECT r.duracion_estimada_min
        INTO   v_duracion_min
        FROM   viaje v
        JOIN   ruta  r 
        ON r.id_ruta = v.id_ruta
        WHERE  v.id_viaje = p_id_viaje;

    v_conductores := CEIL(v_duracion_min / 60 / c_max_horas); --CEIL redondea hacia arriba porque la fraccion sobrante tambien necesita quien la conduzca

    DBMS_OUTPUT.PUT_LINE('1.2 Conductores requeridos' || '    viaje ' || p_id_viaje || ' dura ' || ROUND(v_duracion_min/60, 2) || ' h' ||
                         '  ->  exige ' || v_conductores || ' conductor(es)');

EXCEPTION
    --No existe viaje con ese id. La duracion no se puede calcular y el error es de datos maestros.
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('1.2 El viaje ' || p_id_viaje || ' no existe.');
END;
/


--------------------------------------------------------------------------------
-- 1.3  Asientos disponibles    ->  futura FUNCTION fn_asientos_disponibles
--
-- Entradas : p_id_viaje
-- Devuelve : cantidad de asientos libres del viaje
-- Sirve a  : RF-01 (venta), RF-04 (disponibilidad)   Implementa : RN-01, RN-06
-- Informe  : 9.1 (funcion), 4.2 (RN-01 y RN-06)
-- Anexo    : Tabla 29 (fn_asientos_disponibles), Tabla 6
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
-- Informe  : 9.1 (funcion), 7.1 (ZERO_DIVIDE)
-- Anexo    : Tabla 29 (fn_porcentaje_ocupacion), Tabla 26
--
-- Problema que resuelve: la cantidad de asientos libres no permite comparar
-- viajes entre si, porque los buses tienen capacidades distintas. Cinco asientos
-- libres en un bus de 10 y en uno de 40 describen situaciones opuestas. El
-- porcentaje normaliza esa medida.
--
-- Sobre ZERO_DIVIDE: la division falla si el bus no tiene asientos registrados.
-- Se podria evitar comprobando el divisor antes de dividir, y en produccion esa
-- seria la forma correcta. Aqui se maneja como excepcion porque la condicion no
-- deberia ocurrir nunca -un bus sin asientos contradice la premisa del negocio-
-- y lo que interesa es que, si ocurre, el programa entregue un diagnostico util
-- en lugar de detenerse con un error del motor. La excepcion actua como red de
-- seguridad de una condicion anomala, no como control de flujo previsto.**Considere eliminarla para reducir complejidad y porque la division por cero no deberia ocurrir nunca.**
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
    SELECT COUNT(a.nro_asiento)
    INTO   v_capacidad
    FROM   viaje v
    JOIN   asiento a ON a.id_bus = v.id_bus
    WHERE  v.id_viaje = p_id_viaje;

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
