# Definición de Requerimientos — Sistema de Gestión de Transporte Interurbano

> **Cuaderno de trabajo.** BDY1103 · Evaluación Parcial 1.
> No se entrega. El entregable es `DP_Informe_Requerimiento.docx`.
> Aquí se decide; allá se redacta.
>
> Estado: v7 · 06-sep-2026 · niveles 1 y 2 del script implementados

---

## 0. El alcance manda

Enunciado del profesor, literal. **Es el techo del proyecto:**

> *"Sistema para administrar pasajeros, buses, conductores, rutas, terminales, viajes,
> horarios, asientos y venta de pasajes. El sistema debe controlar la asignación de
> buses y la disponibilidad de asientos para cada viaje."*

**Regla de oro acordada:** dentro de ese enunciado se profundiza y se complejiza todo lo
que haga falta. Fuera de él, **no se avanza**. Este trabajo no recrea un sistema de
gestión de transporte completo: se centra en los requerimientos y las reglas que
sostienen el giro.

Cada vez que aparezca la tentación de agregar algo, la pregunta es: *¿está nombrado en
ese párrafo?* Si no, no entra.

---

## 1. Decisiones cerradas

Todo lo de esta sección está resuelto. No requiere más trabajo, sólo traslado al informe.

| ID | Decisión | Dónde va en el informe |
|---|---|---|
| **D-01** | El alcance es el enunciado del profesor, sin ampliaciones | 1.4 |
| **D-02** | Entra: catálogos (terminales, rutas, tipos de asiento, estados), flota (buses y sus asientos), programación de viajes con asignación de bus y conductores, venta de pasajes con selección de asiento, ciclo de vida del pasaje, control de disponibilidad de asientos | 1.4 |
| **D-03** | Tarificación por ruta, tipo de asiento **y vigencia comercial**. La vigencia se mantiene: RN-07 nombra la condición comercial. Benjamín lo confirmará con el profesor | 1.4 |
| **D-04** | **Sí** entran los reportes de **control operacional**, acotados a los estrictamente necesarios. **No** entran los reportes de analítica y gestión | 1.4 |
| **D-05** | No se listan exclusiones adicionales: el enunciado ya acota el dominio | 1.4 |
| **D-06** | El entorno de referencia es **Oracle Autonomous Database + SQL Developer**. El contenedor Docker local es sólo comodidad de desarrollo, no parte de la arquitectura propuesta | 1.5 |
| **D-07** | **RF-01 Venta.** Precondiciones: el viaje debe estar en estado PRO (programado) y el pasajero debe existir previamente. Resultado: registro de venta, registro del pasaje, la transacción, y el asiento queda no disponible | 3.1 |
| **D-08** | **RF-02 Anulación.** Sólo se anula hasta **4 horas antes** de la salida del servicio — lo que excluye anular pasajes utilizados o de viajes ya salidos. Resultado: se anula, se registra en el historial y el asiento vuelve a estar disponible | 3.1 |
| **D-09** | **RF-03 Programación.** Precondiciones: deben existir ruta, bus, conductor, horario y terminales. Resultado: el servicio queda coordinado y publicable | 3.1 |
| **D-10** | **Origen de los datos.** Catálogos, flota, conductores y operación los ingresa un administrativo. El pasajero se registra voluntariamente como prerrequisito para comprar. Los datos transaccionales los genera el sistema | 3.3 |
| **D-11** | Los datos de las tablas serán **simulados** para demostrar los procesos | 3.3 · ver P-03 |
| **D-12** | Las reglas de negocio **no se cumplen sólo con el modelo**: parte vive en procedimientos, funciones y excepciones. La trazabilidad regla → mecanismo se completará al desarrollar los scripts | 2.2 |
| **D-13** | **Convención de código:** toda abreviatura de estado (`PRO`, `VEN`, `ANU`, `PEN`, `UTI`…) se documenta en el comentario de su entidad. El significado no se intuye | transversal |
| **D-14** | **El pago y los ingresos quedan fuera del trabajo.** No se modela devolución de dinero, retención ni recaudación. La anulación cumple únicamente la regla de liberar el asiento | 1.4 |
| **D-15** | Los reportes operacionales se limitan a **dos**: RF-04 disponibilidad de asientos por viaje y RF-05 registro de viajes. No se amplía el catálogo de salidas | 1.4 · 3.1 |
| **D-16** | **RN-10 (nueva):** por ley un conductor no puede superar las 5 horas de conducción. Todo viaje que exceda ese límite exige al menos un conductor de relevo | 2.4 · 4.2 |
| **D-17** | Se elimina el actor *programador de flota*: sus responsabilidades quedan englobadas en **administrativo** | 2.2 |
| **D-18** | Se reemplaza el término *manifiesto de viaje* por **registro de viajes** en todo el proyecto | transversal |
| **D-19** | El poblamiento del DDL usaba La Serena, Valparaíso y Temuco, que **no están en el contexto de negocio**. Se rehízo con los 7 destinos reales: Rancagua, Talca, Linares, Cauquenes, Chillán, Bulnes y Concepción | anexo DDL |
| **D-20** | Sección 3.1 del informe: cada una de las 14 entidades se documenta con su tabla de *Nombre Dato · Tipo de Dato · Restricciones*, agrupadas en A) Catálogos, B) Flota, C) Operación y D) Comercial | 3.1 |
| **D-21** | El informe se limita a **12 páginas**. Las 29 tablas del proyecto viven en `Anexos/ANEXO_Tablas_de_Referencia.docx` y se referencian desde el cuerpo. Se eliminó el índice | transversal |
| **D-22** | **El profesor descartó las vistas** y cualquier elemento agregado: evaluará los scripts, sus flujos de trabajo y la justificación de por qué se hizo así. Las vistas creadas se eliminaron del script y de la base | script |
| **D-23** | El script se construye en **tres niveles por dependencia de datos**, no por complejidad: (1) cálculos escalares → futuras funciones, (2) consultas con cursores → futuros procedimientos de consulta, (3) operaciones de escritura → futuros procedimientos. Construir al revés obligaría a reescribir | script |
| **D-24** | Cada bloque anónimo se escribe con **frontera del objeto futuro**: entradas como `CONSTANT p_*` al inicio del `DECLARE`, retorno en una sola variable, cuerpo intacto. Convertirlo en función o procedimiento será mover líneas a la firma, no reescribir | script |
| **D-25** | El **índice único parcial** de RN-06 y RN-09 se implementó en el DDL (sección 3) y se verificó con tres casos: impide la doble venta, permite el mismo asiento en otro viaje, y permite revender tras anular | DDL |

