#Requires -Version 5.1
<#
.SYNOPSIS
    Productor de Registros de Calidad (QR) del ecosistema Ovillo.
    Calcula metricas de calidad desde el coverage OpenCover y las publica en el Hub
    (POST /v2/sync/quality-batch) para que el dashboard de calidad las muestre.

.DESCRIPTION
    SOLO-LECTURA del codigo: lee el coverage.opencover.xml que produce
    'dotnet test --collect "XPlat Code Coverage"' con el runsettings de la skill
    (Format=cobertura,opencover). De OpenCover saca, por metodo, complejidad
    ciclomatica + NPath + cobertura -> computa CRAP = comp^2 * (1 - cov)^3 + comp
    (igual que ReportGenerator), agrega el QR (CRAP max, metodos CRAPpy, ciclomatica
    media, NPath max, cobertura linea/rama, top-N hotspots, cobertura por clase/namespace),
    evalua el quality gate y hace el POST al Hub.

    NO reemplaza el gate de cobertura de Mira (R18) ni el analisis interactivo
    crap-analysis: produce los QR que consume el dashboard (hub v1.3.0+).

.NOTES
    ASCII puro (PS 5.1 lee .ps1 sin BOM como CP1252 -> no usar acentos ni em-dash).
    Auth: service-key per-proyecto (ADR-045) en X-Hub-Api-Key, NUNCA hardcodeada
    ni pasada a mano por linea de comandos fuera de CI (queda en PSReadLine y en
    transcripts de agentes IA - eval-gap ErpSync 2026-06-11). Resolucion:
    -ApiKey (CI, VG R16) > DPAPI file por-proyecto > DPAPI file generico >
    env HUB_SERVICE_KEY. Alta interactiva segura: -StoreKey (prompt oculto).
#>

