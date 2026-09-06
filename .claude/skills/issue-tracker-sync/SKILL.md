---
name: issue-tracker-sync
description: |
  Knowledge base for issue-tracker/DevOps platform integration (platform from ecosystem.config.json -> vcs.platform / cicd.platform: azure-devops | github | gitlab | jira). Deep-dive provider currently documented: Azure DevOps Server on-premise; for other platforms apply the same patterns via their native APIs. Azure DevOps coverage — 10 features + Team fix + verify: About (project description), Dashboard (4 Markdown widgets), Boards (Epic/Feature/PBI multi-process), Wiki (9 pages), Assigned To (git log inference), Area Paths (5 areas + Team includeChildren=true fix), Saved Queries (4 WIQL), Iterations/Sprints (from release_cycle), Branch Policies (build validation, reviewers), Notifications, --verify regression tests. TFS on-premises specifics: Scrum (Committed) vs Basic (Doing), raw markdown widgets, api-version=6.0, Kanban shows 1 level only (Epics in backlog).
  USE FOR: conocimiento Azure DevOps, patrones work items, asignaciones, area paths, queries WIQL, iteraciones sprints, branch policies, dashboard widgets, wiki, trazabilidad PBI-codigo, priorizacion automatica, notificaciones equipo.
  DO NOT USE FOR: ejecutar sincronizacion (usar comando /devops-sync), tickets Jira interactivos (usar /jira), git operations, CI/CD pipeline creation.
  Keywords bilingues: Azure DevOps, Boards, work items, PBI, Epic, Feature, wiki, trazabilidad, backlog, Scrum, Committed, TFS, dashboard, queries, area path, sprint, iteration, branch policy, assigned to, notificaciones.
---

# Skill: issue-tracker-sync

Base de conocimiento para integracion con la plataforma de issue-tracking/DevOps configurada
(`ecosystem.config.json → vcs.platform` / `cicd.platform`). El provider documentado en
profundidad es **Azure DevOps Server on-premise** (el contenido de abajo); para GitHub/GitLab/
Jira, aplicar los mismos patrones (deteccion de workflow, identidad exacta, graceful
degradation) con sus APIs nativas.
Este skill proporciona **patrones y conocimiento**. Para ejecutar la sincronizacion, usar el **comando `/devops-sync`**.

## Diferencia con /devops-sync (comando)

| Componente | Proposito |
|------------|-----------|
| **Skill issue-tracker-sync** (este) | Base de conocimiento: patrones, templates, reglas TFS. Se activa automaticamente cuando Claude necesita info sobre AzDO. |
| **Comando /devops-sync** | Ejecucion: flujo guiado de 5 fases con DRY-RUN. Lo invoca el usuario explicitamente. |
| **Regla devops-awareness** | Recordatorios: sugiere sincronizar tras /finalizar-evolutivo, /commit, etc. Modo activo opt-in. |

## Deteccion de Proceso (CRITICO)

El proyecto puede usar distintos procesos. Detectar con:
`GET /_apis/projects/{project}?api-version=6.0` → `capabilities.processTemplate.templateName`

| Proceso | Jerarquia | Work item | Estado activo | Estado pendiente |
|---------|-----------|-----------|---------------|-----------------|
| **Scrum** | Epic → Feature → PBI | Product Backlog Item | Committed | New |
| **Basic** | Epic → Issue (tags) | Issue | Doing | To Do |
| **Agile** | Epic → Feature → Story | User Story | Active | New |

> **NUNCA asumir** el proceso — siempre detectar primero.

## Patrones de Work Items

### Proceso Scrum
```
Epic (proyecto completo)
├── Feature: Seguridad
│   ├── PBI: Configurar Azure AD SSO      [Committed]
│   └── PBI: Implementar CORS policy      [Done]
├── Feature: Endpoints
│   └── PBI: GET /api/scholarships               [Done]
└── Feature: Calidad
    └── PBI: Tests unitarios              [New]
```

### Proceso Basic
```
Epic (proyecto completo)
├── Issue: Configurar Azure AD SSO        [Doing]     tag:Seguridad
├── Issue: Implementar CORS policy        [Done]      tag:Seguridad
├── Issue: GET /api/scholarships                 [Done]      tag:API-Endpoints
└── Issue: Tests unitarios                [To Do]     tag:Calidad
```

> En Basic NO hay Features. Los Issues se vinculan al Epic directamente y se agrupan con **tags**.

### Mapeo area → agrupacion
| Area detectada en codigo | Scrum: Feature | Basic: Tag |
|--------------------------|----------------|------------|
| Endpoints, Controllers, CRUD | Endpoints | API-Endpoints |
| Auth, CORS, headers, seguridad | Seguridad | Seguridad |
| HttpClient, APIs externas, EWP | Integraciones | Integraciones o EWP |
| Logging, health checks, telemetria | Observabilidad | Observabilidad |
| Tests, refactor, DTs | Calidad | Calidad |
| BaseDatos, StoredProcedures, .sql | BaseDatos | BaseDatos |
| Views, Pages, Razor, wwwroot | UI | UI |
| Configuracion, appsettings, web.config | Configuracion | Configuracion |
| Scripts EPIC{N}, Features/EPIC{N} | Epic{N} | EPIC{N} |
| Pipelines, Dockerfile, .azuredevops | DevOps | DevOps |

