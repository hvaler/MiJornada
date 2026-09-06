# Feedback del Ecosistema Ovillo

> **INSTRUCCIONES PARA CLAUDE**: Este archivo registra gaps, bugs y fricciones del **ECOSISTEMA Ovillo**
> (comandos, skills, hooks, reglas, templates, agents, docs, hub) detectados mientras se trabaja en ESTE proyecto.
> NO es para bugs del proyecto: eso va a `_hilo/DEUDA_TECNICA.md` o a un evolutivo.
> `/mcp-sync` sube estos items al hub central (categoria `feedbackEcosistema`, `POST /v2/sync/ecosystem-feedback`)
> donde el equipo constructor del ecosistema los prioriza para las siguientes releases.

---

## Cuando registrar un item

Registra un FB-XXX cuando detectes (tu o el usuario) algo del ecosistema que:

- **Falla**: un comando/hook/skill se rompe o se comporta distinto a lo documentado (ej. un hook bloquea trabajo legitimo).
- **Falta**: un caso real del proyecto que la plantilla no cubre (ej. un stack o modelo de deploy no soportado por `/cicd-init`).
- **Fricciona**: funciona pero obliga a un workaround manual recurrente (documenta el workaround en la descripcion).

NO registres: dudas de uso (consultar docs o `/sos`), bugs del codigo del proyecto, peticiones de features del negocio.

## Como registrar

1. Asigna el siguiente codigo secuencial `FB-NNN` (mira el ultimo de este archivo).
2. Anade un bloque con el formato de abajo (los campos `**Campo**:` son los que parsea `/mcp-sync` — respetar nombres).
3. En la siguiente ejecucion de `/mcp-sync` el item sube al hub. Para subir UN item sin esperar: tool MCP `register_ecosystem_feedback`.
4. El estado lo actualiza el equipo constructor (en el hub) y tu puedes reflejarlo aqui cuando se resuelva (`VersionResolucion`).

**Valores permitidos**:

| Campo | Valores |
|---|---|
| `Categoria` | `comando`, `skill`, `hook`, `regla`, `template`, `agent`, `docs`, `hub`, `otro` |
| `Severidad` | `alta` (bloquea trabajo), `media` (hay workaround), `baja` (mejora) |
| `Estado` | `abierto`, `en_analisis`, `resuelto`, `descartado`, `diferido` |

---

## Items registrados

<!-- Formato de cada item (parseado por .claude/scripts/mcp-sync.ps1 — no cambiar los nombres de campo):

### FB-001: Titulo breve del gap/bug/friccion

- **Categoria**: hook
- **Severidad**: media
- **Estado**: abierto
- **VersionEcosistema**: 3.13.0
- **FechaDeteccion**: 2026-06-15
- **Descripcion**: Que falla/falta, como reproducirlo y workaround aplicado si lo hay.

-->

### FB-001: /onboarding manda guardar el stack en una seccion `stack` que no existe

- **Categoria**: comando
- **Severidad**: baja
- **Estado**: abierto
- **VersionEcosistema**: 1.1.0
- **FechaDeteccion**: 2026-09-06
- **Descripcion**: La Fase 2 de `/onboarding` indica "GUARDAR en `_hilo/ESTADO_PROYECTO.json` -> seccion `stack`", pero esa seccion no existe ni en la plantilla del JSON ni en `_hilo/ESTADO_PROYECTO.schema.md`. El sitio real donde aterriza el stack es `_hilo/CONTEXTO_TECNICO.md`, que la Fase 2 no menciona. Workaround aplicado: escribir el stack en `CONTEXTO_TECNICO.md` y no crear la seccion inexistente. Arreglo sugerido: corregir el texto de la Fase 2 para que apunte a `CONTEXTO_TECNICO.md`, o anadir la seccion `stack` al JSON y al schema. La Fase Final tiene un detalle parecido: da por hecho un `.sln` y no dice explicitamente que hacer cuando el proyecto solo tiene un `.csproj` suelto.

---

## Historial de resoluciones

> Cuando el constructor resuelva un item (release notes / `/actualizar`), mover aqui una linea de resumen.

| Codigo | Titulo | Resuelto en | Notas |
|---|---|---|---|
| — | — | — | — |

---

*Canal de feedback del ecosistema Ovillo v3.13.0 (ADR-044) — per-PROYECTO (ADR-038), atribucion per-dev (ADR-037).*
