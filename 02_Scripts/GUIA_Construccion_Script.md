# Guía de construcción del script

**Sistema de Gestión de Transporte Interurbano** · BDY1103 · Actualizada 07-sep-2026

Este documento explica **cómo está construido el script y por qué en ese orden**, para
que alguien que llega de fuera pueda seguir el desarrollo, entender las decisiones de
diseño y continuar donde quedó.

> **Corrección estructural del 07-sep-2026.** El script dejó de ser una colección de
> bloques anónimos. Toda la lógica vive ahora en **tres packages y dos triggers**; los
> bloques anónimos se conservan, pero en su rol correcto: código que *invoca* a los
> objetos almacenados, más las demostraciones de `RECORD` y `VARRAY` que la pauta pide en
> esa forma. Las §2 y §3 explican qué cambió y qué se ganó.

---

## 1. Qué hay que ejecutar y en qué orden

```
02_Scripts/
├── DDL/Modelo_GestionTransporte_DDL.sql   1. tablas, índice único parcial y datos
├── PLSQL/01_Pkg_Calculos.sql              2. funciones: resuelven UN valor
├── PLSQL/02_Pkg_Consultas.sql             3. procedimientos: recorren y presentan
├── PLSQL/03_Pkg_Operaciones.sql           4. procedimientos: validan y escriben
├── PLSQL/04_Triggers.sql                  5. integridad y auditoría por evento
└── PLSQL/05_Demostraciones.sql            6. bloques anónimos que invocan todo
```

**El número del archivo es el orden real de ejecución, no una sugerencia.** Cada uno
depende de que el anterior exista:

- `02_Pkg_Consultas` invoca `pkg_calculos.fn_conductores_requeridos` y
  `fn_porcentaje_ocupacion` dentro del cuerpo de sus cursores. Sin el package de
  cálculos creado, no compila.
- `03_Pkg_Operaciones` invoca `fn_tarifa_vigente` y `fn_asiento_ocupado`.
- `04_Triggers` va antes que las demostraciones porque estas provocan el evento que el
  trigger audita.
- `05_Demostraciones` depende de los tres packages y de los dos triggers.

El DDL es destructivo: hace `DROP` de las catorce tablas antes de crearlas. En la primera
ejecución sobre un esquema vacío lanza `ORA-00942` en cada `DROP`, lo cual es esperado.
Los cinco archivos PL/SQL son idempotentes: se pueden reejecutar cuantas veces se quiera.
Los bloques de `05_Demostraciones.sql` que escriben terminan siempre en `ROLLBACK`.

Conexión: `benja@//localhost:1521/FREEPDB1` sobre el contenedor `oracle-practica`.

---

## 2. La idea central: tres niveles por dependencia de datos

**Los niveles no ordenan por dificultad. Ordenan por quién necesita el resultado de
quién.** Cada nivel es hoy un package:

| Nivel | Qué hace | Envase | Archivo |
|---|---|---|---|
| 1 | Resuelve **un valor** | `pkg_calculos` — 5 funciones públicas + 1 privada | `01_Pkg_Calculos.sql` |
| 2 | Recorre y **presenta** un conjunto | `pkg_consultas` — 3 procedimientos | `02_Pkg_Consultas.sql` |
| 3 | Valida y **escribe** | `pkg_operaciones` — 3 procedimientos, tipos y excepciones | `03_Pkg_Operaciones.sql` |

El nivel 1 no depende de nadie y todos dependen de él: la venta necesita el precio
vigente, la programación necesita saber cuántos conductores exige el viaje, la
disponibilidad necesita saber si un asiento está libre.

**Por qué importaba el orden, con un ejemplo real y no hipotético.** El RECORD del pasaje
se escribió primero con su propia consulta de tarifa vigente, independiente de la que
después se volvió `fn_tarifa_vigente`. Eran la misma regla escrita dos veces: si la
vigencia cambiara, había que corregirla en dos lugares, y sólo se detectó al revisar el
script con detalle. Construir de abajo hacia arriba es lo que evita que ese tipo de
duplicación pase inadvertida —ver §8—.

---

## 3. Qué aporta el package, más allá de ordenar el código

Agrupar procedimientos en un package suele presentarse como una cuestión de orden. En
este proyecto resuelve **tres problemas concretos** que sin él no tienen solución:

