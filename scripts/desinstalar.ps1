<#
.SYNOPSIS
    Desinstala Mi jornada del usuario actual.

.DESCRIPTION
    Quita la aplicacion, los accesos directos y la entrada de "Aplicaciones instaladas".

    Por defecto CONSERVA tus datos (ajustes, historico de jornadas y la sesion iniciada), que
    viven en %APPDATA%\MiJornada. Una desinstalacion no deberia llevarse por delante meses de
    historico sin preguntar, y ademas lo normal al desinstalar es volver a instalar.

    Se copia junto a la aplicacion durante la instalacion, para que se pueda desinstalar aunque
    ya no exista el repositorio.

.PARAMETER ConDatos
    Borra tambien %APPDATA%\MiJornada: ajustes, historico y la sesion. Pide confirmacion.

.PARAMETER Silencioso
    Sin preguntas. Pensado para reinstalar desde un script.

.EXAMPLE
    .\desinstalar.ps1

.EXAMPLE
    .\desinstalar.ps1 -ConDatos
#>
[CmdletBinding()]
param(
    [switch] $ConDatos,
    [switch] $Silencioso
)

$ErrorActionPreference = 'Stop'

$Nombre       = 'Mi jornada'
$ClaveDesinst = 'MiJornada'
$Destino      = Join-Path $env:LOCALAPPDATA 'Programs\MiJornada'
$Datos        = Join-Path $env:APPDATA 'MiJornada'

function Paso ([string] $t) { Write-Host "`n== $t" -ForegroundColor Cyan }
function Bien ([string] $t) { Write-Host "   $t" -ForegroundColor Green }
function Nota ([string] $t) { Write-Host "   $t" -ForegroundColor DarkGray }

Write-Host "`nDesinstalador de $Nombre" -ForegroundColor White

if (-not $Silencioso) {
    $r = Read-Host "¿Desinstalar $Nombre? Tus ajustes y tu historico se conservan [S/n]"
    if ($r -and $r -notmatch '^[sSyY]') { Write-Host 'Cancelado.'; return }
}

# ------------------------------------------------------------------ 1. cerrar
Paso '1/4  Cerrando la aplicacion'

$vivos = Get-Process MiJornada -ErrorAction SilentlyContinue
if ($vivos) {
    $vivos | Stop-Process -Force
    Start-Sleep -Milliseconds 800
    Bien "Cerradas $($vivos.Count) instancia(s)"
}
else { Bien 'No estaba en marcha' }

# ------------------------------------------------------------------ 2. accesos directos
Paso '2/4  Quitando accesos directos'

$accesos = @(
    (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\$Nombre.lnk"),
    (Join-Path ([Environment]::GetFolderPath('Startup')) "$Nombre.lnk")
)

$quitados = 0
foreach ($a in $accesos) {
    if (Test-Path -LiteralPath $a) { Remove-Item -LiteralPath $a -Force; $quitados++ }
}
Bien "$quitados acceso(s) directo(s)"
Nota 'Si lo anclaste a la barra de tareas, ese anclaje hay que quitarlo a mano.'

# ------------------------------------------------------------------ 3. registro
Paso '3/4  Quitando la entrada de "Aplicaciones instaladas"'

$clave = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$ClaveDesinst"
if (Test-Path -LiteralPath $clave) {
    Remove-Item -LiteralPath $clave -Recurse -Force
    Bien 'Quitada'
}
else { Nota 'No estaba registrada' }

# ------------------------------------------------------------------ 4. ficheros
Paso '4/4  Borrando la aplicacion'

if (Test-Path -LiteralPath $Destino) {
    # El propio desinstalador vive dentro de la carpeta que hay que borrar, asi que no se puede
    # borrar del tiron mientras se esta ejecutando. Se borra todo lo demas ahora y la carpeta
    # queda encargada a un proceso aparte que espera a que este script termine.
    Get-ChildItem -LiteralPath $Destino -Force |
        Where-Object { $_.Name -ne 'desinstalar.ps1' } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    $yo = $MyInvocation.MyCommand.Path
    if ($yo -and $yo.StartsWith($Destino, [StringComparison]::OrdinalIgnoreCase)) {
        Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command',
            "Start-Sleep -Seconds 3; Remove-Item -LiteralPath '$Destino' -Recurse -Force -ErrorAction SilentlyContinue"
        )
        Bien 'Aplicacion borrada (la carpeta desaparece en unos segundos)'
    }
    else {
        Remove-Item -LiteralPath $Destino -Recurse -Force
        Bien 'Aplicacion borrada'
    }
}
else { Nota 'No estaba instalada' }

# ------------------------------------------------------------------ datos
if ($ConDatos) {
    if (-not $Silencioso) {
        Write-Host "`nEsto borra tus ajustes, el historico de jornadas y la sesion iniciada." -ForegroundColor Yellow
        $r = Read-Host "Escribe BORRAR para confirmar"
        if ($r -ne 'BORRAR') { Write-Host 'Los datos se conservan.' -ForegroundColor DarkGray; $ConDatos = $false }
    }

    if ($ConDatos -and (Test-Path -LiteralPath $Datos)) {
        Remove-Item -LiteralPath $Datos -Recurse -Force
        Write-Host "`n   Datos borrados: $Datos" -ForegroundColor Green
    }
}
else {
    Write-Host "`n   Tus datos siguen en: $Datos" -ForegroundColor DarkGray
    Write-Host "   (ajustes, historico y sesion; se reutilizan si vuelves a instalar)" -ForegroundColor DarkGray
}

Write-Host "`n  $Nombre desinstalado.`n" -ForegroundColor Green
Write-Host "  Tu presencia de Teams NO se ha tocado. Si te quedaste marcado como" -ForegroundColor DarkGray
Write-Host "  Fuera del trabajo, cambiala a mano desde Teams." -ForegroundColor DarkGray
Write-Host ""
