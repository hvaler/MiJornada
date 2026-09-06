---
name: cicd-architect
description: |
  Arquitecto CI/CD para la plataforma configurada (ecosystem.config.json -> cicd.platform + cicd.variant + cicd.environments[]). Provider documentado en profundidad: azure-pipelines, incluida la variant server-2020 on-premise (limitaciones validadas empiricamente); para otras plataformas aplicar los invariantes G1-G14 de rules/cicd-runtime.md. Auto-invocacion al editar azure-pipelines.yml. Conoce los invariantes G1-G14 (cicd-runtime.md, incluye el gate de ciberseguridad G8), las 3 fases de adopcion (Fase 0/1/2) y 3 stacks (.NET ASP.NET Core, Vue+Vite+TS, .NET-tool/libreria NuGet). Sirve para sugerir correcciones en YAML inline, validar steps contra los invariantes, generar fragmentos canonicos de stages Build/Deploy, disenar el modelo de deploy (on-demand con variable DeployEnv para que el push NO despliegue, vs modelo auto, vs branch-gated que ademas gatea cada entorno por rama origen Build.SourceBranch en gitlab-flow/gitflow), y guiar el diseno de pipelines en el wizard /cicd-init.
  USE FOR: editar azure-pipelines.yml, sugerir correcciones contra los invariantes G1-G14, generar steps canonicos para pool BUILDERS + capability DeployTarget, smoke test estricto (.NET) o best-effort (SPA), triple rollback PROD, Variable Groups con fail-fast, configurar TLS 1.2+ en steps PS, REST API descarga artifacts, IISWebAppDeploymentOnMachineGroup@0, retention rules, coverage gate nativo (Cobertura XML), anti-patterns linter, idempotencia FASE 0.5, decidir entre Fase 0/1/2 segun infra disponible, disenar stages Build+Deploy, configurar deploy on-demand (variable DeployEnv: que el pipeline NO despliegue en cada push y el deploy se lance bajo demanda, G1) vs modelo auto vs branch-gated (branch-gated G1: DeployEnv + Build.SourceBranch para ramas por entorno gitlab-flow/gitflow, Dev/Demo desde develop y Prod solo desde main, variante netfx con drops por entorno), emitir el gate de ciberseguridad verdict-file (security-scan.ps1: 4 checks, los deploys leen el verdict y bloquean DEMO/PROD por severidad, G8), generar pipeline para stack .NET-tool/libreria NuGet (un solo stage, publicacion del .nupkg al feed interno con tag v*).
  USE FOR (tambien): guiar la migracion MANUAL de pipelines TFS Classic .xaml/.xoml a YAML con validacion side-by-side (references/classic-migration.md, ADR-053 — la skill cicd-classic-migrator se retiro).
  DO NOT USE FOR: ejecutar el wizard de bootstrap (usar comando /cicd-init), auditar YAML existente para reportar hallazgos (usar agent cicd-pipeline-reviewer), ver estado de ultimos builds (usar /cicd-status), configurar branch policies fuera del YAML (TFS UI manual), gestionar work items Boards (usar skill issue-tracker-sync).
  Keywords bilingues: CI/CD, azure-pipelines, TFS 2020, BUILDERS, DeployTarget, capability, MSDeploy, IISWebAppDeployment, smoke test, hairpin NAT, TLS 1.2, REST API artifact, deploymentGroup HARD, Cache@2 HARD, rollback, Variable Group, fail-fast, retention rules, coverage gate, Fase 0, Fase 1, Fase 2, build validation branch policy, ManualValidation, Environment, group approval, rolling deploy, .NET ASP.NET Core, Vue Vite TypeScript, app_offline.htm, ServicePointManager TLS, Invoke-WebRequest SSL, SystemAccessToken, BuildArtifacts download, deploy on-demand, bajo demanda, DeployEnv, push no despliega, modelo on-demand vs auto vs branch-gated, G1, branch-gated, Build.SourceBranch, ramas por entorno, gitlab-flow deploy, drop-dev drop-pre drop-pro, gate de seguridad, security-scan.ps1, verdict-file, security-exceptions, SAST CA5xxx, G8, dotnet tool, dotnet pack, libreria NuGet, PackAsTool, PaquetesNuget feed, dogfooding, .NET-tool, stack nettool.
