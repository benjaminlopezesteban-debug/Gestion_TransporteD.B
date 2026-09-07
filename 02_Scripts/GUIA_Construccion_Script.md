# Guía de construcción del script

**Sistema de Gestión de Transporte Interurbano** · BDY1103 · Actualizada 06-sep-2026

Este documento explica **cómo está construido el script y por qué en ese orden**, para
que alguien que llega de fuera pueda seguir el desarrollo, entender las decisiones de
diseño y continuar donde quedó.

---

## 1. Qué hay que ejecutar y en qué orden

```
02_Scripts/
├── DDL/Modelo_GestionTransporte_DDL.sql     1. tablas, índice y datos de prueba
├── PLSQL/01_Record_Varray.sql               2. tipos compuestos
├── PLSQL/02_Calculos.sql                    3. nivel 1
├── PLSQL/03_Consultas_Cursores.sql          4. nivel 2
└── PLSQL/04_Operaciones.sql                 5. nivel 3  ← pendiente
```

El DDL es destructivo: hace `DROP` de las catorce tablas antes de crearlas. En la
primera ejecución sobre un esquema vacío lanza `ORA-00942` en cada `DROP`, lo cual es
esperado. Todo lo demás es idempotente salvo el nivel 3, que escribe.

Conexión: `benja@//localhost:1521/FREEPDB1` sobre el contenedor `oracle-practica`.

---

## 2. La idea central: tres niveles por dependencia de datos

**Los niveles no ordenan por dificultad. Ordenan por quién necesita el resultado de
quién.**

| Nivel | Qué hace | Envase que tendrá | Archivo |
|---|---|---|---|
| 1 | Resuelve **un valor** | Función | `02_Calculos.sql` |
| 2 | Recorre y **presenta** un conjunto | Procedimiento | `03_Consultas_Cursores.sql` |
| 3 | Valida y **escribe** | Procedimiento | `04_Operaciones.sql` |

El nivel 1 no depende de nadie y todos dependen de él: la venta necesita el precio
vigente, la programación necesita saber cuántos conductores exige el viaje, la
disponibilidad necesita contar asientos libres.

**Por qué importa el orden.** Si se escribe primero la venta con la búsqueda de tarifa
incrustada, cuando esa búsqueda deba convertirse en `fn_tarifa_vigente` hay que abrir y
reescribir el bloque de venta. Construir de abajo hacia arriba evita ese retroceso.

---

## 3. La convención que evita reescribir: frontera del objeto futuro

En esta entrega (RA1) todo son **bloques anónimos**. Los procedimientos, funciones y
packages corresponden al RA2. Para que el paso de una cosa a la otra sea mecánico, cada
bloque se escribe ya con la forma que tendrá:

```sql
--------------------------------------------------------------------
-- 1.1  Tarifa vigente  ->  futura FUNCTION fn_tarifa_vigente
-- Entradas : p_id_ruta, p_id_tipo_asiento, p_fecha
-- Devuelve : precio vigente
-- Sirve a  : RF-01      Implementa : RN-07
--------------------------------------------------------------------
DECLARE
    -- PARAMETROS de la futura funcion
    p_id_ruta  CONSTANT ruta.id_ruta%TYPE := 7;
    ...
    -- RETORNO
    v_precio  tarifa.precio%TYPE;
BEGIN
    ...                          -- el cuerpo no cambia al extraerse
EXCEPTION
    ...
END;
/
```

Tres reglas:

1. **Las entradas van como `CONSTANT` con prefijo `p_`** al inicio del `DECLARE`. Al
   convertirlo en función, esas líneas pasan a la firma y desaparecen del cuerpo.
2. **El resultado se deposita en una sola variable.** Al extraer, se cambia el
   `DBMS_OUTPUT` final por un `RETURN`.
3. **El cuerpo entre `BEGIN` y `EXCEPTION` no se toca** en la conversión.

Prefijos usados en todo el script: `p_` parámetro, `v_` variable, `c_` constante o
cursor, `r_` record, `tr_` tipo record, `tv_` tipo varray, `e_` excepción de usuario.

---

