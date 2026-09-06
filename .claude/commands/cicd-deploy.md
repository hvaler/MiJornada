# /cicd-deploy — Deploy on-demand a un entorno

> Despliega un proyecto a Dev / Pre / Pro **bajo demanda**, encolando el pipeline con la variable `DeployEnv`. NO despliega en cada push — el deploy lo decides tú con este comando.
>
> Audiencia: desarrolladores con un pipeline en **Fase 2** (CD) ya generado por `/cicd-init`.
> Plataforma: Azure DevOps Server 2020 on-premise (`devops.example.org`).

---

## Extended Thinking Mode

**think hard**

El deploy lo ejecuta el **agente de deploy** (MSDeploy al IIS destino), NO la máquina del desarrollador. Este comando solo **encola** el pipeline vía REST API con `DeployEnv=<env>`; el stage de deploy correspondiente corre en el agente con capability `DeployTarget=<env>`. NUNCA hagas MSDeploy ni copia de archivos directa desde el cliente.

---

## Sintaxis

```
/cicd-deploy --env <dev|pre|pro> [--entrypoint <slug>] [--tag vX.Y.Z | --commit <sha>] [--watch] [--dry-run] [--yes]
```

| Flag | Descripción |
|---|---|
| `--env` | **Obligatorio**. Entorno destino: `dev`, `pre` o `pro`. |
| `--entrypoint` | Opcional. Slug del entrypoint a desplegar (R25). Si la solución tiene >1 pipeline y se omite → listar y preguntar. Con 1 solo, se infiere. Cada entrypoint = su propia definición (`<PROYECTO>-<slug>`); su `DeployTarget=<env>-<app\|svc>` ya va horneado en su YAML. |
| `--tag` | Opcional. Despliega la versión de ese tag (`sourceVersion`). Por defecto, HEAD de la rama base. |
| `--commit` | Opcional. Despliega ese commit SHA. Mutuamente excluyente con `--tag`. |
| `--watch` | Opcional. Sigue el estado de la run con polling (30s) hasta que termine. |
| `--dry-run` | Opcional. Muestra qué encolaría (URL, body, entorno) sin ejecutar el POST. |
| `--yes` | Opcional. Salta la confirmación (deploy directo) en el entorno pedido, aunque su `deployConfirm` esté activo. |

---

## CUÁNDO USAR

- Tras un `/cicd-release` (o un push que generó un Build verde) cuando quieras **promover ese artefacto** a un entorno.
- Para re-desplegar una versión anterior (`--tag vX.Y.Z`).

**NO usar para**:
- Generar o promocionar el pipeline → `/cicd-init`.
- Versionar/disparar el build → `/cicd-release`.
- Ver el estado de builds → `/cicd-status`.
- Proyectos en **Fase 0 o Fase 1** (no tienen stages de CD) — este comando ABORTA con mensaje accionable.

---

## FASE 0 — Validaciones previas

### 0.1 Leer estado CI/CD del proyecto

Leer `_hilo/ESTADO_PROYECTO.json.infraestructura.cicd[]` (R25: **N entradas, una por entrypoint**). Seleccionar la del entrypoint a desplegar:
- Si `--entrypoint <slug>` → esa entrada. Si se omite y hay **1** entrypoint → esa. Si hay **>1** → listar (`entrypoint`, `tipo`, `serverType`) y **preguntar** cuál.
- De la entrada elegida: `pipelineId`, `fase`, `nombre`, `url`, `stages`, `stack`, `tipo`, `serverType`, `publico`, `deployConfirm`.
- Datos de conexión TFS (`infraestructura.azureDevOps.url` o derivar de la `url` del pipeline).
- El `serverType` (app/svc) ya está horneado en el `DeployTarget` del YAML de ese entrypoint — `/cicd-deploy` NO lo decide, solo encola con `DeployEnv=<env>`.

### 0.2 Gate de fase (BLOQUEANTE)