**1. Los tipos compuestos se vuelven compartibles.** Un `TYPE ... IS RECORD` declarado en
un bloque anónimo muere con el bloque. Aunque otro bloque declarara un tipo con
exactamente los mismos campos, Oracle los trata como tipos distintos y no permite pasar
uno donde se espera el otro. Declarado en la especificación de `pkg_operaciones`,
`tv_solicitudes` **cruza la frontera**: el bloque anónimo llena la colección y se la pasa
al procedimiento como parámetro. Esa es la diferencia entre demostrar un VARRAY y
usarlo.

**2. Las excepciones de usuario se vuelven parte de la interfaz.** Una `EXCEPTION`
declarada dentro de un bloque anónimo tampoco existe fuera de él: quien lo invocara sólo
podía capturar `OTHERS` y leer el texto del mensaje para adivinar qué pasó. Las ocho
excepciones de `pkg_operaciones` están en la especificación, de modo que el invocador
escribe:

```sql
EXCEPTION
    WHEN pkg_operaciones.e_asiento_no_disponible THEN ...
    WHEN pkg_operaciones.e_fuera_de_plazo        THEN ...
```

Cada error se distingue por nombre y se maneja distinto. Sin package eso es imposible.

**3. Aparece la distinción público / privado.** `pkg_calculos` tiene una sexta función,
`fn_ocupados_viaje`, que existe **sólo en el cuerpo**: no está en la especificación y
nadie fuera del package puede llamarla. Cuenta los asientos ocupados de un viaje, que es
lo que `fn_asientos_disponibles` y `fn_porcentaje_ocupacion` necesitaban ambas. Es
simultáneamente la eliminación de una duplicación real y la demostración del constructor
privado que pide el indicador IL2.2.

---

## 4. Dónde viven los RECORD y los VARRAY

Están en **tres lugares distintos**, y la diferencia entre ellos es deliberada:

| Dónde | Qué | Alcance |
|---|---|---|
| Especificación de `pkg_operaciones` | `tr_solicitud`, `tv_solicitudes`, `tv_conductores` | Almacenado en el diccionario. Cualquier programa lo usa. |
| `DECLARE` de `05_Demostraciones.sql` | `tr_pasaje`, `tv_asientos` | Local. Muere con el bloque. |
| Implícitos | `ruta%ROWTYPE`, `c_viajes_programados%ROWTYPE` | Los construye Oracle desde la tabla o el cursor. |

**Por qué se conservan los dos primeros.** Los locales muestran `RECORD` y `VARRAY` en su
forma pura, que es lo que pide RA1, y de paso dejan ver la limitación que el package
resuelve. Los almacenados muestran esa misma estructura ya compartible. El contraste
entre ambos *es* el argumento de la §3, y por eso conviene presentarlos juntos.

`%ROWTYPE` se usa cuando se necesita la fila completa tal como está en la base o tal como
la devuelve un cursor. Un `RECORD` explícito se declara cuando la estructura combina
campos de varias tablas o incluye datos calculados que no existen como columna.

---

## 5. Reglas de orden que no son de estilo

**Dentro del `DECLARE` el orden es obligatorio:**

```
tipos  →  cursores  →  variables  →  excepciones
```

Una variable declarada como `mi_cursor%ROWTYPE` exige que el cursor ya exista, y un
cursor que devuelva un tipo `RECORD` propio exige que el tipo esté declarado antes.
Invertirlo no compila.

**En la especificación del package el orden es el mismo**, y por la misma razón:
`tv_solicitudes IS VARRAY(6) OF tr_solicitud` exige que `tr_solicitud` esté declarado
arriba.

**Las excepciones se escriben desde el primer bloque, no al final.** Agregar el manejo de
errores después obliga a reestructurar todo lo ya escrito.

**Una función invocada dentro de la consulta de un cursor debe existir antes de que el
cursor compile.** Es otra razón técnica para el orden abajo-arriba.

**Los métodos de colección no se pueden usar dentro de una sentencia SQL.**
`p_solicitudes.COUNT` en un `WHERE` produce `ORA-00904`; hay que pasarlo por una variable
PL/SQL primero. Es un error que aparece tarde, al compilar.

**Prefijos usados en todo el script:** `p_` parámetro, `v_` variable, `c_` constante o
cursor, `r_` record, `tr_` tipo record, `tv_` tipo varray, `e_` excepción de usuario,
`fn_` función, `sp_` procedimiento, `trg_` trigger, `pkg_` package.

---

## 6. Quién escribe el historial: el trigger

