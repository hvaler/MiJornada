# /cicd-init — Scaffolding de CI/CD para proyectos de la organización

> Genera `azure-pipelines.yml` y artefactos asociados para un proyecto siguiendo el patrón canónico del ecosistema: pool `BUILDERS` server-wide + capability `DeployTarget=<env>` por agente, contra Azure DevOps Server 2020 on-premise (`devops.example.org`).
>
> Audiencia: desarrolladores que arrancan CI/CD en un proyecto nuevo o migran de TFS Classic a YAML.

---

## 🧠 Extended Thinking Mode

**think hard**

Inferir del código fuente (path de `.csproj`, layout `03_Desarrollo/04_Pruebas/`, dependencias) tanto como sea posible antes de preguntar al desarrollador. Validar permisos y conectividad con TFS antes de generar nada. Respetar la fase de adopción elegida (Fase 0/1/2) — cada una genera artefactos distintos.

---

## REGLAS CRÍTICAS

- **Detectar TFS Classic ANTES de avanzar**: si hay `TfsBuild/*.xaml`, `*.xoml` o `BuildProcessTemplates/` → ABORTAR apuntando a la guía manual `skills/cicd-architect/references/classic-migration.md` (la skill cicd-classic-migrator se retiró en v3.18.0, ADR-053: la migración es manual guiada, con side-by-side).
- **Respetar los invariantes G1-G14** de `.claude/rules/cicd-runtime.md`. NUNCA emitir features 🔴 HARD listadas en `tfs-2020-limitations.md`.
- **Idempotencia obligatoria**: re-ejecutar en proyecto con instalación previa NO debe romper nada. FASE 0.5 detecta y bifurca.
- **No tocar el Hub MCP en Fase 0**: proyectos sin pipeline TFS no necesitan registro.
- **Backup automático** antes de cualquier escritura sobre `azure-pipelines.yml` pre-existente.

---

## STACKS SOPORTADOS

| Stack | Detección | Notas |
|---|---|---|
| **.NET ASP.NET Core** | `*.csproj` con `Microsoft.NET.Sdk.Web` | Default .NET 10 (no 8/9). Smoke estricto contra `/health/live`. `TakeAppOfflineFlag: true` (libera locks DLL). |
| **Vue 3 + Vite + TypeScript** | `package.json` con `"vue": "^3."` Y `"vite":` | Smoke best-effort (hairpin NAT R11). `TakeAppOfflineFlag: false`. |
| **.NET-tool / librería NuGet** (Variante C) | `*.csproj` con `<PackAsTool>true</PackAsTool>` o `<IsPackable>true</IsPackable>` y SIN proyecto web | Un solo stage BuildTestPublish. Publica `.nupkg` al feed `\\build01\...\PaquetesNuget` con tag `v*`. NO deploy IIS, NO gate R22. Validado en dotnet-reportgenerator-globaltool. |
| **.NET Framework clásico** (netfx, 4ª variante) | `*.csproj` con `<TargetFrameworkVersion>vX.X</TargetFrameworkVersion>` (MVC5/WebApi2, System.Web) + `packages.config` | MSBuild (NO `dotnet`): `NuGetCommand@2` + `VSBuild@1` (+ paquete MSDeploy) + `VSTest@2`. Templates `azure-pipelines.fase{1,2}.netfx.yml.template`. Requiere **VS Build Tools** en BUILD01 + `NuGet.config` con feed Stic. `TakeAppOfflineFlag: true`. Validado en MyCompany.WebCorporativa. |
| ❌ React / Angular / Java / otros | — | Rechazar con mensaje claro. Política mantiene hasta v3.13+ con caso real. |

---

## FASE 0 — Detección y pre-validaciones

### 0.1 Detección del stack (PRIMERO)

Algoritmo en orden estricto, **parar al primer match**:

```
1. ¿Existe package.json en 03_Desarrollo/ o raíz?
   Sí → leer dependencies + devDependencies
   ├─ Contiene "vue": "^3." Y "vite": → STACK = "Vue+Vite+TS"
   ├─ Contiene "react": → STACK = "React" (NO soportado, abortar)
   ├─ Contiene "@angular/core": → STACK = "Angular" (NO soportado, abortar)
   └─ Resto → STACK = "Node-otro" (NO soportado, abortar)

2. ¿Existe algún *.csproj?
   Sí → buscar SDK / formato
   ├─ Contiene Microsoft.NET.Sdk.Web → STACK = ".NET"
   ├─ Contiene <PackAsTool>true</PackAsTool> o <IsPackable>true</IsPackable>
   │  y NINGÚN .csproj con Microsoft.NET.Sdk.Web → STACK = ".NET-tool" (Variante C)
   ├─ Contiene <TargetFrameworkVersion>vX.X</TargetFrameworkVersion> (formato MSBuild clásico,
   │  NO SDK-style) Y/O hay packages.config junto a los .csproj → STACK = "netfx" (4ª variante)
   │  [antes abortaba; desde v3.12.0 soportado — ver templates fase{1,2}.netfx]
   └─ Otros SDKs → avisar y abortar (no soportado todavía)

3. Si no se detecta → STOP. Preguntar stack y rechazar.
```

### 0.1-bis Detección TFS Classic (ABORTAR)

Antes de avanzar:

```powershell
$tfsClassic = (Test-Path "**/TfsBuild/*.xaml") -or `
              (Test-Path "**/*.xoml") -or `
              (Test-Path "**/BuildProcessTemplates")

if ($tfsClassic) {
    Write-Host "❌ Detectado pipeline TFS Classic (.xaml/.xoml/BuildProcessTemplates)"
    Write-Host "   La migración Classic -> YAML es MANUAL GUIADA (con validación side-by-side):"
    Write-Host "   ver .claude/skills/cicd-architect/references/classic-migration.md (ADR-053)."
    Write-Host "   Si quieres mantener el pipeline Classic, NO ejecutes /cicd-init."
    exit 0
}
```

### 0.1-ter Una solución, N entrypoints (v3.15.0, ADR-048 / R25)

**Convención (desde v3.15.0): 1 repo = 1 solución.** Ya NO se elige entre varias soluciones (la lógica
multi-solución y el comando `/cicd-split` se retiraron). Si se detectan >1 `.sln`, **AVISAR** que la
convención es 1 solución por repo y continuar con la solución canónica (confirmar cuál si hay duda):

```powershell
$slns = Get-ChildItem -Recurse -Include *.sln,*.slnx -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\(bin|obj|node_modules|\.vs)\\' }
if ($slns.Count -gt 1) { Write-Warning "Convencion v3.15.0: 1 repo = 1 solucion. Detectadas $($slns.Count) -> usa la canonica." }
```

**Lo NUEVO — detectar los ENTRYPOINTS de la solución (R25)**: una solución puede tener varios proyectos
desplegables/ejecutables. **Se genera un pipeline (1 definición TFS) por cada entrypoint** según su tipo:

| Tipo | Detección | CI | CD | Routing (R25) → `DeployTarget` |
|---|---|---|---|---|
| **Web (UI)** | `Microsoft.NET.Sdk.Web` + Views/Pages/`wwwroot`/`*.razor`/`*.cshtml` (o MVC5 netfx con vistas) | sí | sí | **Aplicaciones** `<env>-app` (público por naturaleza) |
| **Web API** | `Microsoft.NET.Sdk.Web` SIN vistas (solo Controllers/Minimal API) (o WebApi2 netfx) | sí | sí | **Servicios** `<env>-svc` si privado (default) · **Aplicaciones** `<env>-app` si público |
| **Console / Worker** | `<OutputType>Exe</OutputType>` sin SDK.Web, o SDK `Microsoft.NET.Sdk.Worker` / `IHostedService`/`BackgroundService` | sí | **sí (v3.16.0, FB-B)** | **parametrizable** (no app/svc fijo): `DeployTarget` derivado del pool real (FB-002). CD por **Tarea Programada** (default) / Windows Service |

```powershell
# Proyectos de la solucion (excluir bin/obj). Libs y *.Tests NO son entrypoints
# (se compilan/testean dentro del Build de CADA pipeline, no se despliegan).
$projs = Get-ChildItem -Recurse -Include *.csproj | Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' }
foreach ($p in $projs) {
    $xml = Get-Content $p.FullName -Raw
    $isWeb   = $xml -match 'Microsoft\.NET\.Sdk\.Web' -or $xml -match 'WebApplication\.targets'
    $hasView = (Test-Path (Join-Path $p.Directory 'Views')) -or (Test-Path (Join-Path $p.Directory 'Pages')) -or
               (Test-Path (Join-Path $p.Directory 'wwwroot')) -or (Get-ChildItem $p.Directory -Recurse -Include *.razor,*.cshtml -EA SilentlyContinue | Select -First 1)
    $isExe   = $xml -match '<OutputType>\s*Exe\s*</OutputType>' -or $xml -match 'Microsoft\.NET\.Sdk\.Worker' -or $xml -match 'IHostedService|BackgroundService'
    $isTest  = $p.Name -match '\.Tests?\.' -or $xml -match 'IsPackable>\s*false' -or $xml -match 'Microsoft\.NET\.Test\.Sdk'
    # clasificar: Web(isWeb+hasView) | API(isWeb+!hasView) | Console(isExe+!isWeb) | (lib/test -> NO entrypoint)
}
```

La clasificación (tipo Web/API/Console por entrypoint) se **muestra y confirma** en P1, donde además se
pregunta **público** por cada Web/API (ver P3). El `trigger.paths` de cada pipeline se acota al subárbol del
entrypoint (FASE 2). **Cada entrypoint = su propio `DeployTarget`** derivado del tipo+público (Web→`app`, API→`svc`/`app`); **Console/Worker** no tiene tipo fijo → su demand se deriva del pool real (FB-002) y su CD es por **Tarea Programada** (FB-B, v3.16.0; ver P-console).

### 0.2 Detección de detalles del stack

**.NET (repetir por CADA entrypoint desplegable detectado en 0.1-ter → cada uno genera su pipeline):**
- TargetFramework del `.csproj` del entrypoint (`<TargetFramework>net10.0</TargetFramework>`)
- Path del `.csproj` del entrypoint (Web/API → `Microsoft.NET.Sdk.Web`; Console/Worker → Exe/Worker, CI-only)
- **Tipo + routing**: Web → `app` · API privada → `svc` · API pública → `app` (se confirma/pregunta en P1/P3) → `DeployTarget=<env>-<tipo>` + URL apps/svc del inventario (R1/R25)
- Path del `.csproj` Tests (sufijo `.Tests` o `IsPackable=false`). **El paso `dotnet test` del template apunta a `$(solutionPath)`, NO a un único `.Tests`** (FB-002 EWP: auto-descubre todos los proyectos de test presentes y futuros).
- **¿Hay AL MENOS un proyecto de test?** Si **NO** → al generar, ELIMINAR del template el step `dotnet test` + `Publish coverage` + el gate R18 (no hay cobertura que medir). Rama (a) del header del template.
- **¿Expone `/health`?** (grep `MapHealthChecks` / `AddHealthChecks` / `UseHealthChecks` en el proyecto API). Si **NO** → usar `steps/smoke-besteffort-spa.yml` (GET best-effort, no throw) en vez de `steps/smoke-strict-dotnet.yml` (que asume `/health/*` + 401). Rama (b) del header del template.
- Solution file `*.sln` / `*.slnx` (la solución canónica del repo — 1 repo = 1 solución, v3.15.0)
- **`nuget.config` del repo (FB-E, v3.15.0-h2)**: localizar el `nuget.config`/`NuGet.config` que cubre la solución (junto al `.sln`, en la raíz del repo, o en `03_Desarrollo/`). Si **existe** (feed interno de la organización/Stic) → `{{NUGET_CONFIG_PATH}}` = su ruta relativa, y el `dotnet restore` del template conserva `feedsToUse: 'config'` + `nugetConfigPath`. Si **NO** existe → ELIMINAR del template esas 2 líneas (restore default nuget.org). **Sin esto el restore ignora el feed interno y falla `NU1101` en cualquier proyecto con dependencias internas** (caso real ErpSync: `NU1101 MyCompany.Core.Seguridad`; el `DotNetCoreCLI@2 restore` por defecto solo mira nuget.org).

**netfx (.NET Framework clásico):**
- Solution `*.sln` → `{{SLN_PATH}}`. **Verificar que el header `Microsoft Visual Studio Solution File` está en la LÍNEA 1** (un comentario `# ...` delante rompe el parser MSBuild14 de nuget.exe → "No file format header found"; si lo hay, corregirlo conservando el BOM).
- Proyecto WEB (WAP: `Microsoft.WebApplication.targets` / `ProjectTypeGuids` web) → `{{WEB_PROJECT}}` (para el scan R22 y el paquete MSDeploy).
- Proyecto de tests (puede ser SDK-style `netXX` con `ProjectReference` a los clásicos). **Confirmar que TODOS los proyectos del .sln están commiteados** (si falta → `MSB3202` en CI).
- `TargetFrameworkVersion` (ej. `v4.8`). Pre-flight: **VS Build Tools en BUILD01** (msbuild + VSTest).
- Path del `NuGet.config` a generar con el feed interno 'Stic' → `{{NUGET_CONFIG_PATH}}` (ej. `<SRC_DIR>/NuGet.config`).