allowed-tools: Read, Grep, Glob
---

# Skill: cicd-architect

Arquitecto CI/CD para proyectos de la organización sobre TFS 2020 on-premise. Sirve para validar/generar steps de `azure-pipelines.yml` siguiendo los invariantes G1-G14 de `rules/cicd-runtime.md` (+ conocimiento profundo del provider azure-pipelines, incl. variant server-2020) y las 3 fases de adopcion.

## Cuando se activa

Auto-invocacion cuando Claude edita o lee:
- `azure-pipelines.yml` en raiz del repo
- `**/azure-pipelines*.yml`
- `**/.azure-pipelines/**/*.yml`
- `**/.pipelines/**/*.yml`

Tambien al detectar keywords del usuario: "configurar pipeline", "azure devops yaml", "deploy IIS on-premise", "smoke test hairpin NAT", "triple rollback PROD", "TFS 2020 limitations".

## Cuando NO activarse

- Si el archivo es `.github/workflows/*.yml` → GitHub Actions, plataforma distinta a la configurada (responder con los invariantes G1-G14)
- Si el archivo es `.gitlab-ci.yml` → GitLab CI → responder con los invariantes G1-G14 (provider sin referencia profunda)
- Si el usuario pide "migrar pipeline TFS Classic .xaml a YAML" → SÍ activarse, con `references/classic-migration.md` (migración manual guiada + side-by-side; la skill cicd-classic-migrator se retiró en v3.18.0, ADR-053)
- Si el usuario pide "ejecutar el wizard /cicd-init" → no auto-invocar (el comando ya orquesta)
- Si el usuario pide "auditar YAML existente con reporte severidad" → delegar a agent `cicd-pipeline-reviewer`

## Estructura de la skill

```
cicd-architect/
├── SKILL.md                                        ← este archivo
├── eval-set.json                                   ← queries positivas/adversariales
├── references/
│   ├── 19-reglas-resumen.md                        ← R1-R25 condensadas
│   ├── tfs-2020-quick-ref.md                       ← tablas A-F en formato consulta rapida
│   ├── troubleshooting-frecuente.md                ← 30+ sintomas → causa → fix
│   ├── diseno-stages.md                            ← patron Build/DeployDev/Demo/Prod completo
│   └── fases-adopcion.md                           ← Fase 0/1/2: que genera cada una
├── templates/
│   ├── azure-pipelines.fase1.dotnet.yml.template   ← build+test+publish .NET (sin CD)
│   ├── azure-pipelines.fase1.vue.yml.template      ← build+test+publish Vue+Vite (sin CD)
│   ├── azure-pipelines.fase2.dotnet.yml.template   ← pipeline completo .NET con CD
│   ├── azure-pipelines.fase2.vue.yml.template      ← pipeline completo Vue+Vite con CD
│   ├── azure-pipelines.nettool.yml.template        ← stack .NET-tool/libreria → feed NuGet (1 stage, tag v*)
│   ├── azure-pipelines.fase2.netfx.branch-gated.yml.template ← netfx branch-gated R24 (3 VSBuild por rama → drop-dev/pre/pro)
│   ├── security-scan.ps1                            ← gate de ciberseguridad verdict-file (R22, ASCII puro)
│   ├── validate-pipeline-complete.ps1               ← self-check de completitud del YAML vs template (h13, ASCII puro)
│   ├── Get-TemplateStamp.ps1                         ← hash de contenido del template del stack para el sello/drift (v3.14.0-h1, ADR-047, ASCII puro)
│   ├── Provision-QualityCiKey.ps1.template           ← zero-touch HUB_SERVICE_KEY del QR (ADR-046): emite via Hub + VG isSecret + autoriza
│   └── steps/                                       ← steps canonicos reutilizables
│       ├── 01-tls-bootstrap.ps1.snippet            ← bloque TLS 1.2+ (R2)
│       ├── 02-rest-api-artifact-download.ps1.snippet ← descarga artifact (R3)
│       ├── 03-smoke-strict-dotnet.ps1.snippet      ← smoke 6 endpoints .NET
│       ├── 04-smoke-besteffort-spa.ps1.snippet     ← smoke best-effort SPA (R11)
│       ├── 05-backup-pre-deploy.ps1.snippet        ← backup wwwroot (R15 capa 1)
│       ├── 06-rollback-condition-failed.ps1.snippet ← rollback (R15 capa 3)
│       ├── 07-fail-fast-vg-secrets.ps1.snippet     ← validar VG (R16)
│       └── 08-anti-patterns-linter.ps1.snippet     ← linter R12 warning-only
```