### Información que el sistema genera (cerrado)

| # | Información | Quién la usa | Qué decisión habilita |
|---|---|---|---|
| I-01 | Viajes programados: ruta, bus, conductor, tarifa, asientos | Administración, pasajero | Saber qué viajes existen y cuáles puede adquirir el cliente |
| I-02 | Registro de ventas de pasajes | Administración | Registrar la venta e inhabilitar los asientos comprados |
| I-03 | Asientos disponibles de un viaje, en tiempo real | Administración, pasajero | Vender sólo lo que existe |
| I-04 | Asignación de buses a viajes | Administración | Controlar que ningún bus quede en dos servicios superpuestos |

---

## 2. Pendientes

Sólo queda lo que no depende del profesor. Lo demás está en §5.

### P-01 · Actores de cada requerimiento

Los campos "Actor" de RF-01 a RF-05 siguen vacíos. De D-10 se deducen tres roles:
**administrativo**, **pasajero** y **sistema**. Falta decidir si el vendedor de terminal
es un rol distinto del administrativo.

> ✍️ Benjamín, en los próximos días.

### P-02 · Requerimientos no funcionales

Sección 3.2 del informe, aún vacía. En un proyecto de base de datos los RNF que importan
son pocos y concretos:

- **Integridad:** las reglas se cumplen aunque el dato entre por otra vía que no sea la
  aplicación.
