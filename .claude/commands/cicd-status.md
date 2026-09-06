# /cicd-status — Estado del pipeline CI/CD del proyecto

> CLI local para ver estado del pipeline registrado: últimos builds, tiempos por stage, cobertura trend, links TFS.
> Para Fase 0 (sin pipeline): muestra recordatorio de deploy manual.

---

## REGLAS CRÍTICAS

- Leer `_hilo/ESTADO_PROYECTO.json.infraestructura.cicd[]` PRIMERO. Si vacío → no hay pipeline configurado.
- Si fase = 0: NO consultar Hub MCP. Solo recordar deploy manual.
- Si fase ≥ 1: intentar tool MCP `get_cicd_status`. Si Hub no responde, fallback a `/_apis/build/builds` directo del TFS.
- Modo `--watch` opcional para polling cada 30s.

---

## 1. Detectar configuración CI/CD del proyecto

```powershell
$estado = Get-Content "_hilo/ESTADO_PROYECTO.json" -Raw | ConvertFrom-Json
$cicd = $estado.infraestructura.cicd

if (-not $cicd -or $cicd.Count -eq 0) {
    Write-Host "ℹ️  No hay pipeline CI/CD configurado en este proyecto."
    Write-Host "   Ejecuta /cicd-init para configurar (Fase 0/1/2)."
    exit 0
}

# R25: cicd[] tiene una entrada por ENTRYPOINT (1 pipeline = 1 entrypoint). Por defecto mostrar TODOS;
# con --entrypoint <slug> filtrar a uno. (NO usar Out-GridView: el comando corre headless.)
$pipelines = if ($Entrypoint) { $cicd | Where-Object { $_.entrypoint -eq $Entrypoint } } else { @($cicd) }
# Repetir las secciones 2-4 (builds, stages, drift) POR CADA $pipeline de $pipelines, encabezando con
# su entrypoint + tipo + serverType (app/svc) para distinguir Web / API / Console en el output.
```

---

## 1.5 Drift de plantilla (sello del YAML vs versión instalada)

Si existe `azure-pipelines.yml`, comprobar si el **template del stack** cambió desde que se generó el
YAML. El YAML lleva un sello en la cabecera (`# Ovillo cicd-architect <stack> @ vX.Y.Z (tpl <hash12>) gen <fecha>`,
puesto por `/cicd-init` FASE 2.8). El token `tpl <hash12>` es el **hash de contenido del `.yml.template`
del stack** (ADR-047), NO el zip-sha del ecosistema: así el drift solo salta cuando el template de TU
stack cambió realmente, no en cada release. Se recomputa con el **mismo helper** que usó `/cicd-init`
(`Get-TemplateStamp.ps1`) y se compara.

> Sellos en formato antiguo `zip <sha12>` (pipelines generados antes de v3.14.0-h1): no se evalúa drift
> cosmético; se sugiere re-render (Opción 4) para migrarlos a `tpl <hash>`.

