# Guía completa de CI/CD Ovillo — los comandos `/cicd-*` y todas sus variantes

> **Para desarrolladores.** Cómo funcionan los 4 comandos CI/CD de Ovillo y cómo se comportan según
> tu **fase de adopción**, **stack**, **entrypoints** (multi-entrypoint), **estrategia de branching** y **modelo de deploy**.
>
> **Plataforma**: Azure DevOps Server 2020 on-premise (`devops.example.org`), pool de agentes **BUILDERS**.
> **Reglas runtime**: los invariantes G1-G14 **R1-R25** viven en `.claude/rules/cicd-runtime.md`; las limitaciones
> de TFS 2020 en `.claude/rules/tfs-2020-limitations.md` (este documento las referencia, no las repite).

---

## 0. Modelo mental (léelo primero)

Tres ideas que explican todo lo demás:

1. **Build ≠ Deploy.** Un *push* a la rama base **construye** (compila + test + artefacto), pero **no despliega**.
   El deploy es una decisión posterior y **bajo demanda** (`/cicd-deploy`). "Liberar" una versión (`/cicd-release`)
   tampoco despliega: solo crea el tag y dispara el build.
2. **El deploy lo hace el agente, no tu máquina.** Los comandos solo **encolan** el pipeline vía REST; el MSDeploy
   al IIS destino corre en un **agente de deploy** que vive en el propio servidor. Nunca copies archivos a mano.
3. **Una solución = un repo, pero N entrypoints.** Cada proyecto desplegable (Web, API, Console) genera **su propio
   pipeline** (R25). El routing a servidores de **Aplicaciones** o **Servicios** se decide por el tipo del entrypoint.

### Los 4 comandos de un vistazo

| Comando | Qué hace | Cuándo |
|---|---|---|
| **`/cicd-init`** | Genera/actualiza el pipeline (`azure-pipelines.yml` + definición TFS). Wizard por fases. | Una vez por proyecto/entrypoint, y al promocionar de fase o actualizar plantilla. |
| **`/cicd-status`** | Muestra estado: últimos builds, tiempos por stage, cobertura, último deploy por entorno, *drift* de plantilla. | Cuando quieras ver cómo va el pipeline. |
| **`/cicd-release`** | Crea tag semver + push → **dispara el Build**. NO despliega. | Cuando marcas una versión lista. |
| **`/cicd-deploy`** | Encola el deploy a `dev`/`pre`/`pro` (variable `DeployEnv`). | Cuando promueves un artefacto a un entorno. |

---

## 1. Conceptos transversales (de aquí salen "las variantes")

### 1.1 Fases de adopción (0 / 1 / 2)

`/cicd-init` pregunta el **nivel de adopción** (P0). Determina qué se genera:

| Fase | Nombre | Qué genera | CD |
|---|---|---|---|
| **0** | Local-only | Solo docs/runbook manual (`RUNBOOK_DEPLOY_MANUAL.md`). Sin pipeline TFS. | No |
| **1** | Build validation | `azure-pipelines.yml` minimal: build + test + publica artefacto. **1 pipeline de la solución completa** (CI-only). | No |
| **2** | Full CD | Pipeline completo: build + test + gates + **1 pipeline por entrypoint** con stages de deploy, triple rollback, Variable Groups. | Sí |

> **Fase 1 = 1 pipeline de build de la solución.** Los pipelines **por entrypoint con CD** (Web→app, API→svc) son
> **Fase 2**. Promocionar 1→2 no recrea desde cero (idempotencia R14): re-ejecuta `/cicd-init` y elige "promocionar".

Ver detalle en `GUIA_FASES_ADOPCION.md`.

### 1.2 Stacks soportados (4 variantes)

`/cicd-init` detecta el stack en FASE 0.1 y genera el template adecuado:

