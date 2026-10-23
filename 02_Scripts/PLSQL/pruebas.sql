CREATE OR REPLACE PACKAGE pkg_programacion_viaje IS

    -- Calcula la llegada a partir de la duración estimada de la ruta.
    FUNCTION fn_llegada_prog (
        p_id_ruta     IN ruta.id_ruta%TYPE,
        p_salida_prog IN viaje.salida_prog%TYPE
    ) RETURN viaje.llegada_prog%TYPE;

    -- Registro para representar el intervalo del viaje.
    TYPE tr_bloque IS RECORD (
        inicio_prog  viaje.salida_prog%TYPE,
        llegada_prog viaje.llegada_prog%TYPE
    );

    -- Registra un viaje y devuelve su identificador.
    PROCEDURE pr_registrar_viaje (
        p_id_ruta      IN  viaje.id_ruta%TYPE,
        p_id_bus       IN  viaje.id_bus%TYPE,
        p_salida_prog  IN  viaje.salida_prog%TYPE,
        p_llegada_prog IN  viaje.llegada_prog%TYPE DEFAULT NULL,
        p_estado_viaje IN  viaje.estado_viaje%TYPE DEFAULT 'PRO',
        p_id_viaje     OUT viaje.id_viaje%TYPE
    );

END pkg_programacion_viaje;
/
CREATE OR REPLACE PACKAGE BODY pkg_programacion_viaje IS

    ------------------------------------------------------------------
    -- FUNCIÓN: calcular la llegada programada
    ------------------------------------------------------------------
    FUNCTION fn_llegada_prog (
        p_id_ruta     IN ruta.id_ruta%TYPE,
        p_salida_prog IN viaje.salida_prog%TYPE
    ) RETURN viaje.llegada_prog%TYPE
    IS
        v_duracion_min ruta.duracion_estimada_min%TYPE;
    BEGIN
        IF p_salida_prog IS NULL THEN
            RAISE_APPLICATION_ERROR(
                -20001,
                'La fecha y hora de salida son obligatorias.'
            );
        END IF;

        SELECT duracion_estimada_min
        INTO v_duracion_min
        FROM ruta
        WHERE id_ruta = p_id_ruta;

        RETURN p_salida_prog
               + NUMTODSINTERVAL(v_duracion_min, 'MINUTE');

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(
                -20002,
                'La ruta ' || p_id_ruta || ' no existe.'
            );
    END fn_llegada_prog;


    ------------------------------------------------------------------
    -- PROCEDIMIENTO: registrar un viaje
    ------------------------------------------------------------------
    PROCEDURE pr_registrar_viaje (
        p_id_ruta      IN  viaje.id_ruta%TYPE,
        p_id_bus       IN  viaje.id_bus%TYPE,
        p_salida_prog  IN  viaje.salida_prog%TYPE,
        p_llegada_prog IN  viaje.llegada_prog%TYPE DEFAULT NULL,
        p_estado_viaje IN  viaje.estado_viaje%TYPE DEFAULT 'PRO',
        p_id_viaje     OUT viaje.id_viaje%TYPE
    )
    IS
        v_llegada     viaje.llegada_prog%TYPE;
        v_existe      NUMBER;
        v_bus_ocupado NUMBER;
    BEGIN
        p_id_viaje := NULL;

        --------------------------------------------------------------
        -- 1. Validar los datos básicos
        --------------------------------------------------------------
        IF p_salida_prog IS NULL THEN
            RAISE_APPLICATION_ERROR(
                -20003,
                'Debe indicar la fecha y hora de salida.'
            );
        END IF;

        --------------------------------------------------------------
        -- 2. Verificar que la ruta exista
        --------------------------------------------------------------
        SELECT COUNT(*)
        INTO v_existe
        FROM ruta
        WHERE id_ruta = p_id_ruta;

        IF v_existe = 0 THEN
            RAISE_APPLICATION_ERROR(
                -20010,
                'La ruta ' || p_id_ruta || ' no existe.'
            );
        END IF;

        --------------------------------------------------------------
        -- 3. Verificar que el bus exista
        --------------------------------------------------------------
        SELECT COUNT(*)
        INTO v_existe
        FROM bus
        WHERE id_bus = p_id_bus;

        IF v_existe = 0 THEN
            RAISE_APPLICATION_ERROR(
                -20011,
                'El bus ' || p_id_bus || ' no existe.'
            );
        END IF;

        --------------------------------------------------------------
        -- 4. Calcular o aceptar la llegada
        --------------------------------------------------------------
        IF p_llegada_prog IS NULL THEN
            v_llegada :=
                pkg_programacion_viaje.fn_llegada_prog(
                    p_id_ruta,
                    p_salida_prog
                );
        ELSE
            v_llegada := p_llegada_prog;
        END IF;

        --------------------------------------------------------------
        -- 5. Validar el intervalo
        --------------------------------------------------------------
        IF v_llegada <= p_salida_prog THEN
            RAISE_APPLICATION_ERROR(
                -20013,
                'La llegada debe ser posterior a la salida.'
            );
        END IF;

        --------------------------------------------------------------
        -- 6. Comprobar disponibilidad del bus
        -- Los viajes cancelados no bloquean el intervalo.
        --------------------------------------------------------------
        SELECT COUNT(*)
        INTO v_bus_ocupado
        FROM viaje v
        WHERE v.id_bus = p_id_bus
          AND v.estado_viaje <> 'CAN'
          AND v.salida_prog < v_llegada
          AND v.llegada_prog > p_salida_prog;

        IF v_bus_ocupado > 0 THEN
            RAISE_APPLICATION_ERROR(
                -20012,
                'El bus ' || p_id_bus ||
                ' ya tiene un viaje en ese intervalo.'
            );
        END IF;

        --------------------------------------------------------------
        -- 7. Generar el ID e insertar el viaje
        --------------------------------------------------------------
        SELECT seq_viaje.NEXTVAL
        INTO p_id_viaje
        FROM dual;

        INSERT INTO viaje (
            id_viaje,
            id_ruta,
            id_bus,
            salida_prog,
            llegada_prog,
            estado_viaje
        )
        VALUES (
            p_id_viaje,
            p_id_ruta,
            p_id_bus,
            p_salida_prog,
            v_llegada,
            p_estado_viaje
        );

        -- Sin COMMIT: la transacción queda bajo control del llamante.

    END pr_registrar_viaje;