- **Trazabilidad:** toda transición de estado de un pasaje deja registro con fecha,
  usuario y motivo.
- **Tiempo de respuesta:** la consulta de disponibilidad debe resolverse en línea, porque
  bloquea la venta.

No copiar RNF de aplicación web (usuarios concurrentes, navegadores, accesibilidad): ese
fue el ruido de la plantilla anterior.

> ✍️ Tres o cuatro, no más.

### P-03 · Cómo declarar los datos simulados

Decidiste poblar las tablas con datos generados (D-11). Decláralo, no lo escondas: tus
propias notas registran que el profesor pregunta por el uso de IA.

Fraseo sugerido: *"Los datos de las tablas corresponden a un conjunto de prueba
construido para demostrar los procesos, no a datos operacionales reales."*

### P-04 · La tabla de tecnologías quedó rota

Al editarla se desarmaron las columnas. Esta es la versión limpia que refleja D-06, lista
para trasladar al informe:

| Componente | Tecnología | Rol en el proyecto |
|---|---|---|
| Motor de base de datos | Oracle Database (Autonomous Database) | Almacenamiento y ejecución de la lógica de negocio |
| Lenguaje procedimental | PL/SQL | Bloques anónimos, procedimientos, funciones, packages y triggers |
| Herramienta de desarrollo | Oracle SQL Developer | Desarrollo y ejecución sobre la base de datos |
| Modelado | Oracle SQL Developer Data Modeler | Modelo lógico y relacional, ingeniería directa a DDL |
| Control de versiones | Git | Versionado del DDL, scripts y documentación |

---

## 3. Requerimientos funcionales — estado

| ID | Proceso | Estado |
|---|---|---|
| RF-01 | Venta de pasajes | ✅ definido (D-07) · falta actor |
| RF-02 | Anulación de pasaje | ✅ definido (D-08) · falta actor |
| RF-03 | Programación de viajes | ✅ definido (D-09) · falta actor |
| RF-04 | **Consulta de disponibilidad de asientos por viaje** | ✅ reactivado como control operacional (D-04, D-15) |
| RF-05 | **Registro de viajes** (pasajeros de un viaje por asiento) | ✅ control operacional del embarque (D-15) |
| ~~RF-06~~ | Ocupación por ruta y período, ingresos | ❌ fuera: es analítica de gestión (D-04, D-14) |

**RF-04 y RF-05 no son reportes de gestión.** RF-04 lo exige el enunciado con todas sus
letras (*"controlar… la disponibilidad de asientos para cada viaje"*) y RF-05 es el
control operacional del embarque: el conductor necesita saber quién sube. Ambos se
justifican dentro del alcance, no como añadidos.

---

## 4. Trazabilidad técnica

Reparto definitivo de las técnicas que la rúbrica evalúa, ya sin el cálculo de devolución
(descartado por D-14).

