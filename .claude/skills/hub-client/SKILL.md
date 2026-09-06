---
name: hub-client
description: |
  Cliente MCP del Hub Ovillo (URL en ecosystem.config.json -> hub.url; opcional, deshabilitado por defecto). Conocimiento para invocar las 15 tools, 4 resources y 3 prompts del protocolo MCP real desde un proyecto consumidor. El hub centraliza ADRs, lecciones, salud tecnica (vulnerabilidades + deuda), evolutivos, pipelines CI/CD, documentacion de agente (DOC), feedback del ecosistema (FB-XXX) y registro de proyectos cross-equipo. Esta skill cubre los patrones de uso recomendados y el troubleshooting de conexion.
  USE FOR: invocar tools del hub (search_decisions, search_lessons, get_health_summary, list_projects, get_active_workitems, register_decision, register_lesson, register_pipeline, register_agentdoc, get_cicd_status, list_pipelines, register_ecosystem_feedback, ping, get_version, count_projects), leer resources ovillo:// (decisions, lessons, snapshots, projects/status), usar prompts /audit-security, /review-project-decisions, /weekly-status-report, configurar .mcp.json scope project, troubleshooting conexion 4xx/5xx al hub, decidir entre tool/resource/prompt segun caso de uso.
  DO NOT USE FOR: sincronizar Hilo local (usar comando /mcp-sync), registrar proyecto inicial en el hub (usar /mcp-register), opciones de telemetria/opt-in (usar /mcp-forget o /mi-config), trabajo con bases de datos del proyecto consumidor (usar skill database-reviewer), evaluar arquitectura del proyecto (usar analisis-arquitectura).
  Keywords bilingues: MCP hub, ovillo-hub, tools, resources, prompts, JSON-RPC, .mcp.json, search_decisions, register_decision, audit-security, ADR, weekly status, vulnerabilidades cross-proyecto, deuda tecnica, evolutivos activos, proyectos registrados, ping hub, hub disponible, hub offline, 307 redirect, feedback ecosistema, register_ecosystem_feedback, FB-XXX, register_pipeline, cicd status, register_agentdoc, doc de agente, DOC-nnn, contexto de agente, drift de documentacion, docs-batch, stats docs.
---

# Skill: hub-client

Cliente MCP del hub central Ovillo. Sirve para invocar tools/resources/prompts del hub desde un proyecto consumidor via Claude Code.

## Que es el hub

URL: `ecosystem.config.json → hub.url` (ej. `http://localhost:8080` con el `docker-compose` del
Hub; los ejemplos de abajo usan `https://hub.example.org`). Requiere `hub.enabled: true`.

El hub es el centro de conocimiento cross-proyecto del ecosistema Ovillo. Almacena:

- **ADRs** sincronizados desde el Hilo de cada proyecto
- **Lecciones aprendidas** cross-equipo
- **Salud tecnica**: nugets, vulnerabilidades, deuda
- **Evolutivos** (work items) activos por proyecto/dev
- **Registro de proyectos** + heartbeat para saber quien esta vivo
- **Snapshots Hilo** completos para que Claude lea el contexto de un proyecto entero

Implementa **protocolo MCP real** (JSON-RPC 2.0 sobre HTTP+SSE) ademas de la REST API legacy `/v2/*`. Endpoint MCP: `/mcp`.

## Configuracion (.mcp.json)

```jsonc
// .mcp.json en raiz del repo consumidor
{
  "mcpServers": {
    "ovillo-hub": {
      "type": "http",
      "url": "https://hub.example.org/mcp"
    }
  }
}
```

Al abrir el repo en Claude Code, aceptar el trust prompt. Verificar con `/mcp` que aparece `ovillo-hub ✅ connected`.

## Catalogo: 15 tools

### Read tools (10)

