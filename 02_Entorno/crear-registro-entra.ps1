<#
.SYNOPSIS
    Crea en Entra ID el registro de aplicacion que necesita MiJornada y devuelve su ClientId.

.DESCRIPTION
    MiJornada es un cliente PUBLICO de escritorio: no lleva secreto. Este script crea el registro
    con la configuracion exacta que hace falta y que, hecha a mano, son dos pasos que se olvidan:

      - isFallbackPublicClient = true   ("Permitir flujos de cliente publico" en el portal).
                                        Sin esto, el codigo de dispositivo falla con AADSTS7000218.
      - Permisos DELEGADOS sobre Microsoft Graph:
          * Presence.ReadWrite        cambiar la presencia propia en Teams
          * Files.ReadWrite.AppFolder carpeta propia en OneDrive, para compartir el estado
                                      entre equipos (ADR-009). Solo alcanza a esa carpeta.
      - URI de redireccion de aplicacion movil y de escritorio.

    Los ids de los permisos NO se hardcodean: se buscan en el service principal de Graph.

    Es idempotente en los dos sentidos: si no existe el registro lo crea, y si existe le ANADE
    los permisos que le falten sin tocar nada mas. Ejecutarlo dos veces no hace dano.

    Declarar un permiso aqui no concede el consentimiento: la aplicacion lo pide sola la primera
    vez (consentimiento dinamico). Esto sirve para dejar constancia y para que un administrador
    pueda concederlo a toda la organizacion si algun dia hiciera falta.

.NOTES
    Requiere el modulo Microsoft.Graph.Authentication y permiso para registrar aplicaciones en el
    tenant (Application.ReadWrite.All delegado, o rol de desarrollador/administrador de
    aplicaciones).

    CONSOLA: ejecutalo en Windows PowerShell 5.1 (el icono azul). El modulo esta instalado ahi,
    no en PowerShell 7. Ver _hilo/LECCIONES.md, TEC-005.

.EXAMPLE
    .\crear-registro-entra.ps1
    .\crear-registro-entra.ps1 -NombreApp "Mi jornada (pruebas)"
#>

[CmdletBinding()]
param(
    [string] $NombreApp = "Mi jornada",

    # Tenant de Comillas. Ver _hilo/LECCIONES.md, TEC-008.
    [string] $TenantId  = "bcd2701c-aa9b-4d12-ba20-f3e3b83070c1"
)

$ErrorActionPreference = 'Stop'

# Identificadores fijos de Microsoft, no son secretos ni cambian.
$GraphAppId    = "00000003-0000-0000-c000-000000000000"
$PermisosBuscados = @(
    "Presence.ReadWrite",         # cambiar la presencia propia en Teams
    "Files.ReadWrite.AppFolder"   # carpeta propia en OneDrive: estado compartido entre equipos
)
$RedirectUri   = "https://login.microsoftonline.com/common/oauth2/nativeclient"

# ---------------------------------------------------------------- modulo

if (-not (Get-Command Connect-MgGraph -ErrorAction SilentlyContinue)) {
    # Puede estar instalado pero fuera del PSModulePath de esta consola (TEC-005).
    $ruta = Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\Modules\Microsoft.Graph.Authentication'
    $ultima = Get-ChildItem $ruta -Directory -ErrorAction SilentlyContinue |
              Sort-Object Name -Descending | Select-Object -First 1

    if ($ultima) {
        Write-Host "Importando Microsoft.Graph.Authentication $($ultima.Name) por ruta..." -ForegroundColor DarkGray
        Import-Module (Join-Path $ultima.FullName 'Microsoft.Graph.Authentication.psd1')
    }
    else {
        throw "Falta Microsoft.Graph.Authentication. Instalalo con: Install-Module Microsoft.Graph.Authentication -Scope CurrentUser"
    }
}

# ---------------------------------------------------------------- conexion

Write-Host "Conectando a Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -TenantId $TenantId -Scopes "Application.ReadWrite.All" -NoWelcome

$ctx = Get-MgContext
Write-Host "  Cuenta: $($ctx.Account)"
Write-Host "  Tenant: $($ctx.TenantId)"

# ---------------------------------------------------------------- idempotencia

