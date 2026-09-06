#Requires -Version 5.1
<#
.SYNOPSIS
    Descarga las librerias del panel (Bootstrap 5.3, Chart.js, Bootstrap Icons y
    fuentes) a wwwroot/lib para servirlas LOCALES desde IIS (sin depender de CDN en runtime).

.DESCRIPTION
    Se ejecuta UNA vez en scaffold-time (en una maquina/servidor con salida a internet).
    El runtime (los navegadores que abren el panel) carga todo desde wwwroot/lib por ruta
    relativa, asi que el panel funciona en intranets sin CDN. ASCII puro (PS 5.1 safe).

.NOTES
    Pinea versiones para reproducibilidad. Si una descarga falla, avisa y sigue (las fuentes
    son opcionales: el panel cae a system-ui / ui-monospace). Fuente: jsDelivr (mirror de npm).
#>
[CmdletBinding()]
param(
    [string] $LibDir = (Join-Path $PSScriptRoot '.'),   # por defecto: este wwwroot/lib
    [string] $BootstrapVersion = '5.3.3',
    [string] $ChartVersion     = '4.4.1',
    [string] $IconsVersion     = '1.11.3',
    [switch] $SkipFonts
)

$ErrorActionPreference = 'Stop'
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
} catch { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 }

$cdn = 'https://cdn.jsdelivr.net'
$ok = 0; $fail = 0

function Get-File($url, $dest) {
    $dir = Split-Path -Parent $dest
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    try {
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 60
        $size = (Get-Item $dest).Length
        Write-Host ("  [OK]  {0}  ({1:N0} bytes)" -f (Split-Path -Leaf $dest), $size) -ForegroundColor Green
        $script:ok++
    } catch {
        Write-Warning ("  [FAIL] {0} -> {1}" -f $url, $_.Exception.Message)
        $script:fail++
    }
}

Write-Host "Descargando librerias del panel a: $LibDir" -ForegroundColor Cyan

# --- Bootstrap 5.3 (css + bundle js) ---
Get-File "$cdn/npm/bootstrap@$BootstrapVersion/dist/css/bootstrap.min.css"        (Join-Path $LibDir 'bootstrap/bootstrap.min.css')
Get-File "$cdn/npm/bootstrap@$BootstrapVersion/dist/js/bootstrap.bundle.min.js"   (Join-Path $LibDir 'bootstrap/bootstrap.bundle.min.js')

# --- Chart.js (UMD min) ---
Get-File "$cdn/npm/chart.js@$ChartVersion/dist/chart.umd.min.js"                  (Join-Path $LibDir 'chart/chart.umd.min.js')

# --- Bootstrap Icons (css + woff2/woff que el css referencia en ./fonts/) ---
Get-File "$cdn/npm/bootstrap-icons@$IconsVersion/font/bootstrap-icons.min.css"        (Join-Path $LibDir 'bootstrap-icons/font/bootstrap-icons.min.css')
Get-File "$cdn/npm/bootstrap-icons@$IconsVersion/font/fonts/bootstrap-icons.woff2"    (Join-Path $LibDir 'bootstrap-icons/font/fonts/bootstrap-icons.woff2')
Get-File "$cdn/npm/bootstrap-icons@$IconsVersion/font/fonts/bootstrap-icons.woff"     (Join-Path $LibDir 'bootstrap-icons/font/fonts/bootstrap-icons.woff')

# --- Fuentes (opcionales; fallback system-ui / ui-monospace si faltan) ---
if (-not $SkipFonts) {
    Get-File "$cdn/fontsource/fonts/space-grotesk@latest/latin-500-normal.woff2" (Join-Path $LibDir 'fonts/space-grotesk.woff2')
    Get-File "$cdn/fontsource/fonts/jetbrains-mono@latest/latin-500-normal.woff2" (Join-Path $LibDir 'fonts/jetbrains-mono.woff2')
    Get-File "$cdn/fontsource/fonts/inter@latest/latin-400-normal.woff2"          (Join-Path $LibDir 'fonts/inter.woff2')
}

Write-Host ""
Write-Host ("Resultado: {0} OK, {1} fallidas." -f $ok, $fail) -ForegroundColor Cyan
if ($fail -gt 0) {
    Write-Warning "Algunas descargas fallaron. El panel funciona igual (CSS/JS core son lo critico; las fuentes tienen fallback). Reintentar con internet o descargar a mano (ver README)."
}
