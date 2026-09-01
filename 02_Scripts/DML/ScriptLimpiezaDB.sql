--------------------------------------------------------------------------------
-- ScriptLimpiezaDB.sql
--
-- Deja el esquema CONECTADO completamente vacio: tablas, vistas, secuencias,
-- packages, procedimientos, funciones, triggers, tipos, sinonimos, vistas
-- materializadas, jobs y papelera de reciclaje.
--
-- SEGURIDAD
--   * Opera SOLO sobre el esquema del usuario conectado (vistas USER_*).
--     Aunque te conectes como SYSTEM, no toca otros esquemas.
--   * No hace nada hasta que cambies CONFIRMAR de 'NO' a 'SI'.
--   * Con CONFIRMAR = 'NO' funciona como simulacion: lista lo que borraria.
--
-- USO
--   1. Conectate con el usuario cuyo esquema quieres vaciar (ej: benja).
--   2. Ejecuta el script tal cual -> te muestra el inventario sin borrar nada.
--   3. Revisa la lista. Si estas de acuerdo, cambia CONFIRMAR a 'SI'
--      y vuelve a ejecutarlo.
--
-- ESTO NO SE PUEDE DESHACER.
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK OFF
SET LINESIZE 200
SET DEFINE ON

--------------------------------------------------------------------------------
-- INTERRUPTORES
--------------------------------------------------------------------------------
-- 'NO' = simulacion (solo lista)   |   'SI' = borra de verdad
DEFINE CONFIRMAR = 'NO'

-- 'SI' = conserva las tablas y packages que crea la extension SQL Developer
--        de VSCode (ANNOTATIONS_*$, METADATA_ANNOTATIONS, etc.).
--        Recomendado: si los borras, la extension los vuelve a crear sola.
-- 'NO' = borra absolutamente todo.
DEFINE PRESERVAR_IDE = 'SI'


--------------------------------------------------------------------------------
-- PARTE 1  |  INVENTARIO PREVIO
--------------------------------------------------------------------------------
PROMPT
PROMPT ================================================================
PROMPT  INVENTARIO DEL ESQUEMA ACTUAL
PROMPT ================================================================

COL esquema      FORMAT A22
COL tipo_objeto  FORMAT A22
COL cantidad     FORMAT 9999

SELECT USER AS esquema, object_type AS tipo_objeto, COUNT(*) AS cantidad
FROM   user_objects
WHERE  object_type NOT IN ('LOB','TABLE PARTITION','INDEX PARTITION')
GROUP  BY object_type
ORDER  BY object_type;

SELECT COUNT(*) AS objetos_en_papelera FROM user_recyclebin;


--------------------------------------------------------------------------------
-- PARTE 2  |  LIMPIEZA
--------------------------------------------------------------------------------
DECLARE
    c_confirmar   CONSTANT VARCHAR2(4) := UPPER('&CONFIRMAR');
    c_preservar   CONSTANT VARCHAR2(4) := UPPER('&PRESERVAR_IDE');

    v_borrados    PLS_INTEGER := 0;
    v_omitidos    PLS_INTEGER := 0;
    v_errores     PLS_INTEGER := 0;

    ----------------------------------------------------------------------------
    -- Objetos que instala la extension SQL Developer de VSCode.
    -- No son trabajo del usuario: si se borran, la extension los recrea.
    ----------------------------------------------------------------------------
    FUNCTION es_objeto_del_ide (p_nombre IN VARCHAR2) RETURN BOOLEAN IS
    BEGIN
        RETURN c_preservar = 'SI'
           AND (   p_nombre LIKE 'ANNOTATIONS%'
                OR p_nombre LIKE 'METADATA/_ANNOTATIONS%' ESCAPE '/'
                OR p_nombre LIKE 'METADATA/_PREBUILT%'    ESCAPE '/'
                OR p_nombre LIKE 'PRVT/_ANNOTATIONS%'     ESCAPE '/'
                OR p_nombre = 'GROUP_ID_SEQ');
    END es_objeto_del_ide;

    ----------------------------------------------------------------------------
    -- Ejecuta (o simula) un DROP y lleva la cuenta.
    ----------------------------------------------------------------------------
    PROCEDURE ejecutar (p_ddl IN VARCHAR2, p_nombre IN VARCHAR2) IS
    BEGIN
        IF c_confirmar = 'SI' THEN
            EXECUTE IMMEDIATE p_ddl;
            v_borrados := v_borrados + 1;
            DBMS_OUTPUT.PUT_LINE('  [BORRADO ] ' || p_nombre);
        ELSE
            v_borrados := v_borrados + 1;
            DBMS_OUTPUT.PUT_LINE('  [simular ] ' || p_ddl);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            v_errores := v_errores + 1;
            DBMS_OUTPUT.PUT_LINE('  [ERROR   ] ' || p_nombre ||
                                 ' -> ' || SQLERRM);
    END ejecutar;

BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || RPAD('=',64,'='));
    IF c_confirmar = 'SI' THEN
        DBMS_OUTPUT.PUT_LINE(' MODO REAL - los objetos se van a eliminar');
    ELSE
        DBMS_OUTPUT.PUT_LINE(' MODO SIMULACION - no se borra nada');
        DBMS_OUTPUT.PUT_LINE(' Cambia CONFIRMAR a ''SI'' para ejecutar.');
    END IF;
    DBMS_OUTPUT.PUT_LINE(' Esquema destino: ' || USER);
    DBMS_OUTPUT.PUT_LINE(' Preservar objetos del IDE: ' || c_preservar);
    DBMS_OUTPUT.PUT_LINE(RPAD('=',64,'='));

    ----------------------------------------------------------------------------
    -- 2.1  Vistas materializadas (antes que las tablas)
    ----------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '-- Vistas materializadas --');
    FOR r IN (SELECT mview_name AS nombre FROM user_mviews ORDER BY 1) LOOP
        ejecutar('DROP MATERIALIZED VIEW "' || r.nombre || '"', r.nombre);
    END LOOP;

    ----------------------------------------------------------------------------
    -- 2.2  Tablas
    --      CASCADE CONSTRAINTS elimina tambien las FK que apuntan a la tabla,
    --      asi que el orden de borrado no importa.
    --      PURGE evita que pasen por la papelera.
    ----------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '-- Tablas --');
    FOR r IN (SELECT table_name AS nombre
              FROM   user_tables
              WHERE  nested = 'NO'
              AND    (iot_type IS NULL OR iot_type != 'IOT_OVERFLOW')
              ORDER  BY table_name) LOOP
        IF es_objeto_del_ide(r.nombre) THEN
            v_omitidos := v_omitidos + 1;
            DBMS_OUTPUT.PUT_LINE('  [omitido ] ' || r.nombre || ' (IDE)');
        ELSE
            ejecutar('DROP TABLE "' || r.nombre || '" CASCADE CONSTRAINTS PURGE',
                     r.nombre);
        END IF;
    END LOOP;

    ----------------------------------------------------------------------------
    -- 2.3  Vistas
    ----------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '-- Vistas --');
    FOR r IN (SELECT view_name AS nombre FROM user_views ORDER BY 1) LOOP
        IF es_objeto_del_ide(r.nombre) THEN
            v_omitidos := v_omitidos + 1;
            DBMS_OUTPUT.PUT_LINE('  [omitido ] ' || r.nombre || ' (IDE)');
        ELSE
            ejecutar('DROP VIEW "' || r.nombre || '"', r.nombre);
        END IF;
    END LOOP;

    ----------------------------------------------------------------------------
    -- 2.4  Secuencias
    --      Se excluyen las ISEQ$$_* : son las secuencias internas de las
    --      columnas GENERATED AS IDENTITY y Oracle las borra junto con
    --      su tabla. Intentar borrarlas a mano da ORA-32794.
    ----------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '-- Secuencias --');
    FOR r IN (SELECT sequence_name AS nombre
              FROM   user_sequences
              WHERE  sequence_name NOT LIKE 'ISEQ$$/_%' ESCAPE '/'
              ORDER  BY 1) LOOP
        IF es_objeto_del_ide(r.nombre) THEN
            v_omitidos := v_omitidos + 1;
            DBMS_OUTPUT.PUT_LINE('  [omitido ] ' || r.nombre || ' (IDE)');
        ELSE
            ejecutar('DROP SEQUENCE "' || r.nombre || '"', r.nombre);
        END IF;
    END LOOP;

    ----------------------------------------------------------------------------
    -- 2.5  Codigo PL/SQL: packages, procedimientos, funciones, triggers
    ----------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '-- Packages, procedimientos, funciones, triggers --');
    FOR r IN (SELECT object_name AS nombre, object_type AS tipo
              FROM   user_objects
              WHERE  object_type IN ('PACKAGE','PROCEDURE','FUNCTION','TRIGGER')
              ORDER  BY object_type, object_name) LOOP
        IF es_objeto_del_ide(r.nombre) THEN
            v_omitidos := v_omitidos + 1;
            DBMS_OUTPUT.PUT_LINE('  [omitido ] ' || r.nombre || ' (IDE)');
        ELSE
            ejecutar('DROP ' || r.tipo || ' "' || r.nombre || '"',
                     r.tipo || ' ' || r.nombre);
        END IF;
    END LOOP;

    ----------------------------------------------------------------------------
    -- 2.6  Tipos de objeto  (FORCE por las dependencias entre tipos)
    ----------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '-- Tipos --');
    FOR r IN (SELECT type_name AS nombre FROM user_types ORDER BY 1) LOOP
        ejecutar('DROP TYPE "' || r.nombre || '" FORCE', r.nombre);
    END LOOP;

    ----------------------------------------------------------------------------
    -- 2.7  Sinonimos privados
    ----------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '-- Sinonimos --');
    FOR r IN (SELECT synonym_name AS nombre FROM user_synonyms ORDER BY 1) LOOP
        ejecutar('DROP SYNONYM "' || r.nombre || '"', r.nombre);
    END LOOP;

    ----------------------------------------------------------------------------
    -- 2.8  Database links
    ----------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '-- Database links --');
    FOR r IN (SELECT db_link AS nombre FROM user_db_links ORDER BY 1) LOOP
        ejecutar('DROP DATABASE LINK "' || r.nombre || '"', r.nombre);
    END LOOP;

    ----------------------------------------------------------------------------
    -- 2.9  Jobs del scheduler
    ----------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '-- Jobs --');
    FOR r IN (SELECT job_name AS nombre FROM user_scheduler_jobs ORDER BY 1) LOOP
        IF c_confirmar = 'SI' THEN
            BEGIN
                DBMS_SCHEDULER.DROP_JOB(r.nombre, force => TRUE);
                v_borrados := v_borrados + 1;
                DBMS_OUTPUT.PUT_LINE('  [BORRADO ] ' || r.nombre);
            EXCEPTION WHEN OTHERS THEN
                v_errores := v_errores + 1;
                DBMS_OUTPUT.PUT_LINE('  [ERROR   ] ' || r.nombre || ' -> ' || SQLERRM);
            END;
        ELSE
            v_borrados := v_borrados + 1;
            DBMS_OUTPUT.PUT_LINE('  [simular ] DROP JOB ' || r.nombre);
        END IF;
    END LOOP;

    ----------------------------------------------------------------------------
    -- RESUMEN
    ----------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE(CHR(10) || RPAD('=',64,'='));
    IF c_confirmar = 'SI' THEN
        DBMS_OUTPUT.PUT_LINE(' Objetos eliminados : ' || v_borrados);
    ELSE
        DBMS_OUTPUT.PUT_LINE(' Objetos que se eliminarian : ' || v_borrados);
    END IF;
    DBMS_OUTPUT.PUT_LINE(' Omitidos (del IDE) : ' || v_omitidos);
    DBMS_OUTPUT.PUT_LINE(' Errores            : ' || v_errores);
    DBMS_OUTPUT.PUT_LINE(RPAD('=',64,'='));
