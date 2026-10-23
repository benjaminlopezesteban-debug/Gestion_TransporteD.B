# Contexto integrador del proyecto — Sistema de Gestión de Transporte Interurbano

**BDY1103 Taller de Base de Datos · Duoc UC · Benjamín López**
**Estado verificado el 21-09-2026** contra `benja@FREEPDB1`

> Este archivo existe para que cualquier persona —o cualquier sesión nueva— pueda
> retomar el trabajo sin leer el historial completo. Contiene el contexto, las
> decisiones tomadas y por qué, los flujos, el estado real verificado y lo que
> queda pendiente. Cuando algo esté roto o incompleto, lo dice.

---

## 1. Qué es el proyecto

Sistema de gestión para una **empresa de transporte interurbano de pasajeros** que
opera desde el Terminal Alameda (Santiago) hacia siete destinos de la zona
centro-sur. El proyecto es **semestral y único**: se evalúa en tres entregas
parciales, y cada una agrega una capa sobre la misma base.

**Entregable de cada parcial:** informe técnico + script PL/SQL + defensa oral.
La defensa es individual aunque el trabajo sea en equipo.

### Resultados de aprendizaje que evalúa la pauta

| | Indicador | Qué exige |
|---|---|---|
| **RA1** | IL1.1 | Tipos compuestos: **RECORD** y **VARRAY** |
| | IL1.2 | Cursores explícitos **con parámetros**, con **más de un LOOP simultáneo** |
| | IL1.3 | Excepciones **predefinidas** y **de usuario** |
| | IL1.4 | Evalúa procedimientos, funciones, packages y triggers (comparativo) |
| **RA2** | IL2.1 | Procedimientos y funciones almacenadas invocables desde otros programas |
| | IL2.2 | Packages con constructores públicos y privados |
| | IL2.3 | Triggers a nivel de sentencia y de fila |
| **RA3** | IL3.x | NoSQL — **aún no iniciado** |

---

## 2. Entorno

| | |
|---|---|
| Motor | Oracle Database 26ai Free, en Docker |
| Imagen | `gvenzl/oracle-free:latest` |
| Contenedor | `oracle-practica` |
| Servicio | **`FREEPDB1`** — no es `XE` ni `XEPDB1` |
| Cadena | `benja/benja123@//localhost:1521/FREEPDB1` |
| SYS | `ORACLE_PASSWORD=Oracle123` |

```bash
docker start oracle-practica            # tarda ~20 s en aceptar conexiones
docker exec -i oracle-practica sqlplus -S benja/benja123@localhost:1521/FREEPDB1
```

> **El contenedor se detiene solo con frecuencia.** Si aparece
> `failed to connect to the docker API`, es Docker Desktop cerrado, no el
> contenedor. Levantar Docker Desktop primero.

---

## 3. Estructura de carpetas

```
Taller_BBDD/
├── CONTEXTO_PROYECTO.md          ← este archivo
├── README.md
├── 00_Documentacion/
│   ├── 00_DocumentacionAsignatura/   contexto del curso y la pauta (PDF)
│   └── 01_DocumentacionProyecto/
│       ├── Doc.Evaluación1/          pauta y plantillas del parcial 1
│       └── Informe/
│           ├── DP_Informe_Requerimiento.docx      ← entregable, 12 páginas
│           ├── DP_DefinicionRequerimientos.md     ← cuaderno de trabajo, D-01..D-25
│           ├── DP_ModeloRelacionalFinal.pdf
│           └── Anexos/ANEXO_Tablas_de_Referencia.docx  ← 29 tablas, 13 páginas
├── 01_Models/                     modelo de Oracle SQL Data Modeler
└── 02_Scripts/
    ├── DDL/Modelo_GestionTransporte_DDL.sql
    ├── DML/ScriptLimpiezaDB.sql
    ├── GUIA_Construccion_Script.md   ← DESACTUALIZADA, ver §10
    ├── Exerc/                        ejercicios de clase, ajenos al proyecto
    └── PLSQL/
        ├── 01_Calculos.sql
        ├── 02_Record_Varray.sql
        ├── 03_Consultas_Cursores.sql
        ├── 04_Procedimiento.sql
        ├── 05_Triggers.sql
        ├── 06_scriptPresentacion.sql   ← CONSOLIDADO para la defensa
        └── Borradores/                 arquitectura de packages descartada
```

