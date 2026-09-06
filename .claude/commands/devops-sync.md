Sincronizar proyecto con Azure DevOps: work items, wiki, boards (DRY-RUN por defecto)

# /devops-sync - Sincronizacion con Azure DevOps

> Analiza el codigo fuente y sincroniza con Azure DevOps: Epic, Features, PBIs, Wiki.
> **DRY-RUN por defecto** — muestra todo antes de ejecutar cambios reales.

---

## REGLAS CRITICAS

- **DRY-RUN obligatorio** en primera ejecucion (mostrar, no ejecutar)
- **NO crear work items** sin confirmacion explicita del usuario
- **NO sobrescribir** wiki existente sin preguntar (opciones: sobrescribir/versionar/omitir)
- **Verificar duplicados** SIEMPRE antes de crear (buscar Epic/Feature existente)
- **Trazabilidad obligatoria** en cada PBI: endpoint + archivo + commit + tipo

---

## Parametros

| Parametro | Descripcion |
|-----------|-------------|
| (sin parametro) | Sincronizacion completa (5 fases, DRY-RUN) |
| `--live` | Ejecutar cambios reales en Azure DevOps |
| `--wiki-only` | Solo generar/actualizar wiki |
| `--boards-only` | Solo generar work items (Epic/Feature/PBI) |
| `--update-pbi [codigo]` | Actualizar estado de un PBI especifico |
| `--enable-auto` | Activar modo activo en regla devops-awareness (autoSync=true) |
| `--disable-auto` | Desactivar modo activo (volver a solo sugerencias) |
| `--retry` | Reintentar operaciones pendientes por error de conectividad |
| `--verify` | Ejecutar tests de regresion (teamfieldvalues, WIQL count, backlog levels) |
| `--status` | Mostrar estado de sincronizacion actual |

---

## Fase 0: Verificar pre-requisitos

```
================================================================
         VERIFICANDO PRE-REQUISITOS
================================================================

  Azure DevOps accesible    [devops.example.org]
  ESTADO_PROYECTO.json      [Leer configuracion AzDO]
  Code fuente             [03_Desarrollo/ detectado]
  Git log accesible         [git log disponible]
================================================================
```

Verificar:
1. Que `_hilo/ESTADO_PROYECTO.json` tiene seccion `infraestructura`
2. Que existe codigo en `03_Desarrollo/` (o ruta detectada)
3. Que `git log` es accesible

**Detectar proceso del proyecto** (CRITICO):
```bash
# Obtener proceso template del proyecto
curl --negotiate -u : "${URL}/_apis/projects/${PROJECT}?api-version=6.0"
# → capabilities.processTemplate.templateName = "Scrum" | "Basic" | "Agile" | "CMMI"
```

Adaptar segun proceso detectado:

| Proceso | Work item | Jerarquia | Estado activo | Estado pendiente |
|---------|-----------|-----------|---------------|-----------------|
| **Scrum** | Product Backlog Item | Epic → Feature → PBI | Committed | New |
| **Basic** | Issue | Epic → Issue (tags) | Doing | To Do |
| **Agile** | User Story | Epic → Feature → Story | Active | New |

Si es primera vez (no hay `azureDevOps` en ESTADO_PROYECTO.json):
```
Primera sincronizacion detectada.

Necesito:
1. URL del proyecto en Azure DevOps (ej: https://devops.example.org/COLECCION/PROYECTO)
2. Nombre del equipo (Team)
```

Guardar en ESTADO_PROYECTO.json → `infraestructura.azureDevOps`.

---

## Fase 1: Analisis automatico del codigo

Analizar (sin preguntar, automatico):

- **Framework**: leer .csproj → TargetFramework
- **Arquitectura**: detectar Clean Architecture, MVC, N-Capas
- **Endpoints**: Controllers, Minimal APIs → listar rutas
- **Seguridad**: Auth (Azure AD, JWT), CORS, Headers
- **Tests**: detectar proyectos de tests, cobertura estimada
- **Integraciones**: HttpClient, servicios externos
- **ORM**: EF Core, Dapper, ADO.NET
- **Observabilidad**: Serilog, OpenTelemetry, Health Checks
- **Resiliencia**: Polly policies