END pkg_programacion_viaje;
/
SET SERVEROUTPUT ON;
--Listar
DECLARE
    r_bloque pkg_programacion_viaje.tr_bloque;

    v_ruta   ruta.id_ruta%TYPE := 7;
    v_inicio viaje.salida_prog%TYPE := TIMESTAMP '2026-11-10 08:00:00';
    v_fin viaje.llegada_prog%TYPE;

    CURSOR c_libres (
        p_ini viaje.salida_prog%TYPE,
        p_fin viaje.llegada_prog%TYPE
    )IS
        SELECT b.id_bus, b.patente, b.modelo
        FROM bus b
        WHERE NOT EXISTS (
            SELECT 1
            FROM viaje v
            WHERE v.id_bus = b.id_bus
              AND v.estado_viaje <> 'CAN'
              AND v.salida_prog < p_fin
              AND v.llegada_prog > p_ini
        )
        ORDER BY b.id_bus;

    v_cantidad PLS_INTEGER := 0;

BEGIN
    v_fin := pkg_programacion_viaje.fn_llegada_prog(
        v_ruta,
        v_inicio
    );

    r_bloque.inicio_prog  := v_inicio;
    r_bloque.llegada_prog := v_fin;

    DBMS_OUTPUT.PUT_LINE(
        'Intervalo: ' ||
        TO_CHAR(r_bloque.inicio_prog, 'YYYY-MM-DD HH24:MI') ||
        ' - ' ||
        TO_CHAR(r_bloque.llegada_prog, 'YYYY-MM-DD HH24:MI')
    );

    DBMS_OUTPUT.PUT_LINE('Buses disponibles:');

    FOR r IN c_libres(
        r_bloque.inicio_prog,
        r_bloque.llegada_prog
    ) LOOP
        v_cantidad := v_cantidad + 1;

        DBMS_OUTPUT.PUT_LINE(
            'ID: ' || r.id_bus ||
            ' | Patente: ' || r.patente ||
            ' | Modelo: ' || r.modelo
        );
    END LOOP;

    IF v_cantidad = 0 THEN
        DBMS_OUTPUT.PUT_LINE(
            'No hay buses disponibles para este intervalo.'
        );
    END IF;
END;
/
--Ejecutar Programación
DECLARE
    v_id_bus   bus.id_bus%TYPE := &id_bus;
    v_id_viaje viaje.id_viaje%TYPE;
    v_ruta   ruta.id_ruta%TYPE := 7;
    v_salida viaje.salida_prog%TYPE := TIMESTAMP '2026-11-10 08:00:00';

BEGIN


    pkg_programacion_viaje.pr_registrar_viaje(
        p_id_ruta     => v_ruta,
        p_id_bus      => v_id_bus,
        p_salida_prog => v_salida,
        p_id_viaje    => v_id_viaje
    );

    DBMS_OUTPUT.PUT_LINE(
        'Viaje programado correctamente. ID: ' || v_id_viaje
    );

    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;

        DBMS_OUTPUT.PUT_LINE(
            'No se pudo programar el viaje: ' || SQLERRM
        );

        RAISE;
END;
/