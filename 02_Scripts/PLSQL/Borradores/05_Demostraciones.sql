--------------------------------------------------------------------------------
-- Modelo_GestionTransporte  |  Script PL/SQL - Parte 5
-- BLOQUES ANONIMOS: tipos compuestos, invocacion de los objetos almacenados
--
-- Requisito : DDL cargado y ejecutados 01_Pkg_Calculos, 02_Pkg_Consultas,
--             03_Pkg_Operaciones y 04_Triggers
-- Motor     : Oracle Database
--------------------------------------------------------------------------------
-- TRAZABILIDAD CON LA DOCUMENTACION
--
--   Informe  : 5.1, 5.2 y 5.3 (RECORD y VARRAY), 7.1 y 7.2 (excepciones),
--              8.2 y 9.2 (implementacion de procedimientos y funciones),
--              10.3 (beneficios del package)
--   Anexo    : Tabla 26 y 27 (excepciones), Tabla 28 y 29 (procedimientos y
--              funciones), Tabla 3 (requerimientos)
--   Rubrica  : IE1.1.1 - RECORD y VARRAY en bloques anonimos (5% / 15%)
--              IE1.3.1 - excepciones predefinidas y de usuario (10% / 15%)
--              IE1.4.1 - procedimientos, funciones, packages y triggers (15% / 15%)
--
--------------------------------------------------------------------------------
-- QUE HACE ESTE ARCHIVO Y POR QUE EXISTE
--
-- La pauta pide dos cosas que no son la misma: bloques PL/SQL ANONIMOS que
-- demuestren RECORD, VARRAY, cursores y excepciones, y la implementacion de
-- procedimientos, funciones, packages y triggers. Este archivo es donde ambas se
-- encuentran: son bloques anonimos que invocan los objetos almacenados.
--
-- Esa combinacion no es un compromiso: es como se usa PL/SQL en la practica. Los
-- objetos almacenados contienen la logica del negocio; los bloques anonimos son
-- el codigo que los orquesta desde afuera -un script de carga, una prueba, una
-- tarea programada-. Demostrar los dos lados es demostrar el sistema completo.
--
-- LOS BLOQUES 1 Y 2 declaran sus PROPIOS tipos, sin usar los del package. Eso es
-- deliberado: muestran RECORD y VARRAY en su forma pura, que es lo que RA1 pide,
-- y ademas dejan ver el problema que el package resuelve -un tipo declarado en
-- un bloque anonimo muere con el bloque-.
--
-- LOS BLOQUES 3 EN ADELANTE usan los tipos y las excepciones del package. Ahi se
-- ve el contraste: la misma estructura, ahora compartible, y las excepciones
-- capturables por nombre desde fuera del procedimiento que las levanta.
--
-- TRANSACCIONES: los procedimientos no hacen COMMIT ni ROLLBACK. Estos bloques
-- si, y siempre ROLLBACK, para que el archivo pueda ejecutarse cuantas veces se
-- quiera sin ensuciar los datos de prueba.
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 140
SET PAGESIZE 60

PROMPT ================================================================
PROMPT  BLOQUES ANONIMOS - DEMOSTRACION
PROMPT ================================================================


--------------------------------------------------------------------------------
-- 1. RECORD en su forma pura, con %TYPE y con %ROWTYPE
--
-- Problema que resuelve: un pasaje se construye a partir de siete atributos que
-- solo tienen sentido juntos. Sin RECORD habria que declarar siete variables
-- sueltas y pasarlas una por una a cada validacion y a cada INSERT. Cada punto
-- donde se enumeran es un lugar donde se puede olvidar una al modificar el
-- proceso, y el compilador no avisaria.
--
-- Alternativa descartada: variables escalares independientes. Se descarto por lo
-- anterior, no por estilo. Si el proceso necesitara un unico dato -contar
-- asientos libres, por ejemplo- un RECORD estaria de mas.
--
-- Los campos se anclan con %TYPE: si manana cambia el largo o la precision de
-- una columna, el bloque sigue compilando sin tocarlo.
--------------------------------------------------------------------------------
DECLARE
    TYPE tr_pasaje IS RECORD (
        id_viaje         viaje.id_viaje%TYPE,
        id_bus           bus.id_bus%TYPE,
        nro_asiento      asiento.nro_asiento%TYPE,
        id_pasajero      pasajero.id_pasajero%TYPE,
        id_tarifa        tarifa.id_tarifa%TYPE,
        precio_aplicado  pasaje.precio_aplicado%TYPE,
        id_estado        estado_pasaje.id_estado%TYPE
    );

    r_pasaje   tr_pasaje;
    r_ruta     ruta%ROWTYPE;      -- la fila completa, tal como esta en la tabla
    v_id_ruta  ruta.id_ruta%TYPE;
    v_id_tipo  tipo_asiento.id_tipo_asiento%TYPE;
