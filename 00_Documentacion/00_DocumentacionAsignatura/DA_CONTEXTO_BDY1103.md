# CONTEXTO_BDY1103 — Taller de Base de Datos

> Documento de handoff para la sesión de terminal (Claude Code) donde se desarrolla
> el proyecto semestral. Complementa (no reemplaza) `CONTEXTO_SESION.md` de BDY1102.

---

## 1. Datos generales de la asignatura

| | |
|---|---|
| Sigla | BDY1103 |
| Nombre | Taller de Base de Datos |
| Prerrequisito | BDY1102 (Base de Datos Aplicada II) — aprobado |
| Créditos SCT | 3 · Créditos Duoc | 8 |
| Formato | Presencial, Laboratorio de PC |
| Horas totales | 72 (32 de trabajo autónomo) |
| Línea formativa | Base de Datos — **es la asignatura que culmina la línea formativa de BD** |

## 2. Resultados de aprendizaje (RA) e indicadores (IL)

### RA1 — Bloques PL/SQL para procesar datos y generar información de negocio
- **IL1.1** Tipos de datos compuestos: **RECORD** y **VARRAY**.
- **IL1.2** Cursores explícitos **complejos con parámetros**, trabajando con **más de un LOOP simultáneo**.
- **IL1.3** Control de excepciones: **predefinidas de Oracle** y **definidas por el usuario**.
- **IL1.4** Evalúa Procedimientos Almacenados, Funciones, Packages y Triggers (comparativo, para decidir cuál usar).

### RA2 — Implementación de programas PL/SQL como solución integral
- **IL2.1** Procedimientos y funciones almacenadas (con y sin parámetros) para procesamiento masivo, invocables desde otros programas y desde SQL.
- **IL2.2** Packages con constructores públicos y privados.
- **IL2.3** Triggers a nivel de sentencia y de fila.

### RA3 — Modelo de datos NO relacional (NoSQL)
- **IL3.1** Diferencias BD relacional vs no relacional, ventajas/desventajas y aplicabilidad.
- **IL3.2** Modelo de datos no relacional.
- **IL3.3** Operaciones CRUD sobre la base NoSQL.

## 3. Ruta de aprendizaje y evaluaciones

| Semana | Bloque | Contenido | Evaluación |
|---|---|---|---|
| ~1-5 | RA1 | RECORD/VARRAY → Cursores con parámetros → Excepciones → Comparativo procedimientos/funciones/packages/triggers | Eva For 1 + **Eva Parcial 1** (sem. 5→6, entrega+presentación, equipos ≤3, evaluación individual) |
| ~7-11 | RA2 | Procedimientos/funciones → Packages → Triggers → App APEX | Eva For 3 + **Eva Parcial 2** (sem. 11→12) |
| ~13-16 | RA3 | NoSQL: conceptos → modelo → CRUD | Eva For 2 + **Eva Parcial 3** (sem. 16→17) |
| ~18 | Integración | — | **Evaluación Final Transversal** (instrucciones sem. 6, entrega sem. 18) |

**Estructura clave de la evaluación**: es un **proyecto semestral único, dividido en 3 entregas parciales** (30% + 40% + 30%), más la ET final (40% del total). Cada entrega parcial se corrige contra los indicadores del RA correspondiente. **El docente anima a proponer un caso propio**, previa aprobación — se trabaja en equipos de máx. 3, pero **la evaluación de cada estudiante es individual** (informe + presentación + defensa oral con preguntas del docente, máx. 10 slides / 20 min).

## 4. Decisión: caso semestral

Se usará el **modelo de transporte interurbano** (pasajeros, buses, viajes, asientos, pasajes, ventas) diseñado en Oracle Data Modeler — cumple los requisitos de complejidad relacional que RA1/RA2 necesitan (control de cupos, ventas con detalle, estados del pasaje, tarifas vigentes) y da pie natural a RA3 (ej.: log de eventos, catálogo de rutas/horarios, o reseñas de servicio en NoSQL).

### 4.1 Modelo vigente: 14 entidades en 3FN (30-ago-2026)

El modelo original de 10 entidades fue auditado y **reemplazado**. El vigente está implementado en `02_Scripts/DDL/Modelo_GestionTransporte_DDL.sql` y cargado en la BD local.

| Bloque | Entidades |
|---|---|
| Catálogos | `TERMINAL`, `RUTA`, `TIPO_ASIENTO`, `ESTADO_PASAJE` |
| Flota | `BUS`, `ASIENTO` |
| Operación | `CONDUCTOR`, `VIAJE`, `VIAJE_CONDUCTOR` |
| Comercial | `PASAJERO`, `TARIFA`, `VENTA`, `PASAJE`, `PASAJE_ESTADO_HIST` |

**Decisiones de modelado vigentes:**

