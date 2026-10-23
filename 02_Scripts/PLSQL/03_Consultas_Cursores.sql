--------------------------------------------------------------------------------
-- Modelo_GestionTransporte  |  Script PL/SQL - Parte 3
-- NIVEL 2: consultas con cursores explicitos
--
-- Requisito : DDL cargado y 02_Calculos.sql revisado
-- Motor     : Oracle Database
--
--------------------------------------------------------------------------------
-- POR QUE ESTE ARCHIVO VA AQUI
--
-- Los bloques del nivel 1 resuelven un valor; estos recorren conjuntos. Van
-- despues porque consumen esos calculos: la disponibilidad de un viaje usa la
-- capacidad y los ocupados que el nivel 1 ya sabe obtener. Van antes del nivel 3
-- porque solo LEEN: no modifican datos y por lo tanto no dependen de las
-- validaciones de negocio que se escribiran despues.
--
-- FRONTERA DE PROCEDIMIENTO
--
-- Estos bloques no devuelven un valor unico, presentan un conjunto. Por eso su
-- envase futuro es un procedimiento y no una funcion. Se escriben con la misma
-- disciplina del nivel 1: entradas como CONSTANT con prefijo p_, cuerpo intacto.
--
-- ORDEN OBLIGATORIO DENTRO DEL DECLARE
--   1. tipos      2. cursores      3. variables      4. excepciones
-- Una variable declarada como cursor%ROWTYPE exige que el cursor ya exista.
-- Invertirlo no compila; no es una convencion de estilo.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- TRAZABILIDAD CON LA DOCUMENTACION
--
--   Informe  : DP_Informe_Requerimiento.docx, seccion 6 (Cursores)
--                6.1 Cursor explicito              -> los tres bloques
--                6.2 Cursor sin parametros         -> bloque 2.1
--                6.3 Cursor con parametros         -> bloques 2.2 y 2.3
--                6.4 Cursores complejos            -> bloque 2.2
--                6.5 Loops anidados                -> bloque 2.3
--                6.6 Justificacion y limitaciones  -> bloque 2.3
--                8.1 Identificacion de procedimientos -> envase futuro de cada bloque
--   Anexo    : ANEXO_Tablas_de_Referencia.docx
--                Tabla 28 - Procedimientos almacenados
--                Tabla  3 - Requerimientos funcionales (RF-03, RF-04, RF-05)
--                Tabla  9 - Informacion que genera el sistema (I-03, I-05)
--   Rubrica  : IE1.2.1 - cursores explicitos complejos con parametros y mas de un
--              LOOP simultaneo (10% informe / 15% presentacion)
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 140
SET PAGESIZE 60

PROMPT ================================================================
PROMPT  NIVEL 2 - CONSULTAS CON CURSORES
PROMPT ================================================================


--------------------------------------------------------------------------------
-- 3.1  Control de flota        ->  futuro PROCEDURE sp_control_flota
--
-- Cursor SIN parametros, con OPEN / FETCH / CLOSE explicito.
-- Sirve a  : RF-03 (programacion)      Verifica : RN-10
-- Informe  : 6.2 (cursor sin parametros), 8.1 (sp_control_flota)
-- Anexo    : Tabla 28, Tabla 7 (jornada por ruta)
--
-- Por que sin parametros: el conjunto que recorre esta determinado por una
-- condicion fija del negocio -los viajes en estado programado- y no por un
-- criterio que cambie entre invocaciones. No hay nada que parametrizar.
--
-- Por que OPEN/FETCH/CLOSE y no FOR: se escribe aqui en su forma extendida para
-- dejar visible el ciclo de vida completo del cursor. El bloque 2.2 usa la forma
-- FOR, que hace lo mismo de manera implicita. La comparacion entre ambos es
-- deliberada: en produccion se prefiere FOR porque no se puede olvidar el CLOSE.
--------------------------------------------------------------------------------
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


--------------------------------------------------------------------------------
-- 3.2  Registro de viajes      ->  futuro PROCEDURE sp_registro_viaje
--
-- Cursor CON parametro, y ademas cursor complejo.
-- Sirve a  : RF-05      Genera : I-05
-- Informe  : 6.3 y 6.4 (cursor con parametro, complejo), 8.1 (sp_registro_viaje)
-- Anexo    : Tabla 28, Tabla 3 (RF-05), Tabla 9 (I-05)
--
-- Por que con parametro: el conductor necesita el registro de SU viaje, no de
-- todos. El identificador entra por parametro y el mismo cursor sirve para
-- cualquier viaje sin reescribirse. La alternativa -un cursor sin parametros por
-- cada viaje- es inviable, y traer todos los pasajes para filtrarlos despues en
-- PL/SQL le quita al motor un trabajo que resuelve mejor que el bloque.
--
-- Por que complejo: el dato que el negocio necesita no vive en una sola tabla.
-- Hay que reunir el asiento, su tipo, el pasajero que lo ocupa y el estado de su
-- pasaje: cinco tablas. Esa dispersion es el efecto de haber normalizado, y el
-- cursor es donde se vuelve a juntar.
--
-- Se usa la forma FOR: abre, recorre y cierra el cursor de manera implicita, y
-- declara la variable de recorrido sola. Es la forma preferible salvo que se
-- necesite control explicito sobre el ciclo, como en 2.1.
--------------------------------------------------------------------------------
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


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- 3.3  Buscar CONDUCTOR libre
-- Sirve a: RF-03   |   Implementa: RN-03, RN-04
--
-- Ambos cursores invocan fn_recurso_ocupado, que es la funcion del nivel 1 que sabe si un recurso esta ocupado en un intervalo de tiempo. 
-- Si devuelve NULL, el recurso esta libre. Si devuelve un id_viaje, el recurso esta ocupado en ese viaje.
-- Ve tanto para buses como para conductores, y por eso se invoca con parametros de recurso distintos.

-- Primero se declaran los cursores, y luego se invocan con el mismo intervalo de tiempo, que es el del viaje a programar. Obteniendo los busees y conductores libres en ese intervalo de tiempo.
-- Posteriormente se tiene que mostrar la informacion de los buses y conductores libres en ese intervalo de tiempo, para que el usuario pueda elegir uno de cada tipo y programar el viaje.
-- En otro procedimiento se debera programar con el bus y conductor elegidos, asignando el viaje a ese bus y conductor, y cambiando el estado del viaje a programado.
-- Ojo debe de haber 2 conductores si el viaje dura mas de 5 horas, y el procedimiento debe de verificar que los conductores elegidos esten libres en ese intervalo de tiempo.alter
--------------------------------------------------------------------------------
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

--3.4 buscar BUS libre
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