---

## 4. Modelo de datos

**14 entidades en 3ª forma normal.** El DDL las crea, define sus restricciones y
las puebla con datos de prueba.

```
TERMINAL ──< RUTA >── TERMINAL          (origen y destino)
RUTA ──< TARIFA >── TIPO_ASIENTO        (precio por ruta, tipo y vigencia)
BUS ──< ASIENTO >── TIPO_ASIENTO
RUTA ──< VIAJE >── BUS
VIAJE ──< VIAJE_CONDUCTOR >── CONDUCTOR (N:M con rol TIT/REL)
PASAJERO ──< VENTA
VENTA ──< PASAJE >── VIAJE, ASIENTO, TARIFA, PASAJERO, ESTADO_PASAJE
PASAJE ──< PASAJE_ESTADO_HIST
```

### Datos de prueba

| | |
|---|---|
| Terminales | 8 — Alameda (origen) + Rancagua, Talca, Linares, Cauquenes, Chillán, Bulnes, Concepción |
| Rutas | 7, todas desde Alameda. De 75 min (Rancagua) a 390 min (Concepción) |
| Buses | 3 — JKLM45 (12 asientos), PQRS78 (10), TUVW12 (10) |
| Tipos de asiento | Semi Cama, Salón Cama, Premium Suite |
| Conductores | 4 |
| Tarifas | 17, una de ellas vencida (id 17) para demostrar la vigencia |
| Viajes | 6 · Pasajes | 8 · Historial | 18 filas |

### Tres decisiones estructurales que conviene entender antes de tocar nada

**1. La capacidad del bus no es una columna: es el número de filas en `ASIENTO`.**
La PK compuesta `(id_bus, nro_asiento)` hace imposible que exista un número
declarado que contradiga la realidad. Eso es RN-01, y no se programa.

**2. `PASAJE` lleva `id_bus` a propósito, con dos FK compuestas:**
`(id_viaje, id_bus) → VIAJE` y `(id_bus, nro_asiento) → ASIENTO`. Entre las dos,
la base garantiza de forma declarativa que el asiento vendido pertenece al bus que
realiza ese viaje. Sin trigger y sin validación.

**3. El índice único parcial `ux_pasaje_asiento_vigente`:**

```sql
CREATE UNIQUE INDEX ux_pasaje_asiento_vigente ON pasaje (
    CASE WHEN id_estado IN (1,2,3) THEN id_viaje    END,
    CASE WHEN id_estado IN (1,2,3) THEN id_bus      END,
    CASE WHEN id_estado IN (1,2,3) THEN nro_asiento END
);
```

Oracle no tiene índices únicos parciales, pero **un índice único ignora las filas
cuyas columnas indexadas son todas nulas**. Los `CASE` devuelven el valor real
cuando el estado ocupa asiento y `NULL` cuando no. Al anular, el pasaje sale del
índice y su asiento vuelve a estar disponible **sin borrar el registro**. Un
`UNIQUE` corriente impediría revender. Esto resuelve RN-06 y RN-09 a la vez.

---

## 5. Requerimientos y reglas

### Requerimientos funcionales

| RF | Proceso | Estado |
|---|---|---|
| RF-01 | Venta de pasajes | ✅ `sp_venta_pasajes` |
| RF-02 | Anulación de pasaje | ✅ `sp_anular_pasaje` (agregado el 10-09) |
| RF-03 | Programación de viajes | ✅ `sp_programacion_viajes` |
| RF-04 | Consulta de disponibilidad de asientos | ⚠️ solo bloques anónimos |
| RF-05 | Registro de viajes (pasajeros por asiento) | ✅ bloque con cursor parametrizado |
| ~~RF-06~~ | Ocupación por ruta e ingresos | ❌ fuera de alcance — es analítica de gestión |

### Reglas de negocio

