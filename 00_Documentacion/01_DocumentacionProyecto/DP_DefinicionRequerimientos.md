# Definición de Requerimientos — Sistema de Gestión de Transporte Interurbano

> **Documento de trabajo.** BDY1103 · Evaluación Parcial 1 · Encargo (40% de la nota de la parcial).
> Modalidad: mixta. Los bloques marcados **✍️ ESCRIBES TÚ** son tuyos; el resto está
> resuelto a partir de decisiones ya cerradas y sirve de andamio.
>
> Estado: borrador v1 · 01-sep-2026

---

## Cómo usar este documento

> **Este documento NO se entrega.** Es el cuaderno de trabajo. El entregable es
> `DP_Informe_Requerimiento.docx`, que ya tiene su estructura definitiva alineada a la
> pauta. Aquí se piensa; allá se redacta.

### Correspondencia con el informe

| Aquí (cuaderno) | Allá (`DP_Informe_Requerimiento.docx`) | Estado |
|---|---|---|
| §1 Marco referencial y contexto | 1.1 Contexto de Negocio | ✅ redactado |
| §2 Definición del problema | 1.1 (párrafo final) | ✅ redactado |
| §3 Objetivos | 1.2 Objetivo del Sistema | ✅ redactado (5 OE) |
| §6 Reglas de negocio | 1.3 Reglas de Negocio del Dominio | ✅ trasladadas |
| §4 Alcance | 1.4 Alcance del Proyecto | ⬜ pendiente |
| §5 Tecnologías | 1.5 Tecnologías Utilizadas | ⬜ pendiente |
| §6 (col. mecanismo) | 2.2 Trazabilidad regla → mecanismo | ⬜ pendiente |
| §7 Requerimientos funcionales | 3.1 Requerimientos Funcionales | ⬜ pendiente |
| §8 Datos e información | 3.3 Datos a Procesar e Información a Generar | ⬜ pendiente |
| §9 Trazabilidad técnica | Secciones 4, 5, 6 y 7 del informe | ⬜ pendiente |


La pauta pide seis cosas en el encargo (§3 de la pauta, ítems a–f). Este documento
cubre los dos primeros, que son la base de todo lo demás:

| Ítem de la pauta | Dónde se resuelve |
|---|---|
| a. Describir el contexto de negocio | §1, §2 de este documento |
| b. Identificar datos a procesar e información a generar | §8 |
| c. RECORD y VARRAY | §9 (aquí se *justifica*; el código va en el informe final) |
| d. Cursores con y sin parámetros, loops anidados | §9 |
| e. Excepciones predefinidas y de usuario | §9 |
| f. Evaluar procedimientos, funciones, packages y triggers | queda para el informe final |

**El punto estratégico de este documento:** los requerimientos funcionales no se
escriben "en general". Se escriben de modo que **exijan** las técnicas que la rúbrica
evalúa. Si defines requerimientos de CRUD simple, después no tienes dónde poner un
cursor con parámetros ni un VARRAY, y el informe queda forzado. Por eso §7 y §9 se
diseñan juntas.

---

## 1. Marco referencial y contexto de negocio

> **✍️ ESCRIBES TÚ.** Entre 250 y 400 palabras. La rúbrica de presentación
> (IE1.1.2, 15%) premia "un entendimiento profundo del problema y su impacto
> potencial", así que esto no es relleno: es la sección que sostiene la defensa oral.

Preguntas guía — respóndelas y el texto sale solo:

1. **¿Qué organización es?** ¿Una empresa de buses interurbanos real, una ficticia,
   una cooperativa de transportistas? Ponle nombre y tamaño (¿cuántos buses,
   cuántas rutas, cuántos terminales?). Un número concreto vuelve creíble todo lo demás.
2. **¿Cómo opera hoy sin el sistema?** ¿Planillas Excel? ¿Cuadernos en el terminal?
   ¿Un sistema viejo? El "antes" es lo que justifica el proyecto.
3. **¿Cuál es el dolor concreto?** No "falta de automatización" — algo que se pueda
   medir: asientos vendidos dos veces, buses con doble agenda, conductores excedidos
   de jornada, imposibilidad de saber la ocupación real de una ruta.
4. **¿Quiénes son los actores?** Vendedor de terminal, pasajero, conductor,
   programador de flota, administrador. ¿Qué hace cada uno con el sistema?