**Git log** (ultimos 200 commits):
```bash
git log --pretty=format:"%h|%an|%s" -n 200
```
Clasificar por conventional commits:
- `feat:` → Funcionalidad (Feature/PBI)
- `fix:` → Bug (PBI tipo Bug)
- `refactor:` → Deuda tecnica (PBI tipo Tech Debt)
- `docs:` → Documentacion (PBI tipo Documentation)

---

## Fase 2: Generar estructura (DRY-RUN)

Construir jerarquia propuesta segun proceso detectado:

**Si proceso = Scrum:**
```
Epic: [Nombre del proyecto]
├── Feature: Seguridad
│   ├── PBI: Configurar Azure AD SSO          [Done]
│   ├── PBI: Implementar CORS policy          [Done]
│   └── PBI: Añadir rate limiting             [New]
├── Feature: API Endpoints
│   ├── PBI: GET /api/scholarships                   [Done]
│   └── PBI: POST /api/scholarships                  [Committed]
└── Feature: Calidad
    └── PBI: Tests unitarios                  [New]
```

**Si proceso = Basic:**
```
Epic: [Nombre del proyecto]
├── Issue: Configurar Azure AD SSO          [Done]    tag:Seguridad
├── Issue: Implementar CORS policy          [Done]    tag:Seguridad
├── Issue: GET /api/scholarships                   [Done]    tag:API-Endpoints
├── Issue: POST /api/scholarships                  [Doing]   tag:API-Endpoints
└── Issue: Tests unitarios                  [To Do]   tag:Calidad
```

> En Basic NO hay Features. Los Issues se agrupan por **tags** bajo el Epic.

Priorizacion automatica:
  1. Seguridad (critica)
  2. Bugs (critica)
  3. Endpoints (alta)
  4. Observabilidad (media)
  5. Refactor / Deuda tecnica (baja)

================================================================
Total: 1 Epic, 5 Features, 11 PBIs (6 Done, 1 Committed, 4 New)
================================================================
```

**Trazabilidad en cada PBI:**
```
Origen:
- Endpoint: POST /api/becas
- Archivo: src/MyCompany.Scholarships.Web/Controllers/ScholarshipsController.cs:45
- Commit: abc123 "feat(scholarships): crear endpoint POST"
- Tipo: feat
```

---

## Fase 2.5: Validacion obligatoria

```
¿Confirmas esta estructura? [S/N]
¿Quieres modificar algo? (añadir/eliminar Features o PBIs)
```

**NO continuar sin confirmacion.**

---

## Fase 2.6: Control de duplicados

Si el proyecto ya tiene `azureDevOps.epicId` en ESTADO_PROYECTO.json:

```
Se ha detectado contenido existente en Azure DevOps:

Epic: #1234 "GestorLicencias" (existente)
Features: 3 de 5 ya existen
PBIs: 7 de 11 ya existen

Opciones:
1. Reutilizar existentes + crear solo los nuevos
2. Crear todo como nuevos (duplicados)
3. Cancelar

Selecciona:
```

---

## Fase 3: Ejecutar (solo si --live)

### DRY-RUN (default)
- Mostrar TODO en pantalla con formato visual
- NO ejecutar nada en Azure DevOps
- Guardar propuesta en `_hilo/devops_sync_proposal.json`

### LIVE (--live)

**3a. Resumen del proyecto (About)**

Actualizar la descripcion del proyecto en Azure DevOps:

```bash
curl -s --negotiate -u : "${URL}/_apis/projects/${PROJECT_ID}?api-version=6.0" \
  -X PATCH -H "Content-Type: application/json" \
  -d '{"description": "{descripcion_generada}"}'
```

La descripcion debe incluir (formato Markdown, max ~4000 chars):
- Que hace el proyecto (1-2 frases)
- Stack tecnologico (.NET version, DB, auth)
- Endpoints principales (top 5-10)
- Estado de seguridad (auth configurada, CORS, etc.)
- Equipo (JP, lider tecnico, developers)
- Enlace a Wiki para detalles

**3b. Dashboard (Paneles)**

Crear o actualizar dashboard con widgets Markdown informativos:

```bash
# 1. Obtener dashboard existente (o crear uno nuevo)
curl -s --negotiate -u : "${URL}/${TEAM}/_apis/dashboard/dashboards?api-version=6.1-preview.2"