**Decidido el 06-sep-2026: lo escribe `trg_pasaje_historial`, no los procedimientos.**

El historial debe registrarse siempre que un pasaje cambie, sin importar quién lo
modifique. Si la inserción viviera dentro de cada procedimiento, bastaría un `UPDATE`
manual desde SQL\*Plus, una carga masiva o un procedimiento nuevo que alguien olvide
instrumentar para que la transición se pierda en silencio. El trigger se dispara por el
**evento**, no por la llamada, de modo que la trazabilidad no depende de la disciplina de
quien escribe el código.

Es el mismo criterio con que RN-06 se resolvió en un índice único y no en una validación:
la regla se cumple aunque el dato entre por otra vía.

**Consecuencia obligatoria:** ningún procedimiento de `pkg_operaciones` inserta en
`PASAJE_ESTADO_HIST`. Si lo hiciera, cada transición quedaría registrada dos veces.

**Un trigger no recibe parámetros**, y eso plantea un problema real con el motivo de la
anulación, que sólo conoce quien ejecuta la operación. Se resuelve por el contexto de la
sesión: el procedimiento lo declara con `DBMS_APPLICATION_INFO.SET_CLIENT_INFO` antes del
`UPDATE` y el trigger lo lee con `SYS_CONTEXT`. No es una variable global del programa
sino un dato de sesión, que Oracle mantiene aislado entre sesiones concurrentes.
`sp_anular_pasaje` lo limpia en su manejador `WHEN OTHERS` antes de relanzar, para que el
motivo de una anulación fallida no se filtre a la transición siguiente.

**Guarda contra registros falsos:** el trigger ignora los `UPDATE` que no alteran el
estado. Sin ella, corregir un precio generaría una fila de historial que no corresponde a
ninguna transición.

**El segundo trigger, `trg_pasaje_no_revive`,** impide que un pasaje anulado vuelva a
cualquier otro estado (RN-08). Usa la cláusula `WHEN` para no ejecutar cuerpo alguno en
las transiciones que sí son válidas: el filtro está en la definición del trigger, no en
un `IF` dentro de él.

**Orden y recarga:** el poblamiento del DDL inserta el historial a mano, y es correcto
porque en ese momento el trigger no existe. Al recargar el DDL, el `DROP TABLE` de
`PASAJE` elimina ambos triggers junto con la tabla, de modo que la secuencia
DDL → triggers → operaciones siempre queda consistente.

---

## 7. Qué hay escrito hoy

### `01_Pkg_Calculos.sql` — nivel 1

Cinco funciones públicas y una privada. Ninguna captura sus propias excepciones: las deja
propagar para que el invocador decida qué hacer.

| Función | Devuelve | Excepción que puede propagar |
|---|---|---|
| `fn_tarifa_vigente(ruta, tipo_asiento, fecha)` | `id_tarifa` vigente | `NO_DATA_FOUND` |
| `fn_conductores_requeridos(viaje)` | 1 ó 2 según RN-10 | `NO_DATA_FOUND` |
| `fn_asientos_disponibles(viaje)` | asientos libres | `NO_DATA_FOUND` |
| `fn_porcentaje_ocupacion(viaje)` | % ocupación | `ZERO_DIVIDE` |
| `fn_asiento_ocupado(viaje, bus, asiento)` | `'S'` / `'N'` | — |
| `fn_ocupados_viaje(viaje)` *(privada)* | asientos ocupados | — |

Constante pública `c_max_horas_conduccion := 5`, que es RN-10 expresada una sola vez.

**Una diferencia deliberada entre dos funciones parecidas.** `fn_asientos_disponibles`
usa `GROUP BY`, de modo que un viaje inexistente no devuelve fila y levanta
`NO_DATA_FOUND`. `fn_porcentaje_ocupacion` usa un `COUNT` simple, que siempre devuelve
una fila, y por eso un bus sin asientos produce `ZERO_DIVIDE`. Las dos formas son
correctas porque cada una necesita señalar un error distinto; no es una inconsistencia.

### `02_Pkg_Consultas.sql` — nivel 2

| Procedimiento | Cursor | Qué demuestra |
|---|---|---|
| `sp_control_flota` | sin parámetros, `OPEN`/`FETCH`/`CLOSE` explícito | control manual del ciclo, con `CLOSE` en el manejador de excepciones |
| `sp_registro_viaje(p_id_viaje)` | parametrizado, forma `FOR` | cursor complejo sobre 5 tablas |
| `sp_disponibilidad(p_desde, p_hasta)` | **dos cursores parametrizados anidados** | el centro del indicador IE1.2.1 |

