--------------------------------------------------------------------------------
-- Modelo_GestionTransporte  |  Script PL/SQL - Parte 2
-- PKG_CONSULTAS: control operacional con cursores explicitos
--
-- Requisito : DDL cargado y 01_Pkg_Calculos.sql ejecutado
-- Motor     : Oracle Database
--------------------------------------------------------------------------------
-- TRAZABILIDAD CON LA DOCUMENTACION
--
--   Informe  : 6.1 a 6.6 (cursores), 8.1 y 8.2 (procedimientos), 10 (packages)
--   Anexo    : Tabla 28 (procedimientos), Tabla 3 (RF-03, RF-04, RF-05),
--              Tabla 9 (informacion I-03, I-05)
--   Reglas   : RN-01, RN-06, RN-10
--   Rubrica  : IE1.2.1 - cursores explicitos complejos con parametros y mas de
--              un LOOP simultaneo (10% informe / 15% presentacion)
--              IE1.4.1 - procedimientos y packages (15% / 15%)
--
--------------------------------------------------------------------------------
-- POR QUE PROCEDIMIENTOS Y NO FUNCIONES
--
-- Estos tres no devuelven un valor: presentan un conjunto. Una funcion que
-- "devuelve" un listado tendria que retornar una coleccion o un cursor, y el
-- consumidor real de esta informacion es una persona -el programador de flota,
-- el conductor, el vendedor-, no otro programa que vaya a seguir calculando.
--
-- POR QUE ESCRIBEN CON DBMS_OUTPUT
--
-- Es el sustituto pedagogico de una salida real. En un sistema en produccion
-- estos procedimientos devolverian un SYS_REFCURSOR o poblarian una coleccion
-- que la aplicacion formatea. Se deja constancia porque es una limitacion
-- consciente, no un descuido: DBMS_OUTPUT solo sirve mientras haya una sesion
-- interactiva mirando.
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 140
SET PAGESIZE 60


--------------------------------------------------------------------------------
-- ESPECIFICACION
--------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_consultas AS

    -- 2.1  Revisa los viajes programados y verifica que cada uno lleve la
    --      tripulacion que exige su duracion (RN-10). Cursor SIN parametros.
    PROCEDURE sp_control_flota;

    -- 2.2  Registro de embarque de un viaje: quien sube y en que asiento.
    --      Cursor CON parametro y complejo (cinco tablas). RF-05.
    PROCEDURE sp_registro_viaje (
        p_id_viaje IN viaje.id_viaje%TYPE
    );

    -- 2.3  Disponibilidad de asientos de los viajes de un rango de fechas.
    --      DOS cursores con parametros trabajando en forma simultanea. RF-04.
    PROCEDURE sp_disponibilidad (
        p_desde IN DATE,
        p_hasta IN DATE
    );

END pkg_consultas;
/
SHOW ERRORS