| RN | Enunciado | Dónde se hace cumplir |
|---|---|---|
| RN-01 | La capacidad del bus es su número de asientos | **Estructura** · PK compuesta de `ASIENTO` |
| RN-02 | El origen de una ruta es distinto del destino | **Estructura** · FK + CHECK |
| RN-03 | Un conductor no puede estar en dos viajes solapados | **PL/SQL** · `fn_recurso_ocupado` |
| RN-04 | Un bus no puede estar en dos viajes solapados | **PL/SQL** · `fn_recurso_ocupado` |
| RN-05 | Cada pasaje pertenece a un pasajero y a un viaje | **Estructura** · FK compuestas |
| RN-06 | Un asiento no se vende dos veces para el mismo viaje | **Estructura** · índice único parcial |
| RN-07 | El precio depende de ruta, tipo de asiento y vigencia | **Estructura + PL/SQL** · `TARIFA` |
| RN-08 | El pasaje recorre un ciclo de estados y queda registrado | **Triggers** |
| RN-09 | Al anular, el asiento vuelve a estar disponible | **Estructura** · el índice ignora `ANU` |
| RN-10 | Un conductor no supera 5 h; más allá exige relevo | **PL/SQL** · `fn_conductores_requeridos` |

**RN-10 se agregó a mitad del proyecto.** Antes, `VIAJE_CONDUCTOR` era una
conveniencia; con RN-10 pasa a ser una **obligación legal**, y eso justifica la
relación N:M ante el profesor mucho mejor que "en recorridos largos la tripulación
se releva".

---

## 6. Estado verificado de la base

Verificado el **21-09-2026**. Once objetos, todos `VALID`:

| Tipo | Objeto |
|---|---|
| FUNCTION | `obtener_precio_tarifa`, `fn_conductores_requeridos`, `fn_recurso_ocupado`, `fn_llegada_estimada` |
| PROCEDURE | `sp_programacion_viajes`, `sp_venta_pasajes`, `sp_anular_pasaje`, `sp_buscar_bus_libre`, `sp_buscar_conductor_libre` |
| TRIGGER | `trg_pasaje_historial`, `trg_pasaje_no_revive` |
| TYPE | `tv_asientos` |

Datos: 18 tablas (14 del modelo + 4 de la extensión de VSCode), 6 viajes,
8 pasajes, 18 filas de historial.

---

## 7. Arquitectura del script

**Los niveles no ordenan por dificultad. Ordenan por quién necesita el resultado
de quién.** El número del archivo es el orden real de ejecución.

```
DDL  →  01_Calculos  →  02_Record_Varray  →  03_Consultas_Cursores  →  05_Triggers  →  04_Procedimiento
```

> `05_Triggers` debe existir **antes de ejecutar** la venta y la anulación, aunque
> no haga falta para que compilen.

| Nivel | Qué hace | Archivo |
|---|---|---|
| 1 | Resuelve **un valor** | `01_Calculos.sql` |
| — | Demuestra los tipos compuestos | `02_Record_Varray.sql` |
| 2 | Recorre y **presenta** un conjunto | `03_Consultas_Cursores.sql` |
| — | Audita y cuida la integridad | `05_Triggers.sql` |
| 3 | Valida y **escribe** | `04_Procedimiento.sql` |

### Contenido por archivo

**`01_Calculos.sql`** — `obtener_precio_tarifa`, `fn_conductores_requeridos`,
`fn_recurso_ocupado`, `fn_llegada_estimada` son funciones reales. Los bloques 1.3
(asientos disponibles) y 1.4 (porcentaje de ocupación) siguen siendo **bloques
anónimos**.

**`02_Record_Varray.sql`** — cuatro bloques anónimos: RECORD con `%TYPE` de varias
tablas, RECORD anclado con `%ROWTYPE`, VARRAY, y los dos juntos. Más
`fn_proceso_venta`, que **no compila** (ver §10).

**`03_Consultas_Cursores.sql`** — cursor sin parámetros con `OPEN/FETCH/CLOSE`
(control de flota), cursor parametrizado en forma `FOR` (registro de viajes),
`fn_buscar_conductor_libre` (**no compila**, ver §10) y `sp_buscar_bus_libre`.

**`04_Procedimiento.sql`** — el tipo `tv_asientos` y los tres procedimientos de
negocio: 4.1 programación, 4.2 venta, 4.3 anulación.

**`05_Triggers.sql`** — `trg_pasaje_historial` (audita) y `trg_pasaje_no_revive`
(cuida la integridad).

**`06_scriptPresentacion.sql`** — **el consolidado que se lleva a la defensa.**
Reordena todo en cinco secciones: funciones, records/varray, cursores,
procedimientos, triggers. **No es idéntico a los archivos 01-05** — ver §9.

---

## 8. Los dos flujos centrales

### RF-03 · Programación de un viaje

