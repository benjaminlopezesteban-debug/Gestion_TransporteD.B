--------------------------------------------------------------------------------
-- Modelo_GestionTransporte  |  Script PL/SQL - Parte 1
-- Tipos de datos compuestos: RECORD y VARRAY
--
-- Requisito : haber ejecutado 02_Scripts/DDL/Modelo_GestionTransporte_DDL.sql
-- Motor     : Oracle Database
--
-- Nota de alcance: los tipos compuestos se declaran dentro de bloques anonimos,
-- que es donde el curso los aborda (RA1). Cuando el proyecto incorpore packages
-- (RA2), estos mismos tipos se trasladaran a la especificacion del package para
-- que sean reutilizables entre programas.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- TRAZABILIDAD CON LA DOCUMENTACION
--
--   Informe  : DP_Informe_Requerimiento.docx, seccion 5 (Tipos de Datos Compuestos)
--                5.1 Uso de RECORD        -> bloques 2.1 y 2.2
--                5.2 Uso de VARRAY        -> bloque  2.3
--                5.3 Justificacion tecnica-> bloque  2.4
--   Anexo    : ANEXO_Tablas_de_Referencia.docx
--                Tablas 10 a 23 (diccionario de datos, tipos de cada columna)
--   Requisito: RF-01 (venta de pasajes)
--   Rubrica  : IE1.1.1 - tipos de datos compuestos (5% informe / 15% presentacion)
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 140
SET PAGESIZE 60


--------------------------------------------------------------------------------
-- 2. TIPOS DE DATOS COMPUESTOS
--
-- El proyecto usa dos estructuras compuestas y resuelven problemas distintos.
-- La distincion importa, porque no se trata de emplear ambas por figurar en el
-- temario, sino de que cada una responde a una necesidad que la otra no cubre:
--
--   RECORD  agrupa atributos HETEROGENEOS de una misma entidad. Un pasaje tiene
--           un viaje, un asiento y un precio, y cada uno es de un tipo distinto.
--           Se manipulan siempre juntos porque describen una sola cosa.
--
--   VARRAY  agrupa elementos HOMOGENEOS sobre los que se itera. Los asientos que
--           un cliente solicita en una compra son todos del mismo tipo y su
--           cantidad tiene un limite conocido.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- 2.1 RECORD - estructura del pasaje a emitir  (requerimiento RF-01)
-- Informe: seccion 5.1   |   Rubrica: IE1.1.1
--
-- Problema que resuelve: el proceso de venta construye cada pasaje a partir de
-- siete atributos que solo tienen sentido juntos. Sin RECORD habria que declarar
-- siete variables sueltas y pasarlas una por una a cada validacion y a cada
-- INSERT. Cada punto donde se enumeran es un lugar donde se puede olvidar una al
-- modificar el proceso, y el compilador no avisaria.
--
-- Alternativa descartada: variables escalares independientes. Se descarto por lo
-- anterior, no por preferencia de estilo. Si el proceso necesitara un unico dato
-- -por ejemplo contar asientos libres- un RECORD estaria de mas y bastaria una
-- variable escalar.
--------------------------------------------------------------------------------
DECLARE
    -- El tipo describe la unidad de informacion "pasaje por emitir".
    TYPE tr_pasaje IS RECORD (
        id_viaje         viaje.id_viaje%TYPE,
        id_bus           bus.id_bus%TYPE,
        nro_asiento      asiento.nro_asiento%TYPE,
        id_pasajero      pasajero.id_pasajero%TYPE,
        id_tarifa        tarifa.id_tarifa%TYPE,
        precio_aplicado  pasaje.precio_aplicado%TYPE,
        id_estado        estado_pasaje.id_estado%TYPE
    );

    -- Cada campo se declara con %TYPE, anclado a la columna que le corresponde.
    -- Asi, si manana cambia el largo o la precision de una columna, el bloque
    -- sigue compilando sin tocarlo. Es mantenimiento que se evita por diseno.
    r_pasaje  tr_pasaje;

