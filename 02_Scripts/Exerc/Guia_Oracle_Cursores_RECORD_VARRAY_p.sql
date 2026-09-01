-- ============================================================
-- GUÍA ORACLE PL/SQL
-- CURSORES + RECORD + VARRAY


SET SERVEROUTPUT ON;

-- ============================================================
-- 0. PREPARACIÓN DEL AMBIENTE
-- ============================================================

BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE empleados CASCADE CONSTRAINTS';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP TYPE nombres_varray';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -4043 THEN RAISE; END IF;
END;
/

CREATE TABLE empleados (
    id             NUMBER(5) PRIMARY KEY,
    nombre         VARCHAR2(50) NOT NULL,
    departamento   VARCHAR2(30) NOT NULL,
    salario        NUMBER(10,0) NOT NULL
);

INSERT INTO empleados VALUES (101, 'Ana',   'INFORMATICA', 900000);
INSERT INTO empleados VALUES (102, 'Pedro', 'FINANZAS',    850000);
INSERT INTO empleados VALUES (103, 'Maria', 'INFORMATICA', 950000);
INSERT INTO empleados VALUES (104, 'Luis',  'RRHH',        800000);
INSERT INTO empleados VALUES (105, 'Sofia', 'FINANZAS',    920000);
INSERT INTO empleados VALUES (106, 'Diego', 'INFORMATICA', 780000);
INSERT INTO empleados VALUES (107, 'Carla', 'RRHH',        880000);
INSERT INTO empleados VALUES (108, 'Jorge', 'INFORMATICA', 990000);

COMMIT;

SELECT * FROM empleados ORDER BY id;

-- ============================================================
-- EJEMPLO 1: CURSOR EXPLICITO SIN PARAMETROS
-- Ciclo: DECLARE -> OPEN -> FETCH -> PROCESAR -> CLOSE
-- ============================================================

DECLARE
    CURSOR c_empleados IS
        SELECT id, nombre, salario
        FROM empleados
        WHERE departamento = 'INFORMATICA'
        ORDER BY id;

    v_id      empleados.id%TYPE;
    v_nombre  empleados.nombre%TYPE;
    v_salario empleados.salario%TYPE;
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- EJEMPLO 1 ---');

    OPEN c_empleados;

    LOOP
        FETCH c_empleados INTO v_id, v_nombre, v_salario;

        EXIT WHEN c_empleados%NOTFOUND;

        DBMS_OUTPUT.PUT_LINE(
            v_id || ' - ' || v_nombre || ' - $' || v_salario
        );
    END LOOP;

    DBMS_OUTPUT.PUT_LINE(
        'Filas procesadas: ' || c_empleados%ROWCOUNT
    );

    CLOSE c_empleados;
END;
/

-- ============================================================
-- EJEMPLO 2: ATRIBUTOS DEL CURSOR
-- %FOUND, %NOTFOUND, %ROWCOUNT, %ISOPEN
-- ============================================================

DECLARE
    CURSOR c_empleados IS
        SELECT id, nombre
        FROM empleados
        WHERE departamento = 'RRHH'
        ORDER BY id;

    v_empleado_id empleados.id%TYPE;
    v_nombre      empleados.nombre%TYPE;
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- EJEMPLO 2 ---');

    OPEN c_empleados;

    DBMS_OUTPUT.PUT_LINE(
        'Cursor abierto: ' ||
        CASE WHEN c_empleados%ISOPEN THEN 'SI' ELSE 'NO' END
    );

    LOOP
        FETCH c_empleados INTO v_empleado_id, v_nombre;

        EXIT WHEN c_empleados%NOTFOUND;

        DBMS_OUTPUT.PUT_LINE(
            'Empleado: ' || v_empleado_id || ' - ' || v_nombre
        );

        DBMS_OUTPUT.PUT_LINE(
            'Filas recuperadas hasta ahora: ' ||
            c_empleados%ROWCOUNT
        );
    END LOOP;

    CLOSE c_empleados;

    DBMS_OUTPUT.PUT_LINE(
        'Cursor abierto después de CLOSE: ' ||
        CASE WHEN c_empleados%ISOPEN THEN 'SI' ELSE 'NO' END
    );
END;
/

-- ============================================================
-- EJEMPLO 3: CURSOR CON PARAMETROS
-- El mismo cursor puede reutilizarse con distintos departamentos.
-- ============================================================

DECLARE
    CURSOR c_empleados(p_departamento VARCHAR2) IS
        SELECT id, nombre, salario
        FROM empleados
        WHERE departamento = p_departamento
        ORDER BY id;

    v_total NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- EJEMPLO 3 ---');

    DBMS_OUTPUT.PUT_LINE('INFORMATICA');
    v_total := 0;

    FOR empleado IN c_empleados('INFORMATICA') LOOP
        DBMS_OUTPUT.PUT_LINE(
            empleado.id || ' - ' || empleado.nombre ||
            ' - $' || empleado.salario
        );
        v_total := v_total + 1;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('Total: ' || v_total);

    DBMS_OUTPUT.PUT_LINE('FINANZAS');
    v_total := 0;

    FOR empleado IN c_empleados('FINANZAS') LOOP
        DBMS_OUTPUT.PUT_LINE(
            empleado.id || ' - ' || empleado.nombre
        );
        v_total := v_total + 1;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('Total: ' || v_total);
END;
/

-- ============================================================
-- EJEMPLO 4: FOR LOOP CON CURSOR
-- Oracle administra OPEN, FETCH y CLOSE.
-- ============================================================