| Stack | Detección | CD a | Notas clave |
|---|---|---|---|
| **`.NET SDK-style`** (dotnet) | `.csproj` SDK-style, `net8/9/10` | IIS (MSDeploy) | Cobertura Mira R18; config por entorno = KV o VG-injection (R23). |
| **`.NET Framework clásico`** (netfx) | `packages.config` + MVC5/WebApi2, `net48` | IIS (MSDeploy) | MSBuild (`NuGetCommand@2`+`VSBuild@1`+`VSTest@2`); config por entorno = **transforms `Web.<Cfg>.config`** (R23). |
| **`Vue + Vite + TS`** (vue) | `package.json` + `vite` | IIS (archivos estáticos) | Smoke best-effort (R11); `TakeAppOffline:false` (R10); siempre a **Aplicaciones**. |
| **`.NET-tool`** (nettool) | tool/librería NuGet | **No IIS** | Publica `.nupkg` a feed interno; sin stage de deploy (gate de seguridad informativo, R22 N/A). |

La tabla de versiones de task canónicas por stack está en **R4**.

### 1.3 Entrypoints y routing Aplicaciones vs Servicios (R25)

Cada repo = **una solución**, pero puede tener **varios proyectos entrypoint**. `/cicd-init` los detecta TODOS
(FASE 0.1-ter) y genera **un pipeline por entrypoint desplegable**:

| Tipo entrypoint | Detección | CI | CD | Servidor destino |
|---|---|---|---|---|
| **Web (UI)** | `Microsoft.NET.Sdk.Web` con vistas (o MVC5 netfx) | sí | sí | **Aplicaciones** (público por naturaleza) |
| **Web API** | `Microsoft.NET.Sdk.Web` sin vistas | sí | sí | **Servicios** si privada (default) · **Aplicaciones** si marcada pública |
| **Console / Worker** | `OutputType=Exe` sin SDK.Web, `IHostedService` | sí | **sí (v3.16.0, FB-B)** | **parametrizable** (Tarea Programada; `DeployTarget` del pool real, sin tipo fijo app/svc) |

- En P1-bis el wizard **muestra la clasificación** y por cada Web/API **pregunta si es pública**; lo persiste en
  `_hilo/ESTADO_PROYECTO.json.infraestructura.cicd[].publico`.
- **Routing** → `serverType` (`app`/`svc`) → capability **`DeployTarget=<env>-<app|svc>`** (R1, R25).
- **Naming**: 1 entrypoint → `azure-pipelines.yml` + definición `<PROYECTO>` (back-compat). >1 → `azure-pipelines.<slug>.yml`
  + definición `<PROYECTO>-<slug>`, con `trigger.paths` acotado al subárbol de ese entrypoint.

> El `DeployTarget` real **se deriva del pool** (R1/FB-002): `/cicd-init` consulta las capabilities reales de los
> agentes y mapea cada entorno×tipo a un valor existente (no hardcodea `<env>-<app|svc>` si Sistemas usó otro esquema).

Inventario de servidores (Dev `dev01`/`svc01`, Pre `demowww`/`demows`, Prod `APPNODE*`/`SVCNODE*`) y el esquema
de capabilities: tabla en **R1** + handoff `PERMISOS_CICD.md`.

### 1.4 Modelos de deploy (auto / on-demand / branch-gated)

`/cicd-init` P2-bis pregunta el **modelo de deploy** (solo Fase 2). El **default lo sugiere tu estrategia de branching**:

| Modelo | Gate del deploy | Cuándo (default) |
|---|---|---|
| **Auto** | DEV automático en push; PRE/PROD con `ManualValidation`/approval | CD continuo a DEV, una sola rama. |
| **On-demand** (R20) | `DeployEnv=<env>` (push **no** despliega) | Deploy 100% bajo demanda, una sola rama (github-flow, trunk-based...). |
| **Branch-gated** (R24) | `DeployEnv` **+** `Build.SourceBranch` | Bajo demanda **con ramas por entorno** (`gitlab-flow`, `gitflow`). |

### 1.5 Estrategia de branching → trigger + branch policy (R21)