| Proceso | Técnica | Por qué esa y no otra | Indicador |
|---|---|---|---|
| RF-01 Venta | **RECORD** con la estructura del pasaje | Varios atributos del mismo pasaje se manipulan como unidad antes de persistirlo | IE1.1.1 · 5% + 15% |
| RF-01 Venta | **VARRAY** con los asientos solicitados | Colección de tamaño acotado y conocido: nadie compra 200 asientos de una vez | IE1.1.1 |
| RF-01 Venta | Excepción de usuario `asiento_no_disponible` | Regla de negocio, no error de Oracle: necesita nombre propio | IE1.3.1 · 10% + 15% |
| RF-01 Venta | Excepción predefinida `DUP_VAL_ON_INDEX` | La dispara sola el índice único parcial al intentar revender un asiento vigente | IE1.3.1 |
| RF-01 Venta | Excepción de usuario `viaje_no_programado` | El viaje debe estar en estado PRO (D-07) | IE1.3.1 |
| RF-01 Venta | **Función** `fn_tarifa_vigente(ruta, tipo, fecha)` | Devuelve un valor a partir de parámetros y es invocable desde SQL: el caso de libro para una función | IE1.4.1 · 15% + 15% |
| RF-01 Venta | Excepción predefinida `NO_DATA_FOUND` | Una ruta y tipo sin tarifa vigente a la fecha del viaje | IE1.3.1 |
| RF-02 Anulación | Excepción de usuario `fuera_de_plazo` | La ventana de 4 horas es regla de negocio pura (D-08) | IE1.3.1 |
| RF-03 Programación | **Cursor con parámetro** (`id_bus`, rango de fechas) | Se consultan los viajes de *un* bus para detectar solapamiento; el parámetro evita recorrer toda la tabla | IE1.2.1 · 10% + 15% |
| **RF-04 Disponibilidad** | **Dos cursores simultáneos**: viajes → asientos de su bus | Estructura anidada natural del dominio, exigida por el enunciado | **IE1.2.1** |
| RF-04 Disponibilidad | **Función** `fn_asientos_disponibles(id_viaje)` | Reemplaza al cálculo de devolución como segundo caso de función almacenada | IE1.4.1 |
| RF-04 Disponibilidad | Excepción predefinida `ZERO_DIVIDE` | Un viaje sin asientos registrados rompe el cálculo de ocupación | IE1.3.1 |
| RF-05 Manifiesto | **Cursor con parámetro** (`id_viaje`) + loop anidado | Recorrer viaje → sus pasajes por piso y asiento | IE1.2.1 |
| Transversal | Evaluación procedimiento / función / package / trigger | Ítem (f) de la pauta: se argumenta, no se implementa aún | IE1.4.1 |

### Argumentos listos para la defensa

**"¿Por qué un VARRAY y no una tabla anidada?"**
Porque la cantidad de asientos que se compran en una operación tiene un límite conocido y
bajo. VARRAY declara ese límite en el tipo; una tabla anidada permitiría una colección sin
cota. La restricción del negocio queda expresada en la estructura de datos.

**"¿Por qué un cursor con parámetro y no un WHERE fijo?"**
Porque el mismo cursor sirve para cualquier bus o cualquier viaje sin reescribirlo. El
parámetro convierte una consulta específica en un bloque reutilizable.

**"¿Por qué una función y no un procedimiento?"**
Porque devuelve un único valor calculado a partir de sus parámetros y no modifica estado.
Eso permite además invocarla desde una sentencia SQL, cosa que un procedimiento no admite.

---

## 5. Preguntas para el profesor

> Para la clase de mañana. Ordenadas por impacto: las del bloque A cambian **qué se
> construye**; las del bloque B, **cómo se evalúa**. Cada una lleva el supuesto con el que
> se avanza si no hay respuesta, para que el trabajo no se detenga.

### Bloque A — Definen qué se construye

**A-1 · ¿Hasta dónde llegan los reportes?**
El enunciado pide "controlar la asignación de buses y la disponibilidad de asientos".
¿Eso se satisface con consultas de control operacional (disponibilidad por viaje,
manifiesto de embarque), o además espera reportes de gestión (ocupación por ruta y
período, ingresos)?
*Supuesto actual:* sólo control operacional, dos salidas (RF-04 y RF-05).

**A-2 · ¿Qué entiende por "condición comercial" en la regla del precio?**
La regla dice que el precio varía según *tipo de asiento, ruta o condición comercial*.
¿Se refiere a vigencia temporal de tarifas, a descuentos por tipo de pasajero (tercera
edad, estudiante), o a promociones? Define si la tabla de tarifas lleva vigencia.
*Supuesto actual:* vigencia temporal; la tabla la conserva.

