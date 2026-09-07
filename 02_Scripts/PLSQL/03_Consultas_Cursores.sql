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
-- 2.1  Control de flota        ->  futuro PROCEDURE sp_control_flota
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
-- 2.2  Registro de viajes      ->  futuro PROCEDURE sp_registro_viaje
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
-- 2.3  Disponibilidad de asientos  ->  futuro PROCEDURE sp_disponibilidad
--
-- DOS CURSORES CON PARAMETROS TRABAJANDO EN FORMA SIMULTANEA.
-- Sirve a  : RF-04      Genera : I-03      Verifica : RN-01, RN-06
-- Informe  : 6.5 (loops anidados), 6.6 (limitaciones), 8.1 (sp_disponibilidad)
-- Anexo    : Tabla 28, Tabla 3 (RF-04), Tabla 9 (I-03)
--
-- Es el requerimiento que el enunciado exige con todas sus letras: "el sistema
-- debe controlar la asignacion de buses y la disponibilidad de asientos para
-- cada viaje". No es un reporte de gestion sino control operacional: sin esta
-- consulta no se puede vender sin arriesgar sobreventa.
--
-- POR QUE DOS NIVELES Y NO UNO
--
-- La relacion entre ambos ciclos es de dependencia, no de conveniencia: el
-- conjunto que recorre el ciclo interior esta determinado por la fila que el
-- exterior tiene en curso. Los asientos a revisar son los del bus asignado a ESE
-- viaje, de modo que el cursor interior no puede abrirse hasta saber cual es.
--
--     POR CADA VIAJE del rango             <- cursor 1, con parametros
--         POR CADA ASIENTO de su bus       <- cursor 2, con parametros
--             determinar si esta libre u ocupado
--         calcular el porcentaje de ocupacion del viaje
--
-- LIMITACION QUE SE ASUME
--
-- El recorrido fila a fila es mas costoso que una operacion de conjunto. Si solo
-- se necesitara el porcentaje agregado, una consulta con JOIN, GROUP BY y
-- funciones de agregacion lo resolveria sin iterar y con mejor rendimiento. Los
-- dos ciclos se justifican porque el proceso necesita ademas el detalle asiento
-- por asiento, que es lo que el vendedor consulta al momento de vender. Sobre
-- volumenes grandes esta diferencia se vuelve determinante y habria que revisar
-- el diseno.
--------------------------------------------------------------------------------
DECLARE
    -- PARAMETROS del futuro procedimiento
    p_desde  CONSTANT DATE := TO_DATE('01-09-2026','DD-MM-YYYY');
    p_hasta  CONSTANT DATE := TO_DATE('03-09-2026','DD-MM-YYYY') + 1;

    -- CURSOR EXTERIOR: los viajes del rango pedido
    CURSOR c_viajes (cp_desde DATE, cp_hasta DATE) IS
        SELECT v.id_viaje,
               v.id_bus,
               v.salida_prog,
               v.estado_viaje,
               o.ciudad || ' - ' || d.ciudad AS trayecto
        FROM   viaje v
        JOIN   ruta  r     ON r.id_ruta      = v.id_ruta
        JOIN   terminal o  ON o.id_terminal  = r.id_terminal_origen
        JOIN   terminal d  ON d.id_terminal  = r.id_terminal_destino
        WHERE  v.salida_prog >= cp_desde
        AND    v.salida_prog <  cp_hasta
        ORDER  BY v.salida_prog;

    -- CURSOR INTERIOR: los asientos del bus, con la marca de ocupacion para ESE
    -- viaje. El LEFT JOIN es lo que permite ver tambien los asientos libres: un
    -- INNER JOIN devolveria solo los vendidos y la consulta perderia sentido.
    CURSOR c_asientos (cp_id_bus bus.id_bus%TYPE, cp_id_viaje viaje.id_viaje%TYPE) IS
        SELECT a.nro_asiento,
               a.piso,
               ta.codigo AS tipo,
               CASE WHEN p.id_pasaje IS NULL THEN 'LIBRE' ELSE 'OCUPADO' END AS situacion
        FROM   asiento a
        JOIN   tipo_asiento ta ON ta.id_tipo_asiento = a.id_tipo_asiento
        LEFT   JOIN pasaje p
               ON  p.id_bus      = a.id_bus
               AND p.nro_asiento = a.nro_asiento
               AND p.id_viaje    = cp_id_viaje
               AND p.id_estado IN (SELECT id_estado FROM estado_pasaje
                                   WHERE ocupa_asiento = 'S')
        WHERE  a.id_bus = cp_id_bus
        ORDER  BY a.piso, a.nro_asiento;

    v_capacidad   PLS_INTEGER;      -- asientos del bus (RN-01)
    v_ocupados    PLS_INTEGER;      -- asientos tomados en ese viaje
    v_porcentaje  NUMBER;
    v_libres_txt  VARCHAR2(200);    -- numeros de asiento libres, para el vendedor
    v_viajes      PLS_INTEGER := 0;