`/cicd-init` lee `configuracion.branching.estrategia` y deriva el `trigger.branches` y si recomendar la *branch policy*
"Build validation" (que corre el build en PRs):

| Estrategia | `trigger.branches.include` | Branch policy build-validation | Modelo deploy sugerido |
|---|---|---|---|
| `github-flow-simplificado` | `[main]` | **NO** (bloquearía el push directo) | on-demand |
| `trunk-based` | `[main]` | opcional | on-demand |
| `developer-branch` | `[{ramaBase}]` | **NO** | on-demand |
| `github-flow` | `[main]` | **SÍ** (gate PR a main) | on-demand |
| `gitflow` | `[main, develop, release/*]` | **SÍ** | **branch-gated** |
| `release-flow` / `oneflow` | `[main, release/*]` | **SÍ** | on-demand/branch-gated |
| `gitlab-flow` | `[main, pre-production, production]` | **SÍ** | **branch-gated** |

> **Regla de oro**: estrategias de **push directo** (`github-flow-simplificado`, `trunk-based`, `developer-branch`)
> → solo rama base + `pr: none` + **sin** policy (avisa: "NO actives build-validation, bloquea tu push directo").
> Estrategias **con PR** → añade ramas + **recomienda** la policy. `pr: none` siempre en el YAML (en TFS Git los PR
> triggers son la *branch policy*, no `pr:` del YAML).

### 1.6 Config por entorno y secretos

| Stack / caso | Cómo | Regla |
|---|---|---|
| Secretos (todos) | **Variable Group** de TFS (`<PIPELINE>-secrets`, `isSecret`) + fail-fast pre-build | R16 |
| netfx, config por entorno | **Transforms `Web.<Cfg>.config`** (1 build por entorno) + VG para secretos | R23 |
| .NET SDK-style **con** Key Vault | `AddAzureKeyVault(...)`; el deploy NO inyecta nada | R23 (P4-bis) |
| .NET SDK-style **sin** Key Vault | **VG + inyección en deploy** por PowerShell (NO `FileTransform@1`: rompe con JSONC + claves con puntos) | R23 (P4-bis) |
| Service-key del QR de calidad | **Zero-touch**: `/cicd-init` FASE 2.7 la emite vía Hub y la deja `isSecret` en el VG (nunca se imprime) | R16, ADR-046 |

### 1.7 Gates de calidad y seguridad

- **Cobertura (R18)**: gate con `mira summary --threshold-line/--threshold-branch` (herramienta interna
  `dotnet-reportgenerator-globaltool`). **WARN-first** por defecto (avisa, no tumba el build); el equipo lo sube a BLOCK cuando
  su cobertura es estable. Mira 0.10.2 además publica un reporte HTML rico (CRAP/hotspots) como artefacto.
- **Seguridad (R22)**: patrón *verdict-file* — el scan corre 1 vez en Build (deps vulnerables, secretos en config,
  hardening, SAST Roslyn) y cada stage de deploy decide: DEV=WARN, DEMO/PROD=BLOCK si severidad ≥ `High`.

---

## 2. `/cicd-init` — generar / actualizar el pipeline

Es el comando central. Wizard idempotente (R14): re-ejecutarlo no rompe nada.

### 2.1 Sintaxis y cuándo

```
/cicd-init            # wizard interactivo (detecta stack, entrypoints, fase)
```

Úsalo para: crear el pipeline, **promocionar de fase** (0→1→2), **añadir/modificar un stage**, o **re-renderizar** el
YAML a la última plantilla. NO lo uses para desplegar (`/cicd-deploy`) ni versionar (`/cicd-release`).

### 2.2 Flujo (qué pasa por dentro)

**FASE 0 — Detección y pre-validaciones**
- **0.1** Detecta el **stack** (4 variantes). Si es TFS Classic `.xaml` → aborta (no soportado).
- **0.1-ter** Enumera **todos los entrypoints** de la solución y los clasifica (Web/API/Console).
- **0.3-bis** *Brownfield*: si hay secretos preexistentes en config versionada, el gate de seguridad se genera en
  `mode: warn` también para PRE/PROD (no bloquea el primer pipeline por deuda anterior; registra `SEC-XXX`).
