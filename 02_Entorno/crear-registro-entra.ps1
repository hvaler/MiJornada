<#
.SYNOPSIS
    Crea en Entra ID el registro de aplicacion que necesita MiJornada y devuelve su ClientId.

.DESCRIPTION
    MiJornada es un cliente PUBLICO de escritorio: no lleva secreto. Este script crea el registro
    con la configuracion exacta que hace falta y que, hecha a mano, son dos pasos que se olvidan:

      - isFallbackPublicClient = true   ("Permitir flujos de cliente publico" en el portal).
                                        Sin esto, el codigo de dispositivo falla con AADSTS7000218.
      - Permiso DELEGADO Presence.ReadWrite sobre Microsoft Graph.
      - URI de redireccion de aplicacion movil y de escritorio.

    El id del permiso delegado NO se hardcodea: se busca en el service principal de Graph.

    Es idempotente: si ya existe un registro con el mismo displayName, no crea otro; te devuelve
    el que hay.

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
$PermisoBuscado = "Presence.ReadWrite"
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

if ($existe.value -and $existe.value.Count -gt 0) {
    $app = $existe.value[0]
    Write-Host ""
    Write-Host "Ya existia un registro llamado '$NombreApp'. No se crea otro." -ForegroundColor Yellow
    Write-Host "ClientId: $($app.appId)" -ForegroundColor Green
    Write-Host ""
    Write-Host "Comprueba a mano que tiene 'Permitir flujos de cliente publico' activado."
    return
}

# ---------------------------------------------------------------- permiso delegado

Write-Host "Buscando el id del permiso delegado $PermisoBuscado..." -ForegroundColor Cyan

$graphSp = Invoke-MgGraphRequest -Method GET -OutputType PSObject `
    -Uri "https://graph.microsoft.com/v1.0/servicePrincipals(appId='$GraphAppId')"

$permiso = $graphSp.oauth2PermissionScopes | Where-Object { $_.value -eq $PermisoBuscado }

if (-not $permiso) { throw "No se encontro el permiso delegado $PermisoBuscado en Microsoft Graph." }
Write-Host "  $PermisoBuscado -> $($permiso.id)"

# ---------------------------------------------------------------- creacion

$body = @{
    displayName            = $NombreApp
    signInAudience         = "AzureADMyOrg"    # solo cuentas de este directorio
    isFallbackPublicClient = $true             # "Permitir flujos de cliente publico"
    publicClient           = @{ redirectUris = @($RedirectUri) }
    requiredResourceAccess = @(
        @{
            resourceAppId  = $GraphAppId
            resourceAccess = @(@{ id = $permiso.id; type = "Scope" })   # Scope = delegado
        }
    )
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