# Ojo: la URI va en comillas SIMPLES. En comillas dobles, PowerShell interpretaria
# $filter como una variable y la dejaria vacia.
$filtro = [uri]::EscapeDataString("displayName eq '$NombreApp'")
$existe = Invoke-MgGraphRequest -Method GET -OutputType PSObject `
    -Uri ('https://graph.microsoft.com/v1.0/applications?$filter=' + $filtro)

$appExistente = if ($existe.value -and $existe.value.Count -gt 0) { $existe.value[0] } else { $null }

# ---------------------------------------------------------------- permisos delegados

Write-Host "Buscando los ids de los permisos delegados..." -ForegroundColor Cyan

$graphSp = Invoke-MgGraphRequest -Method GET -OutputType PSObject `
    -Uri "https://graph.microsoft.com/v1.0/servicePrincipals(appId='$GraphAppId')"

$accesos = @()
foreach ($nombre in $PermisosBuscados) {
    $permiso = $graphSp.oauth2PermissionScopes | Where-Object { $_.value -eq $nombre }
    if (-not $permiso) { throw "No se encontro el permiso delegado $nombre en Microsoft Graph." }
    Write-Host "  $nombre -> $($permiso.id)"
    $accesos += @{ id = $permiso.id; type = "Scope" }   # Scope = delegado
}

$recursos = @(@{ resourceAppId = $GraphAppId; resourceAccess = $accesos })

# ---------------------------------------------------------------- actualizacion

if ($appExistente) {
    Write-Host ""
    Write-Host "Ya existe el registro '$NombreApp' (ClientId $($appExistente.appId))." -ForegroundColor Yellow

    $actuales = @()
    foreach ($r in $appExistente.requiredResourceAccess) {
        if ($r.resourceAppId -eq $GraphAppId) { $actuales = @($r.resourceAccess | ForEach-Object { $_.id }) }
    }
    $faltan = @($accesos | Where-Object { $actuales -notcontains $_.id })

    if ($faltan.Count -eq 0) {
        Write-Host "Ya tiene declarados todos los permisos. Nada que hacer." -ForegroundColor Green
        Write-Host ""
        Write-Host "ClientId: $($appExistente.appId)" -ForegroundColor Green
        return
    }

    Write-Host "Le faltan $($faltan.Count) permiso(s). Actualizando..." -ForegroundColor Cyan
    try {
        Invoke-MgGraphRequest -Method PATCH `
            -Uri "https://graph.microsoft.com/v1.0/applications/$($appExistente.id)" `
            -Body @{ requiredResourceAccess = $recursos; isFallbackPublicClient = $true } `
            -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Host "No se pudo actualizar: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }

    Write-Host ""
    Write-Host "Registro actualizado." -ForegroundColor Green
    Write-Host "  ClientId: $($appExistente.appId)" -ForegroundColor Green
    Write-Host ""
    Write-Host "Nota: declarar el permiso aqui NO concede el consentimiento. La aplicacion lo pide"
    Write-Host "sola la primera vez (consentimiento dinamico); esto sirve para dejar constancia y"
    Write-Host "para que un administrador pueda concederlo a toda la organizacion si algun dia hace falta."
    return
}

# ---------------------------------------------------------------- creacion

$body = @{
    displayName            = $NombreApp
    signInAudience         = "AzureADMyOrg"    # solo cuentas de este directorio
    isFallbackPublicClient = $true             # "Permitir flujos de cliente publico"
    publicClient           = @{ redirectUris = @($RedirectUri) }
    requiredResourceAccess = $recursos
}

Write-Host "Creando el registro '$NombreApp'..." -ForegroundColor Cyan

try {
    $app = Invoke-MgGraphRequest -Method POST -OutputType PSObject `
        -Uri "https://graph.microsoft.com/v1.0/applications" -Body $body
}
catch {
    Write-Host ""
    Write-Host "No se pudo crear el registro." -ForegroundColor Red
    Write-Host $_.Exception.Message
    Write-Host ""
    Write-Host "Si el error es 403 / Authorization_RequestDenied, tu cuenta no tiene permiso para"
    Write-Host "registrar aplicaciones en el tenant. Habria que pedirselo a quien administre Entra."
    throw
}

Write-Host ""
Write-Host "Registro creado." -ForegroundColor Green
Write-Host "  displayName : $($app.displayName)"
Write-Host "  objectId    : $($app.id)"
Write-Host ""
Write-Host "  ClientId    : $($app.appId)" -ForegroundColor Green
Write-Host ""
Write-Host "Pegalo en 03_Desarrollo/Estado.cs, en Config.ClientId (sustituye PON-AQUI-TU-CLIENT-ID)."
Write-Host "La primera vez que ejecutes MiJornada te pedira consentir Presence.ReadWrite: es normal,"
Write-Host "es un permiso delegado y no necesita aprobacion de administrador."