```
SI fase < 2:
  ❌ "El pipeline '<nombre>' está en Fase <fase> (sin stages de CD).
      /cicd-deploy requiere Fase 2 (pipeline completo).
      Promociona con: /cicd-init  → opción 'promocionar a Fase 2'."
  exit 0
```

### 0.3 Validar entorno solicitado

- `--env` ∈ {dev, pre, pro}. Si no, error.
- Verificar que el stage de deploy de ese entorno existe en `stages` (ej. `DeployDev`, `DeployPre`, `DeployProd`). Si el entorno no tiene stage generado, sugerir `/cicd-init` → "añadir stage".

### 0.4 Pre-flight conectividad TFS

R2 — forzar TLS 1.2+ antes de cualquier HTTPS:

```powershell
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
} catch { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 }
```

Verificar `GET {col}/_apis/connectionData?api-version=6.0` → 200. Si 401/403, avisar que faltan credenciales o permiso de cola sobre el pipeline.

---

## FASE 1 — Confirmación por entorno (configurable)

Política por defecto (v3.15.0): **Dev y Pre = deploy directo**; **Prod = confirmación**. Configurable por proyecto
en `_hilo/ESTADO_PROYECTO.json.infraestructura.cicd[].deployConfirm: { dev:false, pre:false, pro:true }` (override
por entrypoint). `--yes` fuerza directo en cualquier entorno; si `deployConfirm[env]=true`, pedir confirmación.

| Entorno | Confirmación (default) |
|---|---|
| `dev` | **Directo** (no pregunta) — mostrar destino/versión informativo |
| `pre` | **Directo** por defecto (configurable a confirmar) — mostrar entorno, URL destino, versión/commit |
| `pro` | **Confirmación** por defecto + doble check — mostrar aprobadores, balanceo, estrategia rolling |

Ejemplo de confirmación para `pre`:

```
⚠️  DEPLOY A PRE — confirmar
    Proyecto:   MyCompany.Griddo
    Pipeline:   MyCompany.Griddo-CI (id=10)
    Entorno:    pre  (servidor: <server>, URL: <url>)
    Versión:    vX.Y.Z (o HEAD <sha7>)
    Gate:       el stage DeployPre aplicará smoke test + rollback (R11/R15)

    ¿Continuar? (escribe 'pre' para confirmar)
```

NUNCA desplegar a un entorno con `deployConfirm[env]=true` (por defecto **Prod**) sin confirmación explícita del usuario (requisito heredado de ADR-025 § /deploy, formalizado en ADR-042; Dev/Pre directos por defecto desde v3.15.0/ADR-048, salvo que el proyecto active su `deployConfirm`).

---

## FASE 2 — Encolar el pipeline vía REST

R3 — usar PowerShell + REST (no tasks Node). Encolar el build con `DeployEnv=<env>`:

```powershell
# [bloque TLS 1.2+ R2 ya aplicado en FASE 0.4]
$headers = @{ Authorization = "Bearer $env:SYSTEM_ACCESSTOKEN" }   # o --negotiate -u : con credenciales Windows
$col  = '<System.CollectionUri>'
$proj = '<TeamProject>'
$body = @{
    definition  = @{ id = <pipelineId> }
    sourceBranch = 'refs/heads/<rama>'          # ver derivacion abajo; o refs/tags/<tag> si --tag
    # sourceVersion = '<sha>'                    # si --commit
    parameters  = (@{ DeployEnv = '<env>' } | ConvertTo-Json -Compress)
} | ConvertTo-Json -Depth 6

# --dry-run: imprimir $body y la URL, NO ejecutar
Invoke-RestMethod -Uri "$col$proj/_apis/build/builds?api-version=6.0" -Method POST -Headers $headers -Body $body -ContentType 'application/json'
```

> `DeployEnv` debe estar declarada como **variable settable at queue time** en la definición (lo configura `/cicd-init` en Fase 2). El stage `Deploy<Env>` lleva `condition: eq(variables['DeployEnv'], '<env>')`, así que SOLO corre cuando se encola con ese valor. Un push normal (sin `DeployEnv`) construye pero NO despliega.