### Mapeo area → carpetas para git log (inferencia de assignee)
| Tag | Patrones glob |
|-----|---------------|
| API-Endpoints | `**/Controllers/`, `**/Endpoints/`, `**/MinimalApi*/` |
| Seguridad | `**/Auth/`, `**/Security/`, `**/Middleware/`, `**/*Auth*`, `**/*Security*` |
| Integraciones | `**/Integrations/`, `**/HttpClients/`, `**/Services/External*` |
| EWP | `**/EWP/`, `**/ewp/` |
| Observabilidad | `**/Logging/`, `**/Observability/`, `**/HealthChecks/`, `**/Telemetry/` |
| Calidad | `tests/`, `**/*Test*.cs`, `**/*Spec*.cs`, `**/*.Tests/` |
| BaseDatos | `**/BaseDatos/`, `**/Database/`, `**/StoredProcedures/**`, `**/*.sql`, `**/*.sqlproj` |
| UI | `**/Views/`, `**/Pages/`, `**/wwwroot/`, `**/*.cshtml`, `**/*.razor` |
| Configuracion | `**/Config*/`, `**/configuracion/`, `**/Configuracion/`, `appsettings*.json`, `web.config` |
| DevOps | `.azuredevops/`, `azure-pipelines*.yml`, `Dockerfile`, `docker-compose*`, `pipelines/` |
| EPIC{N} | paths que contengan `EPIC{N}` literal (ej. `Scripts/EPIC01_*`, `Features/EPIC01/`) |

### Priorizacion automatica
| Tipo | Prioridad AzDO |
|------|----------------|
| Seguridad, Bugs | 1 (critica) |
| Endpoints | 2 (alta) |
| Observabilidad | 3 (media) |
| Refactor, DTs | 4 (baja) |

## Trazabilidad PBI → Codigo

Cada PBI debe incluir en su descripcion:
```
Origen:
- Endpoint: POST /api/scholarships
- Archivo: src/Controllers/ScholarshipsController.cs:45
- Commit: abc123 "feat(scholarships): crear endpoint POST"
- Tipo: feat
```

## Resumen del Proyecto (About)

Actualizar campo `description` del proyecto via `PATCH /_apis/projects/{id}?api-version=6.0`.
Incluir: que hace, stack, endpoints principales, seguridad, equipo. Max ~4000 chars, Markdown.

## Dashboard (Paneles)

4 widgets Markdown: Arquitectura (capas+framework), Seguridad (checklist), Equipo (tabla roles), Estado (metricas).

> **CRITICO**: `settings` = markdown crudo. NO `{"content":"..."}`. TFS no parsea JSON wrapper.
> ContributionId: `ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.MarkdownWidget`
> API: `POST /_apis/dashboard/dashboards/{id}/widgets?api-version=6.1-preview.2`

## Wiki desde Codigo (9 paginas)

1. **Home** — resumen del proyecto, stack, equipo
2. **Arquitectura** — diagrama de capas, dependencias
3. **Endpoints** — tabla completa de rutas + metodos
4. **Seguridad** — auth, CORS, headers, rate limiting
5. **Resiliencia** — Polly policies, circuit breaker
6. **Observabilidad** — logging, health checks, telemetria
7. **Configuracion** — appsettings, variables, secrets
8. **Desarrollo** — como compilar, ejecutar, testear
9. **Equipo** — miembros, roles, contacto

## Notas TFS on-premises (CRITICO)

### Estados por proceso
**Scrum**: New → Approved → **Committed** → Done
**Basic**: **To Do** → **Doing** → **Done**
**Agile**: New → **Active** → Resolved → Closed

> **NUNCA usar "In Progress"** — no existe en ningun proceso TFS. Devuelve error 400.

### Widgets Markdown Dashboard
- `settings` = markdown crudo directo, NO `{"content":"..."}`
- TFS on-premises no parsea JSON wrapper → muestra texto literal
- ContributionId: `ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.MarkdownWidget`

### API version
- Usar `api-version=6.0` (maximo para Azure DevOps Server 2020 Update 1.2)
- NO usar 7.0 (solo Azure DevOps cloud)

### Autenticacion
- NTLM Negotiate: `curl --negotiate -u :`
- PAT tokens: requiere HTTPS
- Azure AD / OAuth: NO soportado on-premises

### Area Paths y Team (CRITICO)

Al crear sub-areas y asignar work items a ellas, el **Team debe tener `includeChildren: true`**
en su AreaPath raiz, o los Kanban/Backlog quedaran vacios.

**Sintomas del bug:**
- "Elementos de trabajo" muestra todos los items
- "Panel" (Kanban) vacio, "Trabajo pendiente" (Backlog) vacio

**Fix automatico**: El comando `/devops-sync` aplica esto en Fase 3f.1 tras crear areas.

```bash
# Aplicar fix manualmente si es necesario:
curl -s --negotiate -u : "${URL}/${TEAM}/_apis/work/teamsettings/teamfieldvalues?api-version=6.0" \
  -X PATCH -H "Content-Type: application/json" \
  -d '{"defaultValue":"${PROJECT}","values":[{"value":"${PROJECT}","includeChildren":true}]}'
```

### Visibilidad de Epics en Kanban

El Kanban muestra solo UN nivel por defecto:
- **Basic**: Issues (no Epics)
- **Scrum**: PBIs (no Features ni Epics)

Para ver Epics: `${URL}/${TEAM}/_backlogs/backlog/${TEAM}/Epics` (no es bug, es comportamiento estandar).

### Ejemplo real: MyCompany.EuPeace

- Proceso: **Basic** (no Scrum, detectar con `capabilities.processTemplate.templateName`)
- Work item types: Epic, Issue, Task
- Tras crear 6 sub-areas: `includeChildren=true` obligatorio
- Tras fix: Kanban muestra 26 Issues + Backlog con 1 Epic

## Referencia

- **Comando**: `/devops-sync` (ejecucion guiada, DRY-RUN)
- **Regla**: `devops-awareness.md` (recordatorios + modo activo opt-in)
- **Persistencia**: `_hilo/ESTADO_PROYECTO.json → infraestructura.azureDevOps`
- **Log**: `_hilo/devops_execution_log.json`