BEGIN
    DBMS_OUTPUT.PUT_LINE('1. RECORD');

    -- Se carga como una unidad: a partir de aqui el pasaje viaja por el programa
    -- en una sola variable.
    r_pasaje.id_viaje    := 6;    -- Santiago - Concepcion
    r_pasaje.id_bus      := 1;
    r_pasaje.nro_asiento := 5;
    r_pasaje.id_pasajero := 3;
    r_pasaje.id_estado   := 1;    -- PEN, pendiente de pago

    SELECT v.id_ruta INTO v_id_ruta FROM viaje v WHERE v.id_viaje = r_pasaje.id_viaje;
    SELECT a.id_tipo_asiento INTO v_id_tipo FROM asiento a
    WHERE  a.id_bus = r_pasaje.id_bus AND a.nro_asiento = r_pasaje.nro_asiento;

    -- El precio no se inventa ni se recalcula aqui: lo resuelve la funcion del
    -- package, que es donde vive la regla de vigencia (RN-07).
    r_pasaje.id_tarifa := pkg_calculos.fn_tarifa_vigente(v_id_ruta, v_id_tipo);
    SELECT precio INTO r_pasaje.precio_aplicado
    FROM   tarifa WHERE id_tarifa = r_pasaje.id_tarifa;

    DBMS_OUTPUT.PUT_LINE('   RECORD explicito -> viaje ' || r_pasaje.id_viaje ||
                         ' | asiento ' || r_pasaje.nro_asiento ||
                         ' | tarifa '  || r_pasaje.id_tarifa ||
                         ' | $' || TO_CHAR(r_pasaje.precio_aplicado,'FM999G999'));

    -- %ROWTYPE cuando se necesita la fila completa tal como esta en la base.
    -- RECORD explicito cuando la estructura combina campos de varias tablas o
    -- incluye datos calculados que no existen como columna, como el de arriba.
    SELECT * INTO r_ruta FROM ruta WHERE id_ruta = 7;
    DBMS_OUTPUT.PUT_LINE('   %ROWTYPE          -> ruta ' || r_ruta.id_ruta ||
                         ' | ' || r_ruta.distancia_km || ' km' ||
                         ' | ' || ROUND(r_ruta.duracion_estimada_min/60,2) || ' h');
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('   No hay tarifa vigente para esa combinacion.');
END;
/


--------------------------------------------------------------------------------
-- 2. VARRAY en su forma pura
--
-- Problema que resuelve: una venta puede cubrir varios asientos y todos deben
-- validarse ANTES de confirmarla, porque si uno solo no esta disponible la
-- operacion completa no procede. Esa lista necesita recorrerse como coleccion.
--
-- Por que VARRAY y no una tabla anidada: porque la cantidad de elementos tiene
-- un limite conocido y razonable -la empresa no vende mas de 6 asientos en una
-- transaccion de mostrador-. El VARRAY declara ese limite EN EL TIPO, de modo
-- que la restriccion comercial queda expresada en la estructura de datos y no
-- depende de una validacion que alguien pueda omitir.
--
-- Cuando la eleccion se invertiria: si el conjunto pudiera crecer de forma
-- indeterminada -todos los pasajes de un viaje para un proceso masivo- el VARRAY
-- dejaria de ser apropiado y la tabla anidada seria lo correcto.
--------------------------------------------------------------------------------
DECLARE
    TYPE tv_asientos IS VARRAY(6) OF asiento.nro_asiento%TYPE;

    v_solicitados  tv_asientos := tv_asientos(3, 5, 8);   -- constructor
    v_ocupados     PLS_INTEGER := 0;

    c_viaje  CONSTANT viaje.id_viaje%TYPE := 6;
    c_bus    CONSTANT bus.id_bus%TYPE     := 1;
