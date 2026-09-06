[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $SolutionPath,
    [Parameter(Mandatory = $true)] [string] $ApiProject,
    [Parameter(Mandatory = $true)] [string] $SourceRoot,
    [string] $ExceptionsFile = '04_Pruebas/.security-exceptions.yml',
    [Parameter(Mandatory = $true)] [string] $OutputDir,
    [string] $EnableSast = 'true',
    [string] $FailOnSecret = 'true'
)
# =============================================================================
# security-scan.ps1 - Gate de ciberseguridad multi-capa (patron verdict-file)
# Regla R22 de cicd-runtime.md. Origen: DT-005 (BiPublisher build #57).
# Corre 1 vez en el stage Build (continueOnError:true), publica security-report.
# Los stages de deploy parsean el verdict: DeployDev=WARN, DeployDemo/Prod=BLOCK.
# IMPORTANTE: fichero ASCII puro (R13: PS 5.1 lee .ps1 sin BOM como CP1252).
# =============================================================================
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13 }
catch { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 }
$ErrorActionPreference = 'Continue'
$doSast = ($EnableSast -eq 'true')
$failOnSecret = ($FailOnSecret -eq 'true')
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

function New-Finding {
    param([string]$Id, [string]$Severity, [string]$Rule, [string]$Location, [string]$Detail)
    [pscustomobject]@{ id = $Id; severity = $Severity; rule = $Rule; location = $Location; detail = $Detail }
}
$report = [ordered]@{
    schema = 'dt005-security-report/v1'; buildId = $env:BUILD_BUILDID; buildNumber = $env:BUILD_BUILDNUMBER
    sourceRoot = $SourceRoot; checks = [ordered]@{}
    summary = [ordered]@{ Critical = 0; High = 0; Moderate = 0; Low = 0; secrets = 0 }
    effectiveSummary = [ordered]@{ Critical = 0; High = 0; Moderate = 0; Low = 0; secrets = 0 }
    exceptionsApplied = @(); exceptionsExpired = @()
}