**A-3 · ¿El pago entra en el alcance?**
¿Se espera registrar medio de pago y recaudación, o basta con registrar la venta y el
pasaje? Y en la anulación, ¿debe calcularse devolución de dinero?
*Supuesto actual:* no. La anulación sólo libera el asiento.

**A-4 · El enunciado pedía 10 entidades y el modelo quedó en 14.**
El modelo se rediseñó para cumplir las reglas de no-solapamiento y de estados del pasaje,
lo que obligó a separar entidades. ¿El número era referencial o hay un límite real?

### Bloque B — Definen cómo se evalúa

**B-1 · ¿Cuál es la plantilla correcta del informe?**
La plantilla disponible es la de Ingeniería de Software (historias de usuario, product
backlog, sprints). Esa estructura no coincide con los apartados que pide la pauta de
BDY1103. ¿Hay una plantilla propia de la asignatura, o se adapta la estructura a los
apartados de la pauta?
*Supuesto actual:* estructura según los apartados de la pauta.

**B-2 · ¿La ponderación es 40/60 o 30/10/60?**
La pauta indica 40% encargo y 60% presentación. Los apuntes de la clase del 27 de agosto
registran 30% encargo, 10% informe y 60% presentación. ¿Cuál rige?

**B-3 · En esta entrega, ¿los procedimientos, funciones, packages y triggers se
implementan o sólo se evalúan?**
La pauta dice "evaluar la implementación… para construir una solución integral", y el
desarrollo de esos objetos corresponde al RA2 (Parcial 2).
*Supuesto actual:* en la Parcial 1 se argumenta la estrategia; se implementan los bloques
anónimos, cursores y excepciones del RA1.

**B-4 · ¿Hay una cantidad mínima esperada de RECORD, VARRAY y cursores?**
Los apuntes registran "estimar cuántos records y cuántos cursores según mis tablas".
¿Existe un mínimo, o se justifica según lo que el caso necesite?
*Supuesto actual:* los que el caso exija, cada uno justificado.

### Bloque C — Confirmar

**C-1 · Uso de IA.** ¿Cómo debe declararse en el informe? ¿Hay un apartado específico, o
se menciona en la metodología?

**C-2 · Datos de prueba.** ¿Acepta poblamiento sintético para la demostración, o espera
un volumen o realismo determinado?

**C-3 · Informe individual o de equipo.** La evaluación es individual pero se trabaja en
equipos de hasta tres. ¿Se entrega un informe por equipo con defensa individual, o un
informe por estudiante?

---

## 6. Correspondencia con el informe

El informe migró a la **plantilla del profesor** (`Doc.Evaluación1/Estructura_Informe_Proyecto_Base_Datos_Cafeteria.docx`): 17 secciones en lugar de 9.

| Sección del informe | Estado |
|---|---|
| 1.1 Descripción del proyecto | ✅ escrita |
| 1.2 Problemática | ✅ escrita |
| 1.3 Objetivo general | ✅ escrita |
| 1.4 Objetivos específicos | ✅ 5 OE |
| 1.5 Alcance | ✅ escrita |
| 1.6 Tecnologías utilizadas | ✅ escrita |
| 2.1 Descripción del negocio | ✅ escrita |
| 2.2 Actores del sistema | ✅ propuestos — **validar** (P-01) |
| 2.3 Requerimientos funcionales | ✅ RF-01 a RF-05 con detalle |
| 2.4 Reglas de negocio | ✅ RN-01 a RN-09 (sección añadida a la plantilla) |
| 3.1 Datos que deben almacenarse | ✅ 14 entidades agrupadas |
| 3.2 Información que genera | ✅ I-01 a I-05 |
| 4.1 Modelo de datos | ✅ relaciones explicadas |
| 4.2 Trazabilidad regla → mecanismo | ✅ las 9 reglas |
| 5.1–5.3 RECORD y VARRAY | ✅ escritas |
| 6.1–6.6 Cursores | ✅ escritas |
| 7.1–7.4 Excepciones | ✅ escritas |
| 8.1 Identificación de procedimientos | ✅ 4 procedimientos |
| 9.1 Identificación de funciones | ✅ 3 funciones |
| 8.2 / 9.2 justificaciones | ⬜ tras implementar |
| 10 Packages · 11 Triggers · 12 Consideraciones | ⬜ pendiente |
| 16 Conclusiones · 17 Anexos | ⬜ pendiente |

