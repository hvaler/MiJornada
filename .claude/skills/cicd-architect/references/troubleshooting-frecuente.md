# Troubleshooting CI/CD — Azure DevOps Server 2020 (variant server-2020) — Tabla rapida

> 30+ sintomas → causa → fix. Para detalle ver `.claude/rules/cicd-runtime.md` y `Documentos_Base/08_CICD/LIMITACIONES_TFS_2020.md`.

## YAML schema rechaza

| Sintoma exacto | Regla | Fix |
|---|---|---|
| `Unexpected value 'deploymentGroup'` | R1 | Usar `pool: { name: BUILDERS, demands: [...] }` con capability custom `DeployTarget=<env>` |
| `pool.name 'X' must refer to organization agent pools of type Automation` | R1 | Pool tipo `automation` (BUILDERS) unicamente. NO Deployment Pool |
| `TF400898: Pipeline caching is not enabled` | R5 | Eliminar `Cache@2`. Servicio no existe TFS 2020. `npm ci` limpio acepta los ~30-60s extra |
| `Cannot bind argument to parameter 'environmentName'` | R4 | Cambiar `IISWebAppDeployment@1` → `IISWebAppDeploymentOnMachineGroup@0` |

## SSL / TLS / Network

| Sintoma exacto | Regla | Fix |
|---|---|---|
| `The underlying connection was closed: An unexpected error occurred on a send` | R2 | Bloque TLS 1.2+ al inicio del step PS: `[Net.ServicePointManager]::SecurityProtocol = Tls12 -bor Tls13` (con try/catch para fallback Tls12 si .NET Framework < 4.8) |
| `unable to get local issuer certificate` en `DownloadBuildArtifacts@0` | R3 | Usar REST API + PowerShell. PS usa Windows Cert Store y bypasea bug Node.js |
| `Could not establish trust relationship for the SSL/TLS secure channel` | R2/R9 | Cert no en Windows Cert Store. Pedir a Sistemas añadir cert raiz. NO bypass global |
| `Invoke-WebRequest -SkipCertificateCheck` no reconocido | R2 | Param solo PS 7+. En 5.1 usar callback `ServicePointManager.ServerCertificateValidationCallback` cuando sea estrictamente necesario (R9) |
| Smoke timeout o SNI mismatch contra `https://localhost/<app>` desde el server | R9/R11 | Cert es para FQDN publico, no localhost. Bypass solo aqui (R9). Si SPA, smoke best-effort (R11) sin throw |
| Hairpin NAT: `https://pre.example.org/<app>` desde el propio server timeout | R11 | El firewall corporativo no permite host llamarse a si mismo via FQDN publico. Smoke best-effort SPA, NO throw |

## Deploy / MSDeploy

| Sintoma exacto | Regla | Fix |
|---|---|---|
| `One or more files locked` durante MSDeploy | R10 | `.NET ASP.NET Core in-process` requiere `TakeAppOfflineFlag: true` para liberar locks DLL |
| `app_offline.htm` residual sirviendo 503 indefinidamente tras deploy interrumpido | R10 | SPA estatica NUNCA usa `TakeAppOfflineFlag: true`. Cambiar a `false` |
| Permission denied al copiar a `C:\inetpub\wwwroot\<app>` | R6 | Cuenta del agente debe ser `NT AUTHORITY\SYSTEM`. NO `NETWORK SERVICE` |
| `Could not find a part of the path '<wwwroot>'` | — | Path IIS site no existe. Pedir a Sistemas crear site en TFS UI |
| MSDeploy timeout en backup grande | R15 | Aumentar `timeoutInMinutes` del job. Considerar `Robocopy` con `/MT:N` paralelo para backups muy grandes |

## Triggers

| Sintoma exacto | Regla | Fix |
|---|---|---|
| Trigger CI no dispara tras push a master | R7 | Bug TFS 2020 `settingsSourceType=2`. Emitir AMBOS patrones: `'<dir>/**'` Y `'<dir>/**/*'`. Whitelist invariante del ecosistema: `03_Desarrollo/**`, `04_Pruebas/**`, `azure-pipelines.yml` |
| Push tocando un solo archivo profundo NO dispara, mismo push tocando `azure-pipelines.yml` SI | R7 | Mismo bug. Verifica `paths.include` tiene ambos patrones |
| Trigger dispara para cada PR — quiero solo master | — | `pr: none` en el YAML. PR triggers gestionados por branch policy en TFS UI |