# 2. Crear widgets (IMPORTANTE: settings = markdown RAW, no JSON wrapper)
```

Widgets a crear (4 widgets Markdown):

**Widget 1: Arquitectura** (size 2x2)
```markdown
## 🏗️ Arquitectura
| Capa | Proyecto | Responsabilidad |
|------|----------|-----------------|
| Web | MyCompany.X.Web | Controllers, Views |
| Application | MyCompany.X.App | Services, DTOs |
| Domain | MyCompany.X.Domain | Entidades, reglas |
| Infrastructure | MyCompany.X.Infra | EF Core, repos |

**Framework**: .NET 10 | **ORM**: EF Core 10
**Patron**: Clean Architecture
```

**Widget 2: Seguridad** (size 2x1)
```markdown
## 🔒 Seguridad
- **Auth**: Azure AD SSO ✅
- **CORS**: Configurado ✅
- **Key Vault**: Produccion ✅
- **HTTPS**: Obligatorio ✅
- **Rate Limiting**: ⚠️ Pendiente
```

**Widget 3: Equipo** (size 1x1)
```markdown
## 👥 Equipo
| Rol | Nombre |
|-----|--------|
| JP | {nombre} |
| Lead | {nombre} |
| Dev | {nombres} |
📧 {email_equipo}
```

**Widget 4: Estado del Proyecto** (size 2x1)
```markdown
## 📊 Estado
| Metrica | Valor |
|---------|-------|
| Issues | {total} ({done} done) |
| Cobertura | {cobertura}% |
| Build | ✅ Passing |
| Version | {version} |
Ultima sync: {fecha}
```

> **CRITICO TFS**: El campo `settings` del widget debe contener markdown crudo directamente.
> NO usar `{"content":"..."}` — TFS on-premises no parsea JSON wrappers.
> ContributionId: `ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.MarkdownWidget`

**3c. Work Items (Boards)**

- Crear Epic, Issues/PBIs segun proceso detectado (ver Fase 0)
- En Basic: Issues con tags. En Scrum: Features + PBIs

**3d. Wiki (9 paginas)**

- Generar Wiki (9 paginas):
  1. Home (resumen del proyecto)
  2. Arquitectura (diagrama + capas)
  3. Endpoints (tabla completa)
  4. Seguridad (auth, CORS, headers)
  5. Resiliencia (Polly policies)
  6. Observabilidad (logging, health checks)
  7. Configuracion (appsettings, variables)
  8. Desarrollo (como compilar, ejecutar, testear)
  9. Equipo (miembros, roles)
- Si wiki existente: preguntar sobrescribir/versionar/omitir por page

**3e. Asignaciones (Assigned To)**

Asignar work items a miembros del equipo correlacionando git log con el area de cada work item.

**3e.1 Detectar developers** (soporta multi-rol):

```
developers = []
for m in equipo.miembros:
    roles = m.roles if m.roles else ([m.rol] if m.rol else [])
    if "desarrollador" in roles:
        developers.append(m)
```

Nota: un miembro con `roles: ["jefe_proyecto", "desarrollador"]` cuenta como developer. El campo legacy `rol` (string) sigue soportado como `[rol]`.

**3e.2 Tabla ampliada de areas a carpetas** (usar para todos los proyectos):

| Tag/Area del work item | Carpetas/patrones a inspeccionar en git log |
|---|---|
| API-Endpoints / Endpoints | `**/Controllers/`, `**/Endpoints/`, `**/MinimalApi*/` |
| Seguridad | `**/Auth/`, `**/Security/`, `**/Middleware/`, `**/*Auth*`, `**/*Security*` |
| Integraciones / EWP | `**/EWP/`, `**/ewp/`, `**/Integrations/`, `**/HttpClients/` |
| Observabilidad | `**/Logging/`, `**/Observability/`, `**/HealthChecks/`, `**/Telemetry/` |
| Calidad / Tests | `tests/`, `**/*Test*.cs`, `**/*Spec*.cs`, `**/*.Tests/` |
| DevOps / CI-CD | `.azuredevops/`, `azure-pipelines*.yml`, `Dockerfile`, `docker-compose*`, `pipelines/` |
| Configuracion | `**/Config*/`, `**/configuracion/`, `**/Configuracion/`, `appsettings*.json`, `web.config` |
| BaseDatos / SQL | `**/BaseDatos/`, `**/Database/`, `**/StoredProcedures/**`, `**/*.sql`, `**/*.sqlproj` |
| UI / Views | `**/Views/`, `**/Pages/`, `**/wwwroot/`, `**/*.cshtml`, `**/*.razor` |
| EPIC{N} | paths que contengan `EPIC{N}` literal (ej. `Scripts/EPIC01_*.sql`, `Features/EPIC01/`) |
| Deuda tecnica (DT-*) | top contributor del commit original que introdujo la deuda (ver DEUDA_TECNICA.md) |

**3e.3 Algoritmo de asignacion por work item**:

```
para cada work_item creado en fases anteriores:
  1. paths_candidatos = []
     - si tiene tag conocido → paths_candidatos += tabla 3e.2[tag]
     - si titulo/descripcion menciona entidad (ej. "CursoActivo", "GrupoRanking") →
       paths_candidatos += glob("**/*{entidad}*")
     - si titulo incluye EPIC{N} → paths_candidatos += glob("**/*EPIC{N}*")

  2. top_contributor = `git log --pretty=format:"%an" -- {paths_candidatos} | sort | uniq -c | sort -rn | head -1`

  3. resolver developer:
     - buscar m en developers donde m.git_author_name == top_contributor
       o m.nombre == top_contributor
     - si match → assignee = m.nombre (displayName AD para AssignedTo)
     - si NO match → assignee = null (omitir AssignedTo, dejar sin asignar + warning)