Quedan **20 marcadores `[ PENDIENTE ]`**, todos posteriores al desarrollo del script.

---

## 7. Estado del script

Detalle completo del diseño y del orden de construcción en
`02_Scripts/GUIA_Construccion_Script.md`.

| Archivo | Nivel | Estado |
|---|---|---|
| `02_Scripts/DDL/Modelo_GestionTransporte_DDL.sql` | — | ✅ tablas, índice RN-06/RN-09 y poblamiento |
| `02_Scripts/PLSQL/01_Record_Varray.sql` | tipos | ✅ RECORD, `%ROWTYPE`, VARRAY y ambos integrados |
| `02_Scripts/PLSQL/02_Calculos.sql` | 1 | ✅ 4 cálculos escalares |
| `02_Scripts/PLSQL/03_Consultas_Cursores.sql` | 2 | ✅ 3 bloques con cursores |
| `02_Scripts/PLSQL/04_Operaciones.sql` | 3 | ⬜ **pendiente** |

### Nivel 1 — cálculos escalares (futuras funciones)

| Bloque | Futura función | Excepciones | RF · RN |
|---|---|---|---|
| 1.1 | `fn_tarifa_vigente` | `NO_DATA_FOUND`, `TOO_MANY_ROWS` | RF-01 · RN-07 |
| 1.2 | `fn_conductores_requeridos` | `NO_DATA_FOUND` | RF-03 · RN-10 |
| 1.3 | `fn_asientos_disponibles` | `NO_DATA_FOUND` | RF-04 · RN-01, RN-06 |
| 1.4 | `fn_porcentaje_ocupacion` | `ZERO_DIVIDE`, `NO_DATA_FOUND` | RF-04 |

### Nivel 2 — consultas con cursores (futuros procedimientos)

| Bloque | Cursor | Futuro procedimiento | Cubre |
|---|---|---|---|
| 2.1 | Sin parámetros, `OPEN`/`FETCH`/`CLOSE` | `sp_control_flota` | Pauta 6.2 · verifica RN-10 |
| 2.2 | Con parámetro, complejo (5 tablas) | `sp_registro_viaje` | Pauta 6.3 y 6.4 · RF-05 |
| 2.3 | **Dos cursores anidados simultáneos** | `sp_disponibilidad` | Pauta 6.5 · **IE1.2.1** · RF-04 |

### Nivel 3 — operaciones de escritura (pendiente)

| Bloque | Futuro procedimiento | Excepciones de usuario | RF · RN |
|---|---|---|---|
| 3.1 | `sp_programar_viaje` | `e_bus_ocupado`, `e_conductor_ocupado`, `e_jornada_excedida` | RF-03 · RN-02, RN-03, RN-04, RN-10 |
| 3.2 | `sp_vender_pasaje` | `e_viaje_no_programado`, `e_pasajero_inexistente`, `e_asiento_no_disponible` + `DUP_VAL_ON_INDEX` | RF-01 · RN-05, RN-06, RN-07 |
| 3.3 | `sp_anular_pasaje` | `e_fuera_de_plazo` | RF-02 · RN-08, RN-09 |

**Decisión pendiente antes de escribir el nivel 3:** si el historial de estados lo
escribe el procedimiento o un trigger sobre `PASAJE`. Si se decide mal, se duplican
las filas de `PASAJE_ESTADO_HIST` o se pierden. Ver la guía de construcción, §5.

---

## 7 bis. RN-10 — Jornada máxima de conducción