BEGIN
    DBMS_OUTPUT.PUT_LINE('2.3 Disponibilidad entre ' ||
                         TO_CHAR(p_desde,'DD-MM-YYYY') || ' y ' ||
                         TO_CHAR(p_hasta-1,'DD-MM-YYYY'));

    -- CICLO EXTERIOR
    FOR rv IN c_viajes(p_desde, p_hasta) LOOP
        v_viajes     := v_viajes + 1;
        v_capacidad  := 0;
        v_ocupados   := 0;
        v_libres_txt := NULL;

        -- CICLO INTERIOR: depende de rv, la fila que el exterior tiene en curso
        FOR ra IN c_asientos(rv.id_bus, rv.id_viaje) LOOP
            v_capacidad := v_capacidad + 1;

            IF ra.situacion = 'OCUPADO' THEN
                v_ocupados := v_ocupados + 1;
            ELSE
                -- Se arma la lista de libres mientras se recorre, para no tener
                -- que volver a consultar la tabla despues.
                v_libres_txt := v_libres_txt ||
                                CASE WHEN v_libres_txt IS NULL THEN '' ELSE ',' END ||
                                ra.nro_asiento;
            END IF;
        END LOOP;

        -- Al cerrar el ciclo interior ya se tiene todo lo del viaje en curso
        v_porcentaje := ROUND(v_ocupados * 100 / v_capacidad, 1);

        DBMS_OUTPUT.PUT_LINE('    viaje ' || LPAD(rv.id_viaje,2) ||
                             ' | ' || RPAD(rv.trayecto,22) ||
                             ' | ' || TO_CHAR(rv.salida_prog,'DD-MM HH24:MI') ||
                             ' | ' || rv.estado_viaje ||
                             ' | ocupa ' || LPAD(v_ocupados,2) || '/' || LPAD(v_capacidad,2) ||
                             ' (' || LPAD(TO_CHAR(v_porcentaje,'FM990.0'),5) || '%)');

        IF v_libres_txt IS NULL THEN
            DBMS_OUTPUT.PUT_LINE('             sin asientos disponibles');
        ELSE
            DBMS_OUTPUT.PUT_LINE('             libres: ' || v_libres_txt);
        END IF;
    END LOOP;

    IF v_viajes = 0 THEN
        DBMS_OUTPUT.PUT_LINE('    No hay viajes programados en ese rango.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('    ' || v_viajes || ' viaje(s) revisado(s).');
    END IF;
EXCEPTION
    -- Un bus sin asientos registrados deja v_capacidad en cero y rompe el
    -- calculo del porcentaje. No deberia ocurrir, porque contradice RN-01, pero
    -- si ocurre conviene un diagnostico util en lugar de un error del motor.
    WHEN ZERO_DIVIDE THEN
        DBMS_OUTPUT.PUT_LINE('    Hay un viaje cuyo bus no tiene asientos ' ||
                             'registrados: revisar los datos de flota.');
END;
/