```

**Casos criticos a cubrir**:
- No filtrar por `responsable_tecnico` ni "1 solo developer" sin mirar git log. En proyectos con JP que tambien desarrolla, eso causa asignacion monopolizada (bug real detectado 2026-04-21).
- Si ningun path candidato da commits → fallback: buscar en titulo/descripcion la palabra clave y usar `git log --all --pretty=format:"%an" --grep={palabra}`.
- Si hay empate entre 2 developers, elegir el que tenga mas commits totales en ese area (segundo `head` no queda ambiguedad).

**3e.4 Re-sync de asignaciones** (proyecto ya sincronizado):

Si la Fase 2.6 detecta duplicados (proyecto ya sincronizado), ofrecer re-calcular asignaciones:

```
DRY-RUN:
  - Leer todos los work items existentes via WIQL
  - Aplicar algoritmo 3e.3 a cada uno usando git log actual
  - Generar tabla de cambios: ID | titulo | assignee_actual | assignee_propuesto
  - Preguntar al usuario: aplicar solo cambios (patch individual) vs mantener estado actual

LIVE (tras confirmacion):
  - Para cada item con cambio, PATCH System.AssignedTo con nuevo displayName
  - Escribir _hilo/devops_execution_log.json con lista de reasignaciones
```

**3e.5 PATCH final** (sintaxis):

```bash
# IMPORTANTE: value = displayName exacto tal cual figura en AD.
# En TFS on-premises NO se acepta email/UPN - devuelve HTTP 400 "unknown identity".
# Fuente del displayName: equipo.miembros[x].nombre en ESTADO_PROYECTO.json.
curl -s --negotiate -u : "${URL}/_apis/wit/workitems/{ID}?api-version=6.0" \
  -X PATCH -H "Content-Type: application/json-patch+json" \
  -d '[{"op":"add","path":"/fields/System.AssignedTo","value":"{displayName_exacto}"}]'
```

> **Nota TFS on-premises**: `System.AssignedTo` acepta **solo displayName** (ej. `Raquel Agudelo Villarrubia`), NO email ni UPN. Pasar `ragudelo@example.com` devuelve 400 `unknown identity`. Si no hay match en `equipo.miembros`, **omitir el campo** (sin asignar) antes que enviar alias/email invalido. En Azure DevOps cloud si se acepta email.

**3f. Area Paths**

Crear areas que reflejen la estructura del codigo:

```bash
# Crear area path
curl -s --negotiate -u : "${URL}/_apis/wit/classificationnodes/areas?api-version=6.0" \
  -X POST -H "Content-Type: application/json" \
  -d '{"name": "{area_name}"}'
```

Areas estandar a crear:
- `API` — Controllers, Endpoints, Minimal APIs
- `Seguridad` — Auth, CORS, Headers, Secrets
- `Infraestructura` — EF Core, Repos, External Services
- `Testing` — Tests, Mocks, Fixtures
- `DevOps` — Pipelines, Deploy, Config

Asignar cada work item a su area:
```bash
curl -s --negotiate -u : "${URL}/_apis/wit/workitems/{ID}?api-version=6.0" \
  -X PATCH -H "Content-Type: application/json-patch+json" \
  -d '[{"op":"add","path":"/fields/System.AreaPath","value":"{PROJECT}\\{AREA}"}]'