- **`VIAJE` reemplaza a `SERVICIO` + `HORARIO`.** Guarda `salida_prog` y `llegada_prog` como `TIMESTAMP`. Sin hora de llegada, las reglas de no-solapamiento de bus y de conductor son indecidibles: no hay intervalo que comparar.
- **`ASIENTO` pertenece al BUS, no al viaje.** PK compuesta `(id_bus, nro_asiento)`. La "cantidad determinada de asientos" de un bus es la cardinalidad de sus asientos, no un número suelto que puede contradecirlos. Ya no se generan asientos por trigger en cada viaje.
- **`PASAJE` es la entidad central** (reemplaza a `DETALLE_VENTA`): un pasajero, un viaje, un asiento, una tarifa, un estado. El pasajero cuelga del pasaje y no de la venta, lo que permite que una venta cubra a varios viajeros distintos.
- **Integridad asiento–bus–viaje sin trigger.** `PASAJE` lleva `id_bus` a propósito: dos FK compuestas —`(id_viaje, id_bus) → VIAJE` y `(id_bus, nro_asiento) → ASIENTO`— garantizan de forma declarativa que el asiento vendido existe en el bus que efectivamente hace ese viaje.
- **Unicidad del asiento por índice único parcial**, no por cardinalidad 1:1. Un índice basado en función sobre `PASAJE` indexa solo los estados que ocupan asiento; al anular, las expresiones quedan en `NULL`, el pasaje sale del índice y el asiento se libera sin borrar el histórico.
- **`TARIFA(ruta, tipo_asiento, vigencia)`** resuelve el precio variable. `PASAJE.precio_aplicado` guarda el precio congelado en el momento de la venta: es dato histórico, no redundancia.
- **`ESTADO_PASAJE` + `PASAJE_ESTADO_HIST`** modelan los cuatro estados (pendiente, vendido, utilizado, anulado) y dejan rastro de cada transición.
- Cardinalidades corregidas a `1:N` desde el lado maestro (antes estaban como `1:1`, lo que implicaba que cada bus hacía un solo viaje).

**Pendiente de implementar:** el índice único parcial y las vistas materializadas anti-solapamiento (bus y conductor) no están en el DDL todavía; se agregan aparte porque no son constraints inline de tabla.

**Referencia completa:** informe de evaluación del modelo con los 19 hallazgos y la matriz requisito → mecanismo → https://claude.ai/code/artifact/d6ba4568-8821-4adc-ba2a-a3143c0d6daa

## 5. Metodología de trabajo acordada (heredada de BDY1102, vigente aquí)

- **Problema de negocio primero**: cada técnica nueva se practica resolviendo un caso con contexto, no un ejercicio abstracto.
- **El estudiante escribe, el asistente corrige con enfoque pedagógico**: se identifican falencias y su porqué; no se entregan soluciones hechas para tareas evaluadas o exámenes.
- **Cambios mínimos primero**: para que el código ejecute; optimizar después, una vez consolidada la lógica base.
- **Restricción de alcance**: no introducir técnicas que el profesor no haya cubierto aún en clase — se avisa explícitamente cuando algo excede el temario visto hasta la fecha.
- **Documentación obligatoria**: los bloques PL/SQL se comentan explicando qué resuelve cada sentencia (exigencia recurrente en las pautas de evaluación de Duoc).
- **Progresión típica de un módulo nuevo**: (1) explicación conceptual con ejemplo mínimo → (2) ejercicio guiado tipo pregunta-respuesta cuando el tema es sensible a una evaluación próxima → (3) problema de negocio completo sobre el esquema propio → (4) corrección con rúbrica.
- **Separación de roles entre sesiones**: esta sesión (chat) para explicación conceptual, diseño de ejercicios y corrección; la sesión de terminal (Claude Code) para ejecución contra la BD local y desarrollo versionado del proyecto semestral.
- **Límite ético explícito**: si el material corresponde a una evaluación sumativa individual en curso (ET, parciales), no se resuelve completo — se guía por preguntas o se trabaja sobre un caso paralelo de práctica.

## 6. Estado actual / próximo hito

**Cerrado (30-ago-2026):**
- Modelo auditado y rediseñado a 14 entidades en 3FN — ver §4.1.
- DDL + poblamiento escritos y cargados en la BD local (`02_Scripts/DDL/`).
- Resuelto el pendiente de BDY1102 sobre doble agenda de un mismo bus: `VIAJE` con `salida_prog`/`llegada_prog` permite comparar intervalos; el mecanismo anti-solapamiento (vista materializada `ON COMMIT` + `CHECK` imposible) está especificado, falta implementarlo.
- Entorno Oracle local operativo: contenedor `oracle-practica`, service name **`FREEPDB1`**, esquema `BENJA` limpio.

**En curso:**
- **Evaluación Parcial 1** — definición de requerimientos y estructura del proyecto (informe de ingeniería de software). Modalidad de trabajo: **mixta** — el asistente arma esqueleto y preguntas guía, Benjamin redacta el contenido.

**Próximo:**
- Prueba de RA1: cursores explícitos con y sin parámetros, VARRAY, RECORD, excepciones.
- Implementar el índice único parcial y las vistas materializadas anti-solapamiento.

## 7. Archivos asociados

- DDL del modelo de transporte interurbano (a cargar).
- `CONTEXTO_SESION.md` — handoff de la línea de estudio BDY1102 (cursores explícitos simples, esquema Conservador de Propiedades Mineras).