5. **¿Por qué una base de datos con lógica en el servidor** y no una planilla o una
   app que valide en el cliente? (Pista para la defensa: porque las reglas de
   integridad deben cumplirse **aunque el dato entre por otra vía**.)

<!-- ESCRIBE AQUÍ -->

---

## 2. Definición del problema

> **✍️ ESCRIBES TÚ.** Un párrafo. Debe ser una frase que un gerente firmaría.

Plantilla: *"[La organización] no puede [capacidad que le falta] porque
[causa estructural], lo que provoca [consecuencia medible]."*

Preguntas guía:

1. De los dolores que listaste en §1, **¿cuál es el central?** El resto son síntomas.
2. ¿Ese problema es de **datos** (no se registran), de **integridad** (se registran
   mal) o de **información** (están, pero no se pueden explotar)? Tu proyecto ataca
   los tres, pero uno es el que manda.

<!-- ESCRIBE AQUÍ -->

---

## 3. Objetivos

### 3.1 Objetivo general

> **✍️ ESCRIBES TÚ.** Una sola oración, verbo en infinitivo.

Debe ser el espejo del problema de §2: si el problema es "no puede X", el objetivo
es "implementar Y que permita X". **Advertencia:** un objetivo general que diga
"crear una base de datos" está mal formulado — la base de datos es el medio, no el
fin. El fin es lo que el negocio consigue.

<!-- ESCRIBE AQUÍ -->

### 3.2 Objetivos específicos

> **MIXTO.** Te dejo la estructura de los cinco; tú ajustas la redacción y el alcance
> a lo que decidiste en §1.

Cada objetivo específico debe ser verificable (se puede decir "logrado / no logrado")
y debe apuntar a una parte distinta de la solución:

| # | Apunta a | Esqueleto |
|---|---|---|
| OE1 | El modelo | Diseñar e implementar un modelo relacional normalizado en 3FN que garantice por diseño las reglas de negocio del dominio |
| OE2 | Procesamiento | Desarrollar bloques PL/SQL que procesen las operaciones de venta, anulación y programación aplicando las reglas del negocio |
| OE3 | Información | Generar la información de gestión que hoy no existe: ocupación por ruta, manifiestos de viaje, liquidación de conductores |
| OE4 | Robustez | Integrar control de excepciones que impida que una operación inválida deje la base en estado inconsistente |
| OE5 | Evolución | Evaluar qué componentes (procedimientos, funciones, packages, triggers) conviene usar en cada caso y por qué |

> ✍️ Reescribe cada uno con tus palabras y tus cifras. Copiados tal cual se notan.

---

## 4. Alcance

### 4.1 Incluido

> **MIXTO.** Marca lo que entra y agrega lo que falte.

- [ ] Gestión de catálogos: terminales, rutas, tipos de asiento, estados de pasaje
- [ ] Gestión de flota: buses y su configuración de asientos
- [ ] Programación de viajes con asignación de bus y conductores
- [ ] Venta de pasajes con selección de asiento
- [ ] Ciclo de vida del pasaje: pendiente → vendido → utilizado / anulado
- [ ] Tarificación por ruta, tipo de asiento y vigencia comercial
- [ ] Generación de información de gestión (definir cuáles en §8)

### 4.2 Excluido explícitamente

> **✍️ ESCRIBES TÚ.** Esto vale puntos: delimitar lo que **no** haces demuestra
> control del alcance. Candidatos a excluir — decide y justifica en una línea cada uno:

- Interfaz gráfica de usuario (¿o sí, vía APEX en la Parcial 2?)
- Pasarela de pago real / integración bancaria
- Emisión de documentos tributarios (boleta/factura electrónica SII)
- Gestión de encomiendas y equipaje
- Mantenimiento de flota y control de combustible
- Geolocalización del bus en ruta

<!-- ESCRIBE AQUÍ tu justificación de exclusiones -->

---

## 5. Tecnologías utilizadas

> **RESUELTO.** Verifica que coincida con tu entorno y agrega lo que uses.