Entra: **ruta, fecha-hora de salida, bus**. Nada más. Ni la llegada ni los
conductores se ingresan.

```
1. fn_llegada_estimada(ruta, salida)        → la llegada
   fn_conductores_requeridos(ruta)          → 1 ó 2      [RN-10]
   NO_DATA_FOUND → e_ruta_inexistente
2. salida > SYSTIMESTAMP                    → e_salida_en_pasado
3. no hay viaje igual en ruta+salida        → e_viaje_duplicado
4. fn_recurso_ocupado(bus)                  → e_bus_ocupado  [RN-04]
      al rechazar, llama a sp_buscar_bus_libre y lista alternativas
5. OPEN c_conductores_libres                                 [RN-03]
      FETCH → titular
      si requeridos > 1: FETCH → relevo
      NOTFOUND → e_sin_conductores                           [RN-10]
6. INSERT VIAJE + una fila por conductor en VIAJE_CONDUCTOR
```

**El detalle que más conviene saber defender:** los dos conductores salen de **dos
`FETCH` consecutivos sobre el mismo cursor**. Un cursor no devuelve dos veces la
misma fila, así que el relevo es distinto del titular *por definición*. No hay
parámetro de exclusión ni excepción de "conductor repetido" porque el caso no
puede ocurrir. Y RN-10 queda cubierta por el mismo mecanismo: si la ruta exige dos
y solo hay uno libre, el segundo `FETCH` no encuentra fila.

### RF-01 · Venta de pasajes

Entra: **viaje, comprador, VARRAY de asientos** (máximo 6), canal y medio de pago.

```
1. el viaje existe y está en 'PRO'          → e_viaje_no_vendible
2. el VARRAY no viene vacío                 → ORA-20030
3. INSERT VENTA (cabecera)
4. por cada asiento del VARRAY:
      OPEN c_asiento → llena el RECORD tr_pasaje de una vez
         NOTFOUND → e_asiento_no_vendible
      el asiento está libre                 → e_asiento_ocupado  [RN-06]
      INSERT PASAJE  → dispara trg_pasaje_historial              [RN-08]
```

**El historial no se escribe aquí.** Cada `INSERT` en `PASAJE` dispara el trigger,
que registra la transición solo. Si el procedimiento también insertara en
`PASAJE_ESTADO_HIST`, cada venta quedaría registrada dos veces.

### RF-02 · Anulación

Entra: **id del pasaje y motivo**.

```
1. el pasaje existe                         → e_pasaje_inexistente
2. no estaba ya anulado                     → e_ya_anulado        [RN-08]
3. faltan ≥ 4 h para la salida              → e_fuera_de_plazo
4. SET_CLIENT_INFO(motivo)
   UPDATE pasaje SET id_estado = 4          → dispara el trigger
   SET_CLIENT_INFO(NULL)
```

**RN-09 no se programa.** El procedimiento no toca la disponibilidad: al cambiar
el estado a `ANU`, el índice único parcial deja de incluir esa fila y el asiento
se libera solo.

**El motivo llega al trigger por el contexto de la sesión**, porque un trigger no
recibe parámetros. Se declara con `DBMS_APPLICATION_INFO.SET_CLIENT_INFO` antes
del `UPDATE` y `trg_pasaje_historial` lo lee con `SYS_CONTEXT`. El `WHEN OTHERS`
lo limpia siempre: si quedara cargado con el motivo de una anulación fallida, el
trigger lo pegaría a la siguiente transición de esa sesión.

**Verificado el 21-09-2026**, los cuatro caminos:

```
1) pasaje inexistente       → Rechazado: el pasaje 999 no existe.
2) viaje ya salido          → Rechazado: solo se anula hasta 4 horas antes...
3) escenario preparado      → Pasaje 5 anulado | el asiento 6 vuelve a estar disponible
4) segundo intento          → Rechazado por RN-08: ya estaba anulado.
   historial del pasaje 5: 3 filas · con motivo registrado por el trigger: 1
```

---

## 9. Decisiones tomadas y por qué

### Sobre la arquitectura

