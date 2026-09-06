#Requires -Version 5.1
<#
.SYNOPSIS
    Productor de Registros de Documentacion de Agente (DOC) del ecosistema Ovillo.
    Lee los docs de agente ya generados por /analisis-arquitectura --agente, calcula su
    frescura contra el codigo fuente (drift) y su coste de contexto (tokens estimados), y
    publica el DOC en el Hub (POST /v2/sync/docs-batch) para el dashboard del portfolio.

.DESCRIPTION
    SOLO-LECTURA del codigo y del doc: NO deriva ni escribe la documentacion (eso es
    /analisis-arquitectura --agente). Cada doc de agente lleva en cabecera un sello
    '<!-- Ovillo docs-agente <entrypoint> @ vX.Y.Z (src <hash12>) gen <fecha> -->'.
    El script recomputa el hash del subarbol de fuente del entrypoint con el MISMO helper
    que el CI/CD (Get-TemplateStamp.ps1, ADR-047), lo compara con el sello -> fresh/stale,
    estima el coste de contexto (bytes/4), evalua el gate (WARN si stale/orphan/over-budget),
    numera DOC-nnn secuencial y hace el POST al Hub (UPSERT por ProyectoId+Codigo).

    NO reemplaza documentacion-tecnica (docs de desarrollador) ni user-documentation.
    NO inlina nada en CLAUDE.md (prohibido por context-optimization): el doc se referencia.

.NOTES
    ASCII puro (PS 5.1 lee .ps1 sin BOM como CP1252 -> no usar acentos ni em-dash).
    Auth: service-key per-proyecto (ADR-045) en X-Hub-Api-Key, NUNCA hardcodeada ni pasada
    a mano fuera de CI (queda en PSReadLine / transcripts de agentes). Resolucion:
    -ApiKey (CI, VG R16) > DPAPI file por-proyecto > DPAPI file generico >
    apiKey per-dev del repo > env HUB_SERVICE_KEY. Alta segura: -StoreKey.
    Best-effort: si el hub no expone /v2/sync/docs-batch o el POST falla, no rompe el build.
#>

[CmdletBinding()]
param(
    [string]   $ProjectId,                                     # GUID del proyecto en el hub (obligatorio salvo -StoreKey)
    [string]   $ApiKey,                                        # service-key (ADR-045). OPCIONAL: ver cadena de resolucion
    [switch]   $StoreKey,                                      # alta segura de la key en esta maquina (prompt oculto, DPAPI) y salir
    [string]   $ServerUrl      = 'https://hub.example.org',
    [string]   $DocsDir        = 'docs/agente',                # carpeta con los docs de agente sellados
    [string]   $SourceRoot     = '03_Desarrollo',             # raiz del codigo fuente (para recomputar el srcStamp)
    [string]   $StampHelper    = $null,                        # ruta a Get-SourceStamp.ps1 (autodetect junto al script si null)
    [int]      $TokenBudget    = 4000,                         # umbral de tokens del gate (WARN si el doc lo supera)
    [string]   $CodeSearchBase = $null,
    [string]   $BuildId        = $null,
    [string[]] $AdrRelacionados = @(),
    [switch]   $DryRun
)

$ErrorActionPreference = 'Stop'

# --- R2: TLS 1.2+ (PS 5.1 negocia TLS 1.0 por defecto; demowww exige 1.2+) ---
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
} catch {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

function Write-Info($m) { Write-Host "[docs-sync] $m" }
function Write-Warn($m) { Write-Warning "[docs-sync] $m" }

# --- -StoreKey: alta segura per-user (DPAPI), sin dejar la key en la linea de comandos ---
if ($StoreKey) {
    $sec = Read-Host -AsSecureString "Service-key del Hub (no se mostrara)"
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
    $enc = ConvertFrom-SecureString (ConvertTo-SecureString $plain -AsPlainText -Force)
    $dir = Join-Path $env:LOCALAPPDATA 'Ovillo'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $file = if ($ProjectId) { "hubkey.$ProjectId.dpapi" } else { 'hubkey.dpapi' }
    Set-Content -Path (Join-Path $dir $file) -Value $enc -Encoding ASCII
    Write-Info "Key almacenada (DPAPI per-user) en $dir\$file"
    exit 0
}

if (-not $ProjectId) { Write-Error "[docs-sync] -ProjectId es obligatorio (salvo -StoreKey)."; exit 1 }

# --- Cadena de resolucion de la service-key (ADR-045) ---
function Resolve-ApiKey {
    param($Explicit, $ProjectId)
    if ($Explicit) { return $Explicit }                                   # 1. CI (VG R16)
    $dir = Join-Path $env:LOCALAPPDATA 'Ovillo'
    foreach ($f in @("hubkey.$ProjectId.dpapi", 'hubkey.dpapi')) {        # 2-3. DPAPI por-proyecto / generico
        $p = Join-Path $dir $f
        if (Test-Path $p) {
            try {
                $s = ConvertTo-SecureString (Get-Content $p -Raw)
                return [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))
            } catch { }
        }
    }
    $cred = '_hilo/.mcp-credentials.json'                                 # 4. apiKey per-dev del repo
    if (Test-Path $cred) {
        try { $j = Get-Content $cred -Raw | ConvertFrom-Json; if ($j.apiKey) { return $j.apiKey } } catch { }
    }
    if ($env:HUB_SERVICE_KEY) { return $env:HUB_SERVICE_KEY }    # 5. env
    return $null
}