| Componente | Tecnología | Rol en el proyecto |
|---|---|---|
| Motor de base de datos | Oracle AI Database 26ai Free (23.26) | Almacenamiento y ejecución de la lógica de negocio |
| Contenedor | Docker — imagen `gvenzl/oracle-free` | Entorno local reproducible |
| Lenguaje procedimental | PL/SQL | Bloques anónimos, procedimientos, funciones, packages y triggers |
| Modelado | Oracle SQL Developer Data Modeler | Modelo lógico y relacional, ingeniería directa a DDL |
| IDE | VSCode + extensión Oracle SQL Developer | Desarrollo y ejecución contra la BD local |
| Control de versiones | Git | Versionado del DDL, scripts y documentación |

---

## 6. Reglas de negocio

> **RESUELTO.** Son las nueve del enunciado, ya numeradas y trazadas contra el
> mecanismo que las hace cumplir. Esta tabla es oro para la defensa oral: cuando el
> profesor pregunte *"¿por qué lo hiciste así?"*, la respuesta está en la columna
> derecha.

| ID | Regla de negocio | Mecanismo que la garantiza | Tipo |
|---|---|---|---|
| RN-01 | Un bus posee una cantidad determinada de asientos | `ASIENTO` con PK `(id_bus, nro_asiento)`; la capacidad es la cardinalidad | Estructura |
| RN-02 | Un viaje se realiza entre un origen y destino definidos | `RUTA` con dos FK a `TERMINAL` + `CHECK (origen <> destino)` | Estructura |
| RN-03 | Un conductor no puede realizar dos viajes simultáneos | Vista materializada de solapes `ON COMMIT` + `CHECK` imposible | **Pendiente** |
| RN-04 | Un bus no puede ser asignado a dos viajes que se superpongan | Idem, sobre `VIAJE.id_bus` | **Pendiente** |
| RN-05 | Cada pasaje corresponde a un único pasajero y viaje | `PASAJE.id_pasajero` + `PASAJE.id_viaje`, ambos `NOT NULL` | Estructura |
| RN-06 | Un asiento no puede ser vendido dos veces para el mismo viaje | Índice único parcial sobre los pasajes vigentes | **Pendiente** |
| RN-07 | El precio varía según tipo de asiento, ruta o condición comercial | `TARIFA(ruta, tipo, vigencia)` + `precio_aplicado` congelado en el pasaje | Estructura |
| RN-08 | Un pasaje está vendido, utilizado, anulado o pendiente de pago | `ESTADO_PASAJE` + `PASAJE_ESTADO_HIST` | Estructura |
| RN-09 | La anulación de un pasaje libera el asiento correspondiente | El índice único ignora los estados con `ocupa_asiento = 'N'` | **Pendiente** |

> **Nota honesta para el informe:** cuatro reglas están especificadas pero **no
> implementadas todavía**. Decláralo así en el informe — un alcance con pendientes
> declarados puntúa mejor que un alcance que promete todo y no lo muestra.

---

## 7. Requerimientos funcionales

> **MIXTO.** Te propongo los seis procesos. Tu trabajo: completar la descripción,
> las precondiciones y el resultado esperado de cada uno, y decidir si sobra o falta
> alguno. **No los cambies sin mirar §9** — están elegidos para que cada técnica
> evaluada tenga dónde vivir.

**Formato de cada requerimiento** (completa las celdas vacías):

### RF-01 — Venta de pasajes

| Campo | Contenido |
|---|---|
| Descripción | Registrar una venta que contiene uno o más pasajes, cada uno para un pasajero, viaje y asiento determinados |
| Actor | ✍️ |
| Precondiciones | ✍️ (¿el viaje debe estar en estado PRO? ¿el pasajero debe existir previamente?) |
| Reglas que aplica | RN-05, RN-06, RN-07 |
| Resultado | ✍️ |

### RF-02 — Anulación de pasaje

| Campo | Contenido |
|---|---|
| Descripción | Cambiar el estado de un pasaje a ANULADO, liberando su asiento y dejando registro de quién y por qué |
| Actor | ✍️ |
| Precondiciones | ✍️ (**pregunta clave:** ¿se puede anular un pasaje ya UTILIZADO? ¿y uno de un viaje que ya salió?) |
| Reglas que aplica | RN-08, RN-09 |
| Resultado | ✍️ |

### RF-03 — Programación de viajes