BEGIN
    DBMS_OUTPUT.PUT_LINE('2. VARRAY');
    DBMS_OUTPUT.PUT_LINE('   limite del tipo: ' || v_solicitados.LIMIT ||
                         ' | solicitados: '     || v_solicitados.COUNT);

    -- FIRST y LAST delimitan el recorrido sin depender de un contador escrito a
    -- mano. Cada asiento se consulta con la funcion del package: es la misma
    -- pregunta puntual que hace la venta real.
    FOR i IN v_solicitados.FIRST .. v_solicitados.LAST LOOP
        IF pkg_calculos.fn_asiento_ocupado(c_viaje, c_bus, v_solicitados(i)) = 'N' THEN
            DBMS_OUTPUT.PUT_LINE('   asiento ' || v_solicitados(i) || ': disponible');
        ELSE
            DBMS_OUTPUT.PUT_LINE('   asiento ' || v_solicitados(i) || ': OCUPADO');
            v_ocupados := v_ocupados + 1;
        END IF;
    END LOOP;

    -- La decision se toma sobre el conjunto completo: o se venden todos o
    -- ninguno.
    IF v_ocupados = 0 THEN
        DBMS_OUTPUT.PUT_LINE('   resultado: la venta puede confirmarse');
    ELSE
        DBMS_OUTPUT.PUT_LINE('   resultado: rechazada, ' || v_ocupados ||
                             ' asiento(s) no disponible(s)');
    END IF;
END;
/


--------------------------------------------------------------------------------
-- 3. Las funciones del package, incluidos sus caminos de error
--
-- Ninguna funcion atrapa sus propias excepciones: las deja propagar para que el
-- invocador decida. Aqui el invocador es este bloque, y decide informar.
--------------------------------------------------------------------------------
DECLARE
    v_id_tarifa  tarifa.id_tarifa%TYPE;
BEGIN
    DBMS_OUTPUT.PUT_LINE('3. Funciones de pkg_calculos');
    DBMS_OUTPUT.PUT_LINE('   conductores_requeridos(6) = ' ||
                         pkg_calculos.fn_conductores_requeridos(6));
    DBMS_OUTPUT.PUT_LINE('   asientos_disponibles(1)   = ' ||
                         pkg_calculos.fn_asientos_disponibles(1));
    DBMS_OUTPUT.PUT_LINE('   porcentaje_ocupacion(1)   = ' ||
                         pkg_calculos.fn_porcentaje_ocupacion(1) || '%');
    DBMS_OUTPUT.PUT_LINE('   asiento_ocupado(1,1,3)    = ' ||
                         pkg_calculos.fn_asiento_ocupado(1,1,3) || ' (vendido)');

    -- Camino de error: la ruta 1 (Rancagua) no tiene tarifa Premium
    BEGIN
        v_id_tarifa := pkg_calculos.fn_tarifa_vigente(1, 3);
        DBMS_OUTPUT.PUT_LINE('   FALLO: se esperaba NO_DATA_FOUND');
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('   NO_DATA_FOUND: ruta 1 sin tarifa Premium');
    END;

    -- Camino de error: viaje inexistente
    BEGIN
        DBMS_OUTPUT.PUT_LINE('   ' || pkg_calculos.fn_conductores_requeridos(999));
        DBMS_OUTPUT.PUT_LINE('   FALLO: se esperaba NO_DATA_FOUND');
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('   NO_DATA_FOUND: el viaje 999 no existe');
    END;
END;
/


--------------------------------------------------------------------------------
-- 4. Los procedimientos de consulta
--------------------------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE('4. Procedimientos de pkg_consultas');
    pkg_consultas.sp_control_flota;
    pkg_consultas.sp_registro_viaje(4);
    pkg_consultas.sp_disponibilidad(
        TO_DATE('01-09-2026','DD-MM-YYYY'),
        TO_DATE('03-09-2026','DD-MM-YYYY') + 1);
END;
/


--------------------------------------------------------------------------------
-- 5. Programacion de un viaje, y el rechazo por jornada insuficiente
--
-- Aqui se ve lo que la especificacion del package habilita: el bloque captura
-- pkg_operaciones.e_jornada_excedida POR NOMBRE. Con la excepcion declarada
-- dentro de un bloque anonimo eso era imposible -habria que capturar OTHERS y
-- leer el texto del mensaje para adivinar que paso-.
--------------------------------------------------------------------------------
DECLARE
    v_conductores  pkg_operaciones.tv_conductores;
    v_id_viaje     viaje.id_viaje%TYPE;
