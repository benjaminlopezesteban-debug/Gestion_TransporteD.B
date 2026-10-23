-- Script de presentación de la base de datos

-- 1.- Funciones de calculos 

-- 1.1 Tarifa vigente: RF-01 (venta); RN-07 Precio varia según condición comercial
-- Recibe como parámetros la ruta, el tipo de asiento y la fecha.
-- Devuelve el precio vigente para esa combinación en esa fecha. 

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


-- 1.2 Conductores requeridos: RF-03 (programacion); RN-10 Cantidad mínima de conductores según duración del viaje
-- Recibe como parámetro la ruta y devuelve la cantidad mínima de conductores requeridos para esa ruta según la duración del viaje.
-- Devuelve un nro entero que representa la cantidad mínima de conductores requeridos.

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


-- 1.3 Asientos disponibles: RF-01(venta), RF-04(disponibilidad); RN-01 Bus con capacidad
-- determinada de asientos , RN-06 un asiento no puede ser vendido en 2 oportunidades para el mismo viaje
-- Recibe como parámetro el id del viaje y devuelve la cantidad de asientos disponibles para ese viaje.

CREATE OR REPLACE FUNCTION fn_asientos_disponibles (
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

-- 1.4 Evaluar recurso ocupado: RF-03 (programacion); RN-03 y RN-04 Un recurso no puede estar ocupado en 2 viajes al mismo tiempo
-- Recibe como parámetros el id de la ruta, la fecha de salida y la de llegada.
-- devuelve el id del viaje que tiene programado a esa hora y fecha, si no retorna es recurso esta libre

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

-- 1.5 Calcular fecha y hora de llegada: RF-04(programación).
-- Recibe como parámetros la id de la ruta y la hora de salida
-- retorna el horario de llegada estimado 

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

-- 2.- Records y Varray

-- 2.1 Record agrupación: RF-01 (venta)
-- Agrupa los cinco datos que describen un pasaje en formacion; sin el habria que arrastrar cuatro
-- variables sueltas por todo el bucle.
-- Se utiliza en el procedimeinto sp_venta_pasajes

TYPE tr_pasaje IS RECORD (
        nro_asiento      asiento.nro_asiento%TYPE,
        -- El campo NO puede llamarse tipo_asiento: colisionaria con la tabla
        -- homonima y PL/SQL lo resolveria contra el campo (PLS-00320).
        nombre_tipo      tipo_asiento.nombre%TYPE,
        id_tarifa        tarifa.id_tarifa%TYPE,
        precio_aplicado  pasaje.precio_aplicado%TYPE
    );

r_pasaje     tr_pasaje;


-- 2.2 Record anclado con %rowtype
-- Toma las misma dimensione y tipo de datos de la tabla 
-- En esta bloque el Record toma las mismas dimensiones de la tabla ruta
-- Procesa la duración estimada en minutos retornando la duración en horas.

DECLARE
    r_ruta   ruta%ROWTYPE;    -- toma la fila completa tal como esta en la tabla
    v_horas  NUMBER;
    v_conductores  PLS_INTEGER;
BEGIN

    --Uso de función de calculo de la duracion estimada de la ruta, dado el id de la ruta.
    SELECT * INTO r_ruta FROM ruta WHERE id_ruta = 7;
    v_horas := ROUND(r_ruta.duracion_estimada_min / 60, 2);

    -- Uso de función de calculo de la cantidad de conductores requeridos para la ruta, dado la duracion estimada en horas.
    v_conductores := fn_conductores_requeridos(v_horas);

    DBMS_OUTPUT.PUT_LINE('--- 2.2 RECORD anclado con %ROWTYPE ---');
    DBMS_OUTPUT.PUT_LINE('  Ruta ' || r_ruta.id_ruta ||
                         ' | ' || r_ruta.distancia_km || ' km' ||
                         ' | ' || v_horas || ' h' ||
                         ' | exige ' || v_conductores || ' conductor(es)');
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('  La ruta consultada no existe en el catalogo.');
END;
/

-- 2.3 Varray 
-- Se crea un array de elemntos iguales que limitan la capacidad de elementos que puede contener una variables, la restricción del
-- negocio se cumple de forma estructural en los datos, no de logica. 
-- Aqui valida que cada pasajero no pueda acceder a más de 6 asientos por compra, posteriomente los valida recorriendo 
-- la colección de elementos que contiene .


DECLARE
    -- Son 6 el numero de asientos maximo que un cliente puede comprar en una sola transaccion.
    TYPE tv_asientos IS VARRAY(6) OF asiento.nro_asiento%TYPE;

    v_solicitados  tv_asientos%TYPE;  -- constructor
    v_libre        NUMBER;
    v_ocupados     PLS_INTEGER := 0;

    v_viaje        viaje.id_viaje%TYPE;
    v_bus          bus.id_bus%TYPE;

BEGIN
    DBMS_OUTPUT.PUT_LINE('--- 2.3 VARRAY de asientos solicitados ---' || '  Limite del tipo: ' || v_solicitados.LIMIT ||
                         ' | solicitados: '    || v_solicitados.COUNT);

    -- Se recorre la coleccion validando asiento por asiento. Avanzando por contador 

    FOR i IN v_solicitados.COUNT loop --Recorre la coleccion validando asiento por asiento. Avanzando por contador de elementos en la variable

        -- Un asiento esta ocupado si tiene un pasaje en estado que ocupa
        -- asiento. Es la misma condicion que aplica el indice unico parcial.
        SELECT COUNT(*)
        INTO   v_libre
        FROM   pasaje p
        JOIN   estado_pasaje ep ON ep.id_estado = p.id_estado
        WHERE  p.id_viaje    = v_viaje
        AND    p.id_bus      = v_bus
        AND    p.nro_asiento = v_solicitados(i)
        AND    ep.ocupa_asiento = 'S';

        IF v_libre = 0 THEN
            DBMS_OUTPUT.PUT_LINE('  Asiento ' || v_solicitados(i) || ': disponible');
        ELSE
            DBMS_OUTPUT.PUT_LINE('  Asiento ' || v_solicitados(i) || ': OCUPADO');
            v_ocupados := v_ocupados + 1;
        END IF;
    END LOOP;

    -- La decision se toma sobre el conjunto completo, no asiento por asiento:
    -- o se venden todos o no se vende ninguno.
    IF v_ocupados = 0 THEN
        DBMS_OUTPUT.PUT_LINE('  Resultado: la venta puede confirmarse.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('  Resultado: venta rechazada, ' || v_ocupados ||
                             ' asiento(s) no disponible(s).');
    END IF;
END;
/

-- 3.- Cursores 

-- 3.1 Control de Flota. Cursor sin parametros. RF-03 (programación) - RN-10 
-- Realiza recorrdios sobre un conjunto que debe cumplir una condición fija. Aquellos viajes programados
-- Por lo tanto, su comportamiento no depende de un criterio que variable, no hay parámetros que ingresar
-- Ojito tambien se puede realizar con un bucle for, pero al necesitar realizar una acción sobre algun conjunto de 
-- los datos es mejor ocupar el OPEN / FETCH / CLOSE
DECLARE
    -- CURSOR: viajes aun no realizados, con la duracion que hereda de su ruta
    CURSOR c_viajes_programados IS
        SELECT v.id_viaje,
               v.id_bus,
               v.salida_prog,
               r.duracion_estimada_min
        FROM   viaje v
        JOIN   ruta  r ON r.id_ruta = v.id_ruta
        WHERE  v.estado_viaje = 'PRO'                -- PRO = programado
        ORDER  BY v.salida_prog;

    r_viaje        c_viajes_programados%ROWTYPE;     -- anclado al cursor, no a la tabla
    v_asignados    PLS_INTEGER;                      -- conductores que tiene el viaje
    v_requeridos   PLS_INTEGER;                      -- conductores que exige su duracion
    v_revisados    PLS_INTEGER := 0;                 -- contador de filas procesadas
    v_conformes    PLS_INTEGER := 0;                 -- viajes que cumplen RN-10
    c_max_horas    CONSTANT NUMBER := 5;             -- limite legal por conductor
BEGIN
    DBMS_OUTPUT.PUT_LINE('2.1 Control de flota - viajes programados');

    OPEN c_viajes_programados;                       -- se ejecuta la consulta
    LOOP
        FETCH c_viajes_programados INTO r_viaje;     -- se trae una fila
        EXIT WHEN c_viajes_programados%NOTFOUND;     -- se corta al agotar el conjunto
        v_revisados := v_revisados + 1;

        v_requeridos := CEIL(r_viaje.duracion_estimada_min / 60 / c_max_horas);

        SELECT COUNT(*)                              -- tripulacion realmente asignada
        INTO   v_asignados
        FROM   viaje_conductor vc
        WHERE  vc.id_viaje = r_viaje.id_viaje;

        IF v_asignados >= v_requeridos THEN
            v_conformes := v_conformes + 1;
            DBMS_OUTPUT.PUT_LINE('    viaje ' || LPAD(r_viaje.id_viaje,2) ||
                                 ' | sale ' || TO_CHAR(r_viaje.salida_prog,'DD-MM HH24:MI') ||
                                 ' | ' || ROUND(r_viaje.duracion_estimada_min/60,2) || ' h' ||
                                 ' | conductores ' || v_asignados || '/' || v_requeridos ||
                                 ' | conforme');
        ELSE
            DBMS_OUTPUT.PUT_LINE('    viaje ' || LPAD(r_viaje.id_viaje,2) ||
                                 ' | sale ' || TO_CHAR(r_viaje.salida_prog,'DD-MM HH24:MI') ||
                                 ' | ' || ROUND(r_viaje.duracion_estimada_min/60,2) || ' h' ||
                                 ' | conductores ' || v_asignados || '/' || v_requeridos ||
                                 ' | INCUMPLE RN-10');
        END IF;
    END LOOP;
    CLOSE c_viajes_programados;                      -- se libera el cursor

    DBMS_OUTPUT.PUT_LINE('    revisados ' || v_revisados ||
                         ', conformes ' || v_conformes);
EXCEPTION
    WHEN OTHERS THEN
        -- El CLOSE tambien va aqui: si el bloque falla a mitad del recorrido, el
        -- cursor quedaria abierto. Es el costo de usar la forma extendida.
        IF c_viajes_programados%ISOPEN THEN
            CLOSE c_viajes_programados;
        END IF;
        DBMS_OUTPUT.PUT_LINE('    Error en el control de flota: ' || SQLERRM);
END;
/


-- 3.2 Registro pasajeros Viaje. Cursor con parámetros RF-05
-- Aqui se hace el uso del parámetro id_viaje para filtrar los pasajeros que embarcaran en el bus
-- El conductor debe obtener el registro delos pasajeros para su viajes, en cada viaje es distinto id
-- por lo que la condición a solicitar es un parametros. Además es un complejo dado que el cursor
-- hace agregaciones de contenidos desde distintas tablas aplicando JOINs para obtener los datos del registro

DECLARE
    -- PARAMETRO del futuro procedimiento
    p_id_viaje  CONSTANT viaje.id_viaje%TYPE := 4;   -- Bulnes del 02-09

    -- CURSOR parametrizado: el parametro formal se llama distinto que la
    -- variable del bloque para que quede claro cual es cual dentro del SELECT.
    CURSOR c_pasajeros (cp_id_viaje viaje.id_viaje%TYPE) IS
        SELECT a.piso,
               a.nro_asiento,
               ta.nombre                       AS tipo_asiento,
               pa.papellido || ', ' || pa.pnombre AS pasajero,
               pa.run,
               pa.dv,
               ep.codigo                       AS estado,
               ep.ocupa_asiento
        FROM   pasaje        p
        JOIN   asiento       a  ON a.id_bus          = p.id_bus
                               AND a.nro_asiento     = p.nro_asiento
        JOIN   tipo_asiento  ta ON ta.id_tipo_asiento = a.id_tipo_asiento
        JOIN   pasajero      pa ON pa.id_pasajero     = p.id_pasajero
        JOIN   estado_pasaje ep ON ep.id_estado       = p.id_estado
        WHERE  p.id_viaje = cp_id_viaje
        ORDER  BY a.piso, a.nro_asiento;          -- orden de embarque

    v_trayecto    VARCHAR2(80);
    v_salida      viaje.salida_prog%TYPE;
    v_embarcan    PLS_INTEGER := 0;               -- pasajeros que efectivamente suben
    v_anulados    PLS_INTEGER := 0;               -- pasajes anulados del viaje
BEGIN
    -- Encabezado del registro: de que viaje se trata
    SELECT o.ciudad || ' - ' || d.ciudad, v.salida_prog
    INTO   v_trayecto, v_salida
    FROM   viaje v
    JOIN   ruta  r ON r.id_ruta      = v.id_ruta
    JOIN   terminal o ON o.id_terminal = r.id_terminal_origen
    JOIN   terminal d ON d.id_terminal = r.id_terminal_destino
    WHERE  v.id_viaje = p_id_viaje;

    DBMS_OUTPUT.PUT_LINE('2.2 Registro del viaje ' || p_id_viaje ||
                         ' | ' || v_trayecto ||
                         ' | sale ' || TO_CHAR(v_salida,'DD-MM-YYYY HH24:MI'));

    -- El parametro se pasa al abrir el cursor, entre parentesis
    FOR r IN c_pasajeros(p_id_viaje) LOOP
        DBMS_OUTPUT.PUT_LINE('    piso ' || r.piso ||
                             ' asiento ' || LPAD(r.nro_asiento,2) ||
                             ' | ' || RPAD(r.tipo_asiento,14) ||
                             ' | ' || RPAD(r.pasajero,26) ||
                             ' | ' || r.run || '-' || r.dv ||
                             ' | ' || r.estado);

        -- El estado decide si el pasajero embarca: es el mismo criterio que usa
        -- el indice unico parcial, tomado del catalogo y no escrito a mano.
        IF r.ocupa_asiento = 'S' THEN
            v_embarcan := v_embarcan + 1;
        ELSE
            v_anulados := v_anulados + 1;
        END IF;
    END LOOP;

    IF v_embarcan + v_anulados = 0 THEN
        DBMS_OUTPUT.PUT_LINE('    El viaje no tiene pasajes emitidos.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('    Embarcan ' || v_embarcan ||
                             ' pasajero(s), ' || v_anulados || ' anulado(s).');
    END IF;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('2.2 El viaje ' || p_id_viaje || ' no existe.');
END;
/ 

-- 3.3 Buscar bus y conductor libres. Cursores + funciones
-- Ambos ocupan una misma función. fn_recurso_ocupado. Retornan un null si el recurso es libre y un id_viaje 
--si el recurso esta ocupado para ese intervalo de hora y fecha. 


--Conductor
CREATE OR REPLACE FUNCTION fn_buscar_conductor_libre (
    v_salida IN viaje.salida_prog%TYPE,
    v_llegada IN viaje.llegada_prog%TYPE
)
RETURN conductor.id_conductor%TYPE
AS
    -- cursores
    CURSOR c_conductores_libres (cp_salida  viaje.salida_prog%TYPE, cp_llegada viaje.llegada_prog%TYPE) --
        IS
        SELECT c.id_conductor,
               c.papellido || ', ' || c.pnombre nombre,
               c.nro_licencia
        FROM   conductor c
        -- MISMA funcion, otro recurso. Aqui se paga la decision de haberla
        -- escrito con dos parametros de recurso en vez de dos funciones.
        WHERE  fn_recurso_ocupado(cp_salida, cp_llegada,
                                  p_id_conductor => c.id_conductor) IS NULL
        ORDER  BY c.papellido, c.pnombre;

    v_id_conductor_libre  conductor.id_conductor%TYPE;  -- para mostrar el id del conductor libre
    v_id_bus_libre        bus.id_bus%TYPE;              -- para mostrar el id
BEGIN

    FOR r_conductor IN c_conductores_libres(v_salida, v_llegada) LOOP
        DBMS_OUTPUT.PUT_LINE('    conductor ' || r_conductor.id_conductor || ' (' || r_conductor.nombre || ') - Licencia: ' || r_conductor.nro_licencia);
        return; 
        -- Solo se muestra el primer conductor libre, ya que solo se necesita uno para programar el viaje. 
        --Si el viaje dura mas de 5 horas, se debera invocar nuevamente el cursor para obtener otro conductor libre. Para obtener otro conductor libre.
        --Pero se desarrollara esa doble invocacion en otro procedimiento, ya que este procedimiento solo se encarga de mostrar los buses y conductores libres.
    END LOOP;   

    -- 

END;
/

--Bus
CREATE OR REPLACE PROCEDURE sp_buscar_bus_libre (
    v_salida IN viaje.salida_prog%TYPE,
    v_llegada IN viaje.llegada_prog%TYPE
)
AS
    -- CURSORES
    CURSOR c_buses_libres (cp_salida  viaje.salida_prog%TYPE, cp_llegada viaje.llegada_prog%TYPE) -- El intervalo de tiempo es el mismo para todos los buses, y se pasa como parametro.
        IS
        SELECT b.id_bus, b.patente, COUNT(a.nro_asiento) capacidad
        FROM   bus b
        JOIN   asiento a ON a.id_bus = b.id_bus
        -- NULL = libre. Es la respuesta que se busca, no un error.
        WHERE  fn_recurso_ocupado(cp_salida, cp_llegada, p_id_bus => b.id_bus) IS NULL
        GROUP  BY b.id_bus, b.patente
        -- El mas grande primero: si dos sirven, conviene el de mas plazas.
        ORDER  BY capacidad DESC, b.id_bus;

v_id_bus_libre        bus.id_bus%TYPE;   -- para mostrar el id

BEGIN
    --- Se invocan los cursores con el mismo intervalo de tiempo, que es el del viaje a programar
    FOR r_bus IN c_buses_libres(v_salida, v_llegada) LOOP
        DBMS_OUTPUT.PUT_LINE('    bus ' || r_bus.id_bus || ' (' || r_bus.patente || ') - Capacidad: ' || r_bus.capacidad);
    END LOOP;
    
END;
/


-- 4. Procedimientos 

-- 4.1 Programación Viajes. RF-03; RN.03, RN-04, RN-10
-- Este Procedimiento recibe la ruta, la salida y el bus. Calcula la hora de llegada, verifica que no haya conflictos de horarios entre conductores y buses y
-- Asigna los conductores.


CREATE OR REPLACE TYPE tv_asientos AS VARRAY(6) OF NUMBER(4); --Consideración de Varray. este objeto es necesario
/
-- Dado que los Varray viven dentro de un bloque y mueren con el, para que sea parametro debe vivir como SQL es decir como diccionario fuera del 
--PLSQL. Se asigna la cantidad de asientos disponibles y el tipo de dato que tengra, no se ancla al tipo de datos con %TYPE porque es PLSQL y solo vive
-- esa sintaxis dentro de bloque

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

    FETCH c_conductores_libres INTO v_id_titular; --Lee por decirlo asi la primera fila y la asigna

    IF c_conductores_libres%NOTFOUND THEN
        CLOSE c_conductores_libres;
        RAISE e_sin_conductores;
    END IF;

    IF v_requeridos > 1 THEN
        FETCH c_conductores_libres INTO v_id_relevo;   -- Esta abre la segunda fila y la asgina. El cursor puntea desde la segunda fila al reaundar.  
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


-- 4.2 Venta de pasajes. RF-01 (venta); RN-05, RN-06, rN-07
--Aqui se ocupa el Record que prepara los datos de pasaje y se utiliza el varray que limita la capidad de compra
-- El procedimieno solicita el viajes, el comprador y los asientos. A cambio registra el pasaje en la tabla pasaje y la transacción en la tabla venta
-- Cada insert en pasaje dispara el Trigger que registra el historial de los pasajes

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


-- 4.3 Anulación de pasaje. RF-02 (anulación); RN-08, RN-09
-- La anulación no borra el pasaje, le cambia el estado. Por eso queda el registro de quién anuló y cuándo.
-- El asiento se libera solo: el índice único parcial deja de contar a los pasajes cuyo estado no ocupa asiento (RN-09).
-- El motivo se deja en el contexto de la sesión antes del UPDATE, porque el trigger no recibe parámetros y lo lee de ahí.
-- El UPDATE dispara el trigger, que escribe la transición en el historial.

CREATE OR REPLACE PROCEDURE sp_anular_pasaje (
    p_id_pasaje IN pasaje.id_pasaje%TYPE,
    p_motivo    IN VARCHAR2
)
IS
    -- CONSTANTES
    c_ventana  CONSTANT NUMBER := 4;                              -- horas antes de la salida
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
    -- El pasaje debe existir. Se trae junto con la salida de su viaje, que define el plazo.
    BEGIN
        SELECT p.id_estado, p.nro_asiento, v.salida_prog
        INTO   v_id_estado, v_nro, v_salida
        FROM   pasaje p
        JOIN   viaje  v ON v.id_viaje = p.id_viaje
        WHERE  p.id_pasaje = p_id_pasaje;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RAISE e_pasaje_inexistente;
    END;

    -- RN-08: anular dos veces no es una transicion. El trigger trg_pasaje_no_revive
    -- impide el camino inverso, asi que la regla queda cubierta por los dos lados.
    IF v_id_estado = c_anulado THEN
        RAISE e_ya_anulado;
    END IF;

    -- Ventana de 4 horas. El calculo descarta solo los viajes que ya partieron:
    -- si la salida quedo atras, las horas restantes son negativas.
    v_horas := (CAST(v_salida AS DATE) - SYSDATE) * 24;
    IF v_horas < c_ventana THEN
        RAISE e_fuera_de_plazo;
    END IF;

    -- El motivo viaja por el contexto de sesion; el UPDATE dispara el trigger.
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
        -- El contexto se limpia siempre: si quedara con el motivo de una anulacion
        -- fallida, el trigger lo adjuntaria a la proxima transicion de esta sesion.
        DBMS_APPLICATION_INFO.SET_CLIENT_INFO(NULL);
        RAISE;
END sp_anular_pasaje;
/




-- 5.- Triggers 

-- 5. Registro historial de estado. RF-01 y RF-02 (venta-historial); RN-08
-- Cada vez que se produce una modificación en el estado de pasajes, el trigger se ejecuta registrando 
-- en la tabla que contiene el historial del pasaje el nuevo estado adquerido. 
-- El trigger se dispara cada vez que sucede un evento 

CREATE OR REPLACE TRIGGER trg_pasaje_historial
    AFTER INSERT OR UPDATE OF id_estado ON pasaje
    FOR EACH ROW
DECLARE
    v_secuencia  pasaje_estado_hist.secuencia%TYPE;
    v_motivo     pasaje_estado_hist.motivo%TYPE;
    v_usuario    pasaje_estado_hist.usuario%TYPE;
BEGIN
    -- Un UPDATE que no altera el estado no es una transicion y no debe
    -- registrarse. Sin esta guarda, corregir un precio generaria una fila de
    -- historial falsa.
    IF UPDATING AND :OLD.id_estado = :NEW.id_estado THEN
        RETURN;
    END IF;

    -- La secuencia es correlativa DENTRO de cada pasaje, no global. Se calcula
    -- sobre PASAJE_ESTADO_HIST, que es una tabla distinta de la que dispara el
    -- trigger: por eso no se produce el error de tabla mutante.
    SELECT NVL(MAX(secuencia), 0) + 1
    INTO   v_secuencia
    FROM   pasaje_estado_hist
    WHERE  id_pasaje = :NEW.id_pasaje;

    -- Datos que el trigger obtiene del contexto, no de parametros
    v_motivo  := SYS_CONTEXT('USERENV', 'CLIENT_INFO');
    v_usuario := NVL(SYS_CONTEXT('USERENV', 'SESSION_USER'), 'DESCONOCIDO');

    INSERT INTO pasaje_estado_hist (
        id_pasaje, secuencia, fecha_hora, id_estado, usuario, motivo
    ) VALUES (
        :NEW.id_pasaje, v_secuencia, SYSTIMESTAMP, :NEW.id_estado,
        v_usuario, v_motivo
    );
END;
/

SHOW ERRORS