| Campo | Contenido |
|---|---|
| Descripción | Crear un viaje asignándole ruta, bus, conductores y horario de salida y llegada |
| Actor | ✍️ |
| Precondiciones | ✍️ |
| Reglas que aplica | RN-02, RN-03, RN-04 |
| Resultado | ✍️ |

### RF-04 — Emisión del manifiesto de viaje

| Campo | Contenido |
|---|---|
| Descripción | Listar los pasajeros de un viaje ordenados por piso y número de asiento, con su estado |
| Actor | ✍️ |
| Precondiciones | ✍️ |
| Reglas que aplica | — (es lectura) |
| Resultado | ✍️ (¿un reporte impreso? ¿una tabla? ¿salida por `DBMS_OUTPUT`?) |

### RF-05 — Reporte de ocupación por ruta y período

| Campo | Contenido |
|---|---|
| Descripción | Calcular, para cada ruta y cada viaje de un período, el porcentaje de ocupación y los ingresos generados |
| Actor | ✍️ |
| Precondiciones | ✍️ |
| Reglas que aplica | — (es lectura) |
| Resultado | ✍️ |

### RF-06 — ✍️ ¿Falta alguno?

> Candidatos: liquidación de conductores por kilómetros o viajes realizados;
> reprogramación de un viaje cancelado con reubicación de pasajeros; carga masiva
> de tarifas por temporada. **Elige uno solo** — más procesos no dan más nota, y
> cada uno hay que implementarlo después.

---

## 8. Datos a procesar e información a generar

> **MIXTO.** Este es el **ítem b de la pauta** y se evalúa explícitamente. La
> distinción que el profesor busca es exactamente esta: *dato* es lo que entra,
> *información* es lo que el negocio no tenía antes de procesarlo.

### 8.1 Datos que se procesan

> ✍️ Completa la columna de origen. Te dejo las categorías.

| Categoría | Datos | Origen |
|---|---|---|
| Maestros de catálogo | Terminales, rutas, tipos de asiento, estados | ✍️ |
| Flota | Buses, configuración de asientos por bus | ✍️ |
| Personas | Pasajeros, conductores | ✍️ |
| Operación | Viajes programados, asignación de conductores | ✍️ |
| Transaccional | Ventas, pasajes, transiciones de estado | ✍️ |
| Comercial | Tarifas con vigencia | ✍️ |

### 8.2 Información que se genera

> ✍️ **Esta es la parte que tienes que pensar tú.** Para cada una responde:
> ¿quién la usa y qué decide con ella? Una salida que nadie usa para decidir no es
> información, es un listado.

| # | Información | ¿Quién la usa? | ¿Qué decisión habilita? |
|---|---|---|---|
| I-01 | Manifiesto de viaje | ✍️ | ✍️ |
| I-02 | Porcentaje de ocupación por ruta y período | ✍️ | ✍️ |
| I-03 | Ingresos por ruta / por tipo de asiento | ✍️ | ✍️ |
| I-04 | Asientos disponibles de un viaje en tiempo real | ✍️ | ✍️ |
| I-05 | Tasa de anulación y sus motivos | ✍️ | ✍️ |
| I-06 | ✍️ | ✍️ | ✍️ |

---

## 9. Trazabilidad: requerimiento → técnica PL/SQL → indicador evaluado

> **RESUELTO — esta es la sección que decide tu nota.** Conecta cada proceso con la
> técnica que lo resuelve y con el indicador de la rúbrica que la evalúa. Si un
> indicador no aparece en esta tabla, no hay dónde ganar esos puntos.