BEGIN
    -- Se carga el RECORD como una unidad. A partir de aqui el pasaje viaja
    -- por el programa en una sola variable.
    r_pasaje.id_viaje        := 6;    -- Santiago - Concepcion del 03-09
    r_pasaje.id_bus          := 1;
    r_pasaje.nro_asiento     := 5;
    r_pasaje.id_pasajero     := 3;
    r_pasaje.id_estado       := 1;    -- PEN, pendiente de pago

    -- El precio no se inventa: se toma de la tarifa vigente para la ruta del
    -- viaje y el tipo del asiento solicitado.
    SELECT tf.id_tarifa, tf.precio
    INTO   r_pasaje.id_tarifa, r_pasaje.precio_aplicado
    FROM   tarifa  tf
    JOIN   viaje   v ON v.id_ruta         = tf.id_ruta
    JOIN   asiento a ON a.id_tipo_asiento = tf.id_tipo_asiento
    WHERE  v.id_viaje    = r_pasaje.id_viaje
    AND    a.id_bus      = r_pasaje.id_bus
    AND    a.nro_asiento = r_pasaje.nro_asiento
    AND    tf.vigencia_desde <= TRUNC(SYSDATE)
    AND   (tf.vigencia_hasta IS NULL OR tf.vigencia_hasta >= TRUNC(SYSDATE));

    DBMS_OUTPUT.PUT_LINE('--- 2.1 RECORD cargado como unidad ---');
    DBMS_OUTPUT.PUT_LINE('  Viaje '      || r_pasaje.id_viaje    ||
                         ' | bus '       || r_pasaje.id_bus      ||
                         ' | asiento '   || r_pasaje.nro_asiento ||
                         ' | tarifa '    || r_pasaje.id_tarifa   ||
                         ' | precio $'   || TO_CHAR(r_pasaje.precio_aplicado, 'FM999G999'));
END;
/

--------------------------------------------------------------------------------
-- 2.2 RECORD anclado con %ROWTYPE
-- Informe: seccion 5.1   |   Rubrica: IE1.1.1
--
-- Cuando la estructura debe reflejar EXACTAMENTE una tabla o vista, no se
-- declara campo por campo: se ancla con %ROWTYPE. La ventaja es la misma que
-- ofrece %TYPE, pero a nivel de fila completa: si la tabla gana o pierde una
-- columna, el RECORD se ajusta solo.
--
-- Cuando conviene cada uno: %ROWTYPE si se necesita la fila completa tal como
-- esta en la base; RECORD explicito -como el de 2.1- si la estructura combina
-- campos de varias tablas o incluye datos calculados que no existen como
-- columna.
--------------------------------------------------------------------------------
DECLARE
    r_ruta   ruta%ROWTYPE;    -- toma la fila completa tal como esta en la tabla
    v_horas  NUMBER;
BEGIN
    SELECT * INTO r_ruta FROM ruta WHERE id_ruta = 7;
    v_horas := ROUND(r_ruta.duracion_estimada_min / 60, 2);

    DBMS_OUTPUT.PUT_LINE('--- 2.2 RECORD anclado con %ROWTYPE ---');
    DBMS_OUTPUT.PUT_LINE('  Ruta ' || r_ruta.id_ruta ||
                         ' | ' || r_ruta.distancia_km || ' km' ||
                         ' | ' || v_horas || ' h' ||
                         ' | exige ' || CEIL(v_horas / 5) || ' conductor(es)');
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('  La ruta consultada no existe en el catalogo.');
END;
/

--------------------------------------------------------------------------------
-- 2.3 VARRAY - asientos solicitados en una compra  (requerimiento RF-01)
-- Informe: seccion 5.2   |   Rubrica: IE1.1.1
--
-- Problema que resuelve: una venta puede cubrir varios asientos y todos deben
-- validarse ANTES de confirmarla, porque si uno solo no esta disponible la
-- operacion completa no procede. Esa lista necesita recorrerse como coleccion.
--
-- Por que VARRAY y no una tabla anidada: porque la cantidad de elementos tiene
-- un limite conocido y razonable. La empresa no vende mas de 6 asientos en una
-- sola transaccion de mostrador, y en ningun caso podria superar la capacidad
-- del bus. El VARRAY declara ese limite EN EL TIPO, de modo que la restriccion
-- comercial queda expresada en la estructura de datos y no depende de una
-- validacion que alguien pueda omitir. Una tabla anidada no impone cota alguna.
--
-- Cuando la eleccion se invertiria: si el conjunto a procesar pudiera crecer de
-- forma indeterminada -por ejemplo, todos los pasajes de un viaje para un
-- proceso masivo- el VARRAY dejaria de ser apropiado y la tabla anidada o una
-- coleccion asociativa serian la opcion correcta.
--------------------------------------------------------------------------------
DECLARE
    -- El 6 no es arbitrario: es el maximo de asientos por transaccion que
    -- define la politica comercial de la empresa.
    TYPE tv_asientos IS VARRAY(6) OF asiento.nro_asiento%TYPE;

    v_solicitados  tv_asientos := tv_asientos(3, 5, 8);   -- constructor
    v_libre        NUMBER;
    v_ocupados     PLS_INTEGER := 0;

    c_viaje  CONSTANT viaje.id_viaje%TYPE := 6;
    c_bus    CONSTANT bus.id_bus%TYPE     := 1;
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- 2.3 VARRAY de asientos solicitados ---');
    DBMS_OUTPUT.PUT_LINE('  Limite del tipo: ' || v_solicitados.LIMIT ||
                         ' | solicitados: '    || v_solicitados.COUNT);

    -- Se recorre la coleccion validando asiento por asiento. FIRST y LAST
    -- delimitan el recorrido sin depender de un contador escrito a mano.
    FOR i IN v_solicitados.FIRST .. v_solicitados.LAST LOOP

        -- Un asiento esta ocupado si tiene un pasaje en estado que ocupa
        -- asiento. Es la misma condicion que aplica el indice unico parcial.
        SELECT COUNT(*)
        INTO   v_libre
        FROM   pasaje p
        JOIN   estado_pasaje ep ON ep.id_estado = p.id_estado
        WHERE  p.id_viaje    = c_viaje
        AND    p.id_bus      = c_bus
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

