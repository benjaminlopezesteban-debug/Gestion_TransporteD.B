CREATE OR REPLACE PACKAGE pkg_programacion_conductor IS

    -- ¿Cuántos conductores exige un viaje de esta ruta? (RN-10)
    FUNCTION fn_conductores_requeridos (
        p_id_ruta IN ruta.id_ruta%TYPE
    ) RETURN PLS_INTEGER;

    -- ¿Está libre este conductor en el intervalo? (RN-03)
    FUNCTION fn_conductor_disponible (
        p_id_conductor IN conductor.id_conductor%TYPE,
        p_salida       IN viaje.salida_prog%TYPE,
        p_llegada      IN viaje.llegada_prog%TYPE,
        p_excluir      IN viaje.id_viaje%TYPE DEFAULT NULL
    ) RETURN BOOLEAN;

    -- Asignación manual de UN conductor (rol TIT o REL)
    PROCEDURE pr_asignar_conductor (
        p_id_viaje     IN viaje.id_viaje%TYPE,
        p_id_conductor IN conductor.id_conductor%TYPE,
        p_rol          IN viaje_conductor.rol%TYPE DEFAULT 'TIT'
    );

END pkg_programacion_conductor;
/

CREATE OR REPLACE PACKAGE BODY pkg_programacion_conductor IS
    ----------------------------------------------------------------------------
    -- 1. Cantidad de conductores requeridos (RN-10)
    ----------------------------------------------------------------------------
    FUNCTION fn_conductores_requeridos (
        p_id_ruta IN ruta.id_ruta%TYPE
    ) RETURN PLS_INTEGER
    IS
        c_max_horas    CONSTANT NUMBER := 5;
        v_duracion_min ruta.duracion_estimada_min%TYPE;
    BEGIN
        SELECT r.duracion_estimada_min INTO v_duracion_min
        FROM   ruta r WHERE r.id_ruta = p_id_ruta;

        RETURN CEIL(v_duracion_min / 60 / c_max_horas);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20030, 'Ruta ' || p_id_ruta || ' no existe.');
    END fn_conductores_requeridos;
    ----------------------------------------------------------------------------
    -- 2. Disponibilidad: conductor libre en el intervalo
    ----------------------------------------------------------------------------
    FUNCTION fn_conductor_disponible (
        p_id_conductor IN conductor.id_conductor%TYPE,
        p_salida       IN viaje.salida_prog%TYPE,
        p_llegada      IN viaje.llegada_prog%TYPE,
        p_excluir      IN viaje.id_viaje%TYPE DEFAULT NULL
    ) RETURN BOOLEAN
    IS
        v_ocupado NUMBER;
    BEGIN
        SELECT COUNT(*)
        INTO   v_ocupado
        FROM   viaje_conductor vc
        JOIN   viaje v ON v.id_viaje = vc.id_viaje
        WHERE  vc.id_conductor = p_id_conductor
        AND    v.estado_viaje <> 'CAN'
        AND    (p_excluir IS NULL OR v.id_viaje <> p_excluir)
        AND    v.salida_prog  < p_llegada
        AND    v.llegada_prog > p_salida;

        RETURN v_ocupado = 0;
    END fn_conductor_disponible;
    ----------------------------------------------------------------------------
    -- 3. Asignación MANUAL de un conductor
    ----------------------------------------------------------------------------
    PROCEDURE pr_asignar_conductor (
        p_id_viaje     IN viaje.id_viaje%TYPE,
        p_id_conductor IN conductor.id_conductor%TYPE,
        p_rol          IN viaje_conductor.rol%TYPE DEFAULT 'TIT'
    )
    IS
        v_salida  viaje.salida_prog%TYPE;
        v_llegada viaje.llegada_prog%TYPE;
        v_existe  NUMBER;
    BEGIN
        -- Validar que el viaje exista
        BEGIN
            SELECT salida_prog, llegada_prog
            INTO   v_salida, v_llegada
            FROM   viaje WHERE id_viaje = p_id_viaje;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20035,
                    'Viaje ' || p_id_viaje || ' no existe.');
        END;

        -- Validar que el conductor exista
        SELECT COUNT(*) INTO v_existe
        FROM   conductor WHERE id_conductor = p_id_conductor;
        IF v_existe = 0 THEN
            RAISE_APPLICATION_ERROR(-20031,
                'Conductor ' || p_id_conductor || ' no existe.');
        END IF;

        -- Validar solapamiento (RN-03)
        IF NOT fn_conductor_disponible(p_id_conductor, v_salida, v_llegada, p_id_viaje) THEN
            RAISE_APPLICATION_ERROR(-20032,
                'Conductor ' || p_id_conductor ||
                ' ya tiene un viaje en ese intervalo.');
        END IF;

        INSERT INTO viaje_conductor (id_viaje, id_conductor, rol)
        VALUES (p_id_viaje, p_id_conductor, p_rol);
    END pr_asignar_conductor;

