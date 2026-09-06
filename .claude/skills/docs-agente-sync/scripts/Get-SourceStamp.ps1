#Requires -Version 5.1
<#
.SYNOPSIS
    Calcula el sello por HASH DE CONTENIDO del subarbol de codigo fuente de un entrypoint
    (drift de docs de agente). Hermano de Get-TemplateStamp.ps1 (ADR-047) pero para un
    DIRECTORIO de fuentes, no para un unico *.yml.template.

.DESCRIPTION
    Devuelve los primeros 12 hex del SHA256 de los ficheros *.cs + *.csproj bajo -Path
    (excluyendo bin/ y obj/), con los line-endings NORMALIZADOS a LF byte-a-byte (identico
    a Get-TemplateStamp: robusto a CRLF / git autocrlf entre consumidores y entre shells).

    Es la UNICA fuente de verdad del hash de fuente: la invocan IGUAL
    /analisis-arquitectura --agente (al sellar la cabecera del doc) y Sync-AgentDoc.ps1
    (al recomprobar drift). Si las dos partes lo calcularan por separado y divergieran,
    el sync marcaria 'stale' SIEMPRE.

    Por que un helper aparte y no -Path dentro de Get-TemplateStamp: para NO tocar el helper
    critico del que dependen /cicd-init y /cicd-status (su hash de plantilla no debe cambiar
    nunca por un edit colateral). Misma logica de normalizacion, fichero distinto.

.PARAMETER Path
    Carpeta del entrypoint (p.ej. 03_Desarrollo/MyCompany.X.Api).

.PARAMETER Include
    Patrones de fichero a hashear. Default: *.cs, *.csproj.

.OUTPUTS
    Imprime en stdout los 12 hex del hash. exit 0 OK / exit 2 error (path inexistente / sin ficheros).

.EXAMPLE
    pwsh Get-SourceStamp.ps1 -Path 03_Desarrollo/MyCompany.X.Api
    # -> 9f3a1c07be22
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Path,
    [string[]] $Include = @('*.cs', '*.csproj')
)

$ErrorActionPreference = 'Stop'

# Normaliza EOL a nivel de byte (CRLF y CR sueltos -> LF). IDENTICO a Get-TemplateStamp.ps1.
function ConvertTo-LfBytes([byte[]] $raw) {
    $out = New-Object System.Collections.Generic.List[byte]
    for ($i = 0; $i -lt $raw.Length; $i++) {
        $b = $raw[$i]
        if ($b -eq 0x0D) {
            $out.Add([byte]0x0A)                                                   # CR -> LF
            if (($i + 1) -lt $raw.Length -and $raw[$i + 1] -eq 0x0A) { $i++ }      # CRLF -> un solo LF
        }
        else { $out.Add($b) }
    }
    , $out.ToArray()
}

try {
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "ERROR: path no encontrado: $Path" -ForegroundColor Red
        exit 2
    }

    # Enumerar, excluir bin/obj, ORDENAR por ruta completa (ordinal) para hash estable.
    $files = Get-ChildItem -LiteralPath $Path -Recurse -File -Include $Include -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/](bin|obj)[\\/]' } |
        Sort-Object -Property FullName -Culture ''

    if (-not $files) {
        Write-Host "ERROR: sin ficheros ($($Include -join ', ')) bajo $Path" -ForegroundColor Red
        exit 2
    }

    $acc = New-Object System.Collections.Generic.List[byte]
    foreach ($f in $files) {
        $norm = ConvertTo-LfBytes ([System.IO.File]::ReadAllBytes($f.FullName))
        $acc.AddRange($norm)
        $acc.Add([byte]0x0A)                                                       # separador de fichero (frontera estable)
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hashBytes = $sha.ComputeHash($acc.ToArray()) } finally { $sha.Dispose() }

    $hex = -join ($hashBytes | ForEach-Object { $_.ToString('x2') })
    Write-Output $hex.Substring(0, 12)
    exit 0
}
catch {
    Write-Host "ERROR inesperado en Get-SourceStamp.ps1: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
