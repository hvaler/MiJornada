# TFS 2020 quick reference

> Resumen consulta rapida. Detalle completo en `.claude/rules/tfs-2020-limitations.md` y `Documentos_Base/08_CICD/LIMITACIONES_TFS_2020.md`.

## NUNCA emitir (🔴 HARD)

| Item | Por que | Alternativa |
|---|---|---|
| `Cache@2` | Servicio Pipeline Caching no existe | `npm ci` / `dotnet restore` limpio |
| `IISWebAppDeployment@1` | Preview deprecated | `IISWebAppDeploymentOnMachineGroup@0` |
| `DownloadBuildArtifacts@0` / `DownloadPipelineArtifact@2` | Bug SSL Node.js | REST API + PowerShell |
| `deploymentGroup:` | Schema rechaza | `pool: { name: BUILDERS, demands: [...] }` con capability `DeployTarget=<env>` |
| `pool.name:` apuntando a Deployment Pool | API rechaza | Pool tipo `automation` (BUILDERS) unicamente |
| `api-version=7.0` | Maximo TFS 2020 = `6.0` | `api-version=6.0` (o `5.1-preview` para `/_apis/work/*`) |

## AVISAR (🟡 SOFT)

| Item | Comportamiento | Alternativa preferida |
|---|---|---|
| `strategy: canary` | Sintaxis aceptada, comportamiento no garantizado | Multiples jobs en serie con `dependsOn` + `condition: succeeded()` |
| `strategy: rolling` con `maxParallel` | Limitado | Jobs explicitos serie (patron PROD A/B) |
| `extends: template@<repo-externa>` | Repos externos pueden fallar | Templates locales en el mismo repo |
| `PublishCodeCoverageResults@2` | Inputs cambiados, inconsistente | `@1` con `codeCoverageTool: Cobertura` |
| `UseNode@1` | Sintaxis distinta canonica | `NodeTool@0` con `versionSpec: '<v>.x'` |
| `trigger.paths.include` con solo `'<dir>/**'` | Bug subdirectorios profundos | Emitir AMBOS: `'<dir>/**'` Y `'<dir>/**/*'` (R7) |

## Funciona sin restricciones (🟢 OK)

- Multi-stage YAML (`stages:`, `dependsOn`, `condition`)
- `variables: - group: <name>` (Variable Groups Library)
- `template:` local (mismo repo)
- `parameters:` con valores escalares
- `${{ if }}` y `${{ each }}` basicos
- `pool: server` para server jobs (ManualValidation@0)
- `environment:` para approval gates con `deployment:` jobs
- Approval checks por grupos TFS
- `displayName`, `condition`, `continueOnError` en cualquier step
- PowerShell inline con `$(System.AccessToken)`

## PowerShell 5.1 gotchas (agente Windows Server)

| Sintoma | Fix obligatorio al inicio del script |
|---|---|
| `The underlying connection was closed` HTTPS | Bloque TLS 1.2+ (R2) |
| `Out-File` default UTF-16 BOM | `-Encoding UTF8` explicito (R13) |
| `Invoke-WebRequest -SkipCertificateCheck` no reconocido | Param solo PS 7+, usar callback ServicePointManager (R9) |
| `ConvertFrom-Json` con duplicados falla | Limpiar JSON o `[Newtonsoft.Json.Linq.JObject]::Parse()` |

## APIs REST utiles

| Endpoint | Uso | Notas |
|---|---|---|
| `/_apis/connectionData` | Detectar version TFS | api-version=6.0 |
| `/<col>/_apis/projects/<proj>` | Verificar acceso | 200 OK = usuario reconocido + acceso lectura |
| `/_apis/distributedtask/pools` | Listar pools | Filtrar `poolType=automation` |
| `/_apis/distributedtask/pools/<id>/agents?includeCapabilities=true` | Agentes + capabilities | Filtrar `userCapabilities.DeployTarget=<env>` |
| `/<col>/<proj>/_apis/distributedtask/queues` | Queue id de BUILDERS per-proyecto | `pool.name=BUILDERS` |
| `/<col>/<proj>/_apis/build/definitions` (POST) | Crear pipeline | `process.type=2` (YAML) |
| `/<col>/<proj>/_apis/distributedtask/variablegroups` (POST) | Crear VG | `type=Vsts`, variables con `isSecret=true` |
| `/<col>/<proj>/_apis/git/repositories` | Listar repos | Para descubrir `repositoryId` |

---

*Quick ref v3.11.0 — Detalle: `.claude/rules/tfs-2020-limitations.md` Tabla A-F*