- **0.4** Pre-flight contra TFS: pool BUILDERS visible, cola autorizada, etc. (permiso `Use` del pool lo concede
  Sistemas **al grupo del proyecto** — ver `PERMISOS_CICD.md`).
- **0.5** **Idempotencia**: si ya hay `azure-pipelines.yml`, entra en **modo edición** (5 opciones, ver 2.3).

**FASE 1 — Wizard** (`P0`-`P5`)
- **P0** Fase de adopción (0/1/2).
- **P1 / P1-bis** Confirma proyecto + **entrypoints** + pregunta **público** por cada Web/API (persiste los N).
- **P2** Entornos (Fase ≥ 1).
- **P2-bis** **Modelo de deploy** (auto/on-demand/branch-gated; default según branching).
- **P3** Checklist consolidado (trigger, naming, smoke URL, etc.) con defaults inferidos → confirma.
- **P4 / P4-bis** Variable Groups / secretos + config por entorno (.NET SDK-style: KV vs VG-injection).
- **P5** Resumen y confirmación final.

**FASE 2 — Generación**
- Renderiza el `*.yml.template` del stack, **un pipeline por entrypoint desplegable** (Console incluido: CD via Tarea Programada, v3.16.0/FB-B).
- **2.5/2.6** Registra **una definición TFS + un registro en el Hub** por entrypoint (`register_pipeline`, UPSERT).
- **2.7** (opcional, default sí) Auto-cablea el **QR de calidad** al dashboard (zero-touch service-key, ADR-046).
- **2.8** **Self-check** (`validate-pipeline-complete.ps1`) + **sello de plantilla** en la cabecera del YAML
  (`# Ovillo cicd-architect <stack> @ vX.Y.Z (tpl <hash>)`, ADR-047) para detectar *drift* después.

### 2.3 Modo edición (re-ejecutar sobre un proyecto ya inicializado)

Antes de las opciones, **reconcilia entrypoints** (FB-A-bis): re-detecta y añade a `cicd[]` los que falten. Luego:

| Opción | Acción |
|---|---|
| 1 | Añadir un stage |
| 2 | Modificar un stage |
| 3 | Regenerar docs (runbook) |
| 4 | **Actualizar YAML completo** = **re-render COMPLETO** desde el template (NO un parche), preservando bloques `# CUSTOM:` y el `--filter` de tests; cierra con self-check (FASE 2.8) |
| 5 | Salir |

> Si `/cicd-status` te avisa de *drift* de plantilla, la **Opción 4** es la forma correcta de ponerte al día.

---

## 3. `/cicd-status` — ver el estado

```
/cicd-status [--entrypoint <slug>] [--watch] [--last N] [--format json|csv] [--stage <name>]
```

- Lee `cicd[]` (R25: **una entrada por entrypoint**). Por defecto muestra **todos**; `--entrypoint` filtra a uno.
- **Fase 0**: recuerda el deploy manual (runbook).
- **Fase ≥ 1**: pide `get_cicd_status` al Hub MCP; si no responde, *fallback* a `/_apis/build/builds` de TFS.
  Muestra: últimos builds, tiempo por stage, **cobertura trend**, **último deploy por entorno** (Fase 2).
- **1.5 Drift de plantilla**: compara el sello `tpl <hash>` del YAML con el hash actual del template de tu stack
  (ADR-047). Si cambió → sugiere `/cicd-init` Opción 4. (Es informativo, no bloquea.)
- `--watch`: refresca cada 30s (útil durante un deploy).

---

## 4. `/cicd-release` — versionar y disparar el build

```
/cicd-release [--major|--minor|--patch|--version X.Y.Z] [--deploy <dev|pre|pro>] [--no-push] [--dry-run]
```