## Flujo de uso tipico

### 1. Validar step manual del dev

Si el usuario escribe un step en YAML que viola R1-R25:

```yaml
- task: DownloadBuildArtifacts@0     # ❌ R3 HARD: bug SSL Node.js
  inputs:
    artifactName: drop
```

Claude detecta la violacion, cita la regla, propone fix:

> ⚠️ R3 (descarga artifacts REST API): `DownloadBuildArtifacts@0` sufre bug SSL Node.js contra `devops.example.org` (`unable to get local issuer certificate`). Usa PowerShell + REST API en su lugar — ver template `steps/02-rest-api-artifact-download.ps1.snippet`.

### 2. Generar fragment canonico

Si el usuario pide "necesito un step de smoke test para mi API .NET":

Claude lee `references/diseno-stages.md` + `templates/steps/03-smoke-strict-dotnet.ps1.snippet` y emite el step completo con TLS 1.2+, 6 endpoints (`/health/live`, `/health/ready`, `/health`, 3 endpoints protegidos 401), retry logic, throw si falla.

### 3. Decidir entre Fase 0/1/2

Si el usuario pregunta "¿que fase me toca?":

Claude lee `references/fases-adopcion.md` y aplica el arbol de decision:

```
¿Tienes acceso TFS y BUILDERS autorizado?
├── NO  → Fase 0
└── SI  → ¿Tienes agentes <ENV>_DEPLOY online?
         ├── NO  → Fase 1
         └── SI  → ¿Grupo aprobadores TFS con ≥2 miembros?
                  ├── NO  → Fase 1 (crear grupo en paralelo)
                  └── SI  → Fase 2
```

### 4. Sugerir adaptacion stack

Si el stack es Vue+Vite+TS y el dev propone `TakeAppOfflineFlag: true`:

> ⚠️ R10: `TakeAppOfflineFlag: true` es para .NET ASP.NET Core in-process (libera locks de DLLs). En SPA estatica como Vue+Vite, si esta `true` y el deploy se interrumpe queda `app_offline.htm` residual sirviendo 503 indefinidamente. Cambia a `false`.

## Patrones de uso recomendados

### Patron A: Generar stage Build desde cero

```
Usuario: "necesito el stage Build para mi proyecto .NET 10"

Claude:
  1. Lee templates/azure-pipelines.fase1.dotnet.yml.template
  2. Adapta:
     - <PROYECTO_NOMBRE> ← del package.json o .csproj
     - <RAMA_BASE> ← git symbolic-ref refs/remotes/origin/HEAD
     - .NET version ← 10 (default del ecosistema)
     - Coverage thresholds ← line 70% / branch 60% (R18, mira summary; NO CRAP)
  3. Emite el stage Build completo con:
     - pool BUILDERS + Agent.ComputerName=LADYADA (R1)
     - UseDotNet@2 (R4)
     - dotnet restore/build/test/publish (R4)
     - PublishCodeCoverageResults@1 con Cobertura (R4)
     - Linter anti-patterns warning-only (R12, R18)
     - PublishBuildArtifacts@1 (R4)
```

### Patron B: Adaptar stage Deploy a entorno especifico

