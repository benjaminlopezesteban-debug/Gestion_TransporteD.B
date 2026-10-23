--------------------------------------------------------------------------------
-- Modelo_GestionTransporte  |  Script PL/SQL - Parte 5
-- TRIGGERS: auditoria e integridad del ciclo de vida del pasaje
--
-- Requisito : DDL cargado. Debe existir ANTES de EJECUTAR los procedimientos
--             de 04_Procedimiento.sql, que dependen de el para dejar rastro.
-- Motor     : Oracle Database
--------------------------------------------------------------------------------
-- TRAZABILIDAD CON LA DOCUMENTACION
--
--   Informe  : DP_Informe_Requerimiento.docx
--                11   Triggers (identificacion, justificacion, precauciones)
--                2.4  RN-08 ciclo de estados del pasaje
--                4.2  Trazabilidad regla-mecanismo
--   Anexo    : Tabla 5 (RN-08), Tabla 23 (PASAJE_ESTADO_HIST)
--   Requisito: RF-01 y RF-02 dependen de el para dejar rastro
--   Regla    : RN-08 - un pasaje esta vendido, utilizado, anulado o pendiente
--   Rubrica  : IE1.4.1 - evaluacion de triggers (15% informe / 15% presentacion)
--
--------------------------------------------------------------------------------
-- POR QUE UN TRIGGER Y NO CODIGO EN CADA PROCEDIMIENTO
--
-- El historial de estados debe registrarse SIEMPRE que un pasaje cambie, sin
-- importar quien lo modifique. Si la insercion viviera dentro de cada
-- procedimiento, bastaria un UPDATE manual desde SQL*Plus, una carga masiva o un
-- procedimiento nuevo que alguien olvide instrumentar para que la transicion se
-- pierda en silencio. El trigger se dispara por el evento, no por la llamada, de
-- modo que la trazabilidad no depende de la disciplina de quien escribe el
-- codigo.
--
-- Es el mismo criterio con que RN-06 se resolvio en el indice unico y no en una
-- validacion: la regla se cumple aunque el dato entre por otra via.
--
-- CONSECUENCIA PARA EL NIVEL 3
--
-- Los procedimientos de pkg_operaciones NO deben insertar en
-- PASAJE_ESTADO_HIST. Si lo hicieran, cada transicion quedaria registrada dos
-- veces: una por el procedimiento y otra por el trigger.
--
-- ORDEN DE EJECUCION
--
-- El poblamiento del DDL inserta el historial a mano, y eso es correcto: en ese
-- momento el trigger todavia no existe. Al recargar el DDL, el DROP TABLE de
-- PASAJE elimina el trigger junto con la tabla, de modo que la secuencia
-- DDL -> trigger -> operaciones siempre queda consistente.
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 140

--------------------------------------------------------------------------------
-- LIMITACION DE LOS TRIGGERS Y COMO SE RESUELVE AQUI
--
-- Un trigger no recibe parametros: se dispara por un evento, no por una llamada.
-- Eso plantea un problema concreto con el motivo de la anulacion, que solo
-- conoce quien ejecuta la operacion.
--
-- La solucion es pasarlo por el contexto de la sesion. El procedimiento declara
-- el motivo con DBMS_APPLICATION_INFO.SET_CLIENT_INFO antes de modificar el
-- pasaje, y el trigger lo lee con SYS_CONTEXT. No es una variable global del
-- programa sino un dato de la sesion, que Oracle mantiene aislado entre sesiones
-- concurrentes.
--
-- Si nadie lo declara, el motivo queda nulo, que es lo correcto: una venta no
-- necesita motivo, una anulacion si.
--------------------------------------------------------------------------------
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


--------------------------------------------------------------------------------
-- TRIGGER 2: trg_pasaje_no_revive
--
-- Proposito distinto al anterior, y por eso vale la pena tenerlos separados:
-- el primero AUDITA -registra lo que paso sin impedir nada-, este otro CUIDA LA
-- INTEGRIDAD -impide que algo pase-.
--
-- La regla: un pasaje anulado no vuelve atras. RN-08 define cuatro estados, pero
-- no todas las transiciones entre ellos tienen sentido. Que un pasaje pase de
-- ANULADO a VENDIDO significaria que alguien recupero un cupo que el sistema ya
-- devolvio a la disponibilidad, y que probablemente ya se vendio a otra persona.
--
-- POR QUE UN TRIGGER Y NO UNA VALIDACION EN sp_anular_pasaje
--
-- Porque el procedimiento solo protege el camino que pasa por el. Esta regla
-- debe cumplirse tambien si alguien ejecuta un UPDATE a mano desde SQL Developer
-- o si se escribe un procedimiento nuevo que nadie penso instrumentar. Es el
-- mismo criterio con que RN-06 se resolvio en un indice unico y no en codigo.
--
-- POR QUE BEFORE Y NO AFTER
--
-- Un trigger de integridad debe impedir el cambio, no reaccionar a el. BEFORE
-- levanta el error antes de que la fila se modifique; AFTER llegaria tarde y
-- obligaria a deshacer.
--
-- La clausula WHEN filtra en el propio motor: el cuerpo solo se ejecuta en las
-- transiciones que salen de ANULADO. Es mas barato que preguntar dentro del
-- cuerpo y deja la condicion visible en la declaracion.
--------------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_pasaje_no_revive
    BEFORE UPDATE OF id_estado ON pasaje
    FOR EACH ROW
    WHEN (OLD.id_estado = 4 AND NEW.id_estado <> 4)   -- 4 = ANU