BEGIN
    DBMS_OUTPUT.PUT_LINE('5. pkg_operaciones.sp_programar_viaje');

    -- Caso valido: Concepcion son 6,5 h y exige relevo, se asignan dos
    v_conductores := pkg_operaciones.tv_conductores(1, 3);
    pkg_operaciones.sp_programar_viaje(
        p_id_ruta => 7, p_id_bus => 2,
        p_salida  => TIMESTAMP '2026-09-04 08:00:00',
        p_conductores => v_conductores, p_id_viaje => v_id_viaje);
    DBMS_OUTPUT.PUT_LINE('   viaje ' || v_id_viaje || ' programado con 2 conductores');
    ROLLBACK;

    -- Caso rechazado: la misma ruta con un solo conductor incumple RN-10
    BEGIN
        v_conductores := pkg_operaciones.tv_conductores(1);
        pkg_operaciones.sp_programar_viaje(
            p_id_ruta => 7, p_id_bus => 2,
            p_salida  => TIMESTAMP '2026-09-04 08:00:00',
            p_conductores => v_conductores, p_id_viaje => v_id_viaje);
        DBMS_OUTPUT.PUT_LINE('   FALLO: se esperaba e_jornada_excedida');
        ROLLBACK;
    EXCEPTION
        WHEN pkg_operaciones.e_jornada_excedida THEN
            ROLLBACK;
            DBMS_OUTPUT.PUT_LINE('   e_jornada_excedida: la ruta exige 2 conductores (RN-10)');
    END;
END;
/


--------------------------------------------------------------------------------
-- 6. Venta de pasajes: RECORD y VARRAY del package en la operacion real
--
-- La coleccion se llena con EXTEND y asignacion campo a campo porque los tipos
-- RECORD no tienen constructor, a diferencia de los tipos objeto.
--
-- Se venden tres asientos para tres pasajeros DISTINTOS: es el caso que el
-- modelo original no podia representar, porque el pasajero colgaba de la venta y
-- no del pasaje (RN-05).
--------------------------------------------------------------------------------
DECLARE
    v_solicitudes  pkg_operaciones.tv_solicitudes := pkg_operaciones.tv_solicitudes();
    v_id_venta     venta.id_venta%TYPE;
    v_total        NUMBER;
    v_pasajes      PLS_INTEGER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('6. pkg_operaciones.sp_vender_pasaje');

    v_solicitudes.EXTEND(3);
    v_solicitudes(1).nro_asiento := 3;  v_solicitudes(1).id_pasajero := 1;
    v_solicitudes(2).nro_asiento := 4;  v_solicitudes(2).id_pasajero := 2;
    v_solicitudes(3).nro_asiento := 7;  v_solicitudes(3).id_pasajero := 3;

    pkg_operaciones.sp_vender_pasaje(
        p_id_viaje => 6, p_id_comprador => 1,
        p_solicitudes => v_solicitudes, p_id_venta => v_id_venta);

    SELECT COUNT(*), SUM(precio_aplicado) INTO v_pasajes, v_total
    FROM   pasaje WHERE id_venta = v_id_venta;

    DBMS_OUTPUT.PUT_LINE('   venta ' || v_id_venta || ' | ' || v_pasajes ||
                         ' pasajes | total $' || TO_CHAR(v_total,'FM999G999'));

    -- El trigger dejo rastro sin que el procedimiento se lo pidiera
    SELECT COUNT(*) INTO v_pasajes
    FROM   pasaje_estado_hist h
    JOIN   pasaje p ON p.id_pasaje = h.id_pasaje
    WHERE  p.id_venta = v_id_venta;
    DBMS_OUTPUT.PUT_LINE('   trg_pasaje_historial registro ' || v_pasajes ||
                         ' transicion(es) automaticamente');
    ROLLBACK;

    -- Caso rechazado: el asiento 3 del viaje 1 ya esta vendido
    BEGIN
        v_solicitudes := pkg_operaciones.tv_solicitudes();
        v_solicitudes.EXTEND(1);
        v_solicitudes(1).nro_asiento := 3;  v_solicitudes(1).id_pasajero := 1;
        pkg_operaciones.sp_vender_pasaje(
            p_id_viaje => 1, p_id_comprador => 1,
            p_solicitudes => v_solicitudes, p_id_venta => v_id_venta);
        DBMS_OUTPUT.PUT_LINE('   FALLO: se esperaba un rechazo');
        ROLLBACK;
    EXCEPTION
        WHEN pkg_operaciones.e_viaje_no_programado THEN
            ROLLBACK;
            DBMS_OUTPUT.PUT_LINE('   e_viaje_no_programado: el viaje 1 ya finalizo');
        WHEN pkg_operaciones.e_asiento_no_disponible THEN
            ROLLBACK;
            DBMS_OUTPUT.PUT_LINE('   e_asiento_no_disponible: el asiento ya esta vendido (RN-06)');
    END;