function Invoke-VulnerableCheck {
    $result = [ordered]@{ status = 'ok'; findings = @(); note = '' }
    try {
        $solAbs = Join-Path $SourceRoot $SolutionPath
        if (-not (Test-Path $solAbs)) { $solAbs = $SolutionPath }
        Write-Host "==> [1/4] dotnet list package --vulnerable"
        $raw = & dotnet list "$solAbs" package --vulnerable --include-transitive --format json 2>&1
        $exit = $LASTEXITCODE; $text = ($raw | Out-String)
        if ($exit -ne 0 -or $text -match 'no se pudo|could not be|unable to load|Unable to') {
            $result.status = 'inconclusive'
            $result.note = "dotnet list exit=$exit. Posible falta de red a api.nuget.org. Verificar en el agente."
            Write-Warning $result.note; return $result
        }
        $json = $text | ConvertFrom-Json
        foreach ($proj in $json.projects) { foreach ($fw in $proj.frameworks) {
            $pkgs = @(); if ($fw.topLevelPackages) { $pkgs += $fw.topLevelPackages }; if ($fw.transitivePackages) { $pkgs += $fw.transitivePackages }
            foreach ($p in $pkgs) { foreach ($v in $p.vulnerabilities) {
                $sev = switch -Regex ($v.severity) { 'Critical' { 'Critical' } 'High' { 'High' } 'Moderate|Medium' { 'Moderate' } default { 'Low' } }
                $id = $v.advisoryurl; if ([string]::IsNullOrWhiteSpace($id)) { $id = "$($p.id)@$($p.resolvedVersion)" }
                $result.findings += (New-Finding -Id $id -Severity $sev -Rule 'VulnerableDependency' -Location "$($p.id) $($p.resolvedVersion)" -Detail $v.advisoryurl)
            } }
        } }
        if ($result.findings.Count -gt 0) { $result.status = 'findings' }
    } catch { $result.status = 'inconclusive'; $result.note = "Excepcion: $($_.Exception.Message)"; Write-Warning $result.note }
    return $result
}
function Test-IsPlaceholder([string]$val) {
    if ([string]::IsNullOrWhiteSpace($val)) { return $true }
    if ($val -match '^\s*(<.*>|\*+|CHANGEME|TODO|xxx+|\$\(.*\)|%.*%)\s*$') { return $true }
    return $false
}
function Get-TrackedFiles([string[]]$patterns) {
    try { $all = & git -C "$SourceRoot" ls-files 2>$null } catch { $all = @() }
    if (-not $all) { return @() }
    $out = @()
    foreach ($f in $all) {
        if ($f -match '/(bin|obj)/' -or $f -match '^(bin|obj)/') { continue }
        foreach ($pat in $patterns) { if ($f -like $pat) { $out += $f; break } }
    }
    return $out
}
function Invoke-SecretsCheck {
    $result = [ordered]@{ status = 'ok'; findings = @() }
    $secretKeys = 'Password|Pwd|ClaveCorreo|ClientSecret|ApiKey|Api-Key|AccessKey|SecretKey|Secret|Token'
    $files = Get-TrackedFiles @('*appsettings*.json', '*.config')
    Write-Host "==> [2/4] Scan de secretos en $($files.Count) fichero(s)"
    foreach ($rel in $files) {
        $abs = Join-Path $SourceRoot $rel; if (-not (Test-Path $abs)) { continue }
        $lines = @(Get-Content -LiteralPath $abs -ErrorAction SilentlyContinue)
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ($line -match "`"($secretKeys)`"\s*:\s*`"(.*?)`"") {
                $key = $Matches[1]; $val = $Matches[2]
                if (-not (Test-IsPlaceholder $val)) { $result.findings += (New-Finding -Id "secret:$rel`:$($i+1)" -Severity 'High' -Rule "HardcodedSecret($key)" -Location "$rel`:$($i+1)" -Detail "Clave '$key' con valor no vacio en fichero versionado.") }
            }
            if ($line -match '(?i)(Password|Pwd)\s*=\s*([^;"\s]+)') {
                $val = $Matches[2]
                if (-not (Test-IsPlaceholder $val)) { $result.findings += (New-Finding -Id "secret:$rel`:$($i+1):connstr" -Severity 'High' -Rule 'ConnectionStringWithPassword' -Location "$rel`:$($i+1)" -Detail 'Connection string con password embebido.') }
            }
        }
    }
    if ($result.findings.Count -gt 0) { $result.status = 'findings' }
    return $result
}
function Test-IsNamespaceUrl([string]$key, [string]$val) {
    if ($key -match '(?i)(schema|namespace|xmlns|soapenv|soappub|soap)') { return $true }
    if ($val -match '(?i)^https?://(schemas\.|xmlns\.|www\.w3\.org|json-schema\.org)') { return $true }
    return $false
}
function Walk-JsonForInsecureUrls($node, [string]$path, [ref]$findings, [string]$rel) {
    if ($null -eq $node) { return }
    if ($node -is [string]) {
        if ($node -match '(?i)^(http|ws)://') {
            $key = ($path -split '\.')[-1]
            if (-not (Test-IsNamespaceUrl $key $node)) { $findings.Value += (New-Finding -Id "hardening:InsecureUrl:$rel`:$path" -Severity 'High' -Rule 'InsecureUrl' -Location "$rel ($path)" -Detail "URL insegura '$node' (debe ser https:// o wss://).") }
        }
        return
    }
    if ($node -is [System.Collections.IEnumerable] -and -not ($node -is [string])) {
        $idx = 0; foreach ($item in $node) { Walk-JsonForInsecureUrls $item "$path[$idx]" $findings $rel; $idx++ }; return
    }
    foreach ($prop in $node.PSObject.Properties) {
        $childPath = if ($path) { "$path.$($prop.Name)" } else { $prop.Name }
        Walk-JsonForInsecureUrls $prop.Value $childPath $findings $rel
    }
}
function Invoke-HardeningCheck {
    $result = [ordered]@{ status = 'ok'; findings = @() }; $findings = @()
    $cfgFiles = Get-TrackedFiles @('*appsettings*.json')
    Write-Host "==> [3/4] Hardening: $($cfgFiles.Count) appsettings + fuente"
    foreach ($rel in $cfgFiles) {
        $abs = Join-Path $SourceRoot $rel; if (-not (Test-Path $abs)) { continue }
        try { $obj = (Get-Content -LiteralPath $abs -Raw) | ConvertFrom-Json } catch { continue }
        if ($null -ne $obj.AllowedHosts -and $obj.AllowedHosts -eq '*') {
            $sev = if ($rel -match '(?i)production') { 'High' } else { 'Moderate' }
            $findings += (New-Finding -Id "hardening:AllowedHostsWildcard:$rel" -Severity $sev -Rule 'AllowedHostsWildcard' -Location $rel -Detail "AllowedHosts='*' (Host Header Injection). Restringir a FQDN en produccion.")
        }
        Walk-JsonForInsecureUrls $obj '' ([ref]$findings) $rel
    }
    $csFiles = Get-TrackedFiles @('*.cs')
    foreach ($rel in $csFiles) {
        $abs = Join-Path $SourceRoot $rel; if (-not (Test-Path $abs)) { continue }
        $lines = @(Get-Content -LiteralPath $abs -ErrorAction SilentlyContinue)
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ($line -match 'SetIsOriginAllowed\(\s*[_a-zA-Z0-9]+\s*=>\s*true\s*\)') { $findings += (New-Finding -Id "hardening:CorsAllowAll:$rel`:$($i+1)" -Severity 'High' -Rule 'CorsSetIsOriginAllowedTrue' -Location "$rel`:$($i+1)" -Detail 'CORS acepta cualquier origen (SetIsOriginAllowed(_ => true)).') }
            if ($line -match 'AllowAnyOrigin\(\)') { $findings += (New-Finding -Id "hardening:AllowAnyOrigin:$rel`:$($i+1)" -Severity 'High' -Rule 'CorsAllowAnyOrigin' -Location "$rel`:$($i+1)" -Detail 'CORS AllowAnyOrigin() (prohibido con AllowCredentials()).') }
            if ($line -match 'ServerCertificate(Custom)?Validation(Callback)?\s*=.*=>\s*true') { $findings += (New-Finding -Id "hardening:CertBypass:$rel`:$($i+1)" -Severity 'Critical' -Rule 'CertificateValidationDisabled' -Location "$rel`:$($i+1)" -Detail 'Validacion de certificado TLS deshabilitada (callback => true).') }
        }
    }
    $result.findings = $findings; if ($findings.Count -gt 0) { $result.status = 'findings' }
    return $result
}
function Invoke-SastCheck {
    $result = [ordered]@{ status = 'ok'; findings = @(); note = '' }
    if (-not $doSast) { $result.status = 'skipped'; $result.note = 'SAST deshabilitado'; return $result }
    try {
        $projAbs = Join-Path $SourceRoot $ApiProject; if (-not (Test-Path $projAbs)) { $projAbs = $ApiProject }
        Write-Host "==> [4/4] SAST: build con AnalysisModeSecurity=All"
        $raw = & dotnet build "$projAbs" -c Release --no-incremental -v q /p:EnableNETAnalyzers=true /p:RunAnalyzersDuringBuild=true /p:AnalysisModeSecurity=All 2>&1
        $text = ($raw | Out-String); $seen = @{}
        foreach ($line in ($text -split "`r?`n")) {
            if ($line -match 'warning (CA(3|5)\d{3})\s*:\s*(.+?)\s*\[') {
                $rule = $Matches[1]; $msg = $Matches[3].Trim(); $loc = ''
                if ($line -match '^(.*?)\(\d+,\d+\):') { $loc = $Matches[1] }
                $key = "$rule|$loc"; if ($seen.ContainsKey($key)) { continue }; $seen[$key] = $true
                $sev = if ($rule -match '^CA(3001|3003|3006|3007|5358|5359|5360|5364|5386|5397)$') { 'High' } else { 'Moderate' }
                $result.findings += (New-Finding -Id "sast:$rule" -Severity $sev -Rule $rule -Location $loc -Detail $msg)
            }
        }
        if ($result.findings.Count -gt 0) { $result.status = 'findings' }
    } catch { $result.status = 'inconclusive'; $result.note = "Excepcion en SAST: $($_.Exception.Message)"; Write-Warning $result.note }
    return $result
}
function Read-Exceptions {
    $abs = Join-Path $SourceRoot $ExceptionsFile; $out = @()
    if (-not (Test-Path $abs)) { return $out }
    $lines = Get-Content -LiteralPath $abs -ErrorAction SilentlyContinue; $cur = $null
    foreach ($line in $lines) {
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
        if ($line -match '^\s*-\s*(.*)$') {
            if ($cur) { $out += [pscustomobject]$cur }
            $cur = @{ id = ''; severity = ''; owner = ''; target_date = ''; justification = '' }
            $rest = $Matches[1].Trim()
            if ($rest -match '^(\w+)\s*:\s*(.+)$') { $cur[$Matches[1]] = ($Matches[2].Trim().Trim('"').Trim("'")) }
        } elseif ($cur -and $line -match '^\s+(\w+)\s*:\s*(.+)$') { $cur[$Matches[1]] = ($Matches[2].Trim().Trim('"').Trim("'")) }
    }
    if ($cur) { $out += [pscustomobject]$cur }
    return $out
}