**Se construyeron tres packages y después se descartaron.** `pkg_calculos`,
`pkg_consultas` y `pkg_operaciones` llegaron a compilar y a pasar sus pruebas,
pero el resultado se juzgó **sobreproducido y alejado de lo que el informe
especificaba** para RECORD, VARRAY, cursores y excepciones. Se volvió a la
arquitectura de funciones y procedimientos sueltos. Los packages quedan en
`PLSQL/Borradores/` — **no se cargan y no deben cargarse**; ya se eliminaron de la
base con `DROP PACKAGE`.

> El argumento a favor de los packages sigue siendo válido y sirve para RA2 (IL2.2
> pide packages con constructores públicos y privados): los tipos RECORD y las
> excepciones de usuario se vuelven parte de la interfaz, y aparece la distinción
> público/privado. Si el parcial 2 lo exige, el borrador está listo.

**Todo cálculo repetido se convirtió en función.** Una auditoría encontró la
tarifa resuelta en 4 lugares, el criterio de "asiento ocupado" en 4 y la fórmula
de conductores en 4. El principio aplicado: *llamar a la función cuando el dato
que necesita ya existe en ese contexto; no llamarla cuando el dato de entrada no
existe todavía o cuando convertiría una consulta de conjunto en N llamadas.*

**`fn_recurso_ocupado` es UNA función para bus y conductor.** El predicado de
solapamiento —`salida < otra_llegada AND otra_salida < llegada`— es idéntico; lo
único que cambia es de dónde sale el compromiso (el bus es columna de `VIAJE`, el
conductor exige pasar por `VIAJE_CONDUCTOR`). Se resuelve con dos parámetros de
recurso y un `OR`, no duplicando la regla del intervalo.

**`fn_conductores_requeridos` recibe la RUTA, no el viaje.** Así puede llamarse
*antes* de que el viaje exista, que es justo lo que necesita la programación. Con
el parámetro anterior (`id_viaje`) esa llamada era imposible y la fórmula quedaba
duplicada.

### Sobre el modelo

**`llegada_prog` se almacena aunque sea derivable.** Verificado: en los seis
viajes es exactamente `salida_prog + duración de la ruta`. Un profesor puede
señalarlo como dependencia transitiva. **La respuesta que sostiene el diseño:**
`llegada_prog` es la llegada *comprometida*; `duracion_estimada_min` es una
*estimación de la ruta que puede cambiar*. Si mañana se corrige la duración, los
viajes ya vendidos deben conservar la llegada con la que se vendieron. Son dos
hechos distintos que hoy coinciden. Hay además una razón práctica:
`fn_recurso_ocupado` compara contra `v.llegada_prog` directamente; si fuera
derivada, cada verificación de solapamiento tendría que unir con `RUTA` y hacer
aritmética dentro del `WHERE`.

**El historial lo escribe el trigger, no los procedimientos.** Debe registrarse
siempre que un pasaje cambie, sin importar quién lo modifique. Si viviera dentro
de cada procedimiento, bastaría un `UPDATE` manual desde SQL Developer para que la
transición se perdiera en silencio. El trigger se dispara por el **evento**, no
por la llamada.

**El VARRAY tuvo que subir a tipo de esquema.** `tv_asientos` se declara con
`CREATE OR REPLACE TYPE` porque un VARRAY declarado dentro de un procedimiento
muere con él y no puede ser **parámetro**. Va `NUMBER(4)` y no
`asiento.nro_asiento%TYPE` porque un tipo de esquema es SQL, no PL/SQL, y ahí el
anclaje `%TYPE` no existe.

### Sobre las transacciones

**Ningún procedimiento hace `COMMIT` ni `ROLLBACK`.** No sabe si es la operación
completa o un paso dentro de una transacción mayor; quien lo invoca sí lo sabe. El
menú debe confirmar tras el éxito y revertir tras un rechazo.

**Primero se valida todo, después se escribe.** Cuando se llega al primer `INSERT`
ya no queda nada que pueda fallar por regla de negocio.

### Sobre el informe

- Límite de **12 páginas**; las 29 tablas se movieron a un anexo externo.
- Se eliminó el actor "programador de flota".
- Se cambió "manifiesto" por **"registro de viajes"**.
- Las rutas se rehicieron con los **siete destinos reales** del negocio: antes el
  DDL nombraba La Serena, Valparaíso y Temuco, que no existen en el contexto.

---

## 10. Problemas conocidos y pendientes

### Bloqueantes para la presentación

**1. `fn_buscar_conductor_libre` no compila.** Está en
`03_Consultas_Cursores.sql:249` y en `06_scriptPresentacion.sql:431`.