`sp_control_flota` invoca `fn_conductores_requeridos` y `sp_disponibilidad` invoca
`fn_porcentaje_ocupacion`. `sp_disponibilidad` **no** invoca `fn_asiento_ocupado` a
propósito: su cursor interno obtiene todos los asientos con un `LEFT JOIN` en una sola
consulta, y llamar a la función convertiría eso en N llamadas —ver §8—.

### `03_Pkg_Operaciones.sql` — nivel 3

La especificación declara **tres tipos** (§4), **ocho excepciones de usuario** y tres
procedimientos. El cuerpo agrega la constante privada `c_ventana_anulacion := 4`.

| Procedimiento | Reglas que hace cumplir |
|---|---|
| `sp_programar_viaje(..., p_id_viaje OUT)` | RN-03, RN-04, RN-10 |
| `sp_vender_pasaje(..., p_id_venta OUT)` | RN-05, RN-06, RN-07 |
| `sp_anular_pasaje(p_id_pasaje, p_motivo)` | RN-08, RN-09, ventana de 4 h |

**Ningún procedimiento hace `COMMIT` ni `ROLLBACK`.** La decisión es deliberada: el
procedimiento no sabe si es la operación completa o un paso dentro de una transacción
mayor. Quien lo invoca es quien tiene esa información, y por eso es quien confirma o
revierte. Los bloques de `05_Demostraciones.sql` siempre revierten.

`sp_programar_viaje` **no** invoca `fn_conductores_requeridos`, porque el viaje todavía no
existe cuando hay que validar la dotación: recalcula la duración desde la ruta.

### `04_Triggers.sql`

`trg_pasaje_historial` (auditoría del ciclo de vida) y `trg_pasaje_no_revive` (RN-08),
explicados en la §6. El archivo cierra con un bloque de verificación que prueba ambos y
termina en `ROLLBACK`.

### `05_Demostraciones.sql`

Siete bloques anónimos. Los dos primeros declaran sus propios tipos y demuestran `RECORD`
y `VARRAY` en forma pura; los cinco restantes invocan los packages, capturan sus
excepciones **por nombre** y revierten. Cubren tanto los caminos de éxito como los de
rechazo de cada regla.

---

## 8. Auditoría de duplicación: qué convergió y qué no, y por qué

**Origen:** al revisar el RECORD del pasaje se notó que resolvía la tarifa vigente con una
consulta propia, independiente de `fn_tarifa_vigente`. Esta sección documenta la
auditoría completa que eso disparó.

**El principio aplicado, siempre el mismo:** *llamar a la función cuando el dato que
necesita ya existe en ese contexto, sin importar si eso implica una consulta menor
adicional; no llamarla cuando el dato de entrada no existe todavía o cuando convertiría
una consulta de conjunto en N llamadas puntuales.*

| Cálculo | Apariciones antes | Resultado |
|---|---|---|
| Tarifa vigente | 4 | Convergen todas en `fn_tarifa_vigente` |
| Asiento ocupado | 4 | Convergen 3; `sp_disponibilidad` no, usa `LEFT JOIN` de conjunto |
| Conductores requeridos | 4 | Convergen 2; `sp_programar_viaje` no, el viaje aún no existe |
| Asientos ocupados de un viaje | 2 | Convergen en `fn_ocupados_viaje`, **privada** |

**La lección.** Una duplicación es dañina cuando la misma regla se reescribe sin que haya
una razón para la diferencia — ese fue el caso de la tarifa y del asiento ocupado, y
convergieron sin costo. No es dañina cuando dos bloques calculan algo parecido por
motivos genuinamente distintos: `sp_disponibilidad` necesita el conjunto completo, no un
valor suelto; `sp_programar_viaje` no tiene todavía el dato de entrada que la función
exige. Distinguir un caso del otro —y dejarlo escrito en el propio código— es lo que
evita tanto la duplicación silenciosa como la convergencia forzada.

---

## 9. Cómo encontrar la justificación de cada bloque

Cada archivo `.sql` abre con un bloque **TRAZABILIDAD CON LA DOCUMENTACIÓN** y cada
bloque de código lleva sus propias líneas `Informe:` y `Anexo:`:

| Desde el código | Se llega a |
|---|---|
| `-- Informe: seccion 6.5` | El apartado del informe que argumenta la decisión |
| `-- Anexo: Tabla 28` | La ficha de referencia en `ANEXO_Tablas_de_Referencia.docx` |
| `-- Rubrica: IE1.2.1` | El indicador de evaluación que ese bloque alimenta |
| `-- Sirve a: RF-04` | El requerimiento funcional que implementa |
| `-- Implementa: RN-10` | La regla de negocio que hace cumplir |

La cabecera del DDL además separa explícitamente **las reglas que se garantizan por
estructura** —RN-01, 02, 05, 06, 07, 08 y 09— de **las que requieren PL/SQL** —RN-03,
RN-04 y RN-10—. Esa distinción responde a la pregunta de por qué unas cosas están en el
modelo y otras en el código.

---

## 10. Dos criterios transversales que conviene no romper

**El criterio de "asiento ocupado" nunca se escribe a mano.** Vive en `fn_asiento_ocupado`
y en la definición de `ESTADO_PASAJE.ocupa_asiento`, que es la misma condición que aplica
el índice único parcial del DDL. Si mañana se agrega un estado, todo el script lo respeta
sin modificarse.

**La disponibilidad se calcula, nunca se almacena.** Guardarla como columna obligaría a
sincronizarla con cada venta y cada anulación, y bastaría un fallo para que el dato
mintiera.

---

## 11. Cómo el DDL implementa las reglas que el script no valida

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
`ASIENTO`— la base garantiza de forma declarativa que el asiento vendido pertenece al bus
que realiza ese viaje, sin trigger.

---

## 12. Estado de verificación

Ejecutado el 07-sep-2026 sobre `benja@FREEPDB1`, contenedor `oracle-practica`:

- Las cinco funciones sueltas de la versión anterior fueron eliminadas del esquema.
- Los tres packages compilan sin errores: **6 objetos `VALID`**, 0 inválidos.
- Los dos triggers quedan `ENABLED` y su bloque de verificación pasa sus cuatro pruebas.
- Los siete bloques de `05_Demostraciones.sql` corren completos, incluidos los caminos de
  error (`NO_DATA_FOUND`, `e_jornada_excedida`, `e_viaje_no_programado`,
  `e_fuera_de_plazo`).
- Los datos quedan intactos tras la ejecución: 6 viajes, 4 ventas, 8 pasajes, 18 filas de
  historial, 8 asignaciones de conductor. Todos los `ROLLBACK` operan.

---

## 13. Lo que falta

### Documentación

Secciones **8.2, 9.2, 10, 11, 12, 13 y 14** del informe. Ahora que el código existe se
pueden completar con la implementación real. La sección 11 (Triggers) tiene material
directo en `04_Triggers.sql` y en la §6 de esta guía. La sección 10 (Packages) tiene su
argumento en la §3.

La pauta exige además, en Anexos, **"incluir el código completo utilizado en el proyecto"**.

**En `ANEXO_Tablas_de_Referencia.docx`:**
- Tabla 29 — corregir el valor retornado de `fn_tarifa_vigente` a *"Identificador de la
  tarifa vigente"*, y agregar una fila para `fn_asiento_ocupado`.
- Tablas 28 y 29 — los nombres ahora se califican con el package
  (`pkg_calculos.fn_tarifa_vigente`, `pkg_operaciones.sp_vender_pasaje`).
- Tablas 26 y 27 — las ocho excepciones de usuario ahora son públicas y se capturan por
  nombre calificado.

### Observación sobre los datos de prueba

El poblamiento usa fechas fijas de septiembre de 2026. Con el paso del tiempo todos sus
viajes quedan en el pasado, lo que tiene dos efectos:

- Hay viajes en estado `PRO` cuya salida ya ocurrió, que es una inconsistencia entre el
  estado y la fecha.
- La ventana de cuatro horas de RF-02 no puede cumplirse con ningún pasaje existente, por
  lo que el bloque 7 de las demostraciones debe preparar su propio escenario antes de
  probar el camino de éxito.

**Conviene generar las fechas del poblamiento relativas a `SYSDATE`.** Es un cambio
acotado al DDL y haría que la demostración funcione cualquier día, lo que importa para
una defensa en vivo.

### Preguntas abiertas con el profesor

¿Se espera una cantidad mínima de RECORD, VARRAY y cursores, o se justifica según lo que
el caso necesite?