| Tool | Parametros | Uso tipico |
|---|---|---|
| `ping` | — | Smoke test de conectividad |
| `get_version` | — | Version del hub + protocolo + ecosistema Ovillo |
| `count_projects` | — | KPI rapido: total proyectos + con/sin heartbeat |
| `list_projects` | `topN?`, `soloActivos?` | Lista proyectos registrados, ordenados por heartbeat |
| `search_decisions` | `topN?`, `keyword?` | ADRs recientes cross-proyecto con filtro por palabra clave |
| `search_lessons` | `topN?`, `keyword?` | Lecciones aprendidas con filtro keyword |
| `get_health_summary` | — | Resumen salud: nugets + vulnerabilidades + deuda |
| `get_active_workitems` | `asignadoA?` | Evolutivos activos cross-proyecto, opcional filtro por dev |
| `get_cicd_status` | `proyectoId` | Pipelines CI/CD de UN proyecto (fase, ultimo build). Lo usa `/cicd-status` |
| `list_pipelines` | `soloActivos?`, `soloFase?` | Pipelines cross-proyecto con KPIs (dashboard tab CI/CD) |

### Write tools (5)

| Tool | Parametros | Uso tipico |
|---|---|---|
| `register_decision` | `proyectoId`, `codigo`, `titulo`, `estado?`, `contexto?`, `decisionTexto?`, `consecuencias?`, `fechaDecision?`, `tags?`, `devAlias?` | Anadir nueva ADR al hub. Alternativa a sync Hilo cuando solo quieres registrar una decision puntual |
| `register_lesson` | `proyectoId`, `titulo`, `descripcion`, `categoria?`, `severidad?`, `fechaAprendizaje?`, `devAlias?` | Persistir una leccion observada durante una sesion |
| `register_pipeline` | `proyectoId`, `pipelineId`, `nombre`, `url?`, `fase?`, `stages?`, `stack?` | UPSERT de pipeline CI/CD. Lo invoca `/cicd-init` FASE 2.6 |
| `register_ecosystem_feedback` | `proyectoId`, `codigo`, `titulo`, `descripcion?`, `categoria?`, `severidad?`, `estado?`, `versionEcosistema?`, `devAlias?`, `fechaDeteccion?` | Subir UN item FB-XXX de `_hilo/FEEDBACK_ECOSISTEMA.md` sin esperar a `/mcp-sync` (ADR-044 v3.13.0) |
| `register_agentdoc` | `proyectoId`, `codigo?`, `entrypoint`, `docPath`, `srcStamp?`, `srcStampDoc?`, `drift`, `tokensEstimados`, `gate`, `generadoCon?`, `adrRelacionados?` | UPSERT del estado de un doc de contexto-de-agente (DOC-nnn). Lo invoca `docs-agente-sync` / `/docs-sync`. NO deriva el doc (eso es `/analisis-arquitectura --agente`). Endpoints REST: `POST /v2/sync/docs-batch`, `GET /v2/stats/docs/{id}` |

## Catalogo: 4 resources URI-addressable

Los resources devuelven **markdown completo** (no JSON resumido como los tools). Claude Code los expone como files attachables:

```
ovillo://decisions/{proyecto}/{codigo}      → ADR completo (Contexto + Decision + Consecuencias)
ovillo://lessons/{proyecto}/{id}            → Leccion completa con Description MD
ovillo://snapshots/{proyecto}/{categoria}   → Snapshot Hilo mas reciente
ovillo://projects/{nombre}/status           → Ficha sintetica del proyecto
```

**Categorias de snapshots**: `decisiones`, `lecciones`, `funcionalidades`, `dependencias`, `historial`, `contexto_tecnico`.

## Catalogo: 3 prompts (slash-commands)

| Prompt | Que produce |
|---|---|
| `/audit-security` | Mensaje con vulnerabilidades + deuda alta listas para que Claude priorice remediacion |
| `/review-project-decisions {proyecto}` | Listado de ADRs aceptadas del proyecto para detectar incoherencias, gaps, lagunas |
| `/weekly-status-report` | Informe semanal: proyectos activos + evolutivos + carga por dev + bloqueadores |

Los prompts hacen las queries por ti y devuelven un mensaje con datos VIVOS del hub. No tienes que invocar 4 tools manualmente.

## Decidir: tool vs resource vs prompt