$report.checks.vulnerableDependencies = Invoke-VulnerableCheck
$report.checks.secrets = Invoke-SecretsCheck
$report.checks.configHardening = Invoke-HardeningCheck
$report.checks.sast = Invoke-SastCheck

$allFindings = @()
foreach ($k in $report.checks.Keys) { if ($report.checks[$k].findings) { $allFindings += $report.checks[$k].findings } }
foreach ($f in $allFindings) {
    if ($report.summary.Contains($f.severity)) { $report.summary[$f.severity]++ }
    if ($f.rule -like 'HardcodedSecret*' -or $f.rule -eq 'ConnectionStringWithPassword') { $report.summary.secrets++ }
}
$today = (Get-Date).Date; $exceptions = Read-Exceptions; $activeIds = @{}
foreach ($ex in $exceptions) {
    $expired = $false
    if ($ex.target_date) { try { $expired = ([datetime]$ex.target_date).Date -lt $today } catch { $expired = $false } }
    if ($expired) { $report.exceptionsExpired += $ex.id } else { $activeIds[$ex.id] = $true; $report.exceptionsApplied += $ex.id }
}
foreach ($f in $allFindings) {
    if ($activeIds.ContainsKey($f.id)) { continue }
    if ($report.effectiveSummary.Contains($f.severity)) { $report.effectiveSummary[$f.severity]++ }
    if ($f.rule -like 'HardcodedSecret*' -or $f.rule -eq 'ConnectionStringWithPassword') { $report.effectiveSummary.secrets++ }
}
$jsonPath = Join-Path $OutputDir 'security-report.json'
($report | ConvertTo-Json -Depth 12) | Out-File -LiteralPath $jsonPath -Encoding UTF8
Write-Host ''
Write-Host '============================================================'
Write-Host '  ANALISIS DE SEGURIDAD (R22 / DT-005) - verdict generado'
Write-Host "  Crudo:     Crit=$($report.summary.Critical) High=$($report.summary.High) Mod=$($report.summary.Moderate) Low=$($report.summary.Low) Secretos=$($report.summary.secrets)"
Write-Host "  Efectivo:  Crit=$($report.effectiveSummary.Critical) High=$($report.effectiveSummary.High) Mod=$($report.effectiveSummary.Moderate) Low=$($report.effectiveSummary.Low) Secretos=$($report.effectiveSummary.secrets)"
Write-Host '============================================================'
exit 0
