# TFS REST Playbook — modo activo de devops-awareness (autoSync)

> Referencia tecnica del **modo activo** de la regla `.claude/rules/devops-awareness.md`
> (payloads REST, estados por proceso, gotchas TFS on-premises). La regla siempre-cargada
> solo lleva el resumen; este archivo se lee bajo demanda cuando `autoSync=true` y hay que
> crear/transicionar work items. Extraido de la regla en la dieta de contexto (AUD-008).

---

## Prerequisitos del modo activo

`azureDevOps.autoSync = true` **Y** `azureDevOps.epicId != null` en
`_hilo/ESTADO_PROYECTO.json.infraestructura`. Si falta alguno, caer al modo pasivo.

## Deteccion de proceso (CRITICO)

Leer `azureDevOps.proceso`. Si no existe:
`GET /_apis/projects/{project}?api-version=6.0` → `capabilities.processTemplate.templateName`.

| Proceso | Jerarquia | Work item | Estados |
|---|---|---|---|
| **Scrum** | Epic → Feature → PBI | Product Backlog Item | New → Approved → **Committed** → Done |
| **Basic** | Epic → Issue → Task | Issue | **To Do** → **Doing** → **Done** |

> **NUNCA "In Progress"** — no existe en ningun proceso TFS (HTTP 400).

## Crear work items automaticamente

**Scrum:**

| Evento | Accion en Boards |
|---|---|
| `/nuevo-evolutivo` (HV-*) | Crear PBI `{codigo}: {titulo}`, estado **Committed** |
| Nueva DT en DEUDA_TECNICA.md | Crear PBI, estado **New** |
| DT que se empieza a trabajar | Transicionar PBI a **Committed** |

**Basic:** igual pero con Issue y estados **Doing** / **To Do** / **Doing**.

**Mapeo area → agrupacion** (Scrum agrupa bajo Features; Basic con tags):

| Area detectada | Scrum: Feature padre | Basic: Tag |
|---|---|---|
| Endpoints, datos, CRUD | `features.endpoints` | `API-Endpoints` |
| APIs externas, HttpClient | `features.integraciones` | `Integraciones` |
| Auth, headers, CORS, seguridad | `features.seguridad` | `Seguridad` |
| Logging, health checks, telemetria | `features.observabilidad` | `Observabilidad` |
| Tests, refactor, DTs | `features.calidad` | `Calidad` |

**Prioridad automatica:** HV-* → 1 · DT-* Alta → 1 · DT-* Media → 2 · DT-* Baja → 3.

**Ejecucion** (REST via curl o MCP):

```bash
# Leer config
URL=$(jq -r '.infraestructura.azureDevOps.url' _hilo/ESTADO_PROYECTO.json)
FEATURE_ID=$(jq -r '.infraestructura.azureDevOps.features.{area}' _hilo/ESTADO_PROYECTO.json)

# Lookup displayName del asignado (CRITICO en TFS on-premises)
# System.AssignedTo REQUIERE displayName, NO acepta email/UPN en on-premises.
ASIGNADO_ALIAS=$(jq -r '.evolutivos.enProgreso[] | select(.codigo=="{CODIGO}") | .asignadoA' _hilo/ESTADO_PROYECTO.json)
ASIGNADO_DISPLAY=$(jq -r --arg a "$ASIGNADO_ALIAS" '.equipo.miembros[] | select(.usuario==$a) | .nombre' _hilo/ESTADO_PROYECTO.json)

# Crear PBI con parent link + assignee
# Si ASIGNADO_DISPLAY esta vacio, OMITIR System.AssignedTo (NO pasar email/alias)
curl -s --negotiate -u : \
  "${URL}/_apis/wit/workitems/\$${WORK_ITEM_TYPE}?api-version=6.0" \
  -X POST -H "Content-Type: application/json-patch+json" \
  -d '[
    {"op":"add","path":"/fields/System.Title","value":"{CODIGO}: {titulo}"},
    {"op":"add","path":"/fields/System.Description","value":"{descripcion}"},
    {"op":"add","path":"/fields/Microsoft.VSTS.Common.Priority","value":{prioridad}},
    {"op":"add","path":"/fields/System.AssignedTo","value":"'"$ASIGNADO_DISPLAY"'"},
    {"op":"add","path":"/relations/-","value":{
      "rel":"System.LinkTypes.Hierarchy-Reverse",
      "url":"${URL}/_apis/wit/workitems/${PARENT_ID}"
    }}
  ]'
# WORK_ITEM_TYPE: "Product%20Backlog%20Item" (Scrum) o "Issue" (Basic)
# PARENT_ID: Feature ID (Scrum) o Epic ID (Basic, no hay Features)
```