```powershell
# R25: con >1 entrypoint hay varios azure-pipelines.<slug>.yml -> comprobar drift en CADA uno
foreach ($yf in (Get-ChildItem -File azure-pipelines*.yml -ErrorAction SilentlyContinue)) {
    $yamlPath = $yf.FullName
    Write-Host "  -- $($yf.Name) --"
    $head = Get-Content $yamlPath -TotalCount 8
    $stampLine = $head | Where-Object { $_ -match 'Ovillo cicd-architect' } | Select-Object -First 1

    $instVer = $null
    if (Test-Path "_hilo/VERSION.json") {
        $instVer = (Get-Content "_hilo/VERSION.json" -Raw | ConvertFrom-Json).installedVersion
    }
    $helper = ".claude/skills/cicd-architect/templates/Get-TemplateStamp.ps1"

    if (-not $stampLine) {
        Write-Host "[!] El pipeline no tiene sello de plantilla (generado con /cicd-init < v3.13.0-h13)."
        Write-Host "    Regenerar: /cicd-init -> Opcion 4 (re-render + self-check)."
    }
    elseif ($stampLine -match 'tpl\s+inline') {
        Write-Host "[i] Pipeline inline (Fase 1 minimal, sin .template): drift de plantilla no aplicable."
    }
    elseif ($stampLine -match 'tpl\s+([0-9a-f]{6,64})') {
        $stampHash = $Matches[1]
        $stack = if ($stampLine -match 'cicd-architect\s+(\S+)\s+@') { $Matches[1] } else { $null }
        $curHash = $null
        if ($stack -and (Test-Path $helper)) {
            try {
                $curHash = (& $helper -Stack $stack 2>$null | Select-Object -Last 1)
                if ($LASTEXITCODE -ne 0) { $curHash = $null }
            } catch { $curHash = $null }
        }
        if (-not $curHash) {
            Write-Host "[i] Sello hash-de-template (tpl $stampHash) pero no se pudo recomputar (helper ausente o stack '$stack' desconocido)."
            Write-Host "    Plantilla instalada: v$instVer. Ante la duda: /cicd-init -> Opcion 4."
        }
        elseif ($curHash -eq $stampHash) {
            Write-Host "[OK] Pipeline al dia con la plantilla instalada (sin drift; tpl $stampHash)."
        }
        else {
            Write-Host "[!] DRIFT de plantilla: el template del stack '$stack' cambio desde que se genero el YAML."
            Write-Host "      Sello del pipeline: tpl $stampHash"
            Write-Host "      Template actual:    tpl $curHash  (v$instVer)"
            Write-Host "    El pipeline puede no incluir lo ultimo (reglas/gates/steps nuevos)."
            Write-Host "    Accion: /cicd-init -> Opcion 4 (re-render COMPLETO) + self-check (FASE 2.8)."
        }
    }
    elseif ($stampLine -match 'zip\s+[0-9a-f]{6,40}') {
        Write-Host "[i] Sello en formato antiguo (zip-sha del ecosistema, pre-v3.14.0-h1)."
        Write-Host "    Re-render (/cicd-init -> Opcion 4) para migrarlo a hash-por-template (drift fiable, ADR-047)."
    }
    else {
        Write-Host "[i] Sello presente pero sin token de hash reconocible: $stampLine"
    }
}
```

Mostrar este aviso ANTES del listado de builds. Es informativo (no bloquea). Ver runbook
`Documentos_Base/08_CICD/RUNBOOK_ACTUALIZAR_PIPELINE.md`.

---

## 2. Bifurcar por fase

### Si fase = 0

```
═══════════════════════════════════════════════════════════════════════
                      ESTADO CI/CD — <PROYECTO_NOMBRE>
═══════════════════════════════════════════════════════════════════════

Fase de adopción:   0 — Deploy manual

Este proyecto NO tiene pipeline TFS configurado. Los deploys se hacen
manualmente siguiendo el runbook documentado.

📖 Guía: 05_CICD/RUNBOOK_DEPLOY_MANUAL.md
🔄 /verify  ← ejecutar ANTES de cada push (pre-flight 7 fases)

Para promocionar a Fase 1 (build validation) cuando Sistemas autorize
BUILDERS al proyecto + BUILD01 online → ejecutar /cicd-init
═══════════════════════════════════════════════════════════════════════
```

### Si fase ≥ 1 — Invocar tool MCP `get_cicd_status`

Intentar primero vía MCP (tool del Hub Ovillo):

```
Claude invoca: mcp__stic_ia_hub__get_cicd_status({
  projectId: "<projectId from _hilo/.mcp-project.json>"
})
```

Si Hub responde, parsear y mostrar tabla:

```
═══════════════════════════════════════════════════════════════════════
                      ESTADO CI/CD — <PROYECTO_NOMBRE>
═══════════════════════════════════════════════════════════════════════

Pipeline:           <PIPELINE_NAME>
Fase:               <1|2>
URL TFS:            <URL>
Stack:              <stack>
Última actualización (Hub): <fecha>

─── ÚLTIMOS 10 BUILDS ───────────────────────────────────────────────────

| # | Estado | Inicio              | Duración | Rama          | Commit  |
|---|--------|---------------------|----------|---------------|---------|
| 152 | ✅ OK | 2026-06-01 10:15:22 | 4m 12s   | main          | abc123f |
| 151 | ❌ FAIL | 2026-06-01 09:48:11 | 1m 33s   | feature/HV-19 | def456a |
| 150 | ✅ OK | 2026-05-31 17:30:05 | 4m 28s   | main          | 789bcde |
| ... |       |                     |          |               |         |

─── TIEMPO POR STAGE (último build OK) ──────────────────────────────────

| Stage         | Duración | % del total |
|---------------|----------|-------------|
| Build         | 2m 35s   | 61%         |
| DeployDev     | 0m 42s   | 17%         |
| DeployDemo    | 0m 50s   | 20% (incl. gate manual) |  [solo Fase 2]
| DeployProd    | 1m 22s   | (no en último build OK)  |  [solo Fase 2]

─── COBERTURA TREND (últimos 10 builds) ─────────────────────────────────

Line:   72.4% → 73.1% → 73.0% → 71.8% ⚠️ → 72.9% → 73.5% → 73.8% → 74.2% ✅
Branch: 64.2% → 64.8% → 64.7% → 63.5% ⚠️ → 64.6% → 65.1% → 65.4% → 65.9% ✅
Cobertura (line): 55% → 58% → 61% → 64% → 66% → 70% → 71% ✅

─── ÚLTIMO DEPLOY POR ENTORNO ───────────────────────────────────────────  [solo Fase 2]

| Entorno | Build  | Fecha               | Estado |
|---------|--------|---------------------|--------|
| DEV     | #152   | 2026-06-01 10:20:05 | ✅ OK  |
| DEMO    | #150   | 2026-05-31 17:35:12 | ✅ OK  |
| PROD    | #145   | 2026-05-28 19:42:33 | ✅ OK  |

═══════════════════════════════════════════════════════════════════════
🔗 Abrir en TFS:  <URL_TFS>
═══════════════════════════════════════════════════════════════════════
```

### Fallback si Hub no responde

Si tool MCP falla (Hub offline, conectividad), consultar TFS directamente:

```powershell
# [bloque TLS 1.2+ R2]
$headers = @{ Authorization = "Negotiate" }
$builds = Invoke-RestMethod -Uri "$tfsUrl/$proj/_apis/build/builds?definitions=$pipelineId&`$top=10&api-version=5.0" -UseDefaultCredentials
# ... formatear tabla similar al output anterior
```

Mostrar al usuario: `⚠️  Hub MCP no responde — datos de TFS directo (limitados, sin cobertura trend agregada).`

---

## 3. Modo --watch

Si el usuario invoca `/cicd-status --watch`:

```powershell
while ($true) {
    Clear-Host
    # Re-ejecutar el flujo de mostrar estado
    & $estadoCicdScript
    Write-Host ""
    Write-Host "🔄 Refresh cada 30s. Ctrl+C para salir." -ForegroundColor DarkGray
    Start-Sleep -Seconds 30
}
```

Útil durante un deploy en curso para ver progreso sin recargar TFS UI.

---

## 4. Opciones de salida (--format)

| Flag | Output |
|---|---|
| (default) | Tabla formato consola |
| `--format json` | JSON estructurado para parseo |
| `--format csv` | CSV para análisis batch |
| `--watch` | Polling cada 30s |
| `--last N` | Últimos N builds (default 10) |
| `--stage <name>` | Solo info del stage especificado |

---

## REFERENCIAS

- Comando que crea el pipeline: `/cicd-init`
- Tool MCP consumido: `get_cicd_status` (Hub Ovillo v1.1.0+)
- Datos persistidos en: `_hilo/ESTADO_PROYECTO.json.infraestructura.cicd[]`
- Skill complementaria: `hub-client` (para entender el catálogo MCP)
- Drift de plantilla (sección 1.5): sello puesto por `/cicd-init` FASE 2.8 (`Get-TemplateStamp.ps1`, hash-por-template ADR-047 / v3.14.0-h1) + self-check `validate-pipeline-complete.ps1` (h13)
- Runbook de actualización: `Documentos_Base/08_CICD/RUNBOOK_ACTUALIZAR_PIPELINE.md`
- ADR: `_estado/DECISIONES.md` ADR-042

---

*Comando Ovillo v3.11.0 — CLI local de estado CI/CD.*
