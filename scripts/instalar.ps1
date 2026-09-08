<#
.SYNOPSIS
    Instala Mi jornada para el usuario actual.

.DESCRIPTION
    Hace lo que hasta ahora se hacia a mano: publicar, dejar el .exe en un sitio estable, crear
    los accesos directos y registrar la entrada de desinstalacion.

    Instala SOLO para el usuario actual, en %LOCALAPPDATA%\Programs\MiJornada. Es deliberado:
    asi NO hace falta ser administrador, que es la diferencia entre "te lo instalas y ya" y
    "abre un ticket". Ademas la aplicacion es de un usuario por definicion — cambia TU presencia
    de Teams — asi que una instalacion para toda la maquina no tendria sentido.

    NO crea ningun registro en Entra ID, y es a proposito: ya existe uno para todo el tenant
    (signInAudience = AzureADMyOrg) y los permisos son delegados, asi que cada persona solo
    puede tocar su propia presencia. Crear uno por persona multiplicaria registros sin ganar
    nada. Ver 02_Entorno/crear-registro-entra.ps1 y _hilo/LECCIONES.md.

.PARAMETER Origen
    Carpeta con un MiJornada.exe ya publicado. Si se omite, el script busca el codigo en
    la raiz del repositorio y publica el mismo.

.PARAMETER Ligero
    Publica dependiendo del runtime (1,4 MB) en vez de autocontenido (155 MB). Exige tener
    instalado el "Microsoft .NET Desktop Runtime 8". Util para actualizar tu propio equipo;
    para dar la aplicacion a otra persona, mejor el autocontenido.

.PARAMETER ConInicio
    Ademas, arrancar con Windows (acceso directo en la carpeta de Inicio).

.PARAMETER Minimizado
    Con -ConInicio, arrancar en la bandeja sin abrir la ventana.

.EXAMPLE
    .\instalar.ps1
    Publica autocontenido desde el codigo e instala.

.EXAMPLE
    .\instalar.ps1 -ConInicio -Minimizado
    Igual, y ademas arranca solo con Windows, directo a la bandeja.

.EXAMPLE
    .\instalar.ps1 -Origen .\MiJornada-0.11.0
    Instala desde una carpeta ya publicada, sin necesitar el SDK de .NET.
#>
[CmdletBinding()]
param(
    [string] $Origen,
    [switch] $Ligero,
    [switch] $ConInicio,
    [switch] $Minimizado
)

$ErrorActionPreference = 'Stop'

$Nombre      = 'Mi jornada'
$ClaveDesinst = 'MiJornada'
$Destino     = Join-Path $env:LOCALAPPDATA 'Programs\MiJornada'
$Datos       = Join-Path $env:APPDATA 'MiJornada'

function Paso  ([string] $t) { Write-Host "`n== $t" -ForegroundColor Cyan }
function Bien  ([string] $t) { Write-Host "   $t" -ForegroundColor Green }
function Nota  ([string] $t) { Write-Host "   $t" -ForegroundColor DarkGray }
function Aviso ([string] $t) { Write-Host "   $t" -ForegroundColor Yellow }

Write-Host "`nInstalador de $Nombre" -ForegroundColor White
Write-Host "Instalacion para el usuario actual: no hace falta ser administrador." -ForegroundColor DarkGray

# ---------------------------------------------------------------- 1. de donde sale el .exe
Paso '1/6  Preparando los ficheros'

$temporal = $null

if ($Origen) {
    $exeOrigen = Join-Path $Origen 'MiJornada.exe'
    if (-not (Test-Path -LiteralPath $exeOrigen)) {
        throw "No hay ningun MiJornada.exe en '$Origen'."
    }
    Bien "Usando lo ya publicado en $Origen"
}
else {
    $proyecto = Join-Path (Split-Path $PSScriptRoot -Parent) 'MiJornada.csproj'
    if (-not (Test-Path -LiteralPath $proyecto)) {
        throw "No encuentro MiJornada.csproj en la raiz del repositorio. Usa -Origen con una carpeta ya publicada."
    }

    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        throw "Hace falta el SDK de .NET para publicar. O instalalo, o usa -Origen."
    }

    # Autocontenido por defecto: el objetivo es que la aplicacion funcione en un equipo donde
    # no hay nada instalado. Pesa 155 MB frente a 1,4, y merece la pena por no tener que
    # explicarle a nadie que se instale un runtime.
    $auto = -not $Ligero
    Nota $(if ($auto) { 'Publicando autocontenido (~155 MB, no necesita .NET instalado)…' }
           else        { 'Publicando ligero (~1,4 MB, necesita .NET Desktop Runtime 8)…' })

    $temporal = Join-Path ([IO.Path]::GetTempPath()) "mijornada-pub-$(Get-Random)"

    $salida = & dotnet publish $proyecto -c Release -r win-x64 `
        --self-contained $auto.ToString().ToLower() `
        -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
        -o $temporal -v quiet --nologo 2>&1

    if ($LASTEXITCODE -ne 0) {
        $salida | ForEach-Object { Write-Host "   $_" -ForegroundColor Red }
        throw "Fallo la publicacion."
    }

    $Origen = $temporal
    $exeOrigen = Join-Path $Origen 'MiJornada.exe'
    Bien "Publicado ($([math]::Round((Get-Item $exeOrigen).Length / 1MB, 1)) MB)"
}

$version = (Get-Item $exeOrigen).VersionInfo.FileVersion
Nota "Version $version"

# ---------------------------------------------------------------- 2. cerrar lo que este abierto
Paso '2/6  Comprobando que no este en marcha'