```
Usuario: "anade DeployDemo a mi pipeline"

Claude:
  1. Verifica que existe stage Build (depende de el)
  2. Pregunta: ¿manual gate (ManualValidation@0) o environment con group approval?
     - Por defecto DEMO usa ManualValidation@0 (mas simple)
     - PROD obligatorio environment + group approval
  3. Genera stage con:
     - dependsOn: Build + condition: succeeded()
     - job WaitForApproval (pool: server) con ManualValidation@0
     - job DeployToDemo (pool BUILDERS + DeployTarget=pre-<app|svc> segun routing del entrypoint, R1/R25)
     - checkout: none (R8)
     - Descarga artifact via REST API (R3)
     - IISWebAppDeploymentOnMachineGroup@0 con TakeAppOfflineFlag segun stack (R10)
     - Smoke best-effort si SPA / estricto si .NET (R11)
```

> **Modelo multi-entrypoint + routing (R25, v3.15.0)**: 1 repo = 1 solución, pero la solución puede tener
> varios entrypoints (Web/API/Console). Se genera **un pipeline por entrypoint** (Web/API con CD, Console
> CI-only). El `DeployTarget=<env>-<app|svc>` y la URL de smoke salen del **tipo+público** del entrypoint:
> Web→`app`, API privada (default)→`svc`, API pública→`app`. PROD por `Agent.Name` (APPNODE* apps / STORM* svc).
> Inventario de entornos: `ecosystem.config.cicd.environments[]` (override por proyecto en `ESTADO_PROYECTO.infraestructura`).

### Patron D: Stack .NET-tool / libreria NuGet (Variante C)

```
Usuario: "mi proyecto es una CLI/libreria que publica NuGet, no una web"

Claude:
  1. Detecta el stack: .csproj con <PackAsTool>true</PackAsTool> o <IsPackable>true</IsPackable>
     y NINGUN proyecto web host.
  2. Lee templates/azure-pipelines.nettool.yml.template
  3. Adapta placeholders (SLN, packProject, nupkgOutputDir, SDK_VERSION, RAMA_BASE)
  4. Emite UN solo stage BuildTestPublish:
     - trigger: push a {ramaBase} (CI) + tag v* (publica)
     - build + test + cobertura Mira
     - dotnet pack + Copy-Item del .nupkg al feed \\build01\...\PaquetesNuget (solo en tags v*)
     - version inmutable: si el .nupkg ya existe en la share, falla pidiendo subir <Version>
  5. Avisa del prerrequisito de infra: escritura NTFS del agente sobre la share del feed
     (pedir a Sistemas 1 vez, analogo al permiso Use de BUILDERS - TEC-003).
  6. R22 (gate seguridad) NO aplica: no hay deploy a IIS que bloquear.
```

### Patron C: Detectar drift y proponer fix masivo

```
Usuario: "revisa mi azure-pipelines.yml"

Claude (NO auto-invocar agent cicd-pipeline-reviewer):
  1. Lee azure-pipelines.yml
  2. Para cada step, contrasta contra R1-R25
  3. Lista violaciones con severidad y referencia a regla
  4. Para cambios masivos, sugiere: "Esto es trabajo del agent cicd-pipeline-reviewer
     que produce reporte estructurado. Quieres invocarlo?"
```

### Patron E: Self-check de completitud + sello de plantilla (h13)

```
Contexto: tras generar/re-renderizar azure-pipelines.yml (FASE 2 de /cicd-init, o su Opcion 4 de
edicion), hay que VERIFICAR que la salida contiene todos los steps canonicos del template.

Por que: en flujos copia+genera (TFS 2020 no permite 'extends' fiable, tabla B) un edit-mode parcial
puede dejar fuera steps nuevos del template sin que nadie lo note (incidente EWP v3.13.0-h12: faltaron
R18 Mira + reporte HTML CoverageReport + limpieza opencover). La defensa = verificar la salida.

Dos artefactos (h13 + v3.14.0-h1):
  1. SELLO de plantilla en la cabecera del YAML: '# Ovillo cicd-architect <stack> @ vX.Y.Z (tpl <hash12>) gen <fecha>'.
     /cicd-init FASE 2.8 rellena {{TEMPLATE_STAMP}}: version de _hilo/VERSION.json + hash de contenido del
     .yml.template del stack via Get-TemplateStamp.ps1 -Stack <stack> (ADR-047). /cicd-status §1.5 recomputa
     ese hash con el MISMO helper y compara -> drift REAL (el template del stack cambio), no cosmetico por
     bump de ecosistema. Sello antiguo 'zip <sha12>' (pre-v3.14.0-h1) -> re-render para migrar.
  2. SELF-CHECK determinista: templates/validate-pipeline-complete.ps1 -Yaml <yaml> -Template <template-del-stack>.
     Deriva los markers (displayName/ArtifactName/- template:) DEL PROPIO template (cero lista a mantener),
     ignora bloques '# CUSTOM:'. exit 0 = completo; exit 1 = faltan steps -> NO cerrar /cicd-init.
     -Allow "<substr>,..." exime bloques opcionales dropeados a proposito (sin tests / sin /health).
```