# --- Recomputar el hash del subarbol de fuente del entrypoint (usa el helper Get-SourceStamp) ---
# CRITICO: debe coincidir byte-a-byte con lo que sella /analisis-arquitectura --agente. Ambos
# lados llaman al MISMO Get-SourceStamp.ps1; el fallback inline replica su algoritmo EXACTO
# (normalizacion EOL CR/CRLF->LF por fichero + separador 0x0A + orden ordinal + excluir bin/obj).
function Convert-ToLfBytes([byte[]] $raw) {
    $out = New-Object System.Collections.Generic.List[byte]
    for ($i = 0; $i -lt $raw.Length; $i++) {
        $b = $raw[$i]
        if ($b -eq 0x0D) { $out.Add([byte]0x0A); if (($i + 1) -lt $raw.Length -and $raw[$i + 1] -eq 0x0A) { $i++ } }
        else { $out.Add($b) }
    }
    , $out.ToArray()
}
function Get-SourceStamp {
    param($EntryPath, $Helper)
    if ($Helper -and (Test-Path $Helper)) {
        try { $h = & $Helper -Path $EntryPath 2>$null | Select-Object -Last 1; if ($LASTEXITCODE -eq 0 -and $h) { return $h } } catch { }
    }
    # Fallback inline: IDENTICO a Get-SourceStamp.ps1 (para coincidir con el sello aunque falte el helper)
    $files = Get-ChildItem -LiteralPath $EntryPath -Recurse -File -Include *.cs,*.csproj -EA SilentlyContinue |
             Where-Object { $_.FullName -notmatch '[\\/](bin|obj)[\\/]' } | Sort-Object -Property FullName -Culture ''
    if (-not $files) { return $null }
    $acc = New-Object System.Collections.Generic.List[byte]
    foreach ($f in $files) { $acc.AddRange((Convert-ToLfBytes ([IO.File]::ReadAllBytes($f.FullName)))); $acc.Add([byte]0x0A) }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hb = $sha.ComputeHash($acc.ToArray()) } finally { $sha.Dispose() }
    (-join ($hb | ForEach-Object { $_.ToString('x2') })).Substring(0, 12)
}

# --- Autodetect del helper de sello (hermano de este script) ---
if (-not $StampHelper) {
    $cand = Join-Path $PSScriptRoot 'Get-SourceStamp.ps1'
    if (Test-Path $cand) { $StampHelper = $cand }
}

if (-not (Test-Path $DocsDir)) {
    Write-Warn "No existe '$DocsDir'. Genera el contexto primero: /analisis-arquitectura --agente. (best-effort, salida 0)"
    exit 0
}

# --- Version del ecosistema instalada (para 'generadoCon') ---
$eco = $null
if (Test-Path '_hilo/VERSION.json') {
    try { $eco = (Get-Content '_hilo/VERSION.json' -Raw | ConvertFrom-Json).installedVersion } catch { }
}

# --- Descubrir docs + construir los DOC ---
$stampRx = '(?i)Ovillo docs-agente\s+(?<ep>\S+)\s+@\s+v?(?<ver>[0-9][^\s]*)\s+\(src\s+(?<src>[0-9a-f]{6,64})\)'
$docs = Get-ChildItem $DocsDir -Recurse -File -Include *.md -EA SilentlyContinue
if (-not $docs) { Write-Warn "'$DocsDir' no tiene docs .md. Nada que sincronizar (best-effort)."; exit 0 }