- Valida working tree limpio + rama base. Calcula el siguiente semver. Crea **tag anotado** (`-a`) y lo empuja.
- El push **dispara el Build** (compila + test + artefacto `drop`). **Los stages de deploy NO corren** (en on-demand
  la variable `DeployEnv` va vacía).
- `--deploy <env>` es un **atajo explícito** (release → luego `/cicd-deploy`), nunca el comportamiento por defecto.
- **No** confundir con `/publicar` (ese es del **Constructor** Ovillo, publica la plantilla del ecosistema).

---

## 5. `/cicd-deploy` — desplegar bajo demanda

```
/cicd-deploy --env <dev|pre|pro> [--entrypoint <slug>] [--tag vX.Y.Z | --commit <sha>] [--watch] [--dry-run] [--yes]
```

- **Requiere Fase 2** (si fase < 2, aborta y sugiere promocionar).
- **`--entrypoint`**: si hay >1 y se omite → lista y pregunta. Cada entrypoint encola **su** definición; su
  `DeployTarget=<env>-<app|svc>` ya va horneado en el YAML.
- **Confirmación por entorno** (configurable en `cicd[].deployConfirm`): **Dev y Pre directos** por defecto, **Prod
  con confirmación** (doble check). `--yes` fuerza directo (salvo que el proyecto marque `deployConfirm[env]=true`).
- Encola vía REST con `parameters={DeployEnv:<env>}` (R3 + R2 TLS 1.2). El stage `Deploy<Env>` solo corre por su
  `condition`.
- **Branch-gated (R24)**: la rama se deriva del **entorno** (`dev`/`pre`→develop, `pro`→main). Pedir `--env pro` desde
  develop no desplegará (el `condition` por rama no matchea) — el comando te avisa antes de encolar.

---

## 6. Flujos completos (recetas)

### 6.1 Proyecto nuevo .NET, 1 entrypoint, github-flow

```
1. /cicd-init        → P0=Fase 1 (build validation). Genera azure-pipelines.yml + def <PROYECTO>.
                       Recomienda activar branch policy build-validation (PR a main).
2. (push / PR)       → el Build corre y valida.
3. /cicd-init        → promociona a Fase 2 (modelo on-demand). Genera stages DeployDev/Pre/Prod + VG de secretos.
4. /cicd-release --minor   → tag v1.1.0 + Build.
5. /cicd-deploy --env pre  → deploy a Pre (directo). Verifica.
6. /cicd-deploy --env pro  → deploy a Prod (pide confirmación).
```

### 6.2 Solución multi-entrypoint (Web + API privada + Console), gitflow

```
1. /cicd-init  → detecta 3 entrypoints. P1-bis: Web=público(app), API=privada(svc), Console=CD via Tarea Programada.
                 P2-bis: branch-gated (default por gitflow). Genera:
                   azure-pipelines.web.yml      + def <PROYECTO>-web   (CD a Aplicaciones)
                   azure-pipelines.api.yml      + def <PROYECTO>-api   (CD a Servicios)
                   azure-pipelines.console.yml  + def <PROYECTO>-console (CD Tarea Programada)
2. push a develop  → build de las 3 defs; deploy NO corre (DeployEnv vacío).
3. /cicd-deploy --env pre --entrypoint web   → DeployDemo de Web, gateado por DeployEnv=pre + rama develop (R24).
4. (merge a main) /cicd-deploy --env pro --entrypoint api  → DeployProd de API, gateado por rama main.
```
> El Console tiene CD (R25, v3.16.0/FB-B) via **Tarea Programada** (`schtasks`; deploy = file-sync `robocopy /MIR /XF appsettings`). Su `DeployTarget` se deriva del pool real (FB-002). Variante Windows Service always-on diferida.

### 6.3 netfx legacy (MVC5, .NET 4.8), config por entorno