END pkg_programacion_conductor;
/
-- Listar Disponibilidad Y Ver conductores requeridos
DECLARE
    v_ruta       ruta.id_ruta%TYPE      := 7;
    v_salida     viaje.salida_prog%TYPE := TIMESTAMP '2026-11-10 08:00:00';
    v_llegada    viaje.llegada_prog%TYPE;
    v_requeridos PLS_INTEGER;
BEGIN
    v_llegada    := pkg_programacion_viaje.fn_llegada_prog(v_ruta, v_salida);
    v_requeridos := pkg_programacion_conductor.fn_conductores_requeridos(v_ruta);

    DBMS_OUTPUT.PUT_LINE(
        'Ventana: ' || TO_CHAR(v_salida, 'YYYY-MM-DD HH24:MI') ||
        ' - '       || TO_CHAR(v_llegada, 'YYYY-MM-DD HH24:MI')
    );
    DBMS_OUTPUT.PUT_LINE(
        'Ruta ' || v_ruta || ' requiere ' || v_requeridos || ' conductor(es)'
    );
    DBMS_OUTPUT.PUT_LINE('Conductores disponibles:');

    FOR r IN (
        SELECT c.id_conductor,
               c.pnombre || ' ' || c.papellido AS nombre
        FROM   conductor c
        WHERE  NOT EXISTS (
            SELECT 1 FROM viaje_conductor vc
            JOIN   viaje v ON v.id_viaje = vc.id_viaje
            WHERE  vc.id_conductor = c.id_conductor
            AND    v.estado_viaje <> 'CAN'
            AND    v.salida_prog  < v_llegada
            AND    v.llegada_prog > v_salida
        )
        ORDER BY c.id_conductor
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('  ID: ' || r.id_conductor || ' | ' || r.nombre);
    END LOOP;
END;
/
--Asginación Manual
DECLARE
    v_id_viaje viaje.id_viaje%TYPE         := &id_viaje;
    v_id_tit   conductor.id_conductor%TYPE := &id_titular;
    v_id_rel   conductor.id_conductor%TYPE := &id_relevo;  -- dejar vacío si es 1
    v_requeridos PLS_INTEGER;
    v_id_ruta  viaje.id_ruta%TYPE;
BEGIN
    SELECT id_ruta INTO v_id_ruta FROM viaje WHERE id_viaje = v_id_viaje;
    v_requeridos := pkg_programacion_conductor.fn_conductores_requeridos(v_id_ruta);

    -- Titular (siempre obligatorio)
    pkg_programacion_conductor.pr_asignar_conductor(v_id_viaje, v_id_tit, 'TIT');

    -- Relevo solo si la ruta lo exige
    IF v_requeridos > 1 AND v_id_rel IS NOT NULL THEN
        pkg_programacion_conductor.pr_asignar_conductor(v_id_viaje, v_id_rel, 'REL');
    END IF;

    IF v_requeridos > 1 AND v_id_rel IS NULL THEN
        RAISE_APPLICATION_ERROR(-20036,
            'La ruta requiere ' || v_requeridos || ' conductores; falta el relevo.');
    END IF;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Conductores asignados manualmente.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        RAISE;
END;
/