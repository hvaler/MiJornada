#Requires -Version 5.1
<#
.SYNOPSIS
    Calcula el sello de plantilla por HASH DE CONTENIDO del *.yml.template de un stack CI/CD
    (drift de plantilla "preciso", ADR-047).

.DESCRIPTION
    Devuelve los primeros 12 hex del SHA256 del template del stack, con los line-endings
    NORMALIZADOS a LF antes de hashear (robusto a CRLF / git autocrlf entre consumidores).

    Es la UNICA fuente de verdad del hash: la invocan IGUAL /cicd-init (al sellar el YAML
    en FASE 2.8.1) y /cicd-status (al comprobar drift en seccion 1.5). Si las dos partes
    calcularan el hash por separado y divergieran, /cicd-status marcaria drift SIEMPRE.

    Por que hash-de-template y no el zip-sha del ECOSISTEMA (esquema previo, h13): el zip-sha
    cambia en CADA release aunque el template del stack sea identico -> /cicd-status marcaba
    drift cosmetico en cada bump (re-render = solo refrescar el sello). El hash de contenido
    del template solo cambia cuando el template REALMENTE cambia -> drift fiable.

    El placeholder {{TEMPLATE_STAMP}} forma parte del contenido hasheado, pero es CONSTANTE
    en el .template (nunca se sustituye en el fuente), asi que no afecta a la deteccion.

.PARAMETER Stack
    Token de stack del sello: dotnet | console | vue | netfx | netfx-branch-gated | netfx-fase1 | nettool.
    Se resuelve al *.yml.template correspondiente con el mapa interno.

.PARAMETER Template
    Alternativa a -Stack: ruta directa al *.yml.template (tiene prioridad sobre -Stack).

.PARAMETER TemplatesDir
    Carpeta de templates. Default: .claude/skills/cicd-architect/templates (relativa al cwd,
    que es la raiz del repo donde vive azure-pipelines.yml).

.OUTPUTS
    Imprime en stdout los 12 hex del hash (ej. '9f3c1a2b4d5e'). exit 0 OK / exit 2 error.

.EXAMPLE
    pwsh Get-TemplateStamp.ps1 -Stack netfx-branch-gated
    # -> 9f3c1a2b4d5e

.EXAMPLE
    $h = & pwsh .claude/skills/cicd-architect/templates/Get-TemplateStamp.ps1 -Stack dotnet
#>
[CmdletBinding()]
param(
    [string] $Stack,
    [string] $Template,
    [string] $TemplatesDir = '.claude/skills/cicd-architect/templates'
)

$ErrorActionPreference = 'Stop'

try {
    # Mapa stack -> fichero template. Tokens identicos a los de la cabecera de cada template
    # (# Ovillo cicd-architect <stack> @ {{TEMPLATE_STAMP}}). Unica copia del mapa en el
    # ecosistema: /cicd-init y /cicd-status pasan -Stack y NO duplican la tabla.
    $map = @{
        'dotnet'             = 'azure-pipelines.fase2.dotnet.yml.template'
        'console'            = 'azure-pipelines.fase2.console.yml.template'   # FB-B v3.16.0
        'vue'                = 'azure-pipelines.fase2.vue.yml.template'
        'netfx'              = 'azure-pipelines.fase2.netfx.yml.template'
        'netfx-branch-gated' = 'azure-pipelines.fase2.netfx.branch-gated.yml.template'
        'netfx-fase1'        = 'azure-pipelines.fase1.netfx.yml.template'
        'nettool'            = 'azure-pipelines.nettool.yml.template'
    }

    if (-not $Template) {
        if ([string]::IsNullOrWhiteSpace($Stack) -or -not $map.ContainsKey($Stack)) {
            Write-Host "ERROR: stack desconocido: '$Stack'. Validos: $($map.Keys -join ', '). O pasar -Template <ruta>." -ForegroundColor Red
            exit 2
        }
        $Template = Join-Path $TemplatesDir $map[$Stack]
    }

    if (-not (Test-Path -LiteralPath $Template)) {
        Write-Host "ERROR: template no encontrado: $Template" -ForegroundColor Red
        exit 2
    }

    # Leer BYTES CRUDOS (sin decodificar). CRITICO: NO usar Get-Content -Raw aqui -- decodifica
    # con el encoding por defecto del shell (PS 5.1 = ANSI/CP1252, PS 7 = UTF-8), y como los
    # templates tienen acentos/em-dashes el string resultante difiere por shell -> hash distinto
    # -> drift falso si el dev renderiza con un shell y comprueba con otro. Hashear bytes es
    # encoding-agnostico. Normalizar EOL a nivel de byte (CRLF y CR sueltos -> LF) para ser
    # robusto a git autocrlf entre consumidores.
    $raw = [System.IO.File]::ReadAllBytes($Template)
    $out = New-Object System.Collections.Generic.List[byte]
    for ($i = 0; $i -lt $raw.Length; $i++) {
        $b = $raw[$i]
        if ($b -eq 0x0D) {
            $out.Add([byte]0x0A)                                            # CR -> LF
            if (($i + 1) -lt $raw.Length -and $raw[$i + 1] -eq 0x0A) { $i++ }  # CRLF -> un solo LF
        }
        else {
            $out.Add($b)
        }
    }
    $bytes = $out.ToArray()

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha.ComputeHash($bytes)
    }
    finally {
        $sha.Dispose()
    }

    $hex = -join ($hashBytes | ForEach-Object { $_.ToString('x2') })
    Write-Output $hex.Substring(0, 12)
    exit 0
}
catch {
    Write-Host "ERROR inesperado en Get-TemplateStamp.ps1: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