## 4. Reglas de orden que no son de estilo

**Dentro del `DECLARE` el orden es obligatorio:**

```
tipos  →  cursores  →  variables  →  excepciones
```

Una variable declarada como `mi_cursor%ROWTYPE` exige que el cursor ya exista, y un
cursor que devuelva un tipo `RECORD` propio exige que el tipo esté declarado antes.
Invertirlo no compila.

**Las excepciones se escriben desde el primer bloque, no al final.** Agregar el manejo
de errores después obliga a reestructurar todos los bloques ya escritos.

**Los tipos `RECORD` y `VARRAY` se definen una sola vez, en su forma final.** Están en
`01_Record_Varray.sql`. Los bloques posteriores los repiten literalmente hasta que en
RA2 migren a la especificación del package.

**Una función invocada dentro de la consulta de un cursor debe existir antes de que el
cursor compile.** Es otra razón técnica para el orden abajo-arriba.

---

## 5. La decisión pendiente que condiciona el nivel 3

**Antes de escribir `04_Operaciones.sql` hay que decidir quién escribe el historial de
estados del pasaje.**

Los procedimientos se invocan; **un trigger no**: se dispara solo ante un `INSERT`,
`UPDATE` o `DELETE`. Eso significa que un trigger creado sobre `PASAJE` cambia el
comportamiento de todo lo que se escriba después, sin que el código lo mencione.

El caso concreto: el candidato natural es un trigger que registre en
`PASAJE_ESTADO_HIST` cada cambio de estado.

| Si el trigger existe | Si no existe |
|---|---|
| `sp_vender_pasaje` **no debe** insertar el historial | `sp_vender_pasaje` **sí debe** hacerlo |

Escribir primero la venta insertando el historial a mano y agregar el trigger después
produce **dos filas por transición**. Al revés, quitar la inserción manual confiando en
un trigger que aún no existe **pierde el historial en silencio**.

**Estado actual:** no decidido. Mientras tanto, el nivel 3 debe escribir el historial
explícitamente y dejarlo marcado en un comentario de cabecera:

```sql
-- El historial lo escribe este procedimiento. Cuando se incorpore el trigger
-- de auditoria sobre PASAJE, esta insercion se elimina de aqui.
```

Eso basta para que la migración posterior sea localizable y no una cacería.

---

## 6. Qué hay escrito hoy

### `01_Record_Varray.sql` — tipos compuestos

| Bloque | Contenido |
|---|---|
| 2.1 | `RECORD` explícito del pasaje, campos anclados con `%TYPE` |
| 2.2 | `RECORD` anclado con `%ROWTYPE` y cuándo conviene cada forma |
| 2.3 | `VARRAY(6)` de asientos solicitados |
| 2.4 | Ambos trabajando juntos: simulación de una venta |

**Por qué VARRAY y no tabla anidada:** la cantidad de asientos de una venta tiene un
límite conocido —la política comercial fija 6 por transacción— y el `VARRAY` declara ese
límite en el tipo. La restricción del negocio queda expresada en la estructura de datos
en vez de depender de una validación que alguien pueda omitir. Si el conjunto pudiera
crecer sin cota, la tabla anidada sería lo correcto.

**Trampa encontrada:** un campo del `RECORD` no puede llamarse igual que una tabla. Al
nombrarlo `tipo_asiento`, PL/SQL resuelve el identificador contra el campo que está
declarando y falla con `PLS-00320`. Se renombró a `nombre_tipo`.

### `02_Calculos.sql` — nivel 1

| Bloque | Futura función | Excepciones |
|---|---|---|
| 1.1 | `fn_tarifa_vigente` | `NO_DATA_FOUND`, `TOO_MANY_ROWS` |
| 1.2 | `fn_conductores_requeridos` | `NO_DATA_FOUND` |
| 1.3 | `fn_asientos_disponibles` | `NO_DATA_FOUND` |
| 1.4 | `fn_porcentaje_ocupacion` | `ZERO_DIVIDE`, `NO_DATA_FOUND` |