## Transicionar a Done

| Evento | Scrum / Basic |
|---|---|
| `/finalizar-evolutivo` | PBI/Issue → **Done** |
| DT ✅ Completado | → **Done** |
| DT ❌ Descartada | → **Done** + nota |

```bash
# Buscar work item por titulo (WIQL)
curl -s --negotiate -u : "${URL}/_apis/wit/wiql?api-version=6.0" \
  -X POST -H "Content-Type: application/json" \
  -d '{"query":"SELECT [System.Id] FROM WorkItems WHERE [System.Title] CONTAINS '\''{CODIGO}'\'' AND [System.WorkItemType] = '\''Product Backlog Item'\''"}'

# Transicionar
curl -s --negotiate -u : "${URL}/_apis/wit/workitems/{PBI_ID}?api-version=6.0" \
  -X PATCH -H "Content-Type: application/json-patch+json" \
  -d '[{"op":"add","path":"/fields/System.State","value":"Done"}]'
```

**Coherencia de Features** tras crear/cerrar: Feature con PBIs pendientes → **Committed**;
todos Done → Feature puede pasar a **Done**.

## Error de conectividad — graceful degradation

**NO bloquear el trabajo.** Warning + continuar, y encolar la operacion en
`_hilo/devops_pending_ops.json` (se reintenta en la proxima operacion o con
`/devops-sync --retry`):

```json
[
  { "tipo": "crear_pbi", "codigo": "HV-19", "titulo": "Filtro de scholarships por estado",
    "featureArea": "endpoints", "prioridad": 1, "fecha": "2026-04-16", "reintentos": 0 }
]
```

Tras cada sincronizacion, resumen: `✅ Azure DevOps actualizado: PBI #1234 "..." → Committed`.

## Configuracion en ESTADO_PROYECTO.json

```json
"infraestructura": {
  "azureDevOps": {
    "url": "https://devops.example.org/COLECCION/PROYECTO",
    "teamName": "Equipo Principal",
    "epicId": 1234,
    "features": { "endpoints": 1235, "integraciones": 1236, "seguridad": 1237,
                  "observabilidad": 1238, "calidad": 1239 },
    "proceso": "Scrum",
    "autoSync": false,
    "ultimaSync": null,
    "pendingOps": "_hilo/devops_pending_ops.json"
  }
}
```

Opciones de `proceso`: `Scrum` | `Basic` | `Agile` | `CMMI`.
Si `azureDevOps` no existe → sin recordatorios. Si `epicId=null` → sugerir `/devops-sync`.
Si `autoSync=true` pero `epicId=null` → modo pasivo con warning.

---

## Notas tecnicas TFS on-premises (CRITICO)

### System.AssignedTo requiere displayName, NO email

TFS on-premises **no resuelve** email/UPN. Solo acepta el displayName exacto de AD:

```
OK:  {"op":"add","path":"/fields/System.AssignedTo","value":"Francisco Javier Gonzalez Criado"}
KO:  "fjgonzalez@example.com" / "fgonzalez"   → HTTP 400 "unknown identity"
```

Fuente: `equipo.miembros[x].nombre` (donde `usuario == alias_git`). Sin match → **omitir el
campo** (sin asignar es mejor que 400). Descubrir en runtime:
`GET /_apis/identities?searchFilter=General&filterValue={alias}&api-version=6.0`.

### api-version

`6.0` para casi todo (TFS 2020; NUNCA 7.0). Excepciones que exigen `-preview`:

| Endpoint | api-version |
|---|---|
| `/_apis/work/backlogs` (+`/workItems`) | **5.1-preview** |
| Otros `/_apis/work/*` con HTTP 400 | probar `5.1-preview` o `6.0-preview.1` |

### Widgets Markdown en Dashboard

El campo `settings` lleva **markdown crudo directamente**, NO envuelto en `{"content":"..."}`
(TFS 2020 no parsea el wrapper — mostraria el JSON como texto plano).
ContributionId: `ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.MarkdownWidget`.
Para actualizar widgets existentes: PUT del dashboard completo (no widget individual) con eTag.

---

*Referencia issue-tracker-sync — extraida de devops-awareness.md v3.8.2 (fix TFS bugs).*