| Caso | Usar | Por que |
|---|---|---|
| "¿Cuantas ADRs tengo en el proyecto X?" | tool `search_decisions` con filtro | Devuelve JSON resumido, suficiente |
| "Lee el ADR-039 completo de mi proyecto" | resource `ovillo://decisions/.../ADR-039` | Devuelve markdown con contexto+decision+consecuencias |
| "Genera un informe semanal cross-proyecto" | prompt `/weekly-status-report` | El server hace las 4 queries y arma el prompt en un solo paso |
| "Registra esta nueva decision en el hub" | tool `register_decision` | Write operation con argumentos estructurados |
| "Que esta haciendo el equipo hoy" | tool `get_active_workitems` | Lista evolutivos en progreso |
| "Resumen de salud para reporte a direccion" | tool `get_health_summary` + prompt `/audit-security` | Tool para KPIs, prompt para narrativa |
| "Este hook del ecosistema falla, reportalo al equipo del ecosistema" | registrar en `_hilo/FEEDBACK_ECOSISTEMA.md` + tool `register_ecosystem_feedback` | El archivo local es la fuente de verdad; la tool lo sube sin esperar a `/mcp-sync` |

## Patrones de uso

### Patron 1: contexto rapido al abrir un proyecto

```
> Lee el status de mi proyecto MyCompany.ErpSync en el hub.
```
Claude usa resource `ovillo://projects/MyCompany.ErpSync/status` → ficha sintetica con heartbeat, evolutivos activos, ultimas decisiones.

### Patron 2: buscar conocimiento cross-proyecto

```
> Busca en el hub decisiones sobre autenticacion Azure AD.
```
Claude usa `search_decisions(keyword="azure ad")` y luego para cada hit relevante puede cargar el resource `ovillo://decisions/.../ADR-XXX` para ver el detalle.

### Patron 3: detectar duplicidad antes de registrar

```
> Antes de crear esta nueva ADR, busca si ya existe una similar en el hub.
```
Claude usa `search_decisions(keyword="...")`; si no hay match, `register_decision(...)` con los datos.

### Patron 4: auditoria con datos vivos

```
> Audita la seguridad del ecosistema.
```
Claude usa prompt `/audit-security` (el server genera el mensaje con vulnerabilidades + deuda alta + proyectos afectados) y razona sobre el output.

## Troubleshooting

### `/mcp` muestra `ovillo-hub ❌ failed`

1. Verifica que el endpoint responde: `curl https://hub.example.org/` debe devolver `{"service":"Ovillo.Hub", ...}`. Si falla, hub caido — contactar al administrador del Hub.
2. Verifica que el host del Hub es alcanzable desde tu red (si es intranet-only, hace falta VPN/red corporativa).
3. Verifica que tu `.mcp.json` tiene `"type": "http"` (no `"sse"`), correcto a partir de SDK MCP 1.3+.

### Tool invocada devuelve `Internal error`

1. Mira los logs del Hub (Docker: `docker logs -f <contenedor-hub>`; o los logs del host donde corra).
2. Si el error es `proyectoId no esta registrado`: usa `list_projects` para obtener el GUID correcto.
3. Si el error es de timeout: la BD puede estar lenta; reintenta en 30s.

### Resource devuelve "no encontrada"

1. Verifica el nombre del proyecto con `list_projects` (case-sensitive).
2. Verifica que el proyecto sincronizo sus ADRs/lecciones (ejecutar `/mcp-sync` en el repo consumidor).
3. Para snapshots, las categorias validas son `decisiones`, `lecciones`, `funcionalidades`, `dependencias`, `historial`, `contexto_tecnico`.

## Anti-patrones

- **NO usar el hub para datos privados** que no deberian compartirse cross-equipo. El hub es central, todos los devs Ovillo leen.
- **NO confundir tool vs resource**: si lo que quieres es leer markdown completo (ADR), usa resource. Si quieres JSON resumido (KPIs), usa tool.
- **NO duplicar logica del comando `/mcp-sync`** llamando tools `register_decision` en bucle desde un script. El comando ya hace batch eficiente via REST.
- **NO asumir que el hub esta siempre disponible**. Implementa fallback graceful en codigo que dependa de el (timeout 5s, log warning).

## Referencias

- ADR-039 del ecosistema origen: decision arquitectonica del protocolo MCP real
- MCP spec: https://modelcontextprotocol.io/specification/

---

*Skill mantenido por equipo Constructor Ovillo. Actualizar cuando se anadan tools/resources/prompts en el hub.*