```

**3f.1. Configurar Team para incluir sub-areas (CRITICO — ejecutar SIEMPRE tras crear Area Paths)**

> **BUG CRITICO**: Si el Team tiene `includeChildren: false` en su AreaPath raiz, los work items
> asignados a sub-areas (EUPeace\API, EUPeace\Seguridad) NO apareceran en Kanban ni Backlog
> aunque existan. Sintoma: "Elementos de trabajo" muestra todos, pero "Panel" y "Trabajo pendiente" vacios.

Actualizar configuracion del Team para incluir descendientes del AreaPath raiz:

```bash
# 1. Diagnosticar configuracion actual
curl -s --negotiate -u : \
  "${URL}/${TEAM}/_apis/work/teamsettings/teamfieldvalues?api-version=6.0"
# Si la respuesta es: { "values": [{"value": "${PROJECT}", "includeChildren": false}] }
# → hay que aplicar el fix

# 2. Aplicar fix (includeChildren: true)
curl -s --negotiate -u : \
  "${URL}/${TEAM}/_apis/work/teamsettings/teamfieldvalues?api-version=6.0" \
  -X PATCH -H "Content-Type: application/json" \
  -d '{
    "defaultValue": "${PROJECT}",
    "values": [{"value": "${PROJECT}", "includeChildren": true}]
  }'
```

Notas:
- **Siempre ejecutar** tras 3f (no es opcional)
- Si falla (permisos de admin), loguear WARN y continuar — el usuario puede aplicarlo manualmente
- `${PROJECT}` es el nombre del proyecto (raiz del AreaPath) — leer de `azureDevOps.url` o config
- `${TEAM}` es el nombre del equipo — leer de `azureDevOps.teamName`

Output esperado tras ejecucion exitosa:
```
✓ Team configurado: ${PROJECT} (includeChildren: true)
  Ahora Kanban y Backlog mostraran work items de todas las sub-areas
```

**3g. Queries guardadas (Shared Queries)**

Crear queries WIQL utiles para el equipo:

```bash
# Crear query en Shared Queries
curl -s --negotiate -u : "${URL}/_apis/wit/queries/Shared%20Queries?api-version=6.0" \
  -X POST -H "Content-Type: application/json" \
  -d '{"name": "{query_name}", "wiql": "{wiql_query}", "isFolder": false}'
```

Queries a crear:
1. **Mi trabajo** — Items asignados al usuario actual
   ```sql
   SELECT [System.Id], [System.Title], [System.State]
   FROM WorkItems
   WHERE [System.AssignedTo] = @Me
   AND [System.State] <> 'Done'
   ORDER BY [Microsoft.VSTS.Common.Priority]
   ```

2. **Bugs abiertos** — Bugs/Issues sin cerrar
   ```sql
   SELECT [System.Id], [System.Title], [System.State], [System.AssignedTo]
   FROM WorkItems
   WHERE [System.WorkItemType] IN ('Bug', 'Issue')
   AND [System.State] <> 'Done'
   ORDER BY [Microsoft.VSTS.Common.Priority]
   ```

3. **Deuda tecnica** — Items con tag DT-*
   ```sql
   SELECT [System.Id], [System.Title], [System.State]
   FROM WorkItems
   WHERE [System.Tags] CONTAINS 'DT-'
   ORDER BY [Microsoft.VSTS.Common.Priority]
   ```

4. **Completados esta semana** — Done en los ultimos 7 dias
   ```sql
   SELECT [System.Id], [System.Title], [System.ChangedDate]
   FROM WorkItems
   WHERE [System.State] = 'Done'
   AND [System.ChangedDate] >= @Today - 7
   ORDER BY [System.ChangedDate] DESC
   ```

**3h. Iteraciones/Sprints**

Crear iteraciones segun `calendario.release_cycle` de ESTADO_PROYECTO.json:

```bash
# Crear iteracion
curl -s --negotiate -u : "${URL}/_apis/wit/classificationnodes/iterations?api-version=6.0" \
  -X POST -H "Content-Type: application/json" \
  -d '{"name": "{sprint_name}", "attributes": {"startDate": "{start}", "finishDate": "{end}"}}'