[CmdletBinding()]
param(
    [string] $ProjectId,                                      # GUID del proyecto en el hub (obligatorio salvo -StoreKey)
    [string] $ApiKey,                                         # service-key (ADR-045). OPCIONAL: ver cadena de resolucion abajo
    [switch] $StoreKey,                                       # alta segura de la key en esta maquina (prompt oculto, DPAPI per-user) y salir
    [string] $ServerUrl       = 'https://hub.example.org',
    [string] $ResultsDir      = './TestResults',              # donde dotnet test dejo el coverage
    [string] $CodeSearchBase  = $null,                        # base ADO Code Search del repo (el dashboard concatena el fichero)
    [string] $BuildId         = $null,
    [int]    $CrapThreshold   = 30,
    [int]    $CoverageLineMin = 75,
    [int]    $CoverageBranchMin = 60,
    [int]    $TopHotspots     = 20,
    [int]    $TopClases       = 400,                          # tope de clases en el desglose (top por crapMax)
    [string[]] $AdrRelacionados = @(),
    [bool]   $CoberturaIntegracionMedida = $true,   # D2/FB-008: false si la integracion (WebApplicationFactory) NO se midio
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'

# --- R2: TLS 1.2+ (PS 5.1 negocia TLS 1.0 por defecto; demowww exige 1.2+) ---
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
} catch {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

function Write-Info($m) { Write-Host "[calidad-sync] $m" }
function Write-Warn($m) { Write-Warning "[calidad-sync] $m" }

# =============================================================================
# Service-key (ADR-045): cadena de resolucion + alta segura (-StoreKey)
# Origen: eval-gap ErpSync 2026-06-11 (la key acababa en el historial / transcript
# al ser -ApiKey mandatory). Almacen local: fichero DPAPI per-user (cifrado ligado
# a usuario+maquina, ConvertFrom-SecureString sin -Key) en %APPDATA%\Ovillo\.
# NUNCA pasar la key como argumento fuera de CI (queda en PSReadLine/transcripts).
# =============================================================================
$keyStoreDir = Join-Path $env:APPDATA 'Ovillo'
function Get-KeyFilePath([string]$pid_) {
    if ($pid_) { return (Join-Path $keyStoreDir "hub-service-key-$pid_.dat") }
    return (Join-Path $keyStoreDir 'hub-service-key.dat')
}
function Read-StoredKey([string]$path) {
    if (-not (Test-Path $path)) { return $null }
    try {
        $blob = (Get-Content -Path $path -Raw).Trim()                  # Trim: Set-Content anade newline final
        $sec = $blob | ConvertTo-SecureString                          # DPAPI per-user
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    } catch {
        Write-Warn "No se pudo descifrar '$path' (otro usuario/maquina? corrupto?). Re-ejecuta -StoreKey."
        return $null
    }
}

if ($StoreKey) {
    # Alta UNA vez por maquina. La key se teclea/pega en prompt oculto: no toca
    # historial ni linea de comandos. Con -ProjectId guarda la variante por proyecto
    # (gana sobre la generica); sin el, la generica.
    $target = Get-KeyFilePath $ProjectId
    $sec = Read-Host -Prompt 'Introduce la service-key del hub (sk_svc_...)' -AsSecureString
    if ($sec.Length -eq 0) { Write-Warn 'Key vacia, no se guarda nada.'; exit 1 }
    if (-not (Test-Path $keyStoreDir)) { New-Item -ItemType Directory -Path $keyStoreDir -Force | Out-Null }
    $sec | ConvertFrom-SecureString | Set-Content -Path $target -Encoding ASCII
    Write-Info "[OK] Guardada (DPAPI per-user) en: $target"
    Write-Info "Las proximas ejecuciones la resolveran solas (no vuelvas a pasar -ApiKey a mano)."
    exit 0
}

if (-not $ProjectId) {
    Write-Warn '-ProjectId es obligatorio (GUID del proyecto en el hub; ver _hilo/.mcp-project.json).'
    exit 1
}

# Cadena de resolucion (primera fuente que resuelva, gana):
#   1. -ApiKey explicito        -> CI (Variable Group secreta R16) u override puntual
#   2. DPAPI file por proyecto  -> %APPDATA%\Ovillo\hub-service-key-<ProjectId>.dat
#   3. DPAPI file generico      -> %APPDATA%\Ovillo\hub-service-key.dat
#   4. apiKey per-dev del repo  -> _hilo/.mcp-credentials.json (la crea irm|iex; el hub
#      la acepta en quality-batch y atribuye el QR al devAlias del dev en vez de 'ci').
#      Es el camino CERO-CONFIG para cualquier miembro del equipo ya registrado.
#   5. Env var                  -> HUB_SERVICE_KEY (entornos sin DPAPI store)
function Read-DevCredentialKey([string]$projectId_) {
    $credFile = Join-Path (Get-Location) '_hilo/.mcp-credentials.json'
    if (-not (Test-Path $credFile)) { return $null }
    try {
        $cred = Get-Content -Path $credFile -Raw | ConvertFrom-Json
        # Solo si el repo actual ES el proyecto target (no publicar con la identidad de otro repo)
        if ($cred.projectId -and ([string]$cred.projectId).ToLower() -ne $projectId_.ToLower()) { return $null }
        if ($cred.apiKey) {
            Write-Info 'Usando la apiKey per-dev de _hilo/.mcp-credentials.json (QR atribuido a tu devAlias).'
            return [string]$cred.apiKey
        }
    } catch { }
    return $null
}
if (-not $ApiKey) { $ApiKey = Read-StoredKey (Get-KeyFilePath $ProjectId) }
if (-not $ApiKey) { $ApiKey = Read-StoredKey (Get-KeyFilePath $null) }
if (-not $ApiKey) { $ApiKey = Read-DevCredentialKey $ProjectId }
if (-not $ApiKey -and $env:HUB_SERVICE_KEY) { $ApiKey = $env:HUB_SERVICE_KEY }
if (-not $ApiKey) {
    Write-Warn 'No se encontro credencial para el hub. Configura UNA de estas vias:'
    Write-Warn '  a) Cero-config (miembros del equipo): ejecuta irm|iex (arranque.ps1) en este repo -> crea _hilo/.mcp-credentials.json con tu apiKey per-dev'
    Write-Warn '  b) Service-key interactiva (una vez por maquina): .\Sync-QualityRecord.ps1 -StoreKey'
    Write-Warn '  c) CI: parametro -ApiKey leyendo la Variable Group secreta (R16), ej. -ApiKey $env:HUB_SERVICE_KEY'
    Write-Warn '  d) Fallback: variable de entorno HUB_SERVICE_KEY'
    Write-Warn 'Si recibes 401: key rotada/revocada -> pide la nueva al admin del hub y re-ejecuta -StoreKey (o re-irm|iex para la per-dev).'
    exit 1
}

# --- 1. Localizar TODOS los coverage.opencover.xml (solucion multi test-project -> varios) ---
$ocFiles = @(Get-ChildItem -Path $ResultsDir -Recurse -Filter 'coverage.opencover.xml' -ErrorAction SilentlyContinue)
if ($ocFiles.Count -eq 0) {
    Write-Warn "No se encontro coverage.opencover.xml bajo '$ResultsDir'. Asegura 'dotnet test' con la opcion collect XPlat Code Coverage + settings coverage.runsettings (Format=cobertura,opencover)."
    exit 1
}
Write-Info "OpenCover: $($ocFiles.Count) fichero(s) de cobertura"

# --- D2/FB-008: cobertura adicional formato Cobertura (dotnet-coverage) para metodos de integracion ---
# dotnet-coverage (profiler out-of-process) mide los tests WebApplicationFactory que Coverlet cuelga;
# emite formato Cobertura (line-rate por metodo/clase), NO opencover. Se pliega su cobertura en el
# merge (raise-only): cc/NPath siguen del opencover; la cobertura del metodo/clase SUBE si Cobertura
# la trae mayor. Recoge tambien el coverage.cobertura.xml de Coverlet (idempotente: mismos valores).
$cobMethodCov = @{}   # "ClassFull::MetodoCorto" -> max line-rate (0..100)
$cobClassCov  = @{}   # "ClassFull" -> @{ line; branch } (0..100, max)
$cobFiles = @(Get-ChildItem -Path $ResultsDir -Recurse -Filter '*.cobertura.xml' -ErrorAction SilentlyContinue)
foreach ($cf in $cobFiles) {
    try { [xml]$cdoc = Get-Content -Path $cf.FullName -Raw } catch { continue }
    foreach ($pkg in @($cdoc.coverage.packages.package)) {
        foreach ($ccls in @($pkg.classes.class)) {
            $cn = [string]$ccls.name
            if (-not $cn) { continue }
            $clLine = if ($ccls.'line-rate')   { [math]::Round([double]$ccls.'line-rate'   * 100, 1) } else { 0 }
            $clBr   = if ($ccls.'branch-rate') { [math]::Round([double]$ccls.'branch-rate' * 100, 1) } else { 0 }
            if (-not $cobClassCov.ContainsKey($cn)) {
                $cobClassCov[$cn] = [pscustomobject]@{ line = $clLine; branch = $clBr }
            } else {
                $cc = $cobClassCov[$cn]
                if ($clLine -gt $cc.line)   { $cc.line   = $clLine }
                if ($clBr   -gt $cc.branch) { $cc.branch = $clBr }
            }
            foreach ($cm in @($ccls.methods.method)) {
                $mn = [string]$cm.name
                if (-not $mn) { continue }
                $mLine = if ($cm.'line-rate') { [math]::Round([double]$cm.'line-rate' * 100, 1) } else { 0 }
                $mk = "$cn::$mn"
                if ((-not $cobMethodCov.ContainsKey($mk)) -or $mLine -gt $cobMethodCov[$mk]) { $cobMethodCov[$mk] = $mLine }
            }
        }
    }
}
if ($cobFiles.Count -gt 0) { Write-Info "Cobertura (Cobertura/dotnet-coverage): $($cobFiles.Count) fichero(s) cobertura.xml -> pliegue raise-only" }

# --- 2-4. Parsear cada fichero: FUSIONAR cobertura por metodo + acumular cobertura global ---
# D1/FB-009 (EWP 2026-06-15): en una solucion multi-proyecto, un assembly compartido (p.ej.
# Entities) lo cargan VARIOS proyectos de test; en los que NO lo ejercitan sus metodos figuran a
# 0%. Antes el script tomaba el valor por-fichero (el peor 0%) -> crapMax/crappy/hotspots/clases
# falsos. Ahora se fusiona por (clase::firma) tomando el MAXIMO sequenceCoverage entre todos los
# *.opencover.xml (cc/NPath son estaticos). El CRAP se calcula DESPUES, sobre el conjunto fusionado.
$methodsByKey = @{}          # "ClassFull::IL-Name" -> metodo fusionado (covMax)
$clasesAgg    = @{}          # "ClassFull" -> @{ covLineMax; covBranchMax } (Fase C, max entre ficheros)
$seqNum = 0; $seqVis = 0; $brNum = 0; $brVis = 0    # puntos secuencia/rama: visitados / totales

foreach ($oc in $ocFiles) {
    [xml]$doc = Get-Content -Path $oc.FullName -Raw
    $session = $doc.CoverageSession
    if (-not $session) { continue }

    # Cobertura global: sumar puntos de cada fichero (recomputar % al final). NO afectada por D1.
    $gsum = $session.Summary
    if ($gsum) {
        $seqNum += [int]$gsum.numSequencePoints; $seqVis += [int]$gsum.visitedSequencePoints
        $brNum  += [int]$gsum.numBranchPoints;   $brVis  += [int]$gsum.visitedBranchPoints
    }

    # Mapa de ficheros LOCAL a este opencover (los uid son por-fichero, no globales)
    $fileMap = @{}
    foreach ($mod in @($session.Modules.Module)) {
        foreach ($f in @($mod.Files.File)) {
            if ($f -and $f.uid) { $fileMap[[string]$f.uid] = [string]$f.fullPath }
        }
    }

    foreach ($mod in @($session.Modules.Module)) {
        foreach ($cls in @($mod.Classes.Class)) {
            $clsFull = [string]$cls.FullName
            $clsTieneMetodos = $false
            foreach ($m in @($cls.Methods.Method)) {
                if (-not $m.cyclomaticComplexity) { continue }
                $cyclo = [int]$m.cyclomaticComplexity
                $npath = if ($m.nPathComplexity) { [long]$m.nPathComplexity } else { 0 }
                $cov   = if ($m.sequenceCoverage) { [double]$m.sequenceCoverage } else { 0 }

                # Nombre legible: el IL signature trae 'Ret Namespace.Class::Metodo(args)'
                $rawName = [string]$m.Name
                $metodo = $rawName
                $metodoCorto = $null
                if ($rawName -match '([\w.<>`]+)::([\w<>`]+)') {
                    $cl = ($matches[1] -split '\.')[-1]
                    $metodo = "$cl.$($matches[2])"
                    $metodoCorto = $matches[2]
                }
                # Fichero + linea de inicio
                $fileUid = if ($m.FileRef) { [string]$m.FileRef.uid } else { $null }
                $fichero = if ($fileUid -and $fileMap.ContainsKey($fileUid)) { $fileMap[$fileUid] } else { $null }
                $linea = $null
                $sp = @($m.SequencePoints.SequencePoint) | Where-Object { $_ -and $_.sl } | Select-Object -First 1
                if ($sp) { $linea = [int]$sp.sl }

                # FUSION: clave (clase::firma IL); cc/NPath estaticos; cobertura = MAXIMO entre ficheros
                $key = "$clsFull::$rawName"
                if (-not $methodsByKey.ContainsKey($key)) {
                    $methodsByKey[$key] = [pscustomobject]@{
                        clsFull = $clsFull; metodo = $metodo; metodoCorto = $metodoCorto;
                        ciclomatica = $cyclo; npath = $npath;
                        covMax = $cov; fichero = $fichero; linea = $linea
                    }
                } else {
                    $e = $methodsByKey[$key]
                    if ($cov -gt $e.covMax) { $e.covMax = $cov }
                    if ((-not $e.fichero) -and $fichero) { $e.fichero = $fichero }
                    if ((-not $e.linea) -and $linea) { $e.linea = $linea }
                }
                $clsTieneMetodos = $true
            }
            # Cobertura por clase (Fase C): MAXIMO del Summary entre ficheros (mismo problema cross-load).
            # Omitir clases generadas por el compilador: <...>, /, __
            if ($clsTieneMetodos -and $clsFull -and ($clsFull -notmatch '[<>/]') -and ($clsFull -notmatch '__')) {
                $cSum = $cls.Summary
                $cCovL = if ($cSum -and $cSum.sequenceCoverage) { [double]$cSum.sequenceCoverage } else { 0 }
                $cCovB = if ($cSum -and $cSum.branchCoverage) { [double]$cSum.branchCoverage } else { 0 }
                if (-not $clasesAgg.ContainsKey($clsFull)) {
                    $clasesAgg[$clsFull] = [pscustomobject]@{ covLineMax = $cCovL; covBranchMax = $cCovB }
                } else {
                    $a = $clasesAgg[$clsFull]
                    if ($cCovL -gt $a.covLineMax) { $a.covLineMax = $cCovL }
                    if ($cCovB -gt $a.covBranchMax) { $a.covBranchMax = $cCovB }
                }
            }
        }
    }
}

# --- D1: materializar metodos fusionados + calcular CRAP sobre la cobertura MAXIMA ---
$methods = New-Object System.Collections.Generic.List[object]
foreach ($e in $methodsByKey.Values) {
    # D2: pliegue raise-only de la cobertura de cobertura.xml (dotnet-coverage) por (clase::metodo corto).
    # Nunca BAJA la cobertura (un mismatch no inventa deuda); a lo sumo sube un overload (aprox. del max).
    $covEff = $e.covMax
    if ($e.metodoCorto) {
        $ck = "$($e.clsFull)::$($e.metodoCorto)"
        if ($cobMethodCov.ContainsKey($ck) -and $cobMethodCov[$ck] -gt $covEff) { $covEff = $cobMethodCov[$ck] }
    }
    $uncov = 1 - ($covEff / 100.0)
    # CRAP estandar (igual que ReportGenerator): comp^2 * (1-cov)^3 + comp
    $crap  = [math]::Round([math]::Pow($e.ciclomatica, 2) * [math]::Pow($uncov, 3) + $e.ciclomatica, 2)
    $methods.Add([pscustomobject]@{
        metodo = $e.metodo; fichero = $e.fichero; crap = $crap;
        ciclomatica = $e.ciclomatica; npath = $e.npath; coberturaPct = [math]::Round($covEff, 1);
        linea = $e.linea; clsFull = $e.clsFull
    })
}

# --- clases[] (Fase C): agrupar los metodos FUSIONADOS por clase ---
$clases = New-Object System.Collections.Generic.List[object]
foreach ($grp in ($methods | Group-Object clsFull)) {
    $clsFull = $grp.Name
    if (-not $clsFull -or ($clsFull -match '[<>/]') -or ($clsFull -match '__')) { continue }
    $cCrapMax  = [math]::Round([double](($grp.Group | Measure-Object -Property crap -Maximum).Maximum), 2)
    $cCycloMax = [int](($grp.Group | Measure-Object -Property ciclomatica -Maximum).Maximum)
    $cMet      = @($grp.Group).Count
    $cCovL = 0; $cCovB = 0
    if ($clasesAgg.ContainsKey($clsFull)) { $cCovL = $clasesAgg[$clsFull].covLineMax; $cCovB = $clasesAgg[$clsFull].covBranchMax }
    # D2: pliegue raise-only de la cobertura de clase de cobertura.xml (dotnet-coverage)
    if ($cobClassCov.ContainsKey($clsFull)) {
        if ($cobClassCov[$clsFull].line   -gt $cCovL) { $cCovL = $cobClassCov[$clsFull].line }
        if ($cobClassCov[$clsFull].branch -gt $cCovB) { $cCovB = $cobClassCov[$clsFull].branch }
    }
    $ns = if ($clsFull -match '^(.*)\.[^.]+$') { $matches[1] } else { '(global)' }
    $clName = ($clsFull -split '\.')[-1]
    $clases.Add([pscustomobject]@{
        ns = $ns; clase = $clName; coberturaLinea = [math]::Round($cCovL, 1); coberturaRama = [math]::Round($cCovB, 1);
        crapMax = $cCrapMax; ciclomaticaMax = $cCycloMax; metodos = $cMet
    })
}

if ($methods.Count -eq 0) { Write-Warn "OpenCover sin metodos (cobertura vacia?)."; exit 1 }

# Cobertura global agregada (% = visitados / totales, sobre todos los ficheros)
$coberturaLinea = if ($seqNum -gt 0) { [math]::Round(100.0 * $seqVis / $seqNum, 2) } else { 0.0 }
$coberturaRama  = if ($brNum  -gt 0) { [math]::Round(100.0 * $brVis  / $brNum,  2) } else { 0.0 }

# --- 5. Agregados del QR ---
# Measure-Object devuelve Double; castear a los tipos del contrato (nPathMax es long en el hub
# -> System.Text.Json rechaza 42.0 sobre long?; metodosCrappy es int).
$crapMax        = [math]::Round([double](($methods | Measure-Object -Property crap -Maximum).Maximum), 2)
$metodosCrappy  = [int]@($methods | Where-Object { $_.crap -gt $CrapThreshold }).Count
$ciclomaticaMed = [math]::Round([double](($methods | Measure-Object -Property ciclomatica -Average).Average), 2)
$npathMax       = [long](($methods | Measure-Object -Property npath -Maximum).Maximum)

# Hotspots: top-N por CRAP (relativizar el fichero al repo si es ruta absoluta)
$repoRoot = (Get-Location).Path
$hotspots = $methods | Sort-Object crap -Descending | Select-Object -First $TopHotspots | ForEach-Object {
    $fic = $_.fichero
    if ($fic -and $fic.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $fic = $fic.Substring($repoRoot.Length).TrimStart('\','/')
    }
    [pscustomobject]@{ metodo = $_.metodo; fichero = $fic; crap = $_.crap;
        ciclomatica = $_.ciclomatica; npath = $_.npath; coberturaPct = $_.coberturaPct; linea = $_.linea }
}

# Cobertura por clase/namespace (Fase C): top-N por crapMax para acotar el payload
$clasesTop = @($clases | Sort-Object crapMax -Descending | Select-Object -First $TopClases)
if ($clases.Count -gt $TopClases) {
    Write-Warn ("Desglose por clase truncado: {0} clases -> top {1} por crapMax." -f $clases.Count, $TopClases)
}

# --- 6. Quality gate (verdict del PRODUCTOR; el dashboard NO recalcula) ---
$gateReglas = @(
    [pscustomobject]@{ regla = 'CRAP maximo'; umbral = $CrapThreshold; valor = $crapMax; pasa = ($crapMax -le $CrapThreshold) },
    [pscustomobject]@{ regla = 'Cobertura linea minima'; umbral = $CoverageLineMin; valor = [math]::Round($coberturaLinea,1); pasa = ($coberturaLinea -ge $CoverageLineMin) },
    [pscustomobject]@{ regla = 'Cobertura rama minima'; umbral = $CoverageBranchMin; valor = [math]::Round($coberturaRama,1); pasa = ($coberturaRama -ge $CoverageBranchMin) }
)
$gatePass = ($gateReglas | Where-Object { -not $_.pasa }).Count -eq 0

# --- 7. Codigo QR-nnn secuencial por proyecto (consultar el ultimo en el hub) ---
$headers = @{ 'X-Hub-Api-Key' = $ApiKey; 'Accept' = 'application/json' }
$codigo = 'QR-001'
try {
    $existing = Invoke-RestMethod -Uri "$ServerUrl/v2/stats/quality/$ProjectId" -Headers @{ 'Accept' = 'application/json' } -TimeoutSec 30
    if (-not $existing.sin_datos -and $existing.ultimo -and $existing.ultimo.codigo -match 'QR-(\d+)') {
        $codigo = 'QR-{0:D3}' -f ([int]$matches[1] + 1)
    }
} catch { Write-Warn "No se pudo leer el ultimo QR (se usa $codigo): $($_.Exception.Message)" }

# --- 8. Payload ---
$fecha = if ($BuildId) { (Get-Date).ToUniversalTime().ToString('o') } else { (Get-Date).ToUniversalTime().ToString('o') }
$registro = [ordered]@{
    codigo = $codigo
    fechaBuild = $fecha
    buildId = $BuildId
    coberturaLineaPct = [math]::Round($coberturaLinea, 2)
    coberturaRamaPct  = [math]::Round($coberturaRama, 2)
    crapMax = $crapMax
    metodosCrappy = $metodosCrappy
    ciclomaticaMedia = $ciclomaticaMed
    nPathMax = $npathMax
    qualityGatePass = $gatePass
    gateReglas = $gateReglas
    hotspots = $hotspots
    clases = $clasesTop
    adrRelacionados = $AdrRelacionados
    codeSearchBase = $CodeSearchBase
    coberturaIntegracionMedida = $CoberturaIntegracionMedida
}
$body = @{ projectId = $ProjectId; registros = @($registro) }

Write-Info ("Resumen {0}: gate={1} | cobLinea={2}% cobRama={3}% | CRAPmax={4} crappy={5} cicloMed={6} NPathMax={7} | hotspots={8} clases={9}" -f `
    $codigo, $(if($gatePass){'PASS'}else{'FAIL'}), [math]::Round($coberturaLinea,1), [math]::Round($coberturaRama,1), `
    $crapMax, $metodosCrappy, $ciclomaticaMed, $npathMax, $hotspots.Count, $clasesTop.Count)

if ($DryRun) {
    Write-Info "DryRun -> NO se envia. Payload:"
    $body | ConvertTo-Json -Depth 8
    exit 0
}

# --- 9. POST best-effort (no romper el build si el hub no soporta quality) ---
try {
    $resp = Invoke-RestMethod -Uri "$ServerUrl/v2/sync/quality-batch" -Method Post -Headers $headers `
        -Body ($body | ConvertTo-Json -Depth 8) -ContentType 'application/json' -TimeoutSec 60
    Write-Info "[OK] publicado: created=$($resp.created) updated=$($resp.updated) skipped=$($resp.skipped)"
} catch {
    $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
    if ($status -eq 404) {
        Write-Warn "[SKIP] el hub no expone /v2/sync/quality-batch (necesita v1.3.0+). QR no publicado."
    } else {
        Write-Warn "[FAIL] POST quality-batch HTTP $status : $($_.Exception.Message)"
    }
    # best-effort: no romper el build por el sync de calidad
    exit 0
}