--------------------------------------------------------------------------------
-- 2.4 RECORD y VARRAY trabajando juntos
-- Informe: seccion 5.3   |   Rubrica: IE1.1.1
--
-- Demuestra la division de responsabilidades entre ambas estructuras: el VARRAY
-- aporta QUE asientos procesar y el RECORD describe COMO queda cada pasaje que
-- resulta de ellos. Es el esqueleto del procedimiento de venta que se
-- desarrollara mas adelante.
--------------------------------------------------------------------------------
DECLARE
    TYPE tr_pasaje IS RECORD (
        id_viaje         viaje.id_viaje%TYPE,
        id_bus           bus.id_bus%TYPE,
        nro_asiento      asiento.nro_asiento%TYPE,
        -- El campo NO puede llamarse tipo_asiento: colisionaria con la tabla
        -- homonima y PL/SQL resolveria el identificador contra el campo que
        -- esta declarando, no contra la tabla (PLS-00320).
        nombre_tipo      tipo_asiento.nombre%TYPE,
        precio_aplicado  pasaje.precio_aplicado%TYPE
    );
    TYPE tv_asientos IS VARRAY(6) OF asiento.nro_asiento%TYPE;

    r_pasaje       tr_pasaje;
    v_solicitados  tv_asientos := tv_asientos(1, 2, 9);
    v_total        NUMBER := 0;

    c_viaje  CONSTANT viaje.id_viaje%TYPE := 6;   -- Santiago - Concepcion
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- 2.4 RECORD + VARRAY: simulacion de una venta ---');

    r_pasaje.id_viaje := c_viaje;
    SELECT id_bus INTO r_pasaje.id_bus FROM viaje WHERE id_viaje = c_viaje;

    FOR i IN 1 .. v_solicitados.COUNT LOOP
        r_pasaje.nro_asiento := v_solicitados(i);

        -- Se completa el RECORD con el tipo del asiento y su tarifa vigente.
        SELECT ta.nombre, tf.precio
        INTO   r_pasaje.nombre_tipo, r_pasaje.precio_aplicado
        FROM   asiento a
        JOIN   tipo_asiento ta ON ta.id_tipo_asiento = a.id_tipo_asiento
        JOIN   viaje v         ON v.id_viaje = r_pasaje.id_viaje
        JOIN   tarifa tf ON tf.id_ruta         = v.id_ruta
                        AND tf.id_tipo_asiento = a.id_tipo_asiento
        WHERE  a.id_bus = r_pasaje.id_bus
        AND    a.nro_asiento = r_pasaje.nro_asiento
        AND    tf.vigencia_desde <= TRUNC(SYSDATE)
        AND   (tf.vigencia_hasta IS NULL OR tf.vigencia_hasta >= TRUNC(SYSDATE));

        v_total := v_total + r_pasaje.precio_aplicado;

        DBMS_OUTPUT.PUT_LINE('  Asiento ' || LPAD(r_pasaje.nro_asiento, 2) ||
                             ' | ' || RPAD(r_pasaje.nombre_tipo, 14) ||
                             ' | $' || TO_CHAR(r_pasaje.precio_aplicado, 'FM999G999'));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('  Total de la venta: $' || TO_CHAR(v_total, 'FM999G999'));
END;
/