## Variable Groups / Secretos

| Sintoma exacto | Regla | Fix |
|---|---|---|
| Build pasa pero la app falla en runtime con `null reference` en config | R16 | Secretos vacios en VG. Anadir fail-fast pre-build que valide `(Get-Item env:X).Value` no este empty |
| Variable del VG no visible en el step | R16 | VG no autorizado al pipeline. TFS UI → pipeline → "Pipeline permissions" → autorizar VG. O hacer build una vez con error y "Authorize resources" |
| Secret aparece literal en logs | R16 | El VG tiene la variable como secret pero el step la imprime con `Write-Host $env:X`. Nunca printar. Si necesario para debug, `Write-Host "tiene valor: $([bool]$env:X)"` |

## Coverage / Tests

| Sintoma exacto | Regla | Fix |
|---|---|---|
| `PublishCodeCoverageResults@2` da resultado inconsistente | R4 | Usar `@1` con `codeCoverageTool: Cobertura` |
| Cobertura aparece 0% pese a tests verde | — | Verificar `--collect:"XPlat Code Coverage"` o `coverlet.runsettings`. Para Vue, Vitest `reporter: ['cobertura']` |
| Coverage gate (R18) avisa/bloquea por cobertura baja | R18 | Subir cobertura de tests, o ajustar `coverageLineThreshold`/`coverageBranchThreshold`. WARN-first no bloquea por defecto. Invocar `mira` (NO `dotnet mira`). Mira 0.8.1 NO tiene CRAP |
| Tests pasan local pero fallan en CI con `Connection refused localhost:5000` | R12.4 | Tests con localhost hardcoded. Usar `WebApplicationFactory<Program>` |

## Path / Environment / Build vars

| Sintoma exacto | Regla | Fix |
|---|---|---|
| `Could not load file C:\Repos\OtroProyecto\Lib.dll` | R12.2 | `HintPath` absoluto en `.csproj`. Cambiar a NuGet o referencia relativa al solution |
| `vite build` produce paginas vacias en CI pero llenas en local | R12.1 | `vite.config.ts` referencia paths absolutos a otros repos. Versionar contenido en el propio repo |
| Test usa `Environment.GetEnvironmentVariable("X")` que viene null | R12.5 | Sin default. `var x = Environment.GetEnvironmentVariable("X") ?? "test-default"` |
| Build agente falla con `The .NET SDK is not installed for X.Y.Z` | R12.6 | `<TargetFramework>` exigido no instalado en LADYADA. Coordinar con Sistemas para anadir SDK o degradar version |

## Idempotencia / Edicion

| Sintoma exacto | Regla | Fix |
|---|---|---|
| Re-ejecutar `/cicd-init` borra mi step manual | R14 | Envolver el step manual entre `# CUSTOM: descripcion` y `# /CUSTOM`. FASE 0.5 lo preserva literal |
| `azure-pipelines.yml.bak.*` se acumulan | — | Limpiar periodicamente. No commit. `.gitignore`: `azure-pipelines.yml.bak.*` |
| Pipeline TFS quedo registrado con nombre antiguo tras renombrar repo | — | Borrar pipeline en TFS UI + `/cicd-init` modo edicion opcion 4. O renombrar manualmente en TFS UI |

## Otros

| Sintoma exacto | Regla | Fix |
|---|---|---|
| `Access denied. <user> needs Manage permissions for pool BUILDERS` | C1-C2 | Escalar a Sistemas / admin del pool BUILDERS |
| Wizard agente `config.cmd` pide password para `NT AUTHORITY\SYSTEM` | R6 | Se respondio Enter en "ejecutar como servicio?". Ctrl+C, `config.cmd remove`, volver a `config.cmd` y responder `S` explicito |
| Latencia 5-10 min entre push y dispatch del build | — | Normal en TFS 2020 self-hosted. NO encolar manual (memoria `feedback_no_manual_queue`). Esperar |
| `git push` exito pero TFS no muestra el build | C4 | "Conceder permiso a todas las canalizaciones" NO activado en BUILDERS. TFS UI → Project Settings → Agent pools → BUILDERS → Security → autorizar |

---

*Troubleshooting v3.11.0 — Para detalle por regla: `.claude/rules/cicd-runtime.md`*