```
PLS-00503: RETURN <value> statement required for this return from function
```

Declara `RETURN conductor.id_conductor%TYPE` pero su cuerpo solo tiene un
`return;` sin valor dentro del `LOOP`. **Nadie la llama** —
`sp_programacion_viajes` usa el cursor con doble `FETCH`—, así que es código
muerto y roto. Si el profesor ejecuta el 06 de principio a fin, verá el error.
**Opciones:** eliminarla, o darle un `RETURN v_id;` real.

**2. `fn_proceso_venta` tampoco compila.** Está en `02_Record_Varray.sql:227`, con
el mismo problema: declara un tipo de retorno y el cuerpo no tiene `RETURN`.
Tampoco la llama nadie.

### De exactitud

**3. `06_scriptPresentacion.sql:147`** dice *"1.5 Calcular fecha y hora de
llegada: RF-04(programación)"*. Programación es **RF-03**; RF-04 es la consulta de
disponibilidad. Ya corregido en `01_Calculos.sql`, pendiente en el 06.

**4. `GUIA_Construccion_Script.md` está doblemente desactualizada.** Describe la
arquitectura de **tres packages** que se descartó. Hay que reescribirla o
retirarla del entregable.

**5. El artefacto de arquitectura publicado** declara que *"el procedimiento de
anulación queda fuera de esta entrega"*, lo cual dejó de ser cierto el 10-09.

### De diseño, no urgentes

**6. El poblamiento usa fechas fijas de septiembre de 2026.** Todos los viajes
quedaron en el pasado: hay viajes en estado `PRO` cuya salida ya ocurrió, y la
ventana de 4 h de RF-02 no se puede cumplir con ningún pasaje existente sin
preparar el escenario. **Conviene generar las fechas relativas a `SYSDATE`** — es
un cambio acotado al DDL y haría que la demostración funcione cualquier día.

**7. `uk_tarifa_vigencia` no impide vigencias solapadas.** La UK es
`(id_ruta, id_tipo_asiento, vigencia_desde)`: prohíbe repetir la fecha de inicio,
no los rangos superpuestos. Comprobado: con dos tarifas vigentes para la misma
combinación, un `SELECT INTO` levanta `TOO_MANY_ROWS`.

**8. `obtener_precio_tarifa` se traga sus excepciones sin `RETURN`.** Los
manejadores de `NO_DATA_FOUND` y `TOO_MANY_ROWS` solo imprimen; al terminar sin
devolver valor, el invocador recibe `ORA-06503: Function returned without value`.
Hoy no se manifiesta porque el cursor de la venta ya filtra los asientos con
tarifa vigente.

**9. `NVL(MAX(id))+1` no es seguro con sesiones concurrentes.** Dos llamadas
simultáneas calcularían el mismo id. Para el proyecto sirve; en producción
corresponde una `SEQUENCE`. No hay ninguna en el DDL.

**10. `06_scriptPresentacion.sql` no incluye `trg_pasaje_no_revive`.** Solo tiene
`trg_pasaje_historial`. Si la defensa se hace con el 06, falta la mitad de RN-08.

**11. Nada valida que el bus esté físicamente en el terminal de origen.** RN-04
solo prohíbe solaparse en el tiempo: un bus que llega a Concepción a las 14:30
puede, según el modelo, salir de Santiago a las 14:30. Es un hueco real del
negocio; conviene tenerlo identificado antes de que lo pregunten.

### De documentación

- Secciones **8.2, 9.2, 10, 11, 12, 13 y 14** del informe.
- La pauta exige en anexos **"el código completo utilizado en el proyecto"**.
- Anexo tabla 29: corregir el valor retornado de la función de tarifa y agregar
  una fila para el criterio de asiento ocupado.

---

## 11. Divergencias entre los archivos 01-05 y el 06

**Esto importa: el 06 no es la concatenación de los otros.** Si se modifica un
objeto hay que hacerlo en los dos lugares.

| Objeto | En 01-05 | En 06 |
|---|---|---|
| `fn_asientos_disponibles` | bloque anónimo (1.3) | **función real** (línea 66) |
| `sp_buscar_conductor_libre` | procedimiento (03) | **no está** |
| `fn_buscar_conductor_libre` | función rota (03) | función rota (431) |
| `trg_pasaje_no_revive` | trigger (05) | **no está** |
| `fn_proceso_venta` | función rota (02) | **no está** |