```
1. /cicd-init  → detecta netfx. Genera pipeline MSBuild (NuGet+VSBuild+VSTest+MSDeploy).
                 Config por entorno = transforms Web.<Cfg>.config (un VSBuild + paquete por entorno).
                 Secretos en VG con XmlVariableSubstitution.
2. Resto igual que 6.1 (release + deploy on-demand).
```

---

## 7. Tabla rápida: "qué comando para qué"

| Quiero... | Comando |
|---|---|
| Crear el pipeline / promocionar de fase / re-render | `/cicd-init` |
| Ver builds, cobertura, último deploy, drift | `/cicd-status` |
| Marcar una versión y construirla | `/cicd-release` |
| Desplegar a un entorno | `/cicd-deploy` |
| Auditar el YAML contra R1-R25 | agent `cicd-pipeline-reviewer` (`AUDITAR_PIPELINE.md`) |
| Editar el YAML con sugerencias | skill `cicd-architect` |
| Desplegar sin pipeline (Fase 0) | `RUNBOOK_DEPLOY_MANUAL.md` |

---

## 8. Troubleshooting (consolidado)

| Síntoma | Causa probable | Acción |
|---|---|---|
| `/cicd-deploy` dice `requires Fase 2` | Pipeline en Fase 0/1 | `/cicd-init` → promocionar a Fase 2 |
| `DeployEnv not valid at queue time` | YAML sin modelo on-demand | `/cicd-init` Opción 4 (re-render) |
| Build encola pero el stage Deploy se salta | `condition` (`DeployEnv` o rama en branch-gated) no matchea | Verifica entorno y, en branch-gated, la rama del entorno |
| Build queda en `notStarted` | Ningún agente cumple el `demand` (capability real ≠ template) o canalización no autorizada (TEC-003) | `/cicd-init` deriva el demand del pool real; autorización al pool la concede Sistemas |
| `cicd-batch HTTP 400` en `/mcp-sync` | (resuelto en Hub ≥ 1.7.3) PS 5.1 serializa array de 1 elem como escalar | Actualiza el Hub; el Hub ya tolera escalar/array |
| Build no se dispara tras push | Path filters TFS 2020 (R7) | `trigger.paths` con doble patrón `**` y `**/*` |
| `/cicd-status` marca drift de plantilla | El template de tu stack cambió | `/cicd-init` Opción 4 (re-render + self-check) |
| Deploy verde pero app caída | Bug app / dep externa / secreto mal | `RUNBOOK` § "App caída tras deploy verde"; rollback automático R15 en pre/pro |

---

## 9. Referencias

| Documento | Contenido |
|---|---|
| `.claude/rules/cicd-runtime.md` | Las 25 reglas **R1-R25** (inventario, deploy models, routing, gates) |
| `.claude/rules/tfs-2020-limitations.md` | Tablas A-F: tasks/keywords/servicios prohibidos o limitados en TFS 2020 |
| `Documentos_Base/08_CICD/GUIA_FASES_ADOPCION.md` | Detalle de las fases 0/1/2 |
| `Documentos_Base/08_CICD/PERMISOS_CICD.md` | Handoff a Sistemas: pool BUILDERS, capabilities, agentes de deploy |
| `Documentos_Base/08_CICD/AUDITAR_PIPELINE.md` | Auditar el YAML con el agent `cicd-pipeline-reviewer` |
| `Documentos_Base/08_CICD/RUNBOOK_DEPLOY_MANUAL.md` | Deploy manual (Fase 0) |
| `Documentos_Base/08_CICD/RUNBOOK_ACTUALIZAR_PIPELINE.md` | Re-render seguro del YAML (drift) |
| `Documentos_Base/08_CICD/LIMITACIONES_TFS_2020.md` | Guía conceptual humana de las limitaciones |

---

*Ovillo v3.16.0 — Guía completa CI/CD. Familia `/cicd-*` (ADR-042) + modelo 1 solución / N entrypoints + routing
Aplicaciones/Servicios (ADR-048, R25) + CD Console/Worker via Tarea Programada (ADR-049, FB-B). Reglas R1-R25 en `cicd-runtime.md`.*