END;
/


--------------------------------------------------------------------------------
-- 7. Anulacion: los dos caminos, y la verificacion de RN-09
--
-- El poblamiento del DDL usa fechas fijas de septiembre de 2026, de modo que con
-- el paso del tiempo todos sus viajes quedan en el pasado y la ventana de cuatro
-- horas nunca puede cumplirse. Para demostrar el camino de exito, el segundo
-- caso PREPARA EL ESCENARIO reprogramando el viaje a futuro dentro de la misma
-- transaccion, y luego revierte todo.
--
-- Es una observacion sobre los datos de prueba, no sobre el diseno: convendria
-- que el poblamiento generara las fechas relativas a SYSDATE.
--------------------------------------------------------------------------------
DECLARE
    c_pasaje  CONSTANT pasaje.id_pasaje%TYPE := 5;   -- viaje 4, bus 3, asiento 6
    v_id_viaje     pasaje.id_viaje%TYPE;
    v_id_bus       pasaje.id_bus%TYPE;
    v_nro_asiento  pasaje.nro_asiento%TYPE;
    v_antes        VARCHAR2(1);
    v_despues      VARCHAR2(1);
    v_hist_antes   PLS_INTEGER;
    v_hist_desp    PLS_INTEGER;
    v_motivo       pasaje_estado_hist.motivo%TYPE;
BEGIN
    DBMS_OUTPUT.PUT_LINE('7. pkg_operaciones.sp_anular_pasaje');

    SELECT id_viaje, id_bus, nro_asiento
    INTO   v_id_viaje, v_id_bus, v_nro_asiento
    FROM   pasaje WHERE id_pasaje = c_pasaje;

    -- CASO A: el viaje ya salio, la ventana de 4 h debe rechazarlo
    BEGIN
        pkg_operaciones.sp_anular_pasaje(c_pasaje, 'Solicitud del pasajero');
        DBMS_OUTPUT.PUT_LINE('   FALLO: se esperaba e_fuera_de_plazo');
        ROLLBACK;
    EXCEPTION
        WHEN pkg_operaciones.e_fuera_de_plazo THEN
            ROLLBACK;
            DBMS_OUTPUT.PUT_LINE('   e_fuera_de_plazo: solo se anula hasta 4 h antes de la salida');
    END;

    -- CASO B: escenario preparado, el viaje sale en 2 dias
    UPDATE viaje SET salida_prog  = SYSTIMESTAMP + INTERVAL '2' DAY,
                     llegada_prog = SYSTIMESTAMP + INTERVAL '2' DAY + INTERVAL '5' HOUR
    WHERE  id_viaje = v_id_viaje;

    v_antes := pkg_calculos.fn_asiento_ocupado(v_id_viaje, v_id_bus, v_nro_asiento);
    SELECT COUNT(*) INTO v_hist_antes
    FROM   pasaje_estado_hist WHERE id_pasaje = c_pasaje;

    pkg_operaciones.sp_anular_pasaje(c_pasaje, 'Cambio de fecha solicitado por el pasajero');

    v_despues := pkg_calculos.fn_asiento_ocupado(v_id_viaje, v_id_bus, v_nro_asiento);
    SELECT COUNT(*) INTO v_hist_desp
    FROM   pasaje_estado_hist WHERE id_pasaje = c_pasaje;

    SELECT motivo INTO v_motivo
    FROM   pasaje_estado_hist
    WHERE  id_pasaje = c_pasaje
    AND    secuencia = (SELECT MAX(secuencia) FROM pasaje_estado_hist
                        WHERE id_pasaje = c_pasaje);

    DBMS_OUTPUT.PUT_LINE('   asiento ' || v_nro_asiento || ' ocupado: ' ||
                         v_antes || ' -> ' || v_despues ||
                         ' | historial: ' || v_hist_antes || ' -> ' || v_hist_desp);
    DBMS_OUTPUT.PUT_LINE('   motivo registrado por el trigger: ' ||
                         NVL(v_motivo,'(sin motivo)'));

    IF v_despues = 'N' AND v_hist_desp = v_hist_antes + 1 THEN
        DBMS_OUTPUT.PUT_LINE('   RN-09 verificada: el asiento se libero y el pasaje ' ||
                             'conserva su registro');
    ELSE
        DBMS_OUTPUT.PUT_LINE('   FALLO en la verificacion de RN-09');
    END IF;

    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('   ROLLBACK aplicado: escenario y operacion revertidos');
END;
/