## Troubleshooting comun

Ver `references/troubleshooting-frecuente.md` para tabla completa de 30+ sintomas. Atajos:

| Sintoma | Refer |
|---|---|
| `The underlying connection was closed` | R2 — TLS 1.2+ bootstrap |
| `Unexpected value 'deploymentGroup'` | R1 — BUILDERS + capability |
| `One or more files locked` en MSDeploy | R10 — TakeAppOfflineFlag |
| Trigger no dispara tras push | R7 — doble patron `**` Y `**/*` |
| Smoke fail timeout / SNI | R9/R11 — bypass localhost o best-effort |
| Cache@2 falla en runtime | R5 — servicio no existe TFS 2020 |
| `unable to get local issuer certificate` | R3 — REST API + PowerShell |

## Anti-patrones (NO hacer)

- ❌ Recomendar `Cache@2`, `DownloadBuildArtifacts@0`, `IISWebAppDeployment@1`, `deploymentGroup:` — todas HARD 🔴 en TFS 2020
- ❌ Usar `https://localhost/...` callback `{$true}` GLOBAL (R9 solo aplica a smoke local)
- ❌ Recomendar `TakeAppOfflineFlag: true` para SPA (R10)
- ❌ Generar step PS sin bloque TLS 1.2+ inicial (R2)
- ❌ Generar pipeline Fase 2 sin verificar que existen agentes `<ENV>_DEPLOY` + grupo aprobadores (D1-D6 de pre-flight)
- ❌ Saltar la idempotencia FASE 0.5 al editar YAML pre-existente (R14)

## Sinergia con otros componentes

| Componente | Relacion |
|---|---|
| Comando `/cicd-init` | Orquesta el wizard completo. Auto-invoca esta skill al generar steps. |
| Comando `/cicd-status` | CLI local que consume tool MCP `get_cicd_status`. Skill no involucrada. |
| Agent `cicd-pipeline-reviewer` | Audit estructurado de YAML existente. La skill es interactiva/asistencial; el agent es batch/auditor. |
| `references/classic-migration.md` | Migración manual Classic (.xaml/.xoml) → YAML con side-by-side. Absorbe a la skill `cicd-classic-migrator` retirada (ADR-053). |
| Skill `hub-client` | Si `/cicd-init` invoca `register_pipeline` tool del Hub, esta skill puede consultarla. |
| Skill `issue-tracker-sync` | Boards/Wiki/work items. Ortogonal a pipelines runtime. |

## Referencias

- Reglas runtime: `.claude/rules/cicd-runtime.md` (G1-G14; G8 = gate de seguridad verdict-file)
- Limitaciones TFS 2020: `.claude/rules/tfs-2020-limitations.md` + `Documentos_Base/08_CICD/LIMITACIONES_TFS_2020.md`
- Guia fases: `Documentos_Base/08_CICD/GUIA_FASES_ADOPCION.md`
- Runbook Fase 2: `Documentos_Base/08_CICD/RUNBOOK_TEMPLATE.md`
- Runbook Fase 0: `Documentos_Base/08_CICD/RUNBOOK_DEPLOY_MANUAL.md`
- ADR: `_estado/DECISIONES.md` ADR-042 (constructor Ovillo)

---

*Skill condicional Ovillo v3.11.0 — Arquitecto CI/CD (variant azure-pipelines/server-2020).*