**Derivación de `<rama>`** (depende del modelo de deploy elegido en P2-bis de `/cicd-init`):

| Modelo | `sourceBranch` |
|---|---|
| `on-demand` / `auto` | `refs/heads/<ramaBase>` (de `configuracion.branching.ramaBase`) |
| `branch-gated` (R24) | **derivar del entorno pedido**: `dev`/`pre` → `refs/heads/<ramaDevelop>`, `pro` → `refs/heads/<ramaBase>` (mapeo R24, leer `configuracion.branching`) |

En branch-gated, encolar `--env pro` sobre la rama de develop produce un build cuyo stage `DeployProd` **no matchea** el `condition` por rama → el deploy se salta (a propósito). Si el usuario lo intenta, avisar ANTES de encolar.

### Manejo de respuestas

- **HTTP 200**: ✅ build encolado. Mostrar `buildNumber` + URL de la run.
- **HTTP 400 `DeployEnv is not a valid ... queue time variable`**: la definición no tiene `DeployEnv` como queue-time. Causa: pipeline generado antes del modelo on-demand. Fix: `/cicd-init` → "actualizar YAML" para regenerar con el modelo `DeployEnv`.
- **HTTP 403**: falta permiso de cola sobre el pipeline. Escalar a Sistemas (rol Queue builds).

---

## FASE 3 — Seguimiento (--watch) y registro

Con `--watch`: poll `GET {col}{proj}/_apis/build/builds/{buildId}?api-version=6.0` cada 30s hasta `status=completed`. Mostrar `result` (succeeded / failed / canceled).

Tras una run con `result=succeeded`:
1. Actualizar `_hilo/ESTADO_PROYECTO.json`: `metricas.ultimo_deploy` + la entrada `infraestructura.cicd[].ultimoBuildStatus`.
2. Registrar en Hub MCP (si `.mcp.json` referencia `ovillo-hub`): tool `register_pipeline` (UPSERT) con `ultimoBuildStatus` y fecha. Best-effort (try/catch; no fallar el comando si el Hub no responde).

---

## REGLAS CRÍTICAS

- **NUNCA** desplegar a un entorno con `deployConfirm=true` (default **Prod**) sin confirmación explícita (Dev/Pre directos por defecto, R25/ADR-048).
- **NUNCA** hacer MSDeploy/copia directa desde el cliente — el agente de deploy lo hace.
- **NUNCA** encolar si `fase < 2`.
- **SIEMPRE** TLS 1.2+ (R2) antes de tocar `devops.example.org`.
- **SIEMPRE** encolar vía REST + PowerShell (R3), no tasks Node.
- El push NO despliega; el deploy es on-demand vía este comando (modelo `DeployEnv`, R20).

---

## TROUBLESHOOTING

| Síntoma | Causa | Fix |
|---|---|---|
| `requires Fase 2` | Pipeline en Fase 0/1 | `/cicd-init` → promocionar a Fase 2 |
| `DeployEnv not valid at queue time` | YAML sin modelo on-demand | `/cicd-init` → actualizar YAML |
| Build encola pero el stage Deploy se salta | `condition` no matchea `DeployEnv` | Verificar que el valor (`dev`/`pre`/`pro`) coincide con el `condition` del stage |
| HTTP 403 al encolar | Falta permiso Queue builds | Sistemas concede rol al grupo del proyecto |
| Deploy corre pero falla smoke | App no arranca / secreto mal | Ver RUNBOOK 05_CICD § "App caída tras deploy verde"; rollback automático R15 si pre/pro |

---

*Comando plantilla Ovillo v3.11.0 — deploy on-demand. Rescata `/deploy` del ADR-025, formalizado en ADR-042. Modelo `DeployEnv` (R20): push construye, deploy on-demand.*
