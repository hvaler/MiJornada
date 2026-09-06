#Requires -Version 5.1
<#
.SYNOPSIS
    Self-check determinista de completitud de un azure-pipelines.yml generado por /cicd-init.

.DESCRIPTION
    Verifica que un pipeline YAML generado contiene TODOS los steps/artefactos canonicos
    del template del stack del que deberia haberse renderizado. Disena para detectar
    "under-application" del edit-mode de /cicd-init (Opcion 4): cuando el agente hace un
    edit quirurgico de 1 linea en vez de re-renderizar el YAML completo, faltan steps de
    la plantilla (ej. el step R18 de Mira, el reporte HTML CoverageReport, etc.).

    NO mantiene una lista hardcodeada de markers: los DERIVA del propio template
    (displayNames + ArtifactName + referencias a steps/*.yml). Asi auto-sigue la evolucion
    de la plantilla sin tocar este script.

    Filosofia: en flujos copia+genera (forzados por TFS 2020, sin 'extends' fiable) la
    defensa es VERIFICAR LA SALIDA -- igual que el smoke test de /hotfix o validate-zip.ps1.

.PARAMETER Yaml
    Ruta al azure-pipelines.yml generado (la salida a verificar).

.PARAMETER Template
    Ruta al *.yml.template del stack usado para generar (la referencia).

.PARAMETER Quiet
    Solo emite el veredicto final y la lista de ausentes (sin cabeceras).

.OUTPUTS
    exit 0 = COMPLETO (todos los markers del template presentes en el YAML)
    exit 1 = INCOMPLETO (faltan markers -> regeneracion a medias, NO cerrar /cicd-init)
    exit 2 = ERROR (argumentos invalidos / ficheros no encontrados)

.EXAMPLE
    pwsh validate-pipeline-complete.ps1 -Yaml azure-pipelines.yml -Template .claude/skills/cicd-architect/templates/azure-pipelines.fase2.dotnet.yml.template
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Yaml,

    [Parameter(Mandatory = $true)]
    [string] $Template,

    # Substrings de markers que NO se exigen (bloques que /cicd-init dropea legitimamente:
    # sin proyecto de test -> 'dotnet test'/'coverage'/'Coverage gate'/'Reporte HTML'/'CoverageReport';
    # sin endpoint /health -> 'smoke-strict'; etc.). Coma-separados. Default: ninguno (estricto).
    [string] $Allow = '',

    [switch] $Quiet
)

$ErrorActionPreference = 'Stop'

function Write-Info([string] $msg) {
    if (-not $Quiet) { Write-Host $msg }
}

try {
    if (-not (Test-Path -LiteralPath $Yaml)) {
        Write-Host "ERROR: no existe el YAML generado: $Yaml" -ForegroundColor Red
        exit 2
    }
    if (-not (Test-Path -LiteralPath $Template)) {
        Write-Host "ERROR: no existe el template: $Template" -ForegroundColor Red
        exit 2
    }

    $yamlText = Get-Content -LiteralPath $Yaml -Raw
    $tplLines = Get-Content -LiteralPath $Template

    # -------------------------------------------------------------------------
    # Construir el TEXTO DEL YAML SIN bloques CUSTOM. Un marker del template que
    # el usuario haya retirado y envuelto en '# CUSTOM:' ... '# /CUSTOM' no debe
    # contar como presente por accidente, pero tampoco lo exigimos: simplemente
    # buscamos los markers del template en el cuerpo NO-custom del YAML.
    # -------------------------------------------------------------------------
    $yamlLines = Get-Content -LiteralPath $Yaml
    $sb = New-Object System.Text.StringBuilder
    $inCustom = $false
    foreach ($ln in $yamlLines) {
        if ($ln -match '#\s*CUSTOM\s*:') { $inCustom = $true; continue }
        if ($ln -match '#\s*/CUSTOM') { $inCustom = $false; continue }
        if (-not $inCustom) { [void]$sb.AppendLine($ln) }
    }
    $yamlBody = $sb.ToString()

    # -------------------------------------------------------------------------
    # Derivar markers del TEMPLATE.
    #   1) displayName: '<algo>'   -> cada step tiene displayName; si falta el step,
    #                                  falta su displayName en el YAML.
    #   2) ArtifactName: '<algo>'  -> artefactos publicados.
    #   3) - template: steps/x.yml -> sub-steps referenciados.
    # Normalizacion: los placeholders {{...}} se vuelven comodin (.*) porque /cicd-init
    # los sustituye; los $(...) son literales en ambos (variables runtime del pipeline).
    # -------------------------------------------------------------------------
    $markers = New-Object System.Collections.Generic.List[object]

    function Add-Marker([string] $kind, [string] $raw) {
        $val = $raw.Trim()
        # quitar comillas envolventes simples o dobles
        if ($val.Length -ge 2) {
            $first = $val.Substring(0, 1)
            $last = $val.Substring($val.Length - 1, 1)
            if (($first -eq "'" -and $last -eq "'") -or ($first -eq '"' -and $last -eq '"')) {
                $val = $val.Substring(1, $val.Length - 2)
            }
        }
        if ([string]::IsNullOrWhiteSpace($val)) { return }
        $script:markers.Add([pscustomobject]@{ Kind = $kind; Value = $val })
    }

    foreach ($line in $tplLines) {
        $m = [regex]::Match($line, '^\s*displayName:\s*(.+?)\s*$')
        if ($m.Success) { Add-Marker 'displayName' $m.Groups[1].Value; continue }

        $m = [regex]::Match($line, '^\s*ArtifactName:\s*(.+?)\s*$')
        if ($m.Success) { Add-Marker 'ArtifactName' $m.Groups[1].Value; continue }

        $m = [regex]::Match($line, '^\s*-\s*template:\s*(steps/[^\s#]+)')
        if ($m.Success) { Add-Marker 'template' $m.Groups[1].Value; continue }
    }

    if ($markers.Count -eq 0) {
        Write-Host "ERROR: el template no expone markers (displayName/ArtifactName/template). Template invalido?: $Template" -ForegroundColor Red
        exit 2
    }

    # Construir un regex por marker. Key-aware: cada marker se ancla a SU clave YAML
    # (displayName:/ArtifactName:/- template:) al inicio de linea, para no casar por
    # coincidencia el texto de un marker dentro de otra clave (ej. 'CoverageReport'
    # del ArtifactName aparece tambien en el displayName 'Publish CoverageReport...').
    # Los placeholders {{...}} se vuelven comodin (.*); el resto es literal.
    $keyPrefix = @{
        'displayName'  = '^\s*displayName:\s*[''"]?'
        'ArtifactName' = '^\s*ArtifactName:\s*[''"]?'
        'template'     = '^\s*-\s*template:\s*'
    }

    function ConvertTo-ValueRegex([string] $value) {
        # trocear por los placeholders {{...}} y escapar cada trozo literal
        $parts = [regex]::Split($value, '\{\{[^}]+\}\}')
        $escaped = @()
        foreach ($p in $parts) { $escaped += [regex]::Escape($p) }
        return ($escaped -join '.*')
    }

    # Exenciones: markers cuyo Value contiene alguno de estos substrings no se exigen.
    $allowList = @()
    if (-not [string]::IsNullOrWhiteSpace($Allow)) {
        $allowList = $Allow.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    }

    # Matching linea-a-linea sobre el cuerpo NO-custom (markers son de una sola linea).
    $bodyLines = $yamlBody -split "`r?`n"
    $missing = New-Object System.Collections.Generic.List[object]
    $exempted = 0
    $present = 0
    foreach ($mk in $markers) {
        $isAllowed = $false
        foreach ($a in $allowList) {
            if ($mk.Value -like "*$a*") { $isAllowed = $true; break }
        }
        if ($isAllowed) { $exempted++; continue }

        $rx = $keyPrefix[$mk.Kind] + (ConvertTo-ValueRegex $mk.Value)
        $found = $false
        foreach ($bl in $bodyLines) {
            if ($bl -match $rx) { $found = $true; break }
        }
        if ($found) { $present++ } else { $missing.Add($mk) }
    }

    Write-Info ""
    Write-Info "Self-check de completitud del pipeline"
    Write-Info "  YAML:     $Yaml"
    Write-Info "  Template: $Template"
    Write-Info "  Markers derivados del template: $($markers.Count) (presentes: $present, exentos: $exempted, ausentes: $($missing.Count))"

    if ($missing.Count -eq 0) {
        Write-Info ""
        Write-Host "OK: pipeline COMPLETO. Todos los steps/artefactos canonicos del template estan presentes." -ForegroundColor Green
        exit 0
    }

    Write-Host ""
    Write-Host "INCOMPLETO: faltan $($missing.Count) marker(s) del template en el YAML generado:" -ForegroundColor Yellow
    foreach ($mk in $missing) {
        Write-Host ("  [{0}] {1}" -f $mk.Kind, $mk.Value) -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "ACCION: el YAML NO refleja la plantilla completa (probable edit-mode parcial)." -ForegroundColor Yellow
    Write-Host "        Re-renderiza con /cicd-init Opcion 4 (re-render COMPLETO, no patch) y" -ForegroundColor Yellow
    Write-Host "        re-aplica solo los bloques '# CUSTOM:'. NO cerrar /cicd-init con el self-check en rojo." -ForegroundColor Yellow
    exit 1
}
catch {
    Write-Host "ERROR inesperado en validate-pipeline-complete.ps1: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