Cierra con un bloque que **fuerza las excepciones** con entradas inválidas, para
demostrar que el manejo de errores funciona y no sólo está escrito.

**Aquí sólo hay excepciones predefinidas, y es deliberado.** En este nivel los errores
posibles son los que el motor detecta solo: no hay dato, hay más de uno, se divide por
cero. Declarar una excepción propia donde `NO_DATA_FOUND` ya describe la situación sería
usarla por cumplir un requisito formal. Las de usuario corresponden al nivel 3.

### `03_Consultas_Cursores.sql` — nivel 2

| Bloque | Cursor | Futuro procedimiento |
|---|---|---|
| 2.1 | **Sin parámetros**, `OPEN`/`FETCH`/`CLOSE` explícito | `sp_control_flota` |
| 2.2 | **Con parámetro** y complejo (5 tablas) | `sp_registro_viaje` |
| 2.3 | **Dos cursores con parámetros anidados** | `sp_disponibilidad` |

El 2.1 usa la forma extendida a propósito, para dejar visible el ciclo de vida completo
del cursor; el 2.2 usa `FOR`, que hace lo mismo implícitamente. Por eso el 2.1 lleva
`CLOSE` también en su bloque `EXCEPTION`: si falla a mitad del recorrido el cursor
quedaría abierto. Ese es el costo real de la forma extendida y la razón de preferir
`FOR` en producción.

El 2.3 es el bloque que sostiene el indicador **IE1.2.1** de la rúbrica. La relación
entre los dos ciclos es de dependencia: los asientos que recorre el ciclo interior son
los del bus asignado al viaje que el exterior tiene en curso, de modo que el cursor
interior no puede abrirse hasta saber cuál es.

---

## 6 bis. Cómo encontrar la justificación de cada bloque

Cada archivo `.sql` abre con un bloque **TRAZABILIDAD CON LA DOCUMENTACIÓN** y cada
bloque de código lleva sus propias líneas `Informe:` y `Anexo:`. Con eso se puede ir del
código a su justificación sin buscar:

| Desde el código | Se llega a |
|---|---|
| `-- Informe: seccion 6.5` | El apartado del informe que argumenta la decisión |
| `-- Anexo: Tabla 28` | La ficha de referencia en `ANEXO_Tablas_de_Referencia.docx` |
| `-- Rubrica: IE1.2.1` | El indicador de evaluación que ese bloque alimenta |
| `-- Sirve a: RF-04` | El requerimiento funcional que implementa |
| `-- Implementa: RN-10` | La regla de negocio que hace cumplir |

La cabecera del DDL además separa explícitamente **las reglas que se garantizan por
estructura** —RN-01, 02, 05, 06, 07, 08 y 09— de **las que requieren PL/SQL** —RN-03,
RN-04 y RN-10—. Esa distinción es la que responde a la pregunta de por qué unas cosas
están en el modelo y otras en el código.

La integración en sentido inverso, desde el informe hacia los archivos del script, se
hará más adelante en otro formato.

---

## 7. Dos criterios transversales que conviene no romper

**El criterio de "asiento ocupado" nunca se escribe a mano.** Se toma siempre de
`ESTADO_PASAJE.ocupa_asiento`, que es la misma condición que aplica el índice único
parcial del DDL. Si mañana se agrega un estado, todo el script lo respeta sin
modificarse. Aparece así en los bloques 1.3, 1.4, 2.2 y 2.3.

**La disponibilidad se calcula, nunca se almacena.** Guardarla como columna obligaría a
sincronizarla con cada venta y cada anulación, y bastaría un fallo para que el dato
mintiera.

---

## 8. Cómo el DDL implementa las reglas que el script no valida

Tres reglas no se programan: están en la estructura.

**RN-01** — la capacidad del bus es la cantidad de filas en `ASIENTO`, gracias a la clave
primaria compuesta `(id_bus, nro_asiento)`. No hay un número declarado aparte que pueda
contradecirla.

**RN-06 y RN-09** — un índice único parcial sobre `PASAJE`:

```sql
CREATE UNIQUE INDEX ux_pasaje_asiento_vigente ON pasaje (
    CASE WHEN id_estado IN (1,2,3) THEN id_viaje    END,
    CASE WHEN id_estado IN (1,2,3) THEN id_bus      END,
    CASE WHEN id_estado IN (1,2,3) THEN nro_asiento END
);
```

Un `UNIQUE` corriente impediría revender un asiento después de anularlo. Oracle no tiene
índices únicos parciales, pero **un índice único ignora las filas cuyas columnas
indexadas son todas nulas**. Las expresiones `CASE` devuelven el valor real cuando el
estado ocupa el asiento y `NULL` cuando no. Al anular, el pasaje sale del índice y su
asiento vuelve a estar disponible sin borrar el registro.

Consecuencia para el nivel 3: al intentar vender un asiento ya tomado, el motor levanta
`DUP_VAL_ON_INDEX` por sí solo. La regla no se programa, se diseña.

**Integridad asiento–bus–viaje** — `PASAJE` lleva `id_bus` a propósito. Con dos claves
foráneas compuestas —`(id_viaje, id_bus)` hacia `VIAJE` y `(id_bus, nro_asiento)` hacia
`ASIENTO`— la base garantiza de forma declarativa que el asiento vendido pertenece al
bus que realiza ese viaje, sin trigger.

---

## 9. Lo que falta

### Nivel 3 — `04_Operaciones.sql`

| Bloque | Futuro procedimiento | Excepciones de usuario | RF · RN |
|---|---|---|---|
| 3.1 | `sp_programar_viaje` | `e_bus_ocupado`, `e_conductor_ocupado`, `e_jornada_excedida` | RF-03 · RN-02, RN-03, RN-04, RN-10 |
| 3.2 | `sp_vender_pasaje` | `e_viaje_no_programado`, `e_pasajero_inexistente`, `e_asiento_no_disponible` | RF-01 · RN-05, RN-06, RN-07 |
| 3.3 | `sp_anular_pasaje` | `e_fuera_de_plazo` | RF-02 · RN-08, RN-09 |

El 3.1 se escribe antes que el 3.2 porque la venta necesita viajes ya programados.

**Manejo de transacción:** cada bloque termina en `ROLLBACK` y lo declara en su cabecera,
de modo que el script pueda ejecutarse cuantas veces se quiera sin ensuciar los datos de
prueba. Al pasar a procedimientos en RA2 se cambia por `COMMIT` en el punto que
corresponda. La alternativa —hacer `COMMIT` desde ya— obligaría a recargar el DDL cada
vez que se quiera volver a demostrar, lo que en una defensa en vivo es peor.

**Criterio de atomicidad:** una venta de tres asientos donde el segundo no está
disponible se rechaza completa. No se registra la venta parcial de dos pasajes.

### Preguntas abiertas con el profesor

1. **¿Los procedimientos y triggers se implementan en esta entrega o sólo se evalúan?**
   La pauta usa el verbo *evaluar* y su desarrollo corresponde al RA2. De la respuesta
   depende si el nivel 3 queda en bloques anónimos o pasa directo a procedimientos.
   La estructura descrita aquí funciona en ambos escenarios.
2. ¿Se espera una cantidad mínima de RECORD, VARRAY y cursores, o se justifica según lo
   que el caso necesite?

### Documentación

Secciones 8.2, 9.2, 10, 11, 12, 13 y 14 del informe, que se completan una vez que el
nivel 3 exista.

---

## 10. Cómo verificar que todo sigue funcionando

```bash
cd /home/benja/Archivo.Personal/01_Materias/Taller_BBDD/02_Scripts
for f in DDL/Modelo_GestionTransporte_DDL.sql PLSQL/*.sql; do
    docker cp "$f" oracle-practica:/tmp/x.sql
    echo "== $f"
    docker exec oracle-practica bash -lc \
      'sqlplus -s -L benja/benja123@//localhost:1521/FREEPDB1 @/tmp/x.sql' \
      2>&1 | grep -cE "ORA-|PLS-"
done
```

Salvo los `ORA-00942` de los `DROP` en la primera corrida del DDL, el conteo debe ser
**0** en todos los archivos.