END;
/


--------------------------------------------------------------------------------
-- PARTE 3  |  PAPELERA DE RECICLAJE
--   Oracle guarda las tablas borradas en la papelera (nombres BIN$...) y
--   siguen ocupando espacio. Esto la vacia definitivamente.
--   Respeta el interruptor CONFIRMAR igual que el resto del script.
--------------------------------------------------------------------------------
DECLARE
    c_confirmar CONSTANT VARCHAR2(4) := UPPER('&CONFIRMAR');
    v_n         PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_n FROM user_recyclebin;

    IF c_confirmar = 'SI' THEN
        EXECUTE IMMEDIATE 'PURGE RECYCLEBIN';
        DBMS_OUTPUT.PUT_LINE(CHR(10) || 'Papelera vaciada: ' ||
                             v_n || ' objetos eliminados.');
    ELSE
        DBMS_OUTPUT.PUT_LINE(CHR(10) || '[simular ] PURGE RECYCLEBIN -> ' ||
                             v_n || ' objetos en la papelera.');
    END IF;
END;
/


--------------------------------------------------------------------------------
-- PARTE 4  |  VERIFICACION FINAL
--------------------------------------------------------------------------------
PROMPT
PROMPT ================================================================
PROMPT  ESTADO FINAL DEL ESQUEMA
PROMPT ================================================================

COL object_name FORMAT A40
COL object_type FORMAT A20

SELECT object_type, object_name
FROM   user_objects
WHERE  object_type NOT IN ('LOB','TABLE PARTITION','INDEX PARTITION','INDEX')
ORDER  BY object_type, object_name;

SELECT COUNT(*) AS objetos_restantes
FROM   user_objects
WHERE  object_type NOT IN ('LOB','TABLE PARTITION','INDEX PARTITION','INDEX');

SET FEEDBACK ON


--------------------------------------------------------------------------------
-- ANEXO  |  ELIMINAR UN ESQUEMA COMPLETO
--
-- Lo anterior vacia un esquema pero conserva el usuario. Si lo que quieres es
-- eliminar un area de trabajo entera (por ejemplo EVALUACION_UNIDAD3), es mas
-- rapido borrar el usuario: se lleva todos sus objetos de una vez.
--
-- Conectate como SYSTEM en FREEPDB1 y descomenta la linea que corresponda:
--
--   DROP USER evaluacion_unidad3 CASCADE;
--
-- Para volver a crearlo vacio:
--
--   CREATE USER evaluacion_unidad3 IDENTIFIED BY "TuPassword123"
--     DEFAULT TABLESPACE users QUOTA UNLIMITED ON users;
--   GRANT CONNECT, RESOURCE TO evaluacion_unidad3;
--------------------------------------------------------------------------------