```

| release_cycle | Iteraciones a crear |
|---------------|-------------------|
| `continuo` | No crear (flujo libre) |
| `semanal` | 4 sprints de 1 semana |
| `quincenal` | 4 sprints de 2 semanas |
| `mensual` | 3 sprints de 1 mes |
| `por_sprint` | Preguntar duracion al usuario |
| null | No crear (configurar en /onboarding) |

**3i. Branch Policies (si pipeline existe)**

Si `infraestructura.cicd.pipeline_existente = true`, configurar branch policies:

```bash
# Leer config de branching
RAMA_BASE = configuracion.branching.ramaBase
REVIEWERS = configuracion.branching.branchPolicies.reviewersMinimo
BUILD_VAL = configuracion.branching.branchPolicies.buildValidation
```

Policies a configurar:
- **Minimum reviewers**: `reviewersMinimo` (default 1)
- **Build validation**: si `buildValidation = true`
- **Comment resolution**: si `commentResolution = true`
- **Linked work items**: si `linkedWorkItems = true`

> Nota: Branch policies requieren permisos especiales. Si falla, mostrar warning y continuar.

**3j. Notificaciones del equipo**

Crear suscripciones de notificacion para el equipo:

| Evento | Destinatario | Condicion |
|--------|-------------|-----------|
| Build failure | Todo el equipo | Rama base |
| Work item asignado | Developer asignado | AssignedTo changed |
| PR creada | Reviewers | Target = rama base |

> Nota: La API de notificaciones puede requerir permisos de admin. Si falla, documentar y continuar.

---

## Fase 4: Persistencia Hilo

Guardar en `_hilo/ESTADO_PROYECTO.json`:

```json
{
  "infraestructura": {
    "azureDevOps": {
      "url": "https://devops.example.org/COLECCION/PROYECTO",
      "teamName": "Equipo Principal",
      "epicId": 1234,
      "features": {
        "seguridad": 1235,
        "endpoints": 1236,
        "observabilidad": 1237
      },
      "wikiCreada": true,
      "ultimaSync": "2026-04-16",
      "syncMode": "DRY-RUN"
    }
  }
}
```

Guardar log en `_hilo/devops_execution_log.json`:

```json
{
  "fecha": "2026-04-16",
  "usuario": "HV",
  "modo": "DRY-RUN",
  "cambios": [],
  "errores": []
}
```

---

## Fase Opcional: `--verify` (Tests de Regresion)

Si el usuario pasa `--verify`, ejecutar estos 3 checks tras la sincronizacion:

### Check 1: Team configuration (includeChildren)

```bash
curl -s --negotiate -u : \
  "${URL}/${TEAM}/_apis/work/teamsettings/teamfieldvalues?api-version=6.0" \
  | jq '.values[0].includeChildren'
# Resultado esperado: true
```

### Check 2: WIQL devuelve work items creados

```bash
curl -s --negotiate -u : "${URL}/_apis/wit/wiql?api-version=6.0" \
  -X POST -H "Content-Type: application/json" \
  -d '{"query":"SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = '\''${PROJECT}'\''"}'
# Resultado esperado: workItems.length > 0
```

### Check 3: Backlogs devuelven count > 0 por nivel

```bash
# Basic: nivel Issues
curl -s --negotiate -u : "${URL}/${TEAM}/_apis/work/backlogs/Microsoft.RequirementCategory/workItems?api-version=6.0"

# Basic: nivel Epics
curl -s --negotiate -u : "${URL}/${TEAM}/_apis/work/backlogs/Microsoft.EpicCategory/workItems?api-version=6.0"

# Scrum: nivel PBIs
curl -s --negotiate -u : "${URL}/${TEAM}/_apis/work/backlogs/Microsoft.RequirementCategory/workItems?api-version=6.0"
```

Output:

```
🧪 VERIFY RESULTS:
  ✓ Team includeChildren:  true          [OK]
  ✓ WIQL work items:       26 items      [OK]
  ✓ Backlog Issues/PBIs:   20 items      [OK]
  ✓ Backlog Epics:         1 item        [OK]

  Todo OK — sincronizacion verificada.
```

Si algun check falla:

```
🧪 VERIFY RESULTS:
  ✗ Team includeChildren:  false         [FAIL] → Ejecutar Fase 3f.1
  ✓ WIQL work items:       26 items      [OK]
  ✗ Backlog Issues/PBIs:   0 items       [FAIL] → Kanban vacio, revisar Team

  Problemas detectados. Revisar logs y volver a ejecutar /devops-sync --live.