La base de datos refleja **la versión 01-05**: tiene
`sp_buscar_conductor_libre` y `trg_pasaje_no_revive`, y no tiene
`fn_asientos_disponibles` como función.

---

## 12. Errores que costaron tiempo

Vale la pena tenerlos a mano para no repetirlos.

| Síntoma | Causa y solución |
|---|---|
| `ORA-12514 service not available` | El servicio es **`FREEPDB1`**, no `XE` ni `XEPDB1` |
| `SP2-0734: unknown command` tras un `PROMPT` | Un `PROMPT` que termina en `---` se come la línea siguiente en SQL\*Plus. Usar `PROMPT` sin guiones |
| `PLS-00103: Encountered the symbol "/"` | La barra `/` debe ir **sola** en su línea; un comentario pegado la rompe |
| `ORA-00904` con `.COUNT` | Los métodos de colección **no pueden aparecer dentro de una sentencia SQL**. Pasarlos por una variable |
| `PLS-00320` | Un campo de RECORD llamado igual que una tabla: PL/SQL resuelve el identificador contra el campo. Renombrar el campo |
| Una función devuelve `NULL` en vez de fallar | `NO_DATA_FOUND` levantado dentro de una función **llamada desde SQL** se convierte en `NULL` silencioso. Por eso una función que levanta excepciones no debe ir en el `WHERE` de un cursor |
| Se pierde la fracción de segundo | `TIMESTAMP + NUMBER` degrada a `DATE`. Usar `NUMTODSINTERVAL(min,'MINUTE')`, no `/1440` |
| Un `FOR` no ve su índice en el manejador | La variable del `FOR` muere con el bucle. Guardar el valor en una variable antes del `RAISE` |
| `PLS-00307: too many declarations` | No se puede sobrecargar por `%TYPE` si ambos resuelven a `NUMBER` |
| Una función local no se puede usar en SQL | El motor SQL no ve los subprogramas declarados en el bloque. Debe ser objeto almacenado |

**Regla que resume varias de las anteriores:** *una función es segura dentro de un
cursor solo si su "no encontré nada" es un valor legítimo, no una excepción.*
`fn_recurso_ocupado` usa `MIN()` justamente para eso: devuelve `NULL` cuando el
recurso está libre, y por eso puede vivir dentro de un `WHERE`.

---

## 13. Artefactos publicados

| | |
|---|---|
| Arquitectura del script | https://claude.ai/code/artifact/6b53837d-318d-44ae-94c3-ae2980003fd0 |
| Prototipo de frontend (MVP) | https://claude.ai/code/artifact/9b4fa5a1-af55-4925-bc04-2535e743b52c |

El **prototipo** es un MVP autónomo en HTML+JS, sin conexión a Oracle. Replica la
lógica de los tres procedimientos con los datos reales del DDL, tiene portal de
pasajeros (compra con mapa de asientos y anulación) y portal administrativo con
login (`admin` / `admin123`). Imprime una **consola de traza** que muestra qué
procedimientos, funciones y reglas se ejecutarían en cada acción. Sus fechas se
generan relativas al día actual, así que funciona cualquier día.

> El artefacto de arquitectura necesita una actualización: ver §10, punto 5.

---

## 14. Preguntas abiertas con el profesor

1. ¿Se espera una cantidad mínima de RECORD, VARRAY y cursores, o se justifica
   según lo que el caso necesite?
2. ¿El parcial 2 exigirá packages (IL2.2 los menciona explícitamente)? De ser así,
   los borradores de `PLSQL/Borradores/` son el punto de partida.
3. RF-04 (disponibilidad) hoy solo tiene bloques anónimos. ¿Basta, o debe ser
   función almacenada?

---

## 15. Lo primero que haría una sesión nueva

1. Levantar Docker Desktop y `docker start oracle-practica`.
2. Leer este archivo y la §10 en particular.
3. **Decidir qué hacer con las dos funciones rotas** (§10, puntos 1 y 2) — es lo
   único que puede hacer fallar la defensa.
4. Decidir si el entregable es el 06 consolidado o los archivos 01-05, y
   **alinear las divergencias de la §11**.
5. Si hay tiempo: fechas relativas a `SYSDATE` en el poblamiento (§10, punto 6).