BEGIN
    RAISE_APPLICATION_ERROR(-20008,
        'RN-08: el pasaje ' || :OLD.id_pasaje || ' esta anulado y no puede ' ||
        'volver al estado ' || :NEW.id_estado || '. Su asiento ya fue liberado ' ||
        'y pudo venderse a otro pasajero.');
END;
/

SHOW ERRORS

--------------------------------------------------------------------------------
-- VERIFICACION DE LOS DOS TRIGGERS
--------------------------------------------------------------------------------
DECLARE
    c_pasaje  CONSTANT pasaje.id_pasaje%TYPE := 8;   -- pendiente de pago (PEN)
    v_antes   PLS_INTEGER;
    v_despues PLS_INTEGER;
    v_ultimo  pasaje_estado_hist.id_estado%TYPE;
    v_motivo  pasaje_estado_hist.motivo%TYPE;
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== Verificacion de los triggers ===');

    ----------------------------------------------------------------------------
    -- trg_pasaje_historial: registra la transicion y toma el motivo del contexto
    ----------------------------------------------------------------------------
    SELECT COUNT(*) INTO v_antes
    FROM   pasaje_estado_hist WHERE id_pasaje = c_pasaje;

    DBMS_APPLICATION_INFO.SET_CLIENT_INFO('Prueba de auditoria automatica');
    UPDATE pasaje SET id_estado = 2 WHERE id_pasaje = c_pasaje;   -- PEN -> VEN

    SELECT COUNT(*) INTO v_despues
    FROM   pasaje_estado_hist WHERE id_pasaje = c_pasaje;

    SELECT id_estado, motivo INTO v_ultimo, v_motivo
    FROM   pasaje_estado_hist
    WHERE  id_pasaje = c_pasaje
    AND    secuencia = (SELECT MAX(secuencia) FROM pasaje_estado_hist
                        WHERE id_pasaje = c_pasaje);

    DBMS_OUTPUT.PUT_LINE('  historial del pasaje ' || c_pasaje || ': ' ||
                         v_antes || ' -> ' || v_despues || ' fila(s)');
    DBMS_OUTPUT.PUT_LINE('  ultimo estado ' || v_ultimo ||
                         ' | motivo: ' || NVL(v_motivo,'(sin motivo)'));

    -- Un UPDATE que no cambia el estado NO debe generar historial
    UPDATE pasaje SET id_estado = 2 WHERE id_pasaje = c_pasaje;
    SELECT COUNT(*) INTO v_despues
    FROM   pasaje_estado_hist WHERE id_pasaje = c_pasaje;
    DBMS_OUTPUT.PUT_LINE('  tras UPDATE sin cambio de estado: ' || v_despues ||
                         ' fila(s), no aumento');

    DBMS_APPLICATION_INFO.SET_CLIENT_INFO(NULL);

    ----------------------------------------------------------------------------
    -- trg_pasaje_no_revive: impide resucitar un pasaje anulado
    ----------------------------------------------------------------------------
    UPDATE pasaje SET id_estado = 4 WHERE id_pasaje = c_pasaje;   -- VEN -> ANU
    BEGIN
        UPDATE pasaje SET id_estado = 2 WHERE id_pasaje = c_pasaje;  -- ANU -> VEN
        DBMS_OUTPUT.PUT_LINE('  FALLO: se permitio revivir un pasaje anulado');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20008 THEN
                DBMS_OUTPUT.PUT_LINE('  trg_pasaje_no_revive impidio la transicion ANU -> VEN');
            ELSE
                RAISE;
            END IF;
    END;

    ROLLBACK;   -- la prueba no deja rastro
    DBMS_OUTPUT.PUT_LINE('  ROLLBACK aplicado: los datos de prueba quedan intactos');
END;
/