$vivos = Get-Process MiJornada -ErrorAction SilentlyContinue
if ($vivos) {
    Aviso "Hay $($vivos.Count) instancia(s) abierta(s). Hay que cerrarlas para reemplazar el .exe."
    $r = Read-Host '   ¿Las cierro? Si hay una jornada en marcha, seguira contando al reabrir [S/n]'
    if ($r -and $r -notmatch '^[sSyY]') { throw 'Instalacion cancelada.' }

    $vivos | Stop-Process -Force
    Start-Sleep -Milliseconds 800
    Bien 'Cerradas'
}
else { Bien 'No estaba en marcha' }

# ---------------------------------------------------------------- 3. copiar
Paso '3/6  Instalando en la carpeta del usuario'

New-Item -ItemType Directory -Path $Destino -Force | Out-Null
Copy-Item -Path (Join-Path $Origen '*') -Destination $Destino -Recurse -Force -Exclude '*.pdb'

$exe = Join-Path $Destino 'MiJornada.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw "Algo fallo: no hay MiJornada.exe en $Destino." }
Bien $Destino

# El desinstalador se copia junto a la aplicacion: si algun dia se borra el repositorio, la
# aplicacion tiene que seguir pudiendo quitarse.
$desinstOrigen = Join-Path $PSScriptRoot 'desinstalar.ps1'
if (Test-Path -LiteralPath $desinstOrigen) {
    Copy-Item -LiteralPath $desinstOrigen -Destination $Destino -Force
    Bien 'Desinstalador copiado junto a la aplicacion'
}

# ---------------------------------------------------------------- 4. accesos directos
Paso '4/6  Accesos directos'

function Nuevo-Acceso {
    param([string] $Ruta, [string] $Destino, [string] $Argumentos = '')

    $shell = New-Object -ComObject WScript.Shell
    try {
        $a = $shell.CreateShortcut($Ruta)
        $a.TargetPath       = $Destino
        $a.Arguments        = $Argumentos
        $a.WorkingDirectory = Split-Path $Destino -Parent
        $a.Description      = 'Controla tu presencia de Teams'
        $a.IconLocation     = "$Destino,0"
        $a.Save()
    }
    finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
}

$menu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
Nuevo-Acceso -Ruta (Join-Path $menu "$Nombre.lnk") -Destino $exe
Bien 'Menu Inicio'

$inicio = [Environment]::GetFolderPath('Startup')
$lnkInicio = Join-Path $inicio "$Nombre.lnk"

if ($ConInicio) {
    Nuevo-Acceso -Ruta $lnkInicio -Destino $exe -Argumentos $(if ($Minimizado) { '--minimizado' } else { '' })
    Bien $(if ($Minimizado) { 'Arranque con Windows, a la bandeja' } else { 'Arranque con Windows' })
}
elseif (Test-Path -LiteralPath $lnkInicio) {
    # Ya lo tenia activado desde los Ajustes de la aplicacion, apuntando al .exe viejo. Si no se
    # actualiza, al reiniciar arrancaria la version anterior — o nada, si esa ruta ya no existe.
    Nuevo-Acceso -Ruta $lnkInicio -Destino $exe
    Bien 'Arranque con Windows ya estaba activo: reapuntado al .exe nuevo'
}
else {
    Nota 'Sin arranque automatico (se puede activar luego en Ajustes, o con -ConInicio)'
}

# ---------------------------------------------------------------- 5. desinstalacion
Paso '5/6  Registrando en "Aplicaciones instaladas"'

$clave = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$ClaveDesinst"
New-Item -Path $clave -Force | Out-Null

$comando = "powershell.exe -ExecutionPolicy Bypass -File `"$(Join-Path $Destino 'desinstalar.ps1')`""
$tamano  = [math]::Round(((Get-ChildItem -LiteralPath $Destino -Recurse -File | Measure-Object Length -Sum).Sum) / 1KB)

@{
    DisplayName     = $Nombre
    DisplayVersion  = $version
    Publisher       = 'Hugo Valer'
    DisplayIcon     = $exe
    InstallLocation = $Destino
    UninstallString = $comando
    NoModify        = 1
    NoRepair        = 1
    EstimatedSize   = $tamano
}.GetEnumerator() | ForEach-Object {
    New-ItemProperty -Path $clave -Name $_.Key -Value $_.Value `
        -PropertyType $(if ($_.Value -is [int]) { 'DWord' } else { 'String' }) -Force | Out-Null
}
Bien 'Aparecera en Configuracion > Aplicaciones instaladas'

# ---------------------------------------------------------------- 6. limpieza y resumen
Paso '6/6  Terminando'

if ($temporal -and (Test-Path -LiteralPath $temporal)) {
    Remove-Item -LiteralPath $temporal -Recurse -Force
    Bien 'Borrado lo temporal'
}

Write-Host "`n  $Nombre $version instalado." -ForegroundColor Green
Write-Host "  Aplicacion : $Destino"        -ForegroundColor DarkGray
Write-Host "  Tus datos  : $Datos"          -ForegroundColor DarkGray
Write-Host @"

  La primera vez pedira un codigo de dispositivo para iniciar sesion: se copia,
  se pega en el navegador y no lo vuelve a pedir.

  Para anclarlo a la barra de tareas: buscarlo en el menu Inicio, boton derecho,
  "Anclar a la barra de tareas". No se puede hacer desde un script — Windows 11
  quito esa posibilidad a proposito, para que nadie te llene la barra sin permiso.

  Para desinstalar: Configuracion > Aplicaciones instaladas, o
  $Destino\desinstalar.ps1

"@ -ForegroundColor DarkGray

if (-not (Test-Path -LiteralPath $Datos)) {
    Write-Host "  Es una instalacion nueva: no hay datos previos." -ForegroundColor DarkGray
}
else {
    Write-Host "  Se conservan tus ajustes y tu historico." -ForegroundColor DarkGray
}
