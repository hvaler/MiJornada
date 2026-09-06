# R1-R25 — Resumen condensado (referencia rapida)

> Tabla cheatsheet. Para detalle completo ver `.claude/rules/cicd-runtime.md`.

| # | Regla | Sev | Resumen |
|---|---|---|---|
| R1 | Pool BUILDERS + capability `DeployTarget=<env>` | 🔴 | NUNCA `deploymentGroup:`. Pool BUILDERS server-wide + capability per agente. |
| R2 | TLS 1.2+ forzado en TODO step PS | 🔴 | PS 5.1 default TLS 1.0. Bloque al inicio: `[Net.ServicePointManager]::SecurityProtocol = Tls12 -bor Tls13`. |
| R3 | Descarga artifacts REST API + PowerShell | 🔴 | Bug SSL Node.js contra `devops.example.org`. NUNCA `DownloadBuildArtifacts@0` / `DownloadPipelineArtifact@2`. |
| R4 | Versiones task canonicas | 🔴 | `UseDotNet@2`, `DotNetCoreCLI@2`, `NodeTool@0`, `IISWebAppDeploymentOnMachineGroup@0`, `PublishCodeCoverageResults@1`. |
| R5 | NUNCA `Cache@2` | 🔴 | Servicio Pipeline Caching no existe TFS 2020. `npm ci` / `dotnet restore` limpio. |
| R6 | Cuenta agente `NT AUTHORITY\SYSTEM` | 🔴 | NUNCA NETWORK SERVICE. Built-in, sin password, no caduca. |
| R7 | Trigger paths doble patron `**` Y `**/*` | 🟡 | Bug TFS 2020 `settingsSourceType=2` con subdirectorios profundos. Defensa: emitir AMBOS. |
| R8 | `checkout: none` en jobs Deploy | 🟡 | El agente Deploy no necesita codigo, solo artifact. |
| R9 | TLS bypass SSL: SOLO `https://localhost/*` | 🟡 | Justificado en smoke local (SNI mismatch cert publico). NUNCA bypass global. |
| R10 | `TakeAppOfflineFlag` parametrizado por stack | 🟡 | `.NET in-process: true` (libera locks DLL). `SPA estatica: false` (sin app_offline.htm residual). |
| R11 | Smoke best-effort para SPA (no `throw`) | 🟡 | Hairpin NAT + 403.4 + SNI mismatch desde el agente. SPA emite warning + diagnostico, .NET puede ser estricto. |
| R12 | Anti-patterns en codigo (linter warning-only) | 🟡 | 12.1 paths absolutos · 12.2 HintPath absoluto · 12.3 secrets en appsettings · 12.4 tests localhost hardcoded · 12.5 env vars sin default · 12.6 TargetFramework no instalado · 12.7 tests con BD/Redis real. |
| R13 | `Out-File -Encoding UTF8` explicito | 🔴 | PS 5.1 default UTF-16 BOM. Rompe JSON/XML que se leen luego. |
| R14 | Idempotencia `/cicd-init` (9 garantias) | — | Backup auto, diff visible, marcadores CUSTOM, preserva fase elegida, modo edicion 5 opciones, UPSERT Hub. |
| R15 | Triple rollback PROD/DEMO (NUNCA DEV) | 🟡 | Capa 1: backup pre-deploy + metadata · Capa 2: MSDeploy `enableRule:DoNotDeleteRule` · Capa 3: step `condition: failed()` restaura. |
| R16 | Secretos solo VG + fail-fast pre-build | 🔴 | NUNCA `appsettings.json` commiteado con secrets reales. Variable Group Library + step validacion pre-build. |
| R17 | `retentionRules` obligatorias | 🟡 | master: 30d/5 builds. Otras: 7d/1 build. Sin esto disco LADYADA se llena (~15GB/mes). |
| R18 | Coverage gate (`mira summary` --threshold-line/--threshold-branch) | 🟡 | Mira 0.8.1 gatea por % cobertura (NO CRAP). Umbrales coverageLineThreshold/Branch. WARN-first. Invocar `mira`, NO `dotnet mira`. |
| R19 | Runbook obligatorio 6 secciones | 🟡 | Build falla / Deploy DEMO falla / Deploy PROD falla / App caida tras deploy verde / Contactos / Backups. ≤1 pag cada una. |
| R20 | Deploy on-demand via `DeployEnv` | 🟡 | Push solo CONSTRUYE; deploy bajo demanda. `DeployEnv` vacia + `condition: eq(variables['DeployEnv'],'<env>')` por stage. `/cicd-deploy` encola; `/cicd-release` solo tag+build. |
| R21 | Trigger CI + branch policy por `branching.estrategia` | 🟡 | push-directo (github-flow-simplificado/trunk/developer) → `[main]` sin policy. con-PR (gitflow/release-flow/oneflow/gitlab-flow) → +ramas +recomendar policy. `pr:none` siempre (PR triggers por branch policy UI, no YAML). |
| R22 | Gate ciberseguridad multi-capa (verdict-file) | 🟡 | `security-scan.ps1` en Build (no tumba, `continueOnError`). DeployDemo/Prod bloquean por severidad. 4 checks: deps vulnerables / secretos / hardening / SAST CA3xxx-CA5xxx. Excepciones `04_Pruebas/.security-exceptions.yml`. N/A en Variante C (.NET-tool). |
| R23 | Config por entorno netfx (transforms → HIBRIDO) | 🟡 | `XmlVariableSubstitution` solo cubre appSettings/connectionStrings. Con transforms `Web.<Config>.config`: build-por-configuracion (un VSBuild+paquete por entorno, `drop-<env>`) + VG solo para secretos. Gotchas: `Any CPU` vs `AnyCPU`, `--` en comentarios XML, copiar transforms VERBATIM. |
| R24 | Deploy branch-gated (`DeployEnv` + `Build.SourceBranch`) | 🟡 | 3er modelo P2-bis para ramas por entorno (gitlab-flow/gitflow): cada Deploy exige DeployEnv Y rama correcta (Dev/Demo←develop, Prod←main). netfx: 3 VSBuild condicionales por rama → drop-dev/pre/pro. `/cicd-deploy` deriva la rama del entorno. |
| R25 | Un pipeline por entrypoint + routing apps/servicios | 🟡 | 1 repo = 1 solución con N entrypoints. **Fase 2** genera 1 pipeline por entrypoint desplegable (Web→`app`, API→`svc`/`app`) + Console CI-only; **Fase 1** = 1 build de solución (los desplegables quedan `fase:0`). Routing: Web/APIs públicas→Aplicaciones, APIs privadas→Servicios, vía `DeployTarget=<env>-<app|svc>`. >1 entrypoint → `azure-pipelines.<slug>.yml` + def `<PROYECTO>-<slug>`. |

## Politica LLM al editar YAML

1. **NUNCA emitir** features 🔴 HARD. Si el usuario lo pide explicito, RECHAZAR + proponer alternativa.
2. **AVISAR** al usar features 🟡 SOFT.
3. **CITAR** la regla (R_N_) en cada warning/sugerencia.
4. **NO refactorizar masivamente** sin pedirlo el usuario (drift). Proponer fix incremental en proxima edicion.

## Cuando revisar/relajar

| Trigger | Que reactivar |
|---|---|
| Migracion TFS 2022+ | R5 (`Cache@2` vuelve), R7 (workaround paths puede no aplicar) |
| Adopcion Azure DevOps Services cloud | Todas las reglas TFS 2020 |
| Nuevo stack (Angular/React/Java) | Anadir R10/R11/R12 specifics |

---

*Referencia rapida v3.13.0 — Para detalle: `.claude/rules/cicd-runtime.md`*