--------------------------------------------------------------------------------
-- BODY
--------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE BODY pkg_consultas AS

    ----------------------------------------------------------------------------
    -- 2.1  Control de flota
    --
    -- Cursor SIN parametros, con OPEN / FETCH / CLOSE explicito.
    --
    -- Por que sin parametros: el conjunto que recorre esta determinado por una
    -- condicion fija del negocio -los viajes en estado programado- y no por un
    -- criterio que cambie entre invocaciones. No hay nada que parametrizar.
    --
    -- Por que la forma extendida: deja visible el ciclo de vida completo del
    -- cursor. El procedimiento 2.2 usa la forma FOR, que hace lo mismo de manera
    -- implicita. La comparacion es deliberada, y el costo de la forma extendida
    -- se ve en el manejador de excepciones: hay que cerrar el cursor a mano si
    -- el recorrido falla a mitad.
    --
    -- Los conductores requeridos los resuelve pkg_calculos, no un CEIL escrito
    -- aqui: la regla RN-10 vive en un solo lugar del proyecto.
    ----------------------------------------------------------------------------
    PROCEDURE sp_control_flota
    IS
        CURSOR c_viajes_programados IS
            SELECT v.id_viaje,
                   v.id_bus,
                   v.salida_prog,
                   r.duracion_estimada_min
            FROM   viaje v
            JOIN   ruta  r ON r.id_ruta = v.id_ruta
            WHERE  v.estado_viaje = 'PRO'                -- PRO = programado
            ORDER  BY v.salida_prog;

        r_viaje       c_viajes_programados%ROWTYPE;   -- anclado al cursor
        v_asignados   PLS_INTEGER;
        v_requeridos  PLS_INTEGER;
        v_revisados   PLS_INTEGER := 0;
        v_conformes   PLS_INTEGER := 0;
    BEGIN
        DBMS_OUTPUT.PUT_LINE('2.1 Control de flota - viajes programados');

        OPEN c_viajes_programados;
        LOOP
            FETCH c_viajes_programados INTO r_viaje;
            EXIT WHEN c_viajes_programados%NOTFOUND;
            v_revisados := v_revisados + 1;

            v_requeridos := pkg_calculos.fn_conductores_requeridos(r_viaje.id_viaje);

            SELECT COUNT(*)                           -- tripulacion asignada
            INTO   v_asignados
            FROM   viaje_conductor vc
            WHERE  vc.id_viaje = r_viaje.id_viaje;

            DBMS_OUTPUT.PUT_LINE('    viaje ' || LPAD(r_viaje.id_viaje,2) ||
                                 ' | sale ' || TO_CHAR(r_viaje.salida_prog,'DD-MM HH24:MI') ||
                                 ' | ' || ROUND(r_viaje.duracion_estimada_min/60,2) || ' h' ||
                                 ' | conductores ' || v_asignados || '/' || v_requeridos ||
                                 CASE WHEN v_asignados >= v_requeridos
                                      THEN ' | conforme'
                                      ELSE ' | INCUMPLE RN-10' END);

            IF v_asignados >= v_requeridos THEN
                v_conformes := v_conformes + 1;
            END IF;
        END LOOP;
        CLOSE c_viajes_programados;

        DBMS_OUTPUT.PUT_LINE('    revisados ' || v_revisados ||
                             ', conformes ' || v_conformes);
    EXCEPTION
        WHEN OTHERS THEN
            -- Si el recorrido falla a mitad, el cursor quedaria abierto. Este
            -- cierre es el costo real de haber usado OPEN/FETCH/CLOSE en vez
            -- del FOR, que lo resuelve solo.
            IF c_viajes_programados%ISOPEN THEN
                CLOSE c_viajes_programados;
            END IF;
            RAISE;   -- el procedimiento informa, no decide: propaga al invocador
    END sp_control_flota;


    ----------------------------------------------------------------------------
    -- 2.2  Registro de viajes
    --
    -- Cursor CON parametro, y ademas complejo.
    --
    -- Por que con parametro: el conductor necesita el registro de SU viaje, no
    -- de todos. El identificador entra por parametro y el mismo cursor sirve
    -- para cualquier viaje sin reescribirse. Traer todos los pasajes para
    -- filtrarlos despues en PL/SQL le quitaria al motor un trabajo que resuelve
    -- mejor que el procedimiento.
    --
    -- Por que complejo: el dato que el negocio necesita no vive en una sola
    -- tabla. Hay que reunir el asiento, su tipo, el pasajero que lo ocupa y el
    -- estado de su pasaje: cinco tablas. Esa dispersion es el efecto de haber
    -- normalizado, y el cursor es donde se vuelve a juntar.
    ----------------------------------------------------------------------------
    PROCEDURE sp_registro_viaje (
        p_id_viaje IN viaje.id_viaje%TYPE
    )
    IS
        -- El parametro formal se llama distinto que el del procedimiento para
        -- que quede claro cual es cual dentro del SELECT.
        CURSOR c_pasajeros (cp_id_viaje viaje.id_viaje%TYPE) IS
            SELECT a.piso,
                   a.nro_asiento,
                   ta.nombre                          AS tipo_asiento,
                   pa.papellido || ', ' || pa.pnombre AS pasajero,
                   pa.run,
                   pa.dv,
                   ep.codigo                          AS estado,
                   ep.ocupa_asiento
            FROM   pasaje        p
            JOIN   asiento       a  ON a.id_bus           = p.id_bus
                                   AND a.nro_asiento      = p.nro_asiento
            JOIN   tipo_asiento  ta ON ta.id_tipo_asiento = a.id_tipo_asiento
            JOIN   pasajero      pa ON pa.id_pasajero     = p.id_pasajero
            JOIN   estado_pasaje ep ON ep.id_estado       = p.id_estado
            WHERE  p.id_viaje = cp_id_viaje
            ORDER  BY a.piso, a.nro_asiento;          -- orden de embarque

        v_trayecto  VARCHAR2(80);
        v_salida    viaje.salida_prog%TYPE;
        v_embarcan  PLS_INTEGER := 0;
        v_anulados  PLS_INTEGER := 0;
    BEGIN
        SELECT o.ciudad || ' - ' || d.ciudad, v.salida_prog
        INTO   v_trayecto, v_salida
        FROM   viaje v
        JOIN   ruta     r ON r.id_ruta     = v.id_ruta
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

            -- El estado decide si el pasajero embarca: criterio del catalogo,
            -- el mismo que aplica el indice unico parcial.
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
    END sp_registro_viaje;


    ----------------------------------------------------------------------------
    -- 2.3  Disponibilidad de asientos
    --
    -- DOS CURSORES CON PARAMETROS TRABAJANDO EN FORMA SIMULTANEA.
    --
    -- Es el requerimiento que el enunciado exige con todas sus letras: "el
    -- sistema debe controlar la asignacion de buses y la disponibilidad de
    -- asientos para cada viaje". No es un reporte de gestion sino control
    -- operacional: sin esta consulta no se puede vender sin arriesgar sobreventa.
    --
    -- La relacion entre ambos ciclos es de dependencia, no de conveniencia: el
    -- conjunto que recorre el ciclo interior esta determinado por la fila que el
    -- exterior tiene en curso. Los asientos a revisar son los del bus asignado a
    -- ESE viaje, de modo que el cursor interior no puede abrirse hasta saberlo.
    --
    --     POR CADA VIAJE del rango             <- cursor 1, con parametros
    --         POR CADA ASIENTO de su bus       <- cursor 2, con parametros
    --             determinar si esta libre u ocupado
    --         calcular el porcentaje de ocupacion del viaje
    --
    -- LIMITACION QUE SE ASUME: el recorrido fila a fila es mas costoso que una
    -- operacion de conjunto. Si solo se necesitara el porcentaje agregado, una
    -- consulta con JOIN, GROUP BY y agregacion lo resolveria sin iterar. Los dos
    -- ciclos se justifican porque el proceso necesita ademas el detalle asiento
    -- por asiento, que es lo que el vendedor consulta al momento de vender.
    ----------------------------------------------------------------------------
    PROCEDURE sp_disponibilidad (
        p_desde IN DATE,
        p_hasta IN DATE
    )
    IS
        CURSOR c_viajes (cp_desde DATE, cp_hasta DATE) IS
            SELECT v.id_viaje,
                   v.id_bus,
                   v.salida_prog,
                   v.estado_viaje,
                   o.ciudad || ' - ' || d.ciudad AS trayecto
            FROM   viaje v
            JOIN   ruta     r ON r.id_ruta     = v.id_ruta
            JOIN   terminal o ON o.id_terminal = r.id_terminal_origen
            JOIN   terminal d ON d.id_terminal = r.id_terminal_destino
            WHERE  v.salida_prog >= cp_desde
            AND    v.salida_prog <  cp_hasta
            ORDER  BY v.salida_prog;

        -- CURSOR INTERIOR. El LEFT JOIN es lo que permite ver tambien los
        -- asientos libres: un INNER JOIN devolveria solo los vendidos.
        --
        -- Resuelve la misma pregunta que pkg_calculos.fn_asiento_ocupado, pero
        -- deliberadamente NO la invoca: la funcion responde por UN asiento, y
        -- aqui hacen falta TODOS los del bus. Llamarla asiento por asiento
        -- cambiaria una consulta de conjunto por N consultas dentro del ciclo.
        CURSOR c_asientos (cp_id_bus   bus.id_bus%TYPE,
                           cp_id_viaje viaje.id_viaje%TYPE) IS
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

        v_capacidad   PLS_INTEGER;
        v_ocupados    PLS_INTEGER;
        v_porcentaje  NUMBER;
        v_libres_txt  VARCHAR2(200);
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
                    -- La lista se arma mientras se recorre, para no volver a
                    -- consultar la tabla despues.
                    v_libres_txt := v_libres_txt ||
                                    CASE WHEN v_libres_txt IS NULL THEN '' ELSE ',' END ||
                                    ra.nro_asiento;
                END IF;
            END LOOP;

            -- El porcentaje SI se delega en pkg_calculos: es una formula de una
            -- linea cuyo criterio -incluido el de ZERO_DIVIDE- debe vivir en un
            -- solo lugar. A diferencia del chequeo de ocupacion de arriba, aqui
            -- no se pierde ninguna operacion de conjunto al delegar.
            v_porcentaje := pkg_calculos.fn_porcentaje_ocupacion(rv.id_viaje);

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
        WHEN ZERO_DIVIDE THEN
            -- Un bus sin asientos registrados contradice RN-01. No deberia
            -- ocurrir, pero si ocurre conviene un diagnostico util.
            DBMS_OUTPUT.PUT_LINE('    Hay un viaje cuyo bus no tiene asientos ' ||
                                 'registrados: revisar los datos de flota.');
    END sp_disponibilidad;

END pkg_consultas;
/
SHOW ERRORS