DECLARE
    CURSOR c_empleados IS
        SELECT id, nombre, departamento, salario
        FROM empleados
        ORDER BY id;
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- EJEMPLO 4 ---');

    FOR empleado IN c_empleados LOOP
        DBMS_OUTPUT.PUT_LINE(
            empleado.id || ' | ' ||
            empleado.nombre || ' | ' ||
            empleado.departamento || ' | $' ||
            empleado.salario
        );
    END LOOP;
END;
/



-- ============================================================
-- EJERCICIOS
-- ============================================================


--EJERCICIO 1 Crear un cursor explícito sin parámetros que muestre: ID, nombre y salario de todos los empleados de INFORMATICA.
 



--EJERCICIO 2 Crear un cursor explícito que muestre los empleados cuyo salario sea mayor o igual a 900000. Mostrar además %ROWCOUNT.


--EJERCICIO 3 Crear un cursor parametrizado que reciba el nombre del departamento y muestre sus empleados. Probar con INFORMATICA, FINANZAS y RRHH.

DECLARE
    CURSOR c_emp(p_departamento VARCHAR2) IS --filtrar por un texto 
    SELECT 
        id,
        nombre,
        salario
    FROM empleado
    WHERE departamento = p_departamento
    ORDER BY id;

    

BEGIN

    DBMS_OUTPUT.PUT_LINE("Ejercicio 3")

    FOR r in c_emp('INFORMATICA') LOOP --Se le tiene que dar el parametro en el formato de tipo declarado
    DBMS_OUTPUT.PUT_LINE(r.nombre || ' ' || r.salario )
    END LOOP;




END;
/






--EJERCICIO 4 Resolver el ejercicio anterior utilizando FOR LOOP, sin escribir OPEN, FETCH ni CLOSE manualmente.

--EJERCICIO 5 Crear un RECORD basado en el cursor y utilizarlo para mostrar los datos completos de cada empleado de FINANZAS.

DECLARE
    CURSOR c_emp IS 
        SElECT 
            id,
            nombre,
            departamento,
            salario
        FROM empleados
        WHERE departamento = 'FINANZAS'

        v_emp c_emp%ROWTYPE;

BEGIN

END;
/









*/

-- ============================================================
-- RESPUESTAS
-- ============================================================

-- RESPUESTA 1
DECLARE
    CURSOR c_emp IS
        SELECT id, nombre, salario
        FROM empleados
        WHERE departamento = 'INFORMATICA';

BEGIN
    DBMS_OUTPUT.PUT_LINE('RESPUESTA 1');

    FOR r IN c_emp LOOP
        DBMS_OUTPUT.PUT_LINE(
            r.id || ' - ' || r.nombre || ' - $' || r.salario
        );
    END LOOP;
END;
/

-- RESPUESTA 2
-- RESPUESTA 2
DECLARE
    CURSOR c_emp IS
        SELECT id, nombre, salario
        FROM empleados
        WHERE salario >= 900000
        ORDER BY salario DESC;

    v_cantidad NUMBER := 0;

BEGIN
    DBMS_OUTPUT.PUT_LINE('RESPUESTA 2');

    FOR r IN c_emp LOOP

        DBMS_OUTPUT.PUT_LINE(
            r.id || ' - ' ||
            r.nombre || ' - $' ||
            r.salario
        );

        v_cantidad := v_cantidad + 1;

    END LOOP;

    DBMS_OUTPUT.PUT_LINE(
        'Cantidad procesada: ' || v_cantidad
    );

END;
/
-- RESPUESTA 3
DECLARE
    CURSOR c_emp(p_departamento VARCHAR2) IS
        SELECT id, nombre, salario
        FROM empleados
        WHERE departamento = p_departamento
        ORDER BY id;
BEGIN
    DBMS_OUTPUT.PUT_LINE('RESPUESTA 3 - INFORMATICA');

    FOR r IN c_emp('INFORMATICA') LOOP
        DBMS_OUTPUT.PUT_LINE(
            r.id || ' - ' || r.nombre || ' - $' || r.salario
        );
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('RESPUESTA 3 - FINANZAS');

    FOR r IN c_emp('FINANZAS') LOOP
        DBMS_OUTPUT.PUT_LINE(
            r.id || ' - ' || r.nombre || ' - $' || r.salario
        );
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('RESPUESTA 3 - RRHH');

    FOR r IN c_emp('RRHH') LOOP
        DBMS_OUTPUT.PUT_LINE(
            r.id || ' - ' || r.nombre || ' - $' || r.salario
        );
    END LOOP;
END;
/

-- RESPUESTA 4
DECLARE
    CURSOR c_emp(p_departamento VARCHAR2) IS
        SELECT id, nombre, salario
        FROM empleados
        WHERE departamento = p_departamento;
BEGIN
    DBMS_OUTPUT.PUT_LINE('RESPUESTA 4');

    FOR r IN c_emp('INFORMATICA') LOOP
        DBMS_OUTPUT.PUT_LINE(
            r.id || ' - ' || r.nombre || ' - $' || r.salario
        );
    END LOOP;
END;
/

-- RESPUESTA 5
DECLARE
    CURSOR c_emp IS
        SELECT id, nombre, departamento, salario
        FROM empleados
        WHERE departamento = 'FINANZAS';

    v_emp c_emp%ROWTYPE;
BEGIN
    DBMS_OUTPUT.PUT_LINE('RESPUESTA 5');

    OPEN c_emp;

    LOOP
        FETCH c_emp INTO v_emp;
        EXIT WHEN c_emp%NOTFOUND;

        DBMS_OUTPUT.PUT_LINE(
            v_emp.id || ' | ' ||
            v_emp.nombre || ' | ' ||
            v_emp.departamento || ' | ' ||
            v_emp.salario
        );
    END LOOP;

    CLOSE c_emp;
END;
/