| Requerimiento | Técnica que exige | Por qué esa técnica y no otra | Indicador |
|---|---|---|---|
| RF-01 Venta | **RECORD** con la estructura del pasaje a insertar | Se manipulan varios atributos del mismo pasaje como una unidad antes de persistirlo | IE1.1.1 (5%) |
| RF-01 Venta | **VARRAY** con los asientos solicitados en la compra | Colección de tamaño acotado y conocido: nadie compra 200 asientos en una operación | IE1.1.1 (5%) |
| RF-01 Venta | **Excepción de usuario** `asiento_no_disponible` | La regla es de negocio, no de Oracle: hay que nombrarla para que el mensaje sea útil | IE1.3.1 (10%) |
| RF-01 Venta | **Excepción predefinida** `DUP_VAL_ON_INDEX` | El índice único parcial de RN-06 la dispara sola al intentar revender un asiento vigente | IE1.3.1 (10%) |
| RF-02 Anulación | **Excepción de usuario** `pasaje_no_anulable` | Anular un pasaje ya utilizado es válido en SQL pero inválido en el negocio | IE1.3.1 (10%) |
| RF-03 Programación | **Cursor con parámetro** (`id_bus`, rango de fechas) | Se consultan los viajes de *un* bus concreto: el parámetro evita traer toda la tabla | IE1.2.1 (10%) |
| RF-04 Manifiesto | **Cursor con parámetro** (`id_viaje`) + **loops anidados** | Recorrer viaje → sus pasajes es la estructura anidada natural del dominio | IE1.2.1 (10%) |
| RF-05 Ocupación | **Dos cursores simultáneos**: rutas → viajes de esa ruta | La rúbrica exige "más de un LOOP en forma simultánea"; aquí sale del problema, no forzado | IE1.2.1 (10%) |
| RF-05 Ocupación | **Excepción predefinida** `ZERO_DIVIDE` | Un viaje sin asientos registrados haría estallar el cálculo de porcentaje | IE1.3.1 (10%) |
| RF-05 Ocupación | **Excepción predefinida** `NO_DATA_FOUND` | Buscar la tarifa vigente de una ruta que no la tiene | IE1.3.1 (10%) |
| Todos | **Evaluación** procedimiento vs función vs package vs trigger | Ítem f de la pauta; se argumenta, no se implementa aún | IE1.4.1 (15%) |

### Argumento listo para la defensa

Cuando el profesor pregunte **"¿por qué usaste un VARRAY y no una tabla anidada?"**:

> Porque la cantidad de asientos que un cliente compra en una sola operación tiene un
> **límite conocido y bajo**. VARRAY declara ese límite en el tipo; una tabla anidada
> no lo hace y permitiría una colección sin cota. La restricción del negocio queda
> expresada en la estructura de datos.

Y cuando pregunte **"¿por qué un cursor con parámetro y no uno simple con un WHERE fijo?"**:

> Porque el mismo cursor se reutiliza para cualquier bus o cualquier viaje sin
> reescribirlo. El parámetro convierte una consulta específica en un procedimiento
> reutilizable, que es justamente el objetivo del bloque.

---

## 10. Referencias del modelo

- Modelo vigente de 14 entidades: `CONTEXTO_BDY1103.md` §4.1
- DDL y poblamiento: `02_Scripts/DDL/Modelo_GestionTransporte_DDL.sql`
- Auditoría del modelo original con los 19 hallazgos: https://claude.ai/code/artifact/d6ba4568-8821-4adc-ba2a-a3143c0d6daa

---

## Pendientes

### Cerrado el 01-sep-2026

- [x] §1 Contexto de negocio — redactado, con 7 rutas, 30 buses y empresa mediana
- [x] §2 Definición del problema — los dos problemas estructurales
- [x] §3 Objetivos — objetivo general + 5 específicos (se repuso OE5)
- [x] Informe limpiado del proyecto anterior y reestructurado según la pauta
- [x] Reglas de negocio trasladadas de §1.2 a su propia sección 1.3 del informe

### Siguiente bloque de trabajo

- [ ] **§4 Alcance** — decidir exclusiones y justificar cada una en una línea (✍️ tú)
- [ ] **§5 Tecnologías** — verificar la tabla contra tu entorno y trasladarla al informe
- [ ] **§7 Requerimientos funcionales** — completar actor, precondiciones y resultado de
      RF-01 a RF-05; decidir cuál es RF-06 (✍️ tú)
- [ ] **§8 Datos e información** — origen de cada dato y, sobre todo, quién usa cada
      salida y qué decide con ella (✍️ tú)
- [ ] **§2.2 del informe** — trasladar la tabla de trazabilidad regla → mecanismo
- [ ] Actualizar el índice del informe en LibreOffice (clic derecho sobre el índice →
      *Actualizar índice*): las entradas actuales son del documento anterior

### Antes de entregar

- [ ] Revisar el informe contra la rúbrica indicador por indicador
- [ ] Verificar que no quede ningún `[ PENDIENTE ]` en el .docx
- [ ] Actualizar la tabla de integrantes de la Ficha del documento