$records = @()
foreach ($d in $docs) {
    $head = (Get-Content $d.FullName -TotalCount 5 -EA SilentlyContinue) -join "`n"
    $m = [regex]::Match($head, $stampRx)
    if (-not $m.Success) {
        Write-Warn "Doc sin sello docs-agente: $($d.Name) -> re-generar con /analisis-arquitectura --agente. Se omite."
        continue
    }
    $entrypoint = $m.Groups['ep'].Value
    $srcStampDoc = $m.Groups['src'].Value
    $entryPath = Join-Path $SourceRoot $entrypoint
    $srcStamp = if (Test-Path $entryPath) { Get-SourceStamp -EntryPath $entryPath -Helper $StampHelper } else { $null }

    $drift = if (-not $srcStamp) { 'orphan' } elseif ($srcStamp -eq $srcStampDoc) { 'fresh' } else { 'stale' }
    $bytes = (Get-Item $d.FullName).Length
    $tokens = [int]([math]::Ceiling($bytes / 4))
    $gate = if ($drift -ne 'fresh' -or $tokens -gt $TokenBudget) { 'WARN' } else { 'PASS' }

    $records += [ordered]@{
        entrypoint       = $entrypoint
        docPath          = (Resolve-Path -Relative $d.FullName) -replace '\\', '/'
        srcStamp         = $srcStamp
        srcStampDoc      = $srcStampDoc
        drift            = $drift
        tokensEstimados  = $tokens
        gate             = $gate
        generadoCon      = $eco
        adrRelacionados  = $AdrRelacionados
        codeSearchUrl    = if ($CodeSearchBase) { "$CodeSearchBase$entrypoint" } else { $null }
    }
    Write-Info ("{0,-24} drift={1,-6} tokens={2,-5} gate={3}" -f $entrypoint, $drift, $tokens, $gate)
}

if (-not $records) { Write-Warn "Ningun doc con sello valido. Nada que publicar (best-effort)."; exit 0 }

# --- Numeracion DOC-nnn secuencial (mejor esfuerzo; el hub reafirma en el UPSERT) ---
$key = Resolve-ApiKey -Explicit $ApiKey -ProjectId $ProjectId
$headers = @{ 'Content-Type' = 'application/json' }
if ($key) { $headers['X-Hub-Api-Key'] = $key }

$next = 1
try {
    $stats = Invoke-RestMethod -Uri "$ServerUrl/v2/stats/docs/$ProjectId" -Headers $headers -Method GET -TimeoutSec 15
    if ($stats.ultimoNumero) { $next = [int]$stats.ultimoNumero + 1 }
} catch {
    Write-Warn "No se pudo leer el ultimo DOC ($($_.Exception.Message)). Se numera desde DOC-001 (el hub reafirma)."
}
$i = 0
foreach ($r in $records) { $r.codigo = ('DOC-{0:000}' -f ($next + $i)); $i++ }

$payload = [ordered]@{
    proyectoId = $ProjectId
    buildId    = $BuildId
    generados  = $records
} | ConvertTo-Json -Depth 8

if ($DryRun) { Write-Info "DryRun: payload calculado (NO se envia):"; Write-Host $payload; exit 0 }

if (-not $key) { Write-Warn "Sin service-key resoluble (ADR-045). No se publica. Usa -StoreKey o corre 'irm | iex' en el clon. [SKIP]"; exit 0 }

# --- POST best-effort: la doc NO debe tumbar CI ---
try {
    $resp = Invoke-RestMethod -Uri "$ServerUrl/v2/sync/docs-batch" -Headers $headers -Method POST -Body $payload -TimeoutSec 30
    Write-Info "Publicados $($records.Count) DOC en el Hub. (respuesta: $($resp.status))"
} catch {
    $code = $null; try { $code = [int]$_.Exception.Response.StatusCode } catch { }
    if ($code -eq 404) { Write-Warn "El hub no expone /v2/sync/docs-batch (tool register_agentdoc no desplegada). Ver references/hub-contract.md. [SKIP]" }
    elseif ($code -eq 401) { Write-Warn "401: service-key rotada/revocada. En CI actualiza la VG; en local re-'-StoreKey'. [FAIL]" }
    else { Write-Warn "POST fallo ($($_.Exception.Message)). No rompe el build. [FAIL]" }
    exit 0
}