```

---

## Fase Final: Resumen

```
================================================================
         AZURE DEVOPS SINCRONIZADO
================================================================

  Resumen:      OK (descripcion actualizada)
  Dashboard:    4 widgets (Arquitectura, Seguridad, Equipo, Estado)
  Boards:       1 Epic, X Features/Issues, Y asignados
  Wiki:         9 paginas
  Areas:        5 (API, Seguridad, Infraestructura, Testing, DevOps)
  Team fix:     OK (includeChildren=true aplicado)
  Queries:      4 (Mi trabajo, Bugs, Deuda tecnica, Completados)
  Iteraciones:  X sprints creados
  Policies:     X configuradas (o N/A si no hay pipeline)
  Asignaciones: Y work items asignados a Z miembros

  Modo:         DRY-RUN / LIVE
  Siguiente:    /devops-sync --live  (para ejecutar cambios reales)

  Links:
  🔗 Boards (Issues):    ${URL}/${TEAM}/_boards/board/${TEAM}/Issues
  🔗 Backlog (Epics):    ${URL}/${TEAM}/_backlogs/backlog/${TEAM}/Epics
  🔗 Wiki:               ${URL}/${TEAM}/_wiki
  🔗 Dashboard:          ${URL}/${TEAM}/_dashboards
  🔗 Shared Queries:     ${URL}/${TEAM}/_queries/shared

  NOTA: Kanban por defecto muestra Issues (Basic) o PBIs (Scrum).
        Epics se visualizan en el backlog de Epics, no en el Kanban.
================================================================
```

---

## Integracion con otros comandos

| Comando | Relacion |
|---------|----------|
| `/analizar` | Usa el mismo analisis de codigo (no duplicar) |
| `/jira` | Complementario — /jira para Jira Cloud, /devops-sync para Azure DevOps on-premise |
| `/finalizar-evolutivo` | La regla devops-awareness sugiere actualizar PBI tras finalizar |
| `/commit` | La regla sugiere incluir #PBI-ID en mensaje |
| `/onboarding` | Fase 5b detecta infraestructura AzDO |

---

## NOTAS TECNICAS — TFS ON-PREMISES (CRITICO)

### Estados PBI (proceso Scrum)

**NO usar "In Progress"** — no existe en proceso Scrum de TFS.

| Estado | Uso |
|--------|-----|
| **New** | Pending |
| **Approved** | Aprobado en backlog |
| **Committed** | En desarrollo activo |
| **Done** | Completado |

### Widgets Markdown en Dashboard

El campo `settings` debe contener **markdown crudo**, NO `{"content":"..."}`:

```
# CORRECTO:
"settings": "## Titulo\n\n| Col | Val |\n|---|---|\n| A | B |"

# INCORRECTO (muestra JSON como texto):
"settings": json.dumps({"content": "## Titulo\n\n..."})
```

### API version

Usar `api-version=6.0` (compatible TFS 2020). NO usar `7.0` (solo Azure DevOps cloud).

### Area Paths y visibilidad en Kanban/Backlog (CRITICO)

Al crear sub-areas y asignar work items a ellas, el Team DEBE tener
`includeChildren: true` en su AreaPath raiz, o los Kanban/Backlog
quedaran vacios aunque los items existan.

Sintomas del bug:
- "Elementos de trabajo" muestra todos los items correctamente
- "Panel" (Kanban) aparece vacio (0 en todas las columnas)
- "Trabajo pendiente" (Backlog) aparece vacio

Fix: PATCH teamfieldvalues con includeChildren:true tras crear areas (Fase 3f.1).

### Visibilidad de Epics en Kanban (proceso Basic y Scrum)

El Kanban por defecto muestra SOLO un nivel:
- Basic → muestra Issues (no Epics)
- Scrum → muestra PBIs (no Features ni Epics)

Para ver Epics usar el backlog de Epics:
```
${URL}/${TEAM}/_backlogs/backlog/${TEAM}/Epics
```

Esto NO es un bug — es el comportamiento estandar de Azure DevOps.
El output final del comando debe documentar esto para evitar confusion.

---

*Comando v3.8.4 - Sincronizacion completa con Azure DevOps (10 features + Team fix + --verify). Fix Kanban/Backlog vacios: Fase 3f.1 aplica includeChildren=true tras crear sub-areas.*