**Regla:** por ley un conductor no puede superar las 5 horas de conducción.

Es la regla más productiva que se ha incorporado, por tres motivos:

**Justifica `VIAJE_CONDUCTOR`.** Hasta ahora la tabla puente se defendía diciendo que
"en recorridos largos la tripulación se releva". Con RN-10 deja de ser una conveniencia
y pasa a ser una obligación legal: sin ella el modelo no puede cumplir la norma.

**Tiene efecto medible sobre los datos.** Con las duraciones reales de las rutas:

| Ruta | Distancia | Duración | Conductores mínimos |
|---|---|---|---|
| Santiago → Rancagua | 87 km | 1,25 h | 1 |
| Santiago → Talca | 255 km | 3,00 h | 1 |
| Santiago → Linares | 305 km | 3,50 h | 1 |
| Santiago → Cauquenes | 360 km | 4,50 h | 1 |
| Santiago → Chillán | 400 km | 4,75 h | 1 |
| Santiago → Bulnes | 425 km | 5,00 h | 1 (límite exacto) |
| Santiago → Concepción | 500 km | 6,50 h | **2** |

Sólo Concepción supera el límite, y Bulnes queda justo en el borde: eso hace que la regla
se pueda demostrar sin que todos los viajes se vean afectados por igual. El poblamiento
del DDL se rehízo por completo y quedó validado: los seis viajes cumplen RN-10 y no hay
solapamientos de bus ni de conductor.

**Aporta material técnico.** Añade la excepción de usuario `e_jornada_excedida` y la
función `fn_conductores_requeridos`, que calcula el mínimo a partir de la duración.

**Punto a precisar con el profesor:** la norma chilena habla de 5 horas *continuas* de
conducción. La validación implementada exige que la duración dividida por el número de
conductores no supere ese límite, lo que asume que el relevo reparte el tiempo de forma
pareja. Es una simplificación razonable y conviene declararla como tal en el informe.

---

## 8. Preguntas de defensa del profesor

`Doc.Evaluación1/Preguntas_Tipo_Analisis_Justificacion_PLSQL_Oracle.docx` contiene las
preguntas con que se evaluará la justificación técnica. Su criterio central:

> *"No basta con indicar que una técnica se utiliza porque forma parte de la evaluación.
> El estudiante debe explicar qué problema resuelve, qué aporta a la solución y qué
> alternativa podría utilizarse."*

Las dos más exigentes, que conviene tener respondidas por escrito:

- **7.1** — Si se usa RECORD, VARRAY y cursores sólo porque son contenidos exigidos,
  ¿es justificación suficiente? Para cada uno: qué problema concreto resuelve y qué
  alternativa se habría usado si ese problema no existiera.
- **7.2** — Si se eliminara el RECORD, el VARRAY o alguno de los cursores, ¿qué dejaría
  de funcionar? Si la respuesta es "ninguno", ¿está justificado ese componente?

Las secciones 5.3, 6.3 y 6.6 del informe ya están redactadas apuntando a estas preguntas:
incluyen la alternativa descartada y por qué. Revisar que puedas sostenerlas oralmente.

---

## 9. Qué falta, en orden

1. **Escribir el nivel 3** (`04_Operaciones.sql`), decidiendo antes el punto del trigger
2. Completar en el informe 8.2, 9.2, 10 y 11 con la implementación real
3. Secciones 12 (consideraciones técnicas), 13 (conclusiones) y 14 (anexos)
4. Validar los actores propuestos en 2.2 del informe (P-01)
5. Redactar los requerimientos no funcionales (P-02)
6. Responder por escrito las preguntas 7.1 y 7.2 de §8
7. Resolver con el profesor las preguntas abiertas de §5, en particular **B-3**:
   si en esta entrega los procedimientos y triggers se implementan o sólo se evalúan
8. Verificar que no quede ningún `[ PENDIENTE ]` antes de entregar