**Vue+Vite+TS:**
- Versión Node de `engines.node` / `.nvmrc` / asumir Node 22 LTS
- TypeScript: `devDependencies.typescript`
- Vite: `devDependencies.vite`
- ¿Vitest? `devDependencies.vitest`
- ¿Coverage? `devDependencies['@vitest/coverage-v8']`
- ¿Lint? `package.json.scripts.lint`
- Build outDir: `vite.config.ts → build.outDir` (default `dist`)

**.NET-tool / librería NuGet (Variante C):**
- Path del `.csproj` empaquetable (`<PackAsTool>` o `<IsPackable>true</IsPackable>`)
- `<PackageId>` y `<Version>` (versiones NuGet inmutables: si ya existe en el feed, subir `<Version>` y re-taggear)
- Output dir del `.nupkg` (`<PackageOutputPath>` o `bin/$(buildConfiguration)`)
- ¿Dogfooding? (si el propio proyecto ES la herramienta Mira → correr desde fuente con `dotnet run --no-build`; si no, instalar/actualizar la tool global desde el feed)
- Prerrequisito de infra: escritura NTFS del agente sobre `\\build01\Repositorio\MyOrg\PaquetesNuget` (pedir a Sistemas 1 vez, análogo al permiso Use de BUILDERS — TEC-003)
- Template: `skills/cicd-architect/templates/azure-pipelines.nettool.yml.template`. UN solo stage, trigger `v*` publica. NO genera stages de deploy ni gate R22.
- **NUNCA empaquetar con el task `DotNetCoreCLI@2` `command: 'pack'`** (ignora `<PackageOutputPath>`, build #65) — usar `dotnet pack` por PowerShell con guarda de inmutabilidad. Ver Tabla A de `tfs-2020-limitations.md`.

### 0.3 NUEVO Ovillo — Lectura ESTADO_PROYECTO.json

Pre-poblar defaults desde `_hilo/ESTADO_PROYECTO.json` si existe:

```powershell
$estado = Get-Content "_hilo/ESTADO_PROYECTO.json" -Raw | ConvertFrom-Json

$defaults = @{
    proyectoName = $estado.proyecto.nombre
    repositorioUrl = $estado.proyecto.repositorio
    ramaBase = $estado.configuracion.branching.ramaBase   # default "main"
    branchingEstrategia = $estado.configuracion.branching.estrategia
    equipo = $estado.equipo.miembros | ForEach-Object { $_.email }
    aprobadoresPro = $estado.infraestructura.aprobadores.Pro
}
```

Si no existe: fallback al wizard del pack tal cual. Usar valores `[NOMBRE_PROYECTO]` como pistas para preguntar.

### 0.3-bis NUEVO v3.13.0 — Scan de secretos preexistentes (brownfield, GI#6)

Antes de proponer el gate R22, detectar si el proyecto YA tiene secretos versionados (brownfield) — mismo criterio que el check 2 de `skills/cicd-architect/templates/security-scan.ps1`:

- Grep sobre `appsettings*.json` + `*.config` **commiteados**: valores con pinta de credencial (`Password=`, `pwd=`, claves API, connection strings con credenciales).
- **Ignorar placeholders**: `<...>`, `CHANGEME`, `$(...)`, `%...%`, valores vacíos.

**Si hay hallazgos** (caso típico en proyectos legacy, política de la organización WARN-first — ver CLAUDE_BASE §7):

```
⚠️  Secretos preexistentes detectados en config versionada (N archivos).
    Esto es deuda técnica CONOCIDA en la organización (migración progresiva a Key Vault / VG).

    El gate de seguridad R22 se configurará en modo WARN también para PRE/PROD
    (en vez del default BLOCK), para NO bloquear los primeros deploys del pipeline
    por deuda que ya existía antes del CI/CD.

    PLAN: (1) registrar SEC-XXX en _hilo/DEUDA_TECNICA.md (se hace ahora),
          (2) migrar secretos al Variable Group (R16) / transforms (R23),
          (3) cuando el config base quede limpio → subir R22 a BLOCK
              (editar mode: block en steps/security-verdict-gate.yml de PRE/PROD).
```

- Generar el YAML con `security-verdict-gate.yml` en `mode: warn` **también en PRE/PROD** (default brownfield). El usuario puede forzar BLOCK si lo prefiere (confirmar que asume builds rojos hasta limpiar).
- Registrar (o recordar registrar) la entrada `SEC-XXX: secretos en config versionada` en `_hilo/DEUDA_TECNICA.md` con los archivos detectados.
- Documentar la decisión y el plan de subida a BLOCK en `05_CICD/SEGURIDAD_PIPELINE.md`.

**Si NO hay hallazgos** (greenfield/limpio): mantener el default del pack — `mode: warn` en DEV, `mode: block` en PRE/PROD (R22).

### 0.4 Pre-flight bloqueante (validar contra TFS)

> ⚠️ **Solo si la Fase elegida en P0 será ≥ 1**. Para Fase 0 esta validación se salta.

**A — REPOSITORIO**:
| Check | Acción si falla |
|---|---|
| A1: Repo en `devops.example.org` | STOP — no aplica este comando |
| A2: Rama por defecto detectable (`git symbolic-ref refs/remotes/origin/HEAD`) | Adaptar trigger al nombre real |
| A3: Estructura Ovillo (`03_Desarrollo/` existe) | Avisar; permitir continuar con paths custom |
| A4: NO existe `azure-pipelines.yml` previo | FASE 0.5 (modo edición) si existe |

**B — USUARIO**:
| Check | Acción si falla |
|---|---|
| B1: Usuario reconocido por TFS (`/_apis/connectionData` 200) | Renovar credenciales Windows |
| B2: Acceso lectura al proyecto TFS | Escalar a Sistemas |
| B3: Acceso lectura pool BUILDERS | Avisar (no bloquea generar YAML) |

**C — INFRAESTRUCTURA TFS** (server-side, requiere Sistemas):
| Check | Acción si falla |
|---|---|
| C1: Pool BUILDERS existe en `/_apis/distributedtask/pools` | Escalar a Sistemas: crear pool one-time |
| C2: BUILDERS visible al proyecto (`<proj>/_apis/distributedtask/queues` con `pool.name=BUILDERS`) | Sistemas autoriza pool **al GRUPO del proyecto** (no a un usuario individual — ver nota permiso `Use` en FASE 2.5) |
| C3: Agentes Build online (al menos uno con `Agent.ComputerName=BUILD01`) | Sistemas revisa o instala agente |
| C4a: Permiso `Use` del USUARIO sobre BUILDERS (para registrar/encolar) | Sistemas concede rol User al GRUPO del proyecto. (PATCH `pipelinePermissions` da 401 si no eres pool admin.) |
| C4b: Autorización de la CANALIZACIÓN al recurso pool | **NO verificable pre-registro vía API.** Se detecta tras el primer build (FASE 2.5/3): si queda en `notStarted` con `Checkpoint.Authorization` inProgress → banner "Permit" o "grant access to all pipelines" (pool admin). TEC-003 — `Use` del usuario ≠ autorización de la canalización. |

**D — ENTORNOS** (solo si Fase = 2):
| Check | Acción si falla |
|---|---|
| D1: Agente `<SERVER>_DEPLOY` registrado en BUILDERS | Sistemas instala agente |
| D2: Agente online | Sistemas reinicia o coordina |
| D3: Capability `DeployTarget` en los agentes de deploy | Sistemas la configura (objetivo `<env>-<app\|svc>`). `/cicd-init` LEE el valor REAL del pool y deriva los demands — NO asume el esquema (FB-002). |
| D4: Grupo TFS aprobadores existe (solo PROD) | Usuario crea grupo via TFS UI |
| D5: Grupo tiene ≥2 miembros | Añadir miembros via TFS UI |
| D6: Environment con approval check configurado | Usuario crea environment |

**E — PROYECTO (stack Vue+Vite+TS)**:
| Check | Acción si falla |
|---|---|
| E1: `package-lock.json` commiteado | `npm install` + commitear lockfile |
| E2: Script `build` definido en `package.json` | Wizard preguntará comando |
| E3: `@vitest/coverage-v8` instalado | `npm i -D @vitest/coverage-v8` (sin él no hay gate) |
| E4: ESLint configurado | Sin esto, el step lint se omite |

**Mostrar siempre el reporte completo** (incluso si pasa todo) antes del wizard.

**Bloqueadores duros** (A1, B1, B2, C1, C2, C3): STOP, devuelve error accionable.
**Bloqueadores suaves** (resto): warning + permitir continuar si el usuario confirma.

### 0.5 Idempotencia — Detección de instalación previa

Si **existe** alguno de:
- `azure-pipelines.yml` en raíz del repo
- Entrada en `_hilo/ESTADO_PROYECTO.json.infraestructura.cicd[]` con `pipelineId` no null
- Pipeline registrado en TFS con nombre matching `<proyecto>` o `<repo>`

→ activar **modo edición** con 5 opciones:

```
═══════════════════════════════════════════════════════════════════════
                INSTALACIÓN PREVIA DETECTADA
═══════════════════════════════════════════════════════════════════════
  ✓ azure-pipelines.yml (X líneas)
  ✓ Pipeline TFS '<NOMBRE>' (id=<id>)
  ✓ Fase actual: <0|1|2>

  ¿Qué hacer?
  1. Añadir nuevo stage (ej. promoción de Fase 1 → Fase 2 añadiendo CD)
  2. Modificar stage existente (approvals, capability, secrets...)
  3. Regenerar SOLO docs `05_CICD/` (YAML intacto)
  4. Actualizar YAML completo a última plantilla (preserva CUSTOM)
  5. Salir sin cambios

  Elección [1-5]:
═══════════════════════════════════════════════════════════════════════
```

> **🔴 PASO PREVIO del modo edición — reconciliar entrypoints (FB-A-bis, v3.15.0-h2).** ANTES de mostrar
> las 5 opciones, re-ejecutar la **detección 0.1-ter** (enumerar TODOS los entrypoints de la solución) y
> **reconciliar `_hilo/ESTADO_PROYECTO.json.infraestructura.cicd.pipelines[]`**: por cada entrypoint
> detectado que **NO** esté ya en `cicd[]`, añadir su entrada (`{ entrypoint, tipo, publico, serverType,
> slug, fase: 0, modeloDeploy: "pending" }`; preguntar **público** por cada Web/API nuevo, como en P1-bis).
> **NUNCA dejar `cicd[]` con menos entradas que entrypoints detectados.** El modo edición se saltaba P1-bis,
> así que un proyecto que corrió Fase 1 con el modelo viejo (single-entrypoint) se quedaba con Web/API
> **perdidos indefinidamente** aunque re-ejecutara `/cicd-init`. La promoción Fase 1→Fase 2 (Opción 1) lee
> estas entradas para generar los pipelines CD que faltan. Validado: piloto ErpSync (3 entrypoints, el re-run
> dejaba 1 sola entrada Console).

**Antes de cualquier escritura**: backup automático con `azure-pipelines.yml.bak.YYYYMMDD-HHmmss`.

**Marcadores CUSTOM** preservados literalmente:
```yaml
          # CUSTOM: descripción
          - task: PowerShell@2
            displayName: 'Step manual del dev'
            ...
          # /CUSTOM
```

Bloques entre `# CUSTOM:` y `# /CUSTOM` NUNCA se regeneran.

#### Opción 4 — "Actualizar YAML completo a última plantilla" = re-render COMPLETO (NO patch)

Esta opción **re-renderiza el `azure-pipelines.yml` ENTERO** desde el `*.yml.template` del stack
(igual que una instalación nueva), **NO** aplica un parche línea-a-línea sobre el YAML existente.

> **Anti-patrón explícito (origen del incidente)**: en el rollout de v3.13.0-h12 (Mira 0.10.2) al
> consumidor EWP, la Opción 4 se resolvió con un **edit quirúrgico de 1 línea** y se cerró el flujo
> como completo. Faltaban el step R18 (Mira siempre-última), los 2 steps del reporte HTML
> `CoverageReport` y la limpieza `*opencover.xml`. "Editar 1 línea y cerrar" cuando el template
> trae steps nuevos es exactamente lo que h13 previene.

Procedimiento obligatorio:
1. **Backup** `azure-pipelines.yml.bak.YYYYMMDD-HHmmss` (ya descrito arriba).
2. **Re-renderizar el template COMPLETO** del stack (FASE 2) con los placeholders del proyecto
   (leídos de la instalación previa: `ESTADO_PROYECTO.json` + el YAML viejo) — no parchear el viejo.
3. **Re-aplicar SOLO** los bloques `# CUSTOM:` ... `# /CUSTOM` del YAML viejo.
   - **Filtro de tests** (`{{TEST_FILTER}}`, stack .NET): NO es un bloque CUSTOM. Leer `cicd[].testFilter`
     de `ESTADO_PROYECTO.json`; si no existe, **detectar el `--filter "..."` del `dotnet test` del YAML viejo**
     y re-aplicarlo al placeholder. Así la exclusión del equipo (ej. integración sin Docker) **sobrevive sola**.
4. **Mostrar el diff** (viejo vs nuevo) y pedir confirmación.
5. **Self-check obligatorio (FASE 2.8)**: correr `validate-pipeline-complete.ps1`. Si sale rojo
   (exit 1), **NO cerrar** `/cicd-init` — falta algún step del template; volver al paso 2.

> El comando **NO puede darse por terminado con el self-check en rojo** (salvo que los markers
> ausentes correspondan a bloques opcionales legítimamente dropeados — ver FASE 2.8 `-Allow`).

---

## FASE 1 — Wizard interactivo

### P0 NUEVO Ovillo — Nivel de adopción CI/CD

```
¿Qué nivel de CI/CD quieres para este proyecto?

  [0] Fase 0 — Solo Ovillo local (cero infra TFS)
      Genera: RUNBOOK_DEPLOY_MANUAL.md adaptado + recordatorios /verify pre-push
      NO genera: azure-pipelines.yml
      Útil para: proyectos pequeños, sin Sistemas autorizando BUILDERS aún

  [1] Fase 1 — Build validation branch policy
      Genera: azure-pipelines.yml minimal (build + test + publish), gate de PR
      NO genera: stages CD (deploy DEV/DEMO/PROD)
      Requiere: agente BUILD01 online + BUILDERS autorizado al proyecto

  [2] Fase 2 — Pipeline completo CD
      Genera: pipeline canónico con 25 reglas, triple rollback, VG, retention, runbook
      Requiere: agentes <ENV>_DEPLOY + grupo aprobadores (≥2 para PROD)

  (Ver Documentos_Base/08_CICD/GUIA_FASES_ADOPCION.md para detalle)

Elección [0-2]:
```

Guardar elección en `$FASE`. Las preguntas siguientes (P1-P6) dependen de `$FASE`.

### P1. Confirmación proyecto detectado

**Si STACK = ".NET":**
```
Proyecto detectado:
  Stack:            .NET ASP.NET Core
  Nombre:           <PROYECTO_NOMBRE>
  Rama base:        <RAMA_BASE>
  .csproj API:      <API_CSPROJ_PATH>
  .csproj Tests:    <TESTS_CSPROJ_PATH>
  Solution:         <SLN_PATH>
  TargetFramework:  <NET_VERSION>   (default sugerido: net10.0)
  Fase adopción:    <FASE>

¿Correcto? (S/N)
```

**Si STACK = "Vue+Vite+TS":**
```
Proyecto detectado:
  Stack:            Vue 3 + Vite + TypeScript
  Nombre:           <PROYECTO_NOMBRE>
  package.json:     <PATH>
  Node.js:          <NODE_VERSION>
  TypeScript:       <TS_VERSION> · Vite: <VITE_VERSION>
  Vitest:           <VITEST_VERSION o "sin tests">
  Coverage:         <coverage-v8 detectado / no detectado>
  Lint:             <eslint detectado / no detectado>
  Build outDir:     <BUILD_OUTDIR>
  Fase adopción:    <FASE>

¿Correcto? (S/N)
```

### P1-bis. Entrypoints + público (R25, Fase ≥ 1)

Mostrar los entrypoints clasificados (0.1-ter) para confirmar tipo y, por cada Web/API, **preguntar público**:

```
Entrypoints detectados en la solución:
  [1] MyCompany.X.Web      → Web (UI)        → CD a Aplicaciones
  [2] MyCompany.X.Api      → Web API         → ¿accesible desde el exterior (público)? [s/N]
  [3] MyCompany.X.Worker   → Console/Worker  → CD por Tarea Programada (FB-B) — datos en P-console

¿Correcta la clasificación? (puedes reasignar Web↔API). Por cada Web/API responde público [s/N] (default N = privado). Por cada Console/Worker se preguntan los datos de la tarea en **P-console**.
```

- **Web** → siempre `app` (Aplicaciones, público por naturaleza). **API**: privado (default) → `svc`; público → `app`. **Console/Worker** → CD por **Tarea Programada** (FB-B, v3.16.0); sin tipo fijo de servidor → `DeployTarget` derivado del pool real (FB-002), datos de la tarea (schedule/cuenta/carpeta/exe) en **P-console**.
- `serverType` (app|svc) determina las URLs `{{DEV_URL}}`/`{{DEMO_URL}}`/`{{PROD_URL}}` (apps vs svc del inventario R1) y es la **pista** para el mapeo, pero el valor del demand `{{DEPLOY_DEMAND_DEV/PRE/PRO}}` se **deriva de la capability REAL del pool** (FB-002, ver P3); los nodos PROD `{{PROD_NODE_A/B}}` se rellenan con los `Agent.Name` reales (pueden ser 1 solo, ej. APP03).

> **🔴 PERSISTIR TODOS los entrypoints AQUÍ (no en FASE 4) — FB-A v3.15.0-h1.** En cuanto se confirma la
> clasificación, escribir en `_hilo/ESTADO_PROYECTO.json.infraestructura.cicd.pipelines[]` **una entrada por
> CADA entrypoint detectado** (`{ entrypoint, tipo:(web|api|console), publico:bool, serverType:(app|svc), slug,
> fase, modeloDeploy }`) — **aunque esta ejecución sea Fase 1**. FASE 4 luego hace **UPSERT** (rellena
> `pipelineId`/`url`) sin borrar las entradas que aún no tienen pipeline. Esto evita el bug del piloto ErpSync,
> donde una solución de 3 entrypoints quedó con **una sola** entrada (la Console) y se perdieron Web+API.

> **🟡 Fase 1 vs Fase 2 — qué pipelines se generan (FB-D).** Aclarar SIEMPRE al usuario:
> - **Fase 1 (build validation)** genera **UN único `azure-pipelines.yml`** que compila/testea la **solución
>   completa** (CI-only, sin CD). **NO** genera un pipeline por entrypoint. Los entrypoints **desplegables**
>   (Web/API/Console) se persisten con `fase: 0` + `modeloDeploy: "pending"` (detectados, CD pendiente de Fase 2).
> - **Fase 2 (CD)** es donde se genera **un pipeline por entrypoint desplegable** (Web→`app`, API→`svc`/`app`,
>   **Console/Worker→Tarea Programada**, FB-B). Al promover de Fase 1→Fase 2 (modo edición opción 1), el comando lee los
>   entrypoints ya persistidos y genera los pipelines CD que faltan.
>
> No anunciar "1 pipeline por entrypoint" sin decir que eso es **Fase 2**: en Fase 1 es 1 pipeline de solución.

### P-console. Datos de despliegue Console/Worker (R25/FB-B, SOLO Fase 2 + entrypoint Console)

Por CADA entrypoint Console/Worker, preguntar y persistir en su entrada `cicd[]`:

| Dato | Pregunta | Default |
|---|---|---|
| `mecanismo` | ¿**Tarea Programada** (sync periódico) o **Windows Service** (always-on)? | **`tarea-programada`** (recomendado; v3.16.0 ship solo trae el step de tarea programada) |
| `taskName` | Nombre de la tarea programada | `<PROYECTO>.<slug>` (ej. `MyCompany.ErpSync.Sync`) |
| `taskScheduleArgs` | Frecuencia (args de `schtasks`) | preguntar: cada N horas `/SC HOURLY /MO N`, diaria `/SC DAILY /ST hh:mm`, al inicio `/SC ONSTART`, etc. |
| `taskRunAccount` | Cuenta de ejecución | `NT AUTHORITY\SYSTEM` (R6) |
| `deployFolder` | Carpeta destino en el servidor | `D:\Apps\<PROYECTO>` (preguntar; ojo unidad real del host) |
| `consoleExe` | Nombre del exe publicado | derivar del `.csproj` (`<AssemblyName>` o nombre del proyecto + `.exe`) |

El **destino** (`DeployTarget`) se **deriva del pool real** (FB-002, igual que P3 para app/svc): consultar `/_apis/distributedtask/pools/{id}/agents?includeCapabilities=true`, listar los valores `DeployTarget` reales y mapear DEV/PRE/PRO a uno (con confirmación) → rellena `{{CONSOLE_DEPLOY_DEMAND_DEV/PRE}}` y `{{PROD_NODE_A}}`. **Console/Worker NO tiene tipo fijo** de servidor (ni `app` ni `svc`): el host puede ser un servidor de servicios, un batch dedicado o —provisional— la máquina del dev; usar el valor que reporte el agente del host destino. Persistir `serverType: "batch"` para distinguirlo en `cicd[]`/dashboard.

> **Windows Service (always-on)**: el ship v3.16.0 trae solo el step de **Tarea Programada**. Si el equipo pide un worker always-on, avisar que la variante `steps/deploy-windows-service.yml` (`sc stop/start`) está **pendiente** — no bloquea (la mayoría de Console son sync periódico). Mientras tanto, un IHostedService periódico también encaja en tarea programada (arranca, procesa, termina).

FASE 2 inyecta estos datos en `azure-pipelines.fase2.console.yml.template` (placeholders `{{TASK_NAME}}`, `{{TASK_SCHEDULE_ARGS}}`, `{{TASK_RUN_ACCOUNT}}`, `{{DEPLOY_FOLDER}}`, `{{CONSOLE_EXE}}`, `{{CONSOLE_CSPROJ}}`, `{{CONSOLE_DEPLOY_DEMAND_*}}`).

### P2. Entornos — SOLO si Fase ≥ 1

Para Fase 0 saltar a P5/P6 (solo descripción + confirmación).

```
¿Qué entornos quieres en el pipeline?
  [ ] DEV      auto, build validation only en Fase 1, deploy auto en Fase 2
  [ ] DEMO     deploy on-demand (DeployEnv=pre) + smoke test  [solo Fase 2; SIN ManualValidation salvo modelo 'auto']
  [ ] PROD     Environment + group approval, 2 servers rolling [solo Fase 2]

(Marca S/N cada uno. Para Fase 1 solo aplica DEV.)
```

### P2-bis. Modelo de deploy — SOLO Fase 2

**Default inteligente**: leer `configuracion.branching.estrategia` de `_hilo/ESTADO_PROYECTO.json` ANTES de preguntar. Si la estrategia tiene **ramas por entorno** (`gitlab-flow`, `gitflow`) → recomendar **[3] branch-gated** (R24). Resto → recomendar **[1] on-demand** (R20).

```
¿Cómo se disparan los deploys?
  [1] On-demand (R20) — el push solo CONSTRUYE; el deploy a cada entorno se
      lanza con /cicd-deploy --env <dev|pre|pro>. Ningún entorno se despliega
      automáticamente en push. Para estrategias de UNA rama de integración.
  [2] Auto/promoción — DEV se despliega automático en cada push; PRE/PROD con
      aprobación manual. CD continuo a DEV.
  [3] Branch-gated (R24) — on-demand + gate por rama origen: Dev/Demo solo
      aceptan builds de <ramaDevelop> y PROD solo de <ramaBase>. Para
      estrategias con ramas por entorno (gitlab-flow, gitflow).

Selecciona (1-3, default según branching.estrategia):
```

- **Opción 1 (on-demand)** — genera el YAML con la variable `DeployEnv` (vacía por defecto) y `condition: and(succeeded(), eq(variables['DeployEnv'], '<env>'))` en cada stage de deploy. Es el patrón por defecto de los templates `azure-pipelines.fase2.*.yml.template`. **DEMO/Pre va DIRECTO (FB-F, v3.15.0-h3): el `DeployEnv=='pre'` + `/cicd-deploy --env pre` ES la aprobación explícita → los templates NO llevan `ManualValidation@0` en DEMO.** Solo **PROD** conserva su gate (`ManualValidation@0` + Environment/group approval) como gobierno.
- **Opción 2 (auto)** — `DeployDev` con `condition: succeeded()` (sin `DeployEnv`), `DeployProd` encadenado (`dependsOn: DeployDemo`). Ver el bloque final del template para los ajustes exactos.
- **Opción 3 (branch-gated, R24)** — como on-demand pero cada `condition` añade `eq(variables['Build.SourceBranch'], 'refs/heads/<rama>')` según el mapeo entorno→rama de R24 (Dev/Demo←`ramaDevelop`, PROD←`ramaBase`; derivar de `configuracion.branching`, NUNCA hardcodear `main`). El `trigger.branches.include` lleva AMBAS ramas (R21 + doble patrón R7 en paths). Para **netfx** usar la variante `azure-pipelines.fase2.netfx.branch-gated.yml.template` (3 `VSBuild@1` condicionales por rama → `drop-dev`/`drop-pre`/`drop-pro`, R23 híbrido). Mostrar el mapeo entorno→rama en el diff P3 y confirmar. Origen: GI#1+GI#2 (ADR-044).

Guardar en `$DEPLOY_MODE` (`on-demand` | `auto` | `branch-gated`). Afecta a FASE 2 (generación del YAML) y FASE 2.5 (declarar `DeployEnv` como queue-time variable si `on-demand`/`branch-gated`).

### P3. Checklist consolidado — defaults inferibles

**Regla**: NO preguntar valor por valor. Calcular TODOS los defaults del contexto (memorias del ecosistema, ESTADO_PROYECTO.json, package.json, repo name, git config) y mostrar UNA pantalla con todo. El usuario confirma o modifica selectivamente.

**Fuentes de inferencia** (extracto):

| Valor | Default |
|---|---|
| Entrypoints (R25) | Detectados en 0.1-ter: **1 pipeline por** Web/API (CD) y por Console (CI-only). Naming: 1 entrypoint → `azure-pipelines.yml` + def `<PROYECTO>`; >1 → `azure-pipelines.<slug>.yml` + def `<PROYECTO>-<slug>` |
| Routing / público (R25) | Web→`app` · API privada (default)→`svc` · API pública→`app`. `/cicd-init` pregunta **público** por cada Web/API (P3) y persiste en `cicd[].publico` |
| Servidores por entorno×tipo (R1) | **apps**: DEV `dev.example.org`/dev01 · PRE `pre.example.org` · PROD APP01/02 (`intranet`). **svc**: DEV `dev-svc.example.org`/svc01 · PRE `pre-svc.example.org` · PROD SVCNODE01[/02 off] (`serviciosweb`) |
| Demands de deploy (FB-002) | **Derivar del pool REAL**: leer `DeployTarget` de los agentes (`/_apis/distributedtask/pools/{id}/agents?includeCapabilities=true`, ya consultado en pre-flight), mostrar los valores distintos y mapear cada entorno×serverType a uno (default heurístico: el que contenga `dev`/`demo`/`pro`; **confirmar**) → `{{DEPLOY_DEMAND_DEV/PRE/PRO}}`. PROD por `Agent.Name` real (`{{PROD_NODE_A/B}}`; puede ser 1 nodo, ej. APP03). **NUNCA hardcodear `<env>-<app\|svc>`** (build en `notStarted` si ningún agente matchea). Valores reales 2026-06-23: `dev`/`demowww`/`demows`/`produccion`. |
| IIS WebSiteName | `Default Web Site` |
| IIS VirtualApplication | Repo en kebab-case sin tildes |
| IIS PhysicalPath (`{{IIS_PHYSICAL_PATH}}`) | **vacío** = `C:\inetpub\wwwroot\<IIS_VirtualApp>`. Rellenar SOLO si la vApp NO cuelga de wwwroot (ej. EWP: `C:\inetpub\wwwroot\MyApp.api\miapp`). Lo consumen `backup-pre-deploy.yml` + `rollback-on-fail.yml` (R15) |
| URL pública smoke | apps→`https://<devwww\|demowww\|intranet>/<vApp>/` · svc→`https://<devws\|demows\|serviciosweb>/<vApp>/` (según tipo del entrypoint; rellena `{{DEV_URL}}`/`{{DEMO_URL}}`/`{{PROD_URL}}`). .NET smoke=localhost; SPA/netfx best-effort=esta URL |
| Modelo deploy (P2-bis) | `on-demand` (R20), `auto` o `branch-gated` (R24 si `branching.estrategia` ∈ {gitlab-flow, gitflow}) |
| Tipo gate — on-demand / branch-gated | DEV/PRE/PROD se activan por `DeployEnv` (`/cicd-deploy`) — **eso ES el gate**. **DEV y PRE/Demo van DIRECTO, SIN `ManualValidation@0`** (FB-F, v3.15.0-h3); solo PROD añade `ManualValidation@0` + `Environment + group approval` |
| Tipo gate — auto | DEV=auto en push, DEMO=`ManualValidation@0` (sí gatea: se despliega en push), PROD=`Environment + group approval`. Si el usuario elige 'auto', re-añadir el job `WaitForApproval` en el stage DeployDemo del template (snippet comentado en el propio YAML) |
| Tipo gate — branch-gated | como on-demand + `Build.SourceBranch`: DEV/PRE←`ramaDevelop`, PROD←`ramaBase` (mapeo R24, mostrar en diff) |
| Approver email | `git config user.email` del usuario actual |
| Smoke scope | .NET: 6 endpoints `/health/*` + 401 protegidos. SPA: GET raíz best-effort |
| `TakeAppOfflineFlag` | `.NET in-process: true`, `SPA estática: false` (R10) |
| Coverage gate | line ≥70%, branch ≥60% via `mira summary` (R18) |
| Trigger branches (R21) | rama base = `git symbolic-ref refs/remotes/origin/HEAD`; ramas extra derivadas de `branching.estrategia` (push-directo→solo base; gitflow→+`develop`; release-flow/oneflow→+`release/*`; gitlab-flow→+entornos). Expandir el marcador `{{TRIGGER_BRANCHES_EXTRA}}` del template |
| Branch policy build-validation (R21) | push-directo (github-flow-simplificado/trunk-based/developer-branch)→**NO** (bloquearía push directo); con-PR→**recomendar** (gobierno, NO la aplica /cicd-init) |
| Pool + demands | BUILDERS + `Agent.ComputerName=BUILD01` (Build) / `DeployTarget=<valor REAL del pool>` (Deploy, FB-002; PROD por `Agent.Name` real) |

**Output del checklist** (formato consolidado, varía por Fase):

```
═══════════════════════════════════════════════════════════════════════
       CONFIGURACIÓN — REVISA Y CONFIRMA  (Fase <X>)
═══════════════════════════════════════════════════════════════════════

─── COMUNES ─────────────────────────────────────────────────────────
   1. Trigger branch:        <RAMA>
   2. Pipeline name:          <NOMBRE>

─── BUILD ────────────────────────────────────────────────────────────
   3. Pool + demand:          BUILDERS + Agent.ComputerName=BUILD01
   4. TargetFramework:        .NET 10 (.NET) / Node 22 LTS (Vue)
   5. Tests:                  <dotnet test / vitest run --coverage>
   6. Coverage gate:          line 70% / branch 60% (mira summary)
   7. Anti-patterns linter:   warning-only

─── DEV ──────────────────────────────────────────────────────────────  [solo Fase ≥ 1]
   8. Server:                 dev.example.org
   9. Agente:                 DEVWWW_DEPLOY  [solo Fase 2]
  10. IIS VirtualApp:         <REPO_KEBAB>
  10b. IIS PhysicalPath:      <vacio = wwwroot\VirtualApp>  [rellenar si la vApp no cuelga de wwwroot]
  11. Smoke scope:            <auto según stack>

─── DEMO ─────────────────────────────────────────────────────────────  [solo Fase 2]
  12. Server:                 pre.example.org
  13. Agente:                 DEMOWWW_DEPLOY
  14. Approver:               <git config user.email>
  15. Smoke scope:            <auto según stack>

─── PROD ─────────────────────────────────────────────────────────────  [solo Fase 2 + opt-in]
  16. Servers:                strify01 + strify02 (rolling)
  17. Grupo aprobadores:      <Proyecto>-Approvers-Prod (≥2 miembros)
  18. Backup pre-deploy:      D:\Backups\<APP>\ (triple rollback R15)
  19. Variable Group:         <PIPELINE_NAME>-secrets (R16)

═══════════════════════════════════════════════════════════════════════

Respuestas válidas:
  > S                                  Acepta todos
  > N                                  Modo sequential (raro)
  > "cambia 10 a guia-cicd"            Modificar valor
  > "VirtualApp guia-cicd, approver pp@example.com"   Múltiples cambios
═══════════════════════════════════════════════════════════════════════
```

Reglas de interpretación: si el usuario indica cambios en lenguaje natural, parsear, aplicar, re-mostrar y confirmar. Repetir hasta "S".

### P4. Variable Groups / secretos — SOLO Fase 2

```
¿El pipeline necesita acceder a secretos (API keys, connection strings,
 tokens, Oracle BIPublisher, AzureAd ClientSecret)?

  1. Sí — crear Variable Group ahora vía API
  2. Sí — Variable Group ya existe en TFS
  3. No — sin secretos
  4. Decidir después

Elección [1-4]:
```

Si caso 1: pedir lista de nombres (sin valores; el dev rellena en UI), POST a `/_apis/distributedtask/variablegroups` con todos los secretos `isSecret: true`. Mostrar URL del VG creado + recordatorio de rellenar valores.

Si caso 2: validar VG existe vía API. Si no, ofrecer crear (caso 1).

Si caso 3: continuar sin sección `variables.group`.

Si caso 4: ⚠️ `azure-pipelines.yml` se generará sin VG. Para añadir luego, re-ejecutar `/cicd-init` modo edición opción 2.

**Inyección al YAML** (casos 1 y 2):
```yaml
variables:
  - group: <PIPELINE_NAME>-secrets
  - name: BuildConfiguration
    value: 'Release'
```

**Step fail-fast pre-build** (R16):
```yaml
- task: PowerShell@2
  displayName: 'Fail-fast: validar secretos VG'
  inputs:
    targetType: inline
    script: |
      # [bloque TLS R2]
      $required = @('<NombreSecreto1>', '<NombreSecreto2>')
      $missing = $required | Where-Object { [string]::IsNullOrWhiteSpace((Get-Item "env:$_" -EA SilentlyContinue).Value) }
      if ($missing.Count -gt 0) {
        Write-Error "Secretos vacíos: $($missing -join ', '). Rellenar en VG '<PIPELINE_NAME>-secrets'."
        exit 1
      }
```

### P4-bis. Config por entorno (.NET SDK-style) — SOLO Fase 2 con CD (FB-001 / R23)

> Solo para stacks **.NET SDK-style** (`appsettings.json`) con CD a >1 entorno (netfx usa transforms, R23). Evita que el MSDeploy (`RemoveAdditionalFilesFlag: true`) **machaque el `appsettings.json` del servidor** con los placeholders del paquete (incidente real ErpSync).

```
¿Cómo gestiona la app la config/secretos POR ENTORNO?
  1. Azure Key Vault (la app usa AddAzureKeyVault + Managed Identity) — el deploy NO inyecta
  2. Variable Groups + inyección en el deploy (sin Key Vault) — RECOMENDADO si no hay KV
  3. Sin config por entorno (mismo appsettings para todos)

Elección [1-3]:
```

- **Caso 1 (Key Vault)** → **ELIMINAR** el marcador `{{CONFIG_INJECT_STEP}}` de todos los stages (la app lee de KV con Managed Identity / `DefaultAzureCredential`; `appsettings.json` sin secretos).
- **Caso 2 (VG-injection)** → por cada entorno con CD:
  1. Crear/usar 1 VG `<App>-<env>` (`isSecret`) con las claves secretas (reusa P4).
  2. Añadir `variables: - group: <App>-<env>` al stage de deploy de ese entorno.
  3. **Rellenar `{{CONFIG_INJECT_STEP}}`** (en cada stage, tras `download-artifact`) con un step PowerShell que: mapea en `env:` cada secreto (`CLAVE: $(CLAVE)`), construye `$map` clave→valor, **sustituye por clave** en `$(MsDeployPackage)\appsettings.json` (`"<clave>": ""` → `"<clave>": "<valor escapado JSON>"`), `Set-Content -Encoding UTF8` (R13) y `Write-Error; exit 1` si falta algún valor (fail-fast — no desplegar config vacía). **NUNCA `FileTransform@1`** (JSONC + claves con puntos; ver R23). En `rollback-on-fail.yml` **excluir también `appsettings.json`** del borrado.
  4. `appsettings.json` en git: no-secretos reales + claves secretas (y no-secretos que varíen por entorno, ej. `SmtpSettings.Entorno`) con valor `""`.
- **Caso 3** → ELIMINAR `{{CONFIG_INJECT_STEP}}`.

Patrón completo (variables de stage, escape, caveat servidor-nuevo) en **R23 § .NET SDK-style**. Validado en MyCompany.ErpSync (FB-001).

### P5. Resumen y confirmación final

Mostrar resumen estructurado de TODO lo que se va a crear:
- Ficheros: `azure-pipelines.yml` (si Fase ≥ 1), `05_CICD/PIPELINE_*.md`, `05_CICD/RUNBOOK.md` (Fase 2), `05_CICD/RUNBOOK_DEPLOY_MANUAL.md` (Fase 0), `05_CICD/SECRETOS.md` (si VG)
- TFS: pipeline definition (Fase ≥ 1), Variable Group (si aplica)
- Hub MCP: registro vía `register_pipeline` tool (Fase ≥ 1)
- `_hilo/ESTADO_PROYECTO.json.infraestructura.cicd[]`: entrada nueva

Pedir confirmación. Si N → abortar sin escribir nada.

---

## FASE 2 — Generación de artefactos

Variación por Fase:

### Fase 0 — Solo docs locales

1. **`05_CICD/RUNBOOK_DEPLOY_MANUAL.md`** generado desde `Documentos_Base/08_CICD/RUNBOOK_DEPLOY_MANUAL.md` con placeholders rellenados (`{{PROYECTO_NOMBRE}}`, `{{APP_POOL}}`, `{{IIS_PATH}}`, etc.)
2. **`05_CICD/README.md`** índice del proyecto
3. **NO** genera `azure-pipelines.yml`
4. **NO** toca Hub MCP

### Fase 1 — YAML minimal

```yaml
# =============================================================================
# <PROYECTO_NOMBRE> — Pipeline CI (Fase 1: build validation)
# Ovillo cicd-architect <stack> @ <TEMPLATE_STAMP>   (sello de plantilla; ver FASE 2.8)
# Referencias: .claude/rules/cicd-runtime.md (G1-G14)
#              Documentos_Base/08_CICD/LIMITACIONES_TFS_2020.md
#
# Alcance (Fase 1, CI-only): compila y testea la SOLUCION COMPLETA. NO despliega.
# Si la solucion tiene varios entrypoints (Web/API/Console), el CD por entrypoint
# (Web->Aplicaciones, API->Servicios/Aplicaciones) se genera al promover a FASE 2
# (un pipeline por entrypoint, R25); los desplegables quedan fase:0 en cicd[].
# =============================================================================

name: $(date:yyyyMMdd)$(rev:.r)

trigger:
  branches:
    include:
      - <RAMA_BASE>
  paths:
    # R7: workaround TFS 2020 — emitir AMBOS patrones
    include:
      - '03_Desarrollo/**'
      - '03_Desarrollo/**/*'
      - '04_Pruebas/**'
      - '04_Pruebas/**/*'
      - 'azure-pipelines.yml'

pr: none

variables:
  BuildConfiguration: 'Release'
  # ... resto según stack

stages:
  - stage: Build
    displayName: 'Build & Test'
    jobs:
      - job: BuildAndTest
        pool:
          name: BUILDERS                # R1
          demands:
            - Agent.ComputerName -equals BUILD01   # R1
        timeoutInMinutes: 30
        steps:
          # [steps según stack — ver templates en cicd-architect skill]
          # .NET: UseDotNet@2 + dotnet restore/build/test + PublishCodeCoverageResults@1 + dotnet publish + PublishBuildArtifacts@1
          #   FB-E: el 'dotnet restore' DEBE llevar feedsToUse:'config' + nugetConfigPath:'{{NUGET_CONFIG_PATH}}' si el repo
          #   tiene nuget.config (feed interno de la organización/Stic, detectado en 0.2). Sin ello -> NU1101 con dependencias internas.
          # Vue: NodeTool@0 + npm ci + vue-tsc + npm run lint + vitest + npm run build + ArchiveFiles@2 + PublishBuildArtifacts@1
```

### Fase 2 — Pipeline completo

> **Generación por entrypoint (R25)**: se renderiza **un `azure-pipelines[.<slug>].yml` por cada entrypoint
> desplegable** desde el template del stack (`skills/cicd-architect/templates/azure-pipelines.fase2.*.yml.template`),
> NO un YAML con todos los entrypoints. Naming: 1 entrypoint → `azure-pipelines.yml` + def `<PROYECTO>`;
> >1 → `azure-pipelines.<slug>.yml` + def `<PROYECTO>-<slug>` (`<slug>` = nombre del entrypoint kebab). `trigger.paths`
> acotado al subárbol del entrypoint (+ doble patrón R7). **Console/Worker (FB-B, v3.16.0)** → template
> `azure-pipelines.fase2.console.yml.template` + `steps/deploy-scheduled-task.yml`: Build + CD por **Tarea
> Programada** (NO IIS, NO smoke HTTP). Datos de la tarea en **P-console**; placeholders extra: `{{CONSOLE_CSPROJ}}`,
> `{{TASK_NAME}}`, `{{TASK_SCHEDULE_ARGS}}`, `{{TASK_RUN_ACCOUNT}}` (R6 SYSTEM), `{{DEPLOY_FOLDER}}`, `{{CONSOLE_EXE}}`,
> `{{CONSOLE_DEPLOY_DEMAND_DEV/PRE}}` + `{{PROD_NODE_A}}` (demand REAL del pool, FB-002; Console no tiene tipo fijo).
>
> **Placeholders de routing a sustituir por entrypoint**:
> `{{DEPLOY_DEMAND_DEV}}`/`{{DEPLOY_DEMAND_PRE}}`/`{{DEPLOY_DEMAND_PRO}}` = **valor REAL de la capability `DeployTarget`** del agente que sirve ese entorno+serverType, **derivado del pool** (FB-002, ver P3; NO `<env>-<app|svc>` hardcodeado) ·
> `{{DEV_URL}}`/`{{DEMO_URL}}`/`{{PROD_URL}}` = URL apps o svc del inventario (R1, según `serverType` de P1-bis) ·
> `{{PROD_NODE_A}}`/`{{PROD_NODE_B}}` = `Agent.Name` REAL de los nodos PROD del pool (ej. APP03 — puede ser 1 solo; omitir B si no hay segundo nodo).

Mismo trigger + Build, MÁS (ejemplo .NET; el real sale del template):

```yaml
  - stage: DeployDev
    displayName: 'Deploy a DEV (auto)'
    dependsOn: Build
    condition: succeeded()
    jobs:
      - job: DeployToDev
        pool:
          name: BUILDERS
          demands:
            - DeployTarget -equals {{DEPLOY_DEMAND_DEV}}   # R1/FB-002: valor REAL del pool (NO <env>-<app|svc> hardcodeado)
        steps:
          - checkout: none                       # R8
          - task: PowerShell@2
            displayName: 'Descargar artefacto (REST API)'  # R3
            env:
              SYSTEM_ACCESSTOKEN: $(System.AccessToken)
            inputs:
              targetType: inline
              script: |
                # [bloque TLS 1.2+ R2]
                # [descarga REST API según R3]
          - task: IISWebAppDeploymentOnMachineGroup@0  # R4
            inputs:
              WebSiteName: 'Default Web Site'
              VirtualApplication: '<REPO_KEBAB>'
              Package: '$(MsDeployPackage)'
              RemoveAdditionalFilesFlag: true
              TakeAppOfflineFlag: <true|false>   # R10 según stack

  - stage: DeployDemo
    displayName: 'Deploy a DEMO (manual)'
    dependsOn: Build
    condition: succeeded()
    jobs:
      - job: WaitForApproval
        pool: server
        timeoutInMinutes: 1440
        steps:
          - task: ManualValidation@0
            inputs:
              notifyUsers: '<APPROVER_EMAIL>'
              instructions: 'Aprobar deploy a DEMO del build $(Build.BuildNumber).'
              onTimeout: 'reject'

      - job: DeployToDemo
        dependsOn: WaitForApproval
        condition: succeeded()
        pool:
          name: BUILDERS
          demands:
            - DeployTarget -equals {{DEPLOY_DEMAND_PRE}}   # R1/FB-002: valor REAL del pool
        steps:
          # backup pre-deploy (R15 capa 1) → MSDeploy enableRule (R15 capa 2) → smoke → rollback condition:failed() (R15 capa 3)
          # smoke estricto .NET o best-effort SPA según stack (R11)

  - stage: DeployProd
    displayName: 'Deploy a PROD (manual, 2 servers rolling)'
    dependsOn: DeployDemo
    condition: succeeded()
    jobs:
      - deployment: DeployToProd_A
        environment: '<PROYECTO>-Prod'         # approval check del grupo
        pool:
          name: BUILDERS
          demands:
            - Agent.Name -equals STRIFY01_DEPLOY
        strategy:
          runOnce:
            deploy:
              steps:
                # backup + MSDeploy + smoke local + rollback condition:failed()
      - job: DeployToProd_B
        dependsOn: DeployToProd_A
        condition: succeeded()
        pool:
          name: BUILDERS
          demands:
            - Agent.Name -equals STRIFY02_DEPLOY
        steps:
          # mismo pattern
```

> **Templates completos** YAML por stack (.NET / Vue) y por fase (1 / 2) viven en `.claude/skills/cicd-architect/templates/`. Esta sección documenta SOLO la estructura. La skill `cicd-architect` se auto-invoca para emitir los steps detallados.
>
> **Steps reutilizables (OBLIGATORIO materializar)**: los `- template: steps/*.yml` que referencian los YAML de Fase 2 se **copian literalmente** desde `.claude/skills/cicd-architect/templates/steps/` a la carpeta `steps/` del repo (junto a `azure-pipelines.yml`, raíz). Incluyen el gate de seguridad R22 ya cableado: `security-scan-build.yml` (en Build, `continueOnError`, publica `security-report`) + `security-verdict-gate.yml` (primer step de cada deploy: `mode: warn` en DEV, `mode: block` en PRE/PROD). NUNCA dejar una referencia `steps/*.yml` sin materializar su fichero — el pipeline no validaría (`template not found`).

### Filtro de tests — `{{TEST_FILTER}}` (FB-008, stack .NET)

Algunos proyectos tienen tests que **no pueden correr en BUILD01** (integración con Docker/Testcontainers,
`WebApplicationFactory`, dependencias externas). El template `fase2.dotnet` expone el placeholder
`{{TEST_FILTER}}` en los `arguments` del `dotnet test` para excluirlos **de forma canónica** (sobrevive a
los re-renders, sin `# CUSTOM` — que duplicaría el step).

**Preguntar al usuario** (solo si hay proyecto de test; default: sin filtro):
`¿Excluir algún grupo de tests del CI? (ej. integración que necesita Docker y BUILD01 no tiene). [Enter = ninguno]`
`  Ejemplos: 'FullyQualifiedName!~Integration'  ·  'Category!=Integration'  ·  'TestCategory!=E2E'`

**Sustitución de `{{TEST_FILTER}}`**:
- Sin filtro (default) → cadena **vacía** (`--no-build --collect:...`).
- Con filtro → ` --filter "<expr>"` **con espacio inicial** (`--no-build --filter "FullyQualifiedName!~Integration" --collect:...`).

**Persistencia**: guardar la expresión en `_hilo/ESTADO_PROYECTO.json.infraestructura.cicd[].testFilter`
(string, default `""`). En **Opción 4** (re-render), leer ese valor — y si no existe, **detectar el `--filter`
del `dotnet test` del YAML actual** — para re-aplicarlo a `{{TEST_FILTER}}` sin preguntar (con opción de cambiarlo).
Así el filtro del equipo nunca se pierde en un re-render.

> Si el filtro excluye los tests de integración, considéralo deuda: lo ideal (FB-008) es **medirlos** con
> `dotnet-coverage` por-proyecto (ver `skills/calidad-codigo-sync/references/ci-wiring.md` §1-bis) en vez de
> excluirlos — pero si BUILD01 no tiene Docker, excluir es la decisión pragmática válida. Anótalo en `DEUDA_TECNICA.md`.

### Generación stack netfx (.NET Framework clásico) — desde v3.12.0

Si STACK = "netfx", usar **`azure-pipelines.fase1.netfx.yml.template`** (Fase 1) o **`azure-pipelines.fase2.netfx.yml.template`** (Fase 2) en vez de los `.NET`/Vue. Diferencias clave (MSBuild, NO dotnet):
- **Restore/Build/Test**: `NuGetToolInstaller@1` + `NuGetCommand@2` (`feedsToUse:config` + `nugetConfigPath`) + `VSBuild@1` (`vsVersion:latest` + `/p:DeployOnBuild=true;WebPublishMethod=Package` para el paquete MSDeploy) + `VSTest@2` (`codeCoverageEnabled:false`). NUNCA `UseDotNet@2`/`DotNetCoreCLI@2`.
- **Deploy**: `IISWebAppDeploymentOnMachineGroup@0` con `Package: '$(MsDeployPackage)\*.zip'` (netfx empaqueta un **.zip** MSDeploy, NO una carpeta como .NET) + `TakeAppOfflineFlag:true`.
- **Fase 1 = pipeline PLANO** (pool+steps raíz, sin `stages:`) o la ejecución manual da "No pool was specified". **Fase 2 = multi-stage**.

**Compañeros OBLIGATORIOS a materializar** (además de los `steps/*.yml`): el **`{{NUGET_CONFIG_PATH}}`** con feed Stic (ver tabla) y el `05_CICD/scripts/security-scan.ps1` (stack `dotnet`, best-effort en netfx).

**Pre-flight netfx (FASE 0.4)**: VS Build Tools en BUILD01 · `.sln` header en línea 1 · todos los proyectos del `.sln` commiteados (sino `MSB3202`).
**Post-registro netfx (FASE 2.5)**: TEC-007 `definition.queue`≠NULL + rol `User` de la cola para `Project Valid Users`. Ver memorias `cicd-netfx-classic-stack` + `cicd-tfs2020-definition-queue`. Validado en MyCompany.WebCorporativa (build verde).
**TEC-008 - test project net48 con MSTest 4.x (piloto GuiasDocentes, 2026-06-05)**: `VSTest@2` falla con "Could not load 'System.Memory, Version=4.0.1.2'" cuando el agente corre `vstest.console` 16.11 (VS2019) y el test usa el adapter MSTest 4.x. CAUSA RAIZ = la VERSION de vstest.console, NO un binding redirect (el assembly lo carga el Test Platform, no el dominio del test). El enum de `vsTestVersion` en TFS 2020 solo admite (latest, 16.0, 15.0, 14.0, toolsInstaller) por lo que `17.0` NO existe, y `latest`=16.11. Bajar el test a MSTest 3.x TAMPOCO sirve: el codigo de tests usa API 4.x (`Assert.ThrowsExactly`) y rompe la compilacion (CS0117), y reescribir asserts cambiaria su semantica. FIX VALIDADO (sin tocar codigo de tests): `VisualStudioTestPlatformInstaller@1` con `packageFeedSelector: netShare` apuntando a `Microsoft.TestPlatform` 18.x en el feed Stic, + `VSTest@2` con `vsTestVersion: toolsInstaller`. Prerequisito infra (1 vez): `Microsoft.TestPlatform` 18.x en el feed Stic (ver PERMISOS_CICD). Con xUnit (caso WebCorporativa) no aparece.

**Config multi-entorno netfx (R23, piloto GuiasDocentes 2026-06-08)**: en Fase 2 con **>1 entorno**, NO hornear un único paquete `Release` para todos (el transform queda fijado al de Release → dev/demo reciben config de prod). Si la app tiene transforms `Web.<Config>.config` → **HÍBRIDO**: (a) **build-por-configuración** — un `VSBuild@1` + paquete MSDeploy POR ENTORNO (`Configuration={{CFG_ENV}}`, `PackageLocation=…\<env>` → publica `drop-<env>`; cada deploy descarga su `drop-<env>`); placeholders `{{CFG_DEV}}`/`{{CFG_PRE}}`/`{{CFG_PRO}}` + `{{VG_<ENV>}}`. (b) **Variable Group por entorno SOLO con los secretos** (`isSecret`), inyectados con `XmlVariableSubstitution: true`. Detectar las `Configuration` del `.sln`/`.csproj`; crear las que falten (p.ej. `Web.Dev.config` para el entorno de CI + `Configuration` Dev en `.sln` [Web→Dev, resto→Release] y `.csproj`). **`XmlVariableSubstitution` SOLO toca `appSettings`/`connectionStrings`** — NO `sessionState`/`mailSettings`/secciones arbitrarias → para esas, transforms obligatorios. **Gotchas VG** (documentar en `05_CICD/SECRETOS.md`): clave vacía BORRA el valor del `Web.config`; carrera UI (refrescar antes de guardar; un save con pestaña vieja sobrescribe lo añadido por API); claves con `:` (`ida:*`) válidas pero verificar la sustitución en el 1er deploy; borrar secretos del `Web.config` base para cerrar deuda (entonces R22 → BLOCK). Ver regla **R23**.

> R18 (Mira) en netfx: VSTest emite `.coverage` (binario VS) que Mira no lee → gate OMITIDO. Cobertura real = coverlet + `dotnet test` sobre el proyecto de tests SDK-style.

### Documentación operativa

| Fichero | Cuándo se crea | Plantilla |
|---|---|---|
| `05_CICD/PIPELINE_DEV.md` | Si stage DEV | Adaptado del proyecto |
| `05_CICD/PIPELINE_DEMO.md` | Si stage DEMO | Idem |
| `05_CICD/PIPELINE_PROD.md` | Si stage PROD | Idem |
| `05_CICD/RUNBOOK.md` | Fase 2 siempre | Desde `Documentos_Base/08_CICD/RUNBOOK_TEMPLATE.md` |
| `05_CICD/RUNBOOK_DEPLOY_MANUAL.md` | Fase 0 | Desde Documentos_Base |
| `05_CICD/LIMITACIONES_TFS_2020.md` | Siempre Fase ≥ 1 | Copia checksum-tracked de Documentos_Base |
| `05_CICD/SECRETOS.md` | Si VG creado (P4) | Plantilla con inventario + procedimientos |
| `05_CICD/scripts/security-scan.ps1` | Fase 2 + stack con deploy (NO Variante C) | Desde `skills/cicd-architect/templates/security-scan.ps1` (ASCII puro, R22) |
| `05_CICD/SEGURIDAD_PIPELINE.md` | Fase 2 + stack con deploy | Doc operacional del gate de ciberseguridad (R22) |
| `05_CICD/PERMISOS_CICD.md` | Fase ≥ 1 | Desde `Documentos_Base/08_CICD/PERMISOS_CICD.md` (handoff Sistemas: `Use` pool, agentes `DeployTarget`, approvals PROD) |
| `steps/*.yml` (raíz, junto a `azure-pipelines.yml`) | Fase 2 | Copia literal de `skills/cicd-architect/templates/steps/`: download-artifact-rest, security-scan-build, security-verdict-gate, backup-pre-deploy, smoke-{strict-dotnet/besteffort-spa}, rollback-on-fail |
| `<SRC_DIR>/NuGet.config` | Stack **netfx** (Fase ≥ 1) | `<clear/>` + feed **Internal** `\\build01.example.org\repositorio\myorg\PaquetesNuget` + nuget.org. Sin él, el agente solo usa nuget.org y los `MyCompany.*` dan NotFound |
| `05_CICD/README.md` | Siempre | Índice de la carpeta |
| (sin fichero de excepciones) | Fase 2 + stack .NET | R18 gatea por umbral coverageLineThreshold/Branch, no por excepciones por metodo |
| `04_Pruebas/.security-exceptions.yml` | Fase 2 + stack con deploy | Vacío inicial; excepciones con `owner` + `target_date` (R22) |
| `steps/quality-sync.yml` | **Fase 2 + .NET con tests (incluido por defecto, opt-out)** | Copia de `skills/cicd-architect/templates/steps/quality-sync.yml`. Publica el QR de calidad al hub para el dashboard. Best-effort (no gatea; sin `HUB_SERVICE_KEY` solo avisa). Marcadores `{{QUALITY_SYNC_STEP}}`/`{{QUALITY_SYNC_VARS}}` en el template fase2.dotnet — ver FASE 2.7 abajo. |
| `05_CICD/provision-quality-ci-key.ps1` | **Fase 2 + .NET + QR Auto (zero-touch, ADR-046)** | Materializado de `skills/cicd-architect/templates/Provision-QualityCiKey.ps1.template` (sustituir `{{TFS_COLLECTION_URL}}`/`{{TFS_PROJECT}}`/`{{PIPELINE_ID}}`/`{{VG_NAME}}`). Emite la service-key via Hub (≥1.7.0) y la deja `isSecret` en el VG + autoriza VG→canalización. La key nunca se imprime. Corre en la máquina del dev. Solo si el usuario elige Auto en FASE 2.7 paso 4. |

---

## FASE 2.8 — Sello de versión + self-check de completitud (OBLIGATORIO si se generó YAML)

> **Origen h13**: incidente EWP v3.13.0-h12 — la Opción 4 hizo un edit parcial y dejó fuera steps del
> template (R18 Mira, reporte HTML `CoverageReport`, limpieza opencover). La defensa: **verificar la
> salida** (mismo principio que el smoke test de `/hotfix` y `validate-zip.ps1`). En flujos copia+genera
> —forzados por TFS 2020, sin `extends` fiable (tabla B)— "confiar en que se regeneró" ≠ "verificar".

Tras escribir `azure-pipelines.yml` (instalación nueva **o** re-render de Opción 4), DOS pasos
mecánicos cierran la generación. Aplica a Fase ≥ 1 que produzca YAML.

### 2.8.1 Sustituir el sello de plantilla `{{TEMPLATE_STAMP}}` (drift por HASH de template, ADR-047)

La cabecera del template trae `# Ovillo cicd-architect <stack> @ {{TEMPLATE_STAMP}}`. Rellenar
`{{TEMPLATE_STAMP}}` en el YAML generado con:

```
v<installedVersion> (tpl <templateHash12>) gen <YYYY-MM-DD>
```

- `installedVersion`: de `_hilo/VERSION.json` (fallback: `ecosistema.version` de
  `_hilo/ESTADO_PROYECTO.json`; si nada, `desconocida`).
- `templateHash12`: hash de contenido del `.yml.template` del stack usado, calculado con el helper
  (NO es el zip-sha del ecosistema — ver más abajo). Ejecutar:

  ```powershell
  pwsh .claude/skills/cicd-architect/templates/Get-TemplateStamp.ps1 -Stack <stack>
  ```

  donde `<stack>` es el token de la cabecera del template usado: `dotnet`, `vue`, `netfx`,
  `netfx-branch-gated`, `netfx-fase1`, `nettool`, `console`. Capturar su stdout (12 hex).
  Para el **YAML minimal inline** de .NET/Vue Fase 1 (no derivado de un `.template`): usar el
  literal `tpl inline` (no hay template que hashear).

Ejemplo resultante:
`# Ovillo cicd-architect netfx-branch-gated @ v3.14.0 (tpl 87c5e2b2243c) gen 2026-06-22`.

Este sello lo lee `/cicd-status` §1.5 para **detectar drift de plantilla**. El token `tpl <hash>`
identifica el **contenido del template del stack**, no la versión del ecosistema: así el drift solo
salta cuando el template de TU stack cambió realmente (re-render con cambios), no en cada release
del ecosistema (que antes, con el esquema `zip <sha>` de h13, marcaba drift cosmético en stacks cuyo
template no había cambiado). Si el template cambió → re-`/cicd-init` Opción 4 (re-render + self-check).

### 2.8.2 Self-check determinista (NO cerrar en rojo)

Correr el verificador de completitud contra el **template del stack usado**:

```powershell
pwsh .claude/skills/cicd-architect/templates/validate-pipeline-complete.ps1 `
     -Yaml azure-pipelines.yml `
     -Template .claude/skills/cicd-architect/templates/<TEMPLATE_DEL_STACK>.yml.template
```

| Stack + Fase | `<TEMPLATE_DEL_STACK>` |
|---|---|
| .NET Fase 2 | `azure-pipelines.fase2.dotnet` |
| Console/Worker Fase 2 (FB-B) | `azure-pipelines.fase2.console` |
| Vue Fase 2 | `azure-pipelines.fase2.vue` |
| netfx Fase 1 | `azure-pipelines.fase1.netfx` |
| netfx Fase 2 | `azure-pipelines.fase2.netfx` |
| netfx Fase 2 branch-gated (R24) | `azure-pipelines.fase2.netfx.branch-gated` |
| .NET-tool (Variante C) | `azure-pipelines.nettool` |
| **.NET / Vue Fase 1** | *(YAML minimal inline, NO derivado de un `.template` → self-check N/A; aplicar solo el sello 2.8.1)* |

Interpretación del exit code:
- **exit 0** → pipeline COMPLETO (todos los `displayName:` / `ArtifactName:` / `- template:` del template presentes). Cerrar OK.
- **exit 1** → INCOMPLETO: el verificador lista los markers ausentes. **NO cerrar `/cicd-init`**: el YAML
  no refleja la plantilla (típico de un edit-mode parcial). Re-renderizar (Opción 4) y repetir.
- **exit 2** → error técnico (revisar rutas).

El verificador **deriva los markers del propio template** (cero lista que mantener) e ignora lo que esté
dentro de bloques `# CUSTOM:`.

**Bloques opcionales dropeados legítimamente** (no son drift): pasar `-Allow` con substrings de los
markers que `/cicd-init` quitó a propósito, para que no salgan como ausentes:
- **Sin proyecto de test** (branch (a) del template): `-Allow "dotnet test,Publish coverage,Coverage gate,Reporte HTML,CoverageReport"`.
- **Sin endpoint /health** (branch (b), se cambió `smoke-strict-dotnet` por `smoke-besteffort-spa`): `-Allow "smoke-strict-dotnet"`.

Ejemplo (.NET Fase 2 sin tests):
```powershell
pwsh .claude/skills/cicd-architect/templates/validate-pipeline-complete.ps1 `
     -Yaml azure-pipelines.yml `
     -Template .claude/skills/cicd-architect/templates/azure-pipelines.fase2.dotnet.yml.template `
     -Allow "dotnet test,Publish coverage,Coverage gate,Reporte HTML,CoverageReport"
```

---

## FASE 2.5 — Registro pipeline en TFS — SOLO Fase ≥ 1

> Si Fase = 0, saltar a FASE 3.

Tras escribir los ficheros, **registrar build definition en TFS vía API REST**.

> **Por entrypoint (R25)**: con >1 entrypoint hay >1 `azure-pipelines.<slug>.yml` → **una definición TFS por
> cada uno** (`<PROYECTO>-<slug>`, con su `yamlFilename` y `trigger.paths` propios). Repetir FASE 2.5 (y 2.6)
> por cada pipeline generado; cada entrada se persiste en su `cicd[]` (FASE 4). Console/Worker = definición CI-only (sin stages de deploy).

> **R20 — si `$DEPLOY_MODE = on-demand`**: el JSON de la definición DEBE incluir la sección `variables` con `DeployEnv` y `allowOverride: true` (= *settable at queue time*). Sin esto, `/cicd-deploy --env <env>` falla al encolar con `DeployEnv is not a valid queue-time variable`. Si `$DEPLOY_MODE = auto`, omitir esa variable (el YAML no la usa).

### Descubrimiento

```powershell
# 1. RepositoryId
$repos = Invoke-RestMethod -Uri "$tfsUrl/$proj/_apis/git/repositories?api-version=5.0" -UseDefaultCredentials
$repoId = ($repos.value | Where-Object { $_.name -eq $repoName }).id

# 2. QueueId de BUILDERS (per-proyecto)
$queues = Invoke-RestMethod -Uri "$tfsUrl/$proj/_apis/distributedtask/queues?api-version=5.0-preview" -UseDefaultCredentials
$queueId = ($queues.value | Where-Object { $_.pool.name -eq 'BUILDERS' }).id

# 3. Default branch
$defaultBranch = "refs/heads/$ramaBase"
```

### POST build definition

```json
{
  "name": "<PIPELINE_NAME>",
  "path": "\\",
  "type": "build",
  "process": {
    "yamlFilename": "azure-pipelines.yml",
    "type": 2
  },
  "queue": { "id": <queueId> },
  "repository": {
    "id": "<repoId>",
    "name": "<repoName>",
    "type": "TfsGit",
    "defaultBranch": "<defaultBranch>"
  },
  "variables": {
    "DeployEnv": { "value": "", "allowOverride": true }
  },
  "triggers": [{
    "branchFilters": [],
    "pathFilters": [],
    "settingsSourceType": 2,
    "batchChanges": false,
    "maxConcurrentBuildsPerBranch": 1,
    "triggerType": "continuousIntegration"
  }],
  "retentionRules": [
    {
      "branches": ["+refs/heads/<RAMA_BASE>"],
      "daysToKeep": 30,
      "minimumToKeep": 5,
      "artifacts": ["drop"]
    },
    {
      "branches": ["+refs/heads/*", "-refs/heads/<RAMA_BASE>"],
      "daysToKeep": 7,
      "minimumToKeep": 1,
      "artifacts": ["drop"]
    }
  ]
}
```

Validar tras POST: que `retentionRules` quedó aplicado (algunas versiones TFS 2020 lo ignoran silenciosamente — warning si así).

### Manejo de respuestas

- **HTTP 200**: ✅ pipeline registrado. Mostrar URL: `https://devops.example.org/<COL>/<PROJ>/_build?definitionId=<id>`
- **HTTP 400/409 con "already exists"**: en modo edición es esperado. En modo creación inicial, ofrecer 4 opciones (vincular existente / nombre v2 / cancelar / borrar y recrear).
- **HTTP 401/403** (típico: `<usuario> needs Use permissions for pool BUILDERS`): el usuario no tiene permiso `Use` sobre el pool BUILDERS. Es un gate de Sistemas, **no es verificable vía API antes del POST** (por eso aflora aquí y no en FASE 0.4). NO reintentar — el script ya descubrió `repoId` + `queueId`, así que al reanudar el registro es inmediato. Acción a comunicar al usuario:
  - **Pedir a Sistemas** que conceda rol **User** (permiso `Use`) sobre `Agent pools → BUILDERS → Security` **PARA EL GRUPO DEL PROYECTO** (`[<Proyecto>]\Contributors` o `Project Valid Users`), NO para la identidad individual. Razón: si se concede solo al usuario actual, el **siguiente dev** del mismo proyecto que registre vuelve a bloquearse. Concedido al grupo, todo el equipo queda autorizado. Alternativa equivalente: activar "Grant access permission to all pipelines" del pool para el proyecto.
  - **Quién paga el permiso**: solo el **primer dev** que registra la definición, **una vez por proyecto**. Los demás devs que clonan un repo ya registrado NO necesitan el permiso — el `azure-pipelines.yml` ya está commiteado y la definición ya existe; solo hacen `git push`.
  - **Tras conceder**: re-ejecutar `/cicd-init` (modo idempotente FASE 0.5 → opción "registrar definición") o el script standalone `05_CICD/registrar-pipeline-tfs.ps1` si se generó. El POST ahora pasa.
  - Si el usuario no puede esperar a Sistemas: documentar el bloqueador en `_hilo/ESTADO_PROYECTO.json.infraestructura.cicd[]` con `repoId`/`queueId` resueltos y continuar con las instrucciones manuales de TFS UI.
- **HTTP 5xx / network**: mostrar response + sugerir reintento o manual.

**NO encolar el primer build vía API** — dejar que `git push` lo dispare (memoria `feedback_no_manual_queue`).

### Autorización canalización → pool (TEC-003, intento auto-servicio)

Tras crear la definición, el primer build puede quedar en `notStarted` con `Checkpoint.Authorization: inProgress` (agentes BUILD01 libres) — la **canalización** no está autorizada a usar el recurso pool BUILDERS. Distinto del permiso `Use` del USUARIO (que sirve para registrar/encolar, no para despachar). `/cicd-init` debe **intentar autorizar por API** (auto-servicio si el dev es pool admin, validado en piloto Griddo Fase 2 def 13):

```powershell
# R2 TLS 1.2+. $defId = id de FASE 2.5; $queueId = queue de BUILDERS.
$body = @{ pipelines = @(@{ id = $defId; authorized = $true }) } | ConvertTo-Json -Depth 5
$uri  = "$tfsUrl/$proj/_apis/pipelines/pipelinePermissions/queue/$queueId?api-version=5.1-preview.1"
try {
    Invoke-RestMethod -Uri $uri -Method Patch -Body $body -ContentType 'application/json' -UseDefaultCredentials | Out-Null
    Write-Host "OK: canalizacion autorizada al pool BUILDERS por API (eres pool admin). Build desbloqueado."
} catch {
    $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
    Write-Host "Autorizacion por API no permitida (HTTP $code) -> derivar a Sistemas (banner 'Permit' o 'grant access to all pipelines')."
}
```

- **HTTP 200** → autorizado automáticamente, build desbloqueado sin Sistemas (caso pool admin; frecuente en líder técnico / pilotos).
- **HTTP 401/403** → derivar al banner "Permit" del build o a Sistemas (`Agent pools → BUILDERS → Security → grant access to all pipelines`).

NO confundir con el `Use` del usuario (401/403 en el POST de FASE 2.5): son **dos gates distintos**.

### Cola por defecto de la definición — `queue` NULL → "No pool was specified" (TEC-007)

**Síntoma**: TODO build (push, manual o API) falla **instantáneo** (`startTime == finishTime`, ~0s), con **timeline vacío** (ningún job arranca) y `build.validationResults[].message = "No pool was specified."`. Da igual dónde esté el `pool:` en el YAML (raíz, stage o job): el error persiste.

**Causa**: la **definición** de build tiene `queue = NULL` (sin pool por defecto). En TFS 2020 la definición necesita una `queue` por defecto **además** del `pool:` del YAML. El POST de esta FASE 2.5 ya incluye `"queue": { "id": <queueId> }`, pero **un pipeline creado por el wizard de la UI** (New pipeline → Existing YAML) se queda con `queue=NULL` → de ahí el fallo. Validado en piloto MyCompany.WebCorporativa (def 15: TODOS los builds instant-fail hasta asignar la cola por API).

**Verificación OBLIGATORIA tras registrar** — y también en **FASE 0.5** si el pipeline ya existía (típico: creado por UI antes de `/cicd-init`):

```powershell
# $defId de FASE 2.5; $queueId = queue de BUILDERS en el proyecto; $poolId = 6
$d = Invoke-RestMethod -Uri "$tfsUrl/$proj/_apis/build/definitions/$defId`?api-version=5.0" -UseDefaultCredentials
if (-not ($d.PSObject.Properties.Name -contains 'queue') -or -not $d.queue) {
    $q = [pscustomobject]@{ id = $queueId; name = 'BUILDERS'; pool = [pscustomobject]@{ id = $poolId; name = 'BUILDERS' } }
    $d | Add-Member -NotePropertyName queue -NotePropertyValue $q -Force   # la propiedad puede NO existir
    $json = $d | ConvertTo-Json -Depth 40
    Invoke-RestMethod -Method Put -Uri "$tfsUrl/$proj/_apis/build/definitions/$defId`?api-version=5.0" -Body $json -ContentType 'application/json' -UseDefaultCredentials | Out-Null
    Write-Host "Cola por defecto (BUILDERS) asignada a la definicion $defId."
}
```

> TRAMPA: el objeto de la definición puede venir **sin** la propiedad `queue` (ausente, no `null`) → `$d.queue = ...` lanza *"The property 'queue' cannot be found on this object"*. Usar **`Add-Member -Force`** (añade o reemplaza).

**Pre-requisito del PATCH de autorización (rol de la COLA, no del pool)**: para que el PATCH `pipelinePermissions` funcione en auto-servicio, el grupo del proyecto (`Project Valid Users`) debe tener rol **User** sobre la **cola del proyecto** — un proyecto **nuevo** suele crearla con **Reader** → el PATCH da `AccessDenied` aunque seas admin del pool de colección. Mismo gate de Sistemas que el `Use`, pero a nivel de la cola. Validado: Griddo queue 3 = `Project Valid Users → User` (funciona); WebCorporativa queue 13 = `Reader` (bloqueaba) hasta cambiarlo a `User`. Comprobar con `GET .../securityroles/scopes/distributedtask.agentqueuerole/roleassignments/resources/{projectId}_{queueId}`.

---

## FASE 2.6 NUEVO Ovillo — Registro Hub MCP — SOLO Fase ≥ 1

Si `.mcp.json` referencia `ovillo-hub` y la Fase elegida ≥ 1:

```
🔗 Invocando tool MCP `register_pipeline` para registrar el pipeline
   en el Hub central Ovillo (ProjectId={projectId}, PipelineId={pipelineIdTfs}).

   Esto permitirá:
   - Dashboard tab CI/CD muestre el estado de tu pipeline
   - `/cicd-status` local pueda consultar el Hub
   - Telemetría agregada cross-proyecto
```

Claude invoca el tool MCP con payload:

```json
{
  "projectId": "<projectId from _hilo/.mcp-project.json>",
  "pipelineId": "<id devuelto por FASE 2.5>",
  "nombre": "<PIPELINE_NAME>",
  "url": "https://devops.example.org/<COL>/<PROJ>/_build?definitionId=<id>",
  "fase": <0|1|2>,
  "stages": ["Build", "DeployDev", "DeployDemo", "DeployProd"],  // según fase
  "stack": ".NET ASP.NET Core" | "Vue+Vite+TS"
}
```

Best-effort: si el Hub no responde o el tool falla, mostrar warning + sugerir re-ejecutar `mcp-sync` luego. NO bloquear `/cicd-init`.

---

## FASE 2.7 — Publicar el Registro de Calidad (QR) al dashboard — Fase 2 + .NET con tests

Para que **cada build publique su Registro de Calidad (QR)** en el dashboard de calidad del portfolio
(hub v1.3.0+, vivo en 1.7.0), el stage Build incluye el step productor `quality-sync` (skill
`calidad-codigo-sync`, mismo motor que el comando local `/calidad-sync`). **Best-effort: NO gatea el build**
(el gate de cobertura sigue siendo Mira/R18) y **no rompe nada sin la service-key** (si `HUB_SERVICE_KEY`
falta en el VG, el step loguea un warning y sale 0). Por eso se **incluye por defecto** en Fase 2 .NET con
tests. Detalle: `skills/calidad-codigo-sync/references/ci-wiring.md`.

**Preguntar al usuario** (default SÍ — es inocuo sin la key):
`¿Publicar el QR de calidad al dashboard en cada build? (best-effort; tendras que anadir HUB_SERVICE_KEY al Variable Group cuando quieras que empiece a publicar) [S/n]`

**Si SÍ** (rellenar los marcadores del template `fase2.dotnet`):
1. **Step**: sustituir el marcador `# {{QUALITY_SYNC_STEP}}` por `- template: steps/quality-sync.yml` y
   **materializar** `steps/quality-sync.yml` desde `skills/cicd-architect/templates/steps/` a la carpeta
   `steps/` del repo (junto a `azure-pipelines.yml`). Va en el stage Build, tras el reporte HTML de cobertura.
2. **Variables** (no secretas): sustituir el marcador `# {{QUALITY_SYNC_VARS}}` por dos vars:
   `qualityProjectId` = projectId del hub (`mcpSync.projectId` de `ESTADO_PROYECTO.json` / `_hilo/.mcp-project.json`)
   y `codeSearchBase` = `https://devops.example.org/<COL>/<PROJ>/_search?type=code&text=`.
3. **OpenCover ya emitido**: el `dotnet test` del template ya pasa `Format=cobertura,opencover` (desde h12)
   → el productor encuentra el `*.opencover.xml` en `$(Agent.TempDirectory)` **sin** el `coverage.runsettings`
   de la skill (ese runsettings solo hace falta en pipelines hand-rolled o netfx que no emitan opencover).
   El `cobertura` sigue alimentando el gate de Mira (R18) sin cambios.
4. **Service-key del Variable Group** (`HUB_SERVICE_KEY`, R16 `isSecret`, ADR-045 — NO la apiKey per-dev).
   Es lo único que el step necesita para publicar de verdad. **Sub-pregunta (default Auto)**:

   `¿Configuro la service-key del dashboard automaticamente (zero-touch)? Usare tu apiKey per-dev para que el Hub emita la key y la dejare en el Variable Group (nunca se muestra). [1] Auto (recomendado)  [2] Manual`

   - **[1] Auto (ADR-046, zero-touch)** — requiere `_hilo/.mcp-credentials.json` (apiKey per-dev) + Hub ≥ 1.7.0 +
     `PipelineId` (de FASE 2.5). **Materializar** `Provision-QualityCiKey.ps1.template` →
     `05_CICD/provision-quality-ci-key.ps1` sustituyendo `{{TFS_COLLECTION_URL}}`, `{{TFS_PROJECT}}`,
     `{{PIPELINE_ID}}` (def de FASE 2.5) y `{{VG_NAME}}` (`<PIPELINE_NAME>-secrets` o el VG elegido); los
     `{{HUB_*}}` el script los resuelve de las credenciales. Ejecutarlo en la **máquina del dev** (Windows auth
     a TFS, igual que `registrar-pipeline-tfs.ps1` — NO en el sandbox del comando):
     ```
     pwsh 05_CICD/provision-quality-ci-key.ps1
     ```
     Emite/rota la key vía Hub (`POST /v2/sync/emit-service-key`) y la deja `isSecret` en el VG + autoriza
     VG→canalización. **La key NUNCA se imprime ni la maneja el agente** — no la pidas ni la eco; solo lee el
     `[OK]`/`[WARN]` del script. **Fallback automático a Manual** si el script sale con exit ≠ 0:
     `3` (sin apiKey → `irm|iex` primero), `4` (apiKey rotada), `5` (Hub < 1.7.0), `6` (REST TFS / el VG tiene
     otros secretos). El exit 0 con `autorizada=manual` significa que la key quedó puesta pero hay que autorizar
     el VG en TFS UI (no eres admin de Library).
   - **[2] Manual** — el admin emite la key una vez y la pega en el VG (vía clásica, sigue válida):
     `EXEC mcp.EmitirServiceKey @ProyectoId='<GUID>', @Label='ci-quality', @ServiceKey=@k OUTPUT, @Id=@id OUTPUT`
     (o `mcp.EmitirServiceKeyRotando` si quieres rotación limpia). Marcar la variable `isSecret` en el VG.

   Mientras no haya key, el step no publica (warning, build verde). Tras configurarla (auto o manual),
   **empieza a publicar sin re-`/cicd-init`**.

**Si NO** (al QR): eliminar del YAML generado los marcadores `# {{QUALITY_SYNC_STEP}}` y `# {{QUALITY_SYNC_VARS}}`
(y no materializar `steps/quality-sync.yml` ni `provision-quality-ci-key.ps1`).

> Tests de integración `WebApplicationFactory` (coverlet cuelga el testhost) → medir con `dotnet-coverage`
> por-proyecto (FB-008); ver `ci-wiring.md` §1-bis. El productor **no necesita ReportGenerator** (parsea el
> opencover directo, sin internet ni tool install). Si el hub es < v1.3.0 el step loguea `[SKIP]` y no falla.
>
> **netfx/Vue**: N/A — netfx emite `.coverage` binario (no opencover) y Vue no tiene cobertura .NET. El QR es
> solo Fase 2 .NET SDK-style (coverlet). El marcador `{{QUALITY_SYNC_STEP}}` solo existe en el template `fase2.dotnet`.

---

## FASE 3 — Checklist post-install

Mostrar al usuario instrucciones finales adaptadas a la Fase elegida:

### Fase 0
```
✅ Generado RUNBOOK_DEPLOY_MANUAL.md en 05_CICD/

PRÓXIMOS PASOS:
  1. Lee 05_CICD/RUNBOOK_DEPLOY_MANUAL.md y adapta a tu proyecto si necesario
  2. Antes de cada push, ejecutar /verify (7 fases) en local
  3. Para hacer deploy: seguir el runbook paso a paso (RDP a server)
  4. Cuando Sistemas autorice BUILDERS al proyecto + BUILD01 online: re-ejecutar /cicd-init para promocionar a Fase 1
```

### Fase 1
```
✅ Pipeline TFS registrado: <URL>

PRÓXIMOS PASOS:
  1. Branch policy "Build validation" — SEGÚN tu branching.estrategia (R21):
     · push-directo (github-flow-simplificado / trunk-based / developer-branch):
         NO la actives — bloquearía tu push directo a <RAMA_BASE>.
         El CI trigger del YAML ya construye en cada push a <RAMA_BASE>.
     · con-PR (github-flow / gitflow / release-flow / oneflow / gitlab-flow):
         Actívala para el gate en PR (gobierno — /cicd-init NO la aplica):
         Project Settings → Repos → <repo> → Policies → <rama> → Build validation
         Build pipeline: <PIPELINE_NAME> | requirement: required
  2. Commit + push para disparar el primer build:
     git add azure-pipelines.yml 05_CICD/ _hilo/ESTADO_PROYECTO.json
     git commit -m "ci: configurar build validation (Fase 1, /cicd-init)"
     git push origin <RAMA_BASE>
  3. TFS arrancará el build (latencia 0-5 min). Verificar stage Build verde.
     Si el build queda en 'notStarted' indefinidamente (agentes online, no arranca):
        es la AUTORIZACIÓN de la canalización al pool (C4b, Checkpoint.Authorization), NO capacidad.
        -> Página del build, banner "This pipeline needs permission..." -> Permit (pool admin),
           o Agent pools -> BUILDERS -> Security -> "grant access to all pipelines". (TEC-003)
  4. Cuando Sistemas instale agentes <ENV>_DEPLOY + grupo aprobadores PROD listo: re-ejecutar /cicd-init para promocionar a Fase 2
```

### Fase 2
```
✅ Pipeline completo registrado: <URL>

PRÓXIMOS PASOS:
  1. (Si VG creado) Rellenar valores de secretos en TFS UI:
     <URL_VARIABLE_GROUP>
  2. (Si PROD) Verificar Environment + group approval configurado:
     Pipelines → Environments → '<PROYECTO>-Prod'
  3. Commit + push para arrancar el primer build:
     git add azure-pipelines.yml 05_CICD/ _hilo/ESTADO_PROYECTO.json
     git commit -m "ci: configurar pipeline completo (Fase 2, /cicd-init)"
     git push origin <RAMA_BASE>
  4. Validar end-to-end:
     [ ] Stage Build verde
     [ ] Stage DeployDev verde (auto)
     [ ] Stage DeployDemo pending approval → aprobar → verde
     [ ] Stage DeployProd pending approval (group) → aprobar → verde
  5. Lee 05_CICD/RUNBOOK.md para manejar incidentes futuros
```

---

## FASE 4 NUEVO Ovillo — Persistir en ESTADO_PROYECTO.json

Las entradas **por entrypoint ya se crearon en P1-bis** (FB-A v3.15.0-h1). Aquí, tras FASE 2 (y 2.5/2.6 si Fase ≥ 1), hacer **UPSERT** de cada pipeline generado sobre su entrada (rellenar `pipelineId`/`url`/`fase`/`stages`/`hubMcpRegistrado`/`fechaActualizacion`) **sin borrar** las entradas de entrypoints que aún no tienen pipeline (los desplegables `fase: 0` / `modeloDeploy: "pending"`, pendientes de Fase 2). **NUNCA dejar `pipelines[]` con menos entradas que entrypoints detectados en 0.1-ter/P1-bis.**

**Forma CANÓNICA (HALLAZGO G)**: `cicd` es un **OBJETO** que conserva `plataforma` (lo lee `devops-awareness`) **y** un array `pipelines[]` (lo consume `mcp-sync`). NO emitir `cicd` como array suelto: rompería el disparador `cicd.plataforma` de `devops-awareness`.

```json
{
  "infraestructura": {
    "cicd": {
      "plataforma": "azure-pipelines",
      "_plataformas_disponibles": ["azure-pipelines", "github-actions", "manual"],
      "pipeline_existente": true,
      "deployment_groups": false,
      "pipelines": [
        {
          "entrypoint": "<MyCompany.X.Web | MyCompany.X.Api | MyCompany.X.Console>",
          "tipo": "web | api | console",
          "publico": false,
          "serverType": "app | svc | null (console)",
          "slug": "<web|api|console kebab; '' si 1 solo entrypoint>",
          "pipelineId": "<id TFS, 'manual' si Fase=0, o null si entrypoint aún sin pipeline>",
          "nombre": "<PIPELINE_NAME>",
          "yamlFile": "<azure-pipelines.yml | azure-pipelines.<slug>.yml>",
          "url": "<URL TFS o null>",
          "fase": "<0|1|2>  (0 = entrypoint detectado, CD pendiente de Fase 2)",
          "stages": ["Build", ...],
          "stack": ".NET ASP.NET Core" | "Vue+Vite+TS",
          "modeloDeploy": "on-demand | auto | branch-gated | ci-only | pending",
          "hubMcpRegistrado": <true|false>,
          "fechaCreacion": "<ISO timestamp>",
          "fechaActualizacion": "<ISO timestamp>"
        }
      ]
    }
  }
}
```

- `devops-awareness` lee `cicd.plataforma` (objeto) → se mantiene.
- `mcp-sync` lee `cicd.pipelines[]` y envía a `/v2/sync/cicd-batch` los de `fase >= 1`.
- Si `cicd` ya era objeto (viene de `/onboarding`), AÑADIR/actualizar `pipelines[]` **sin tocar** `plataforma`. Si la entrada del pipeline ya existía (modo edición), UPDATE in-place preservando `fechaCreacion`.

---

## TROUBLESHOOTING (común)

| Síntoma | Causa | Solución |
|---|---|---|
| `Unexpected value 'deploymentGroup'` | YAML schema TFS rechaza | Usar `pool: { name: BUILDERS, demands: [...] }` (R1) |
| Build falla en `DownloadBuildArtifacts@0` con SSL | Bug Node.js cert | Usar REST API + PowerShell (R3) |
| `The underlying connection was closed` en step PS | TLS 1.0 default PS 5.1 | Bloque TLS 1.2+ al inicio (R2) |
| Trigger no dispara tras push (build no aparece) | Path filters TFS 2020 bug; agravado si el commit solo toca subcarpetas profundas (ej. `04_Pruebas/**`) | Emitir AMBOS `**` y `**/*` (R7). Si aun así no encola: encolado manual REST `POST /_apis/build/builds` (excepción legítima a "no encolar manual"). Ver RUNBOOK §1b. **NO** confundir con build encolado parado en `notStarted` (eso es autorización de pool, TEC-003) |
| `One or more files locked` en MSDeploy .NET | Falta `TakeAppOfflineFlag: true` | Configurar según stack (R10) |
| Smoke test SPA falla con timeout/SNI | Hairpin NAT topología la organización | Smoke best-effort para SPA (R11) |
| `Cannot bind argument to parameter 'environmentName'` | `IISWebAppDeployment@1` deprecated | Usar `@0` (R4) |
| `Resource X-Prod does not exist in environment` / Build no arranca | PROD `deployment`+`environment:` inexistente; valida al encolar antes de las `condition` (TEC-006) | PROD placeholder = `job` normales; environment sin puntos (`{{PROYECTO_SLUG}}Prod`) creado antes |
| Coverage gate (R18) no ejecuta Mira (`OMITIDO`) | `mira` no instalado o fuente del .nupkg inalcanzable desde el AGENTE | Auto-install desde el repo NuGet de build01 (`\\build01.example.org\repositorio\MyOrg\PaquetesNuget`, con dependencias); invocar `mira` (NO `dotnet mira`); WARN-first no bloquea. Ver ANALISIS_R18_MIRA_COVERAGE_GATE |
| `/mcp-sync` no manda pipelines al Hub (0 cicd-batch) | `cicd` es objeto y mcp-sync solo leía arrays (HALLAZGO G) | Forma canónica objeto + `pipelines[]`; mcp-sync lee `cicd.pipelines[]` |

Ver `Documentos_Base/08_CICD/LIMITACIONES_TFS_2020.md` para tabla completa.

---

## REFERENCIAS

- Reglas runtime: `.claude/rules/cicd-runtime.md` (G1-G14)
- Limitaciones TFS 2020: `.claude/rules/tfs-2020-limitations.md` + `Documentos_Base/08_CICD/LIMITACIONES_TFS_2020.md`
- Guía fases: `Documentos_Base/08_CICD/GUIA_FASES_ADOPCION.md`
- Skill complementaria: `.claude/skills/cicd-architect/` (auto-invocación al editar YAML)
- Agent audit: `.claude/agents/cicd-pipeline-reviewer.md` (audita YAML contra R1-R25)
- ADR: `_estado/DECISIONES.md` ADR-042 (constructor)

---

*Comando Ovillo v3.11.0 — Integración CI/CD nativa. Diseño conceptual battle-tested en 2 pilotos del pack del colega (BiPublisher.Api DT-004 + MyCompany.Claude.Guía), adaptado a artefactos nativos Ovillo. Atribución en ADR-042 § Atribución.*
