# mcp-sync.ps1
# Script estable que invoca el comando /mcp-sync.
# Sincroniza 7 categorias del proyecto con el MCP Server Ovillo v2.
#
# Origen: Hotfix #8 v3.9.0 (ADR-035/036) - evita que cada ejecucion de /mcp-sync
# pida a Claude generar codigo ad-hoc (fragil, con bugs de parse).
#
# Uso:
#   pwsh .claude/scripts/mcp-sync.ps1                  # todas las categorias habilitadas
#   pwsh .claude/scripts/mcp-sync.ps1 -DryRun          # muestra que se enviaria
#   pwsh .claude/scripts/mcp-sync.ps1 -Categoria nugets  # solo una

#Requires -Version 5.1

[CmdletBinding()]
param(
    [switch]$DryRun,
    [ValidateSet('all', 'decisiones', 'lecciones', 'nugets', 'deuda', 'evolutivos', 'equipo', 'feedbackEcosistema')]
    [string]$Categoria = 'all'
)

$ErrorActionPreference = 'Stop'

# ---------- Pre-checks ----------

$credsPath = '_hilo/.mcp-credentials.json'
$estadoPath = '_hilo/ESTADO_PROYECTO.json'

if (-not (Test-Path $credsPath)) {
    Write-Host "ERROR: $credsPath no existe. Ejecuta /mcp-register primero." -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $estadoPath)) {
    Write-Host "ERROR: $estadoPath no existe. Ejecuta /onboarding primero." -ForegroundColor Red
    exit 1
}

$creds = Get-Content $credsPath -Raw | ConvertFrom-Json
$estado = Get-Content $estadoPath -Raw | ConvertFrom-Json

if (-not $estado.mcpSync -or -not $estado.mcpSync.habilitado) {
    Write-Host "ERROR: mcpSync.habilitado = false. Ejecuta /mcp-register para habilitar." -ForegroundColor Red
    exit 1
}

$serverUrl = if ($creds.serverUrl) { $creds.serverUrl } else { 'https://hub.example.org' }
$projectId = $creds.projectId
$apiKey = $creds.apiKey
$headers = @{ 'X-Hub-Api-Key' = $apiKey }
$categorias = $estado.mcpSync.categorias

function ShouldSync($name) {
    if ($Categoria -ne 'all') {
        return $Categoria -eq $name
    }
    # Si la categoria existe en mcpSync.categorias, respetar el valor.
    # Si NO existe (categoria nueva post-registro), defaultear a TRUE - asi nuevas
    # categorias funcionan sin obligar a re-ejecutar /mcp-register en cada hotfix.
    if ($null -eq $categorias) { return $true }
    $prop = $categorias.PSObject.Properties[$name]
    if ($null -eq $prop) { return $true }
    return $prop.Value -eq $true
}

# ---------- Parsers ----------

function Parse-Decisiones {
    if (-not (Test-Path '_hilo/DECISIONES.md')) { return @() }
    $content = Get-Content '_hilo/DECISIONES.md' -Raw
    $items = @()
    # Patron: ## ADR-XXX: Titulo  (o ### D1: ...)
    $pattern = '(?ms)^##+\s+(ADR-\d+|D\d+)[:\s]+([^\r\n]+).*?(?=^##+\s+(?:ADR-|D\d+)|\Z)'
    foreach ($m in [regex]::Matches($content, $pattern)) {
        $codigo = $m.Groups[1].Value.Trim()
        $titulo = $m.Groups[2].Value.Trim()
        $body = $m.Value

        # Skip placeholders del template (ej. "[Titulo de la Decision]", "[YYYY-MM-DD]").
        # Heuristica: si el titulo es exactamente "[...]" o contiene solo bracket-text, ignorar.
        if ($titulo -match '^\[.+\]$') { continue }

        $estado_ = $null
        if ($body -match '\*\*Estado\*\*\s*:\s*(?:[\p{So}\p{S}]\s*)?([A-Za-z]+)') { $estado_ = $matches[1] }
        # Skip si el "estado" es tambien placeholder tipo "[Aceptada/Deprecada/...]"
        if ($estado_ -match '^\[') { $estado_ = $null }
        $fecha = $null
        if ($body -match '\*\*Fecha\*\*\s*:\s*(\d{4}-\d{2}-\d{2})') { $fecha = $matches[1] }
        $tags = $null
        if ($body -match '\*\*Tags\*\*\s*:\s*([^\r\n]+)') {
            $t = $matches[1].Trim()
            if ($t -notmatch '^\[') { $tags = $t }
        }

        $items += @{
            codigo = $codigo
            titulo = $titulo
            estado = $estado_
            fechaDecision = $fecha
            tags = $tags
        }
    }
    return $items
}

function Parse-Lecciones {
    if (-not (Test-Path '_hilo/LECCIONES.md')) { return @() }
    $content = Get-Content '_hilo/LECCIONES.md' -Raw
    $items = @()
    $pattern = '(?ms)^###\s+([^\r\n]+)(.*?)(?=^###\s+|\Z)'
    foreach ($m in [regex]::Matches($content, $pattern)) {
        $titulo = $m.Groups[1].Value.Trim()
        $body = $m.Groups[2].Value

        # Skip placeholders del template (ej. "PAT-001: [Nombre del patron]").
        if ($titulo -match '\[.+\]') { continue }

        # Skip headers estructurales del template (no son lecciones reales).
        # Una leccion real SIEMPRE tiene al menos un campo etiquetado **Categoria/Severidad/...**: en body.
        # Si el body NO tiene NINGUNO de esos campos -> es un H3 estructural (ej. "Automaticamente", "Manualmente").
        if ($body -notmatch '(?im)^\s*\*?\*?(Categoria|Severidad|Fecha|Descripcion|Patron|Aplicacion|Impacto|Solucion|Workaround|Contexto)\*?\*?\s*:') {
            continue
        }

        $categoria_ = $null
        if ($body -match '(?im)^\s*\*?\*?Categoria\*?\*?\s*:\s*([^\r\n]+)') {
            $c = $matches[1].Trim()
            if ($c -notmatch '^\[') { $categoria_ = $c }
        }
        # h10: si no hay campo Categoria explicito, inferirla del PREFIJO del codigo del titulo
        # (PAT-/ERR-/TEC-/PREF- del template LECCIONES.md). Asi las lecciones se categorizan
        # solas en el dashboard (eje 'categoria') sin que el consumidor anada nada; aplica tambien
        # a lecciones ya existentes en el proximo /mcp-sync (UPSERT).
        if (-not $categoria_) {
            switch -regex ($titulo) {
                '^\s*PAT-'  { $categoria_ = 'patron' }
                '^\s*ERR-'  { $categoria_ = 'error' }
                '^\s*TEC-'  { $categoria_ = 'tecnica' }
                '^\s*PREF-' { $categoria_ = 'preferencia' }
                '^\s*LEC-'  { $categoria_ = 'leccion' }
            }
        }
        $severidad = $null
        if ($body -match '(?im)^\s*\*?\*?Severidad\*?\*?\s*:\s*(alta|media|baja)') { $severidad = $matches[1].ToLower() }
        $fecha = $null
        if ($body -match '(?im)^\s*\*?\*?Fecha\*?\*?\s*:\s*(\d{4}-\d{2}-\d{2})') { $fecha = $matches[1] }

        $descripcion = ($body -replace '(?im)^\s*\*?\*?(Categoria|Severidad|Fecha)\*?\*?\s*:\s*[^\r\n]+\r?\n', '').Trim()
        if ($descripcion.Length -gt 4000) { $descripcion = $descripcion.Substring(0, 4000) + '...' }

        $items += @{
            titulo = $titulo
            categoria = $categoria_
            descripcion = $descripcion
            severidad = $severidad
            fechaAprendizaje = $fecha
        }
    }
    return $items
}

function Parse-Nugets {
    $items = @{}  # packageId -> @{packageId, version, isCpm, esVulnerable}

    # 1. Directory.Packages.props (CPM)
    foreach ($props in (Get-ChildItem -Recurse -Filter 'Directory.Packages.props' -ErrorAction SilentlyContinue)) {
        try {
            [xml]$x = Get-Content $props.FullName
            # Aplanar todos los <ItemGroup>: cuando hay varios, $x.Project.ItemGroup es array
            # y necesitamos iterar cada uno explicitamente.
            $itemGroups = @($x.Project.ItemGroup)
            foreach ($ig in $itemGroups) {
                if (-not $ig) { continue }
                $pvs = @($ig.PackageVersion)
                foreach ($pv in $pvs) {
                    if (-not $pv -or -not $pv.Include) { continue }
                    $id = $pv.Include
                    $ver = $pv.Version
                    if ($id -and $ver) {
                        $items[$id] = @{packageId = $id; version = $ver; isCpm = $true; esVulnerable = $false}
                    }
                }
            }
        } catch {}
    }

    # 2. *.csproj (PackageReference no-CPM)
    foreach ($csproj in (Get-ChildItem -Recurse -Filter '*.csproj' -ErrorAction SilentlyContinue)) {
        try {
            [xml]$x = Get-Content $csproj.FullName
            $itemGroups = @($x.Project.ItemGroup)
            foreach ($ig in $itemGroups) {
                if (-not $ig) { continue }
                $refs = @($ig.PackageReference)
                foreach ($r in $refs) {
                    if (-not $r -or -not $r.Include) { continue }
                    $id = $r.Include
                    $ver = if ($r.Version) { $r.Version } elseif ($items[$id]) { $items[$id].version } else { $null }
                    if (-not $ver) { continue }
                    if (-not $items.ContainsKey($id)) {
                        $items[$id] = @{packageId = $id; version = $ver; isCpm = $false; esVulnerable = $false}
                    }
                }
            }
        } catch {}
    }

    return @($items.Values)
}

# h11 (CVE): escaneo best-effort de vulnerabilidades via 'dotnet list package --vulnerable'.
# Marca esVulnerable/severidad/cveCodigo en los items que correspondan (el Hub ya los acepta en f3-batch).
# Requiere dotnet CLI + proyecto restaurado + acceso a la BD de avisos de NuGet; si algo falta, SKIP silencioso
# (los nugets se envian sin marca, como hasta ahora). NO bloquea ni rompe el sync.
function Add-VulnerabilityInfo {
    param([object[]]$nugets)
    if (-not $nugets -or $nugets.Count -eq 0) { return }
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { return }
    $sln = Get-ChildItem -Recurse -Filter '*.sln' -ErrorAction SilentlyContinue | Select-Object -First 1
    $target = if ($sln) { $sln.FullName } else { (Get-Location).Path }
    Write-Host "Escaneando vulnerabilidades (dotnet list package --vulnerable, best-effort)..." -ForegroundColor Cyan
    try {
        $raw = & dotnet list $target package --vulnerable --include-transitive --format json 2>$null | Out-String
        if (-not $raw -or $raw.IndexOf('{') -lt 0) { Write-Host "  [SKIP] sin salida JSON (SDK < 8 o proyecto sin restore)" -ForegroundColor DarkGray; return }
        $data = $raw | ConvertFrom-Json
        $byId = @{}
        foreach ($n in $nugets) { if ($n.packageId) { $byId["$($n.packageId)".ToLower()] = $n } }
        $marcados = 0
        foreach ($proj in @($data.projects)) {
            foreach ($fw in @($proj.frameworks)) {
                $pkgs = @($fw.topLevelPackages) + @($fw.transitivePackages)
                foreach ($pkg in $pkgs) {
                    if (-not $pkg -or -not $pkg.vulnerabilities -or @($pkg.vulnerabilities).Count -eq 0) { continue }
                    $item = $byId["$($pkg.id)".ToLower()]
                    if (-not $item) { continue }
                    $worst = 'baja'; $cve = $null
                    foreach ($v in @($pkg.vulnerabilities)) {
                        $sev = "$($v.severity)".ToLower()
                        $map = if ($sev -match 'crit|high|alto') { 'alta' } elseif ($sev -match 'mod|med') { 'media' } else { 'baja' }
                        if ($map -eq 'alta') { $worst = 'alta' } elseif ($map -eq 'media' -and $worst -ne 'alta') { $worst = 'media' }
                        if (-not $cve -and "$($v.advisoryurl)" -match '(GHSA-[\w-]+|CVE-\d{4}-\d+)') { $cve = $matches[1] }
                    }
                    $item.esVulnerable = $true
                    $item.severidad = $worst
                    if ($cve) { $item.cveCodigo = $cve }
                    $marcados++
                }
            }
        }
        if ($marcados -gt 0) { Write-Host "  [OK] $marcados paquete(s) con vulnerabilidades conocidas" -ForegroundColor Yellow }
        else { Write-Host "  [OK] sin vulnerabilidades conocidas" -ForegroundColor Green }
    } catch {
        Write-Host "  [SKIP] escaneo no disponible (requiere restore + acceso a la BD de avisos)" -ForegroundColor DarkGray
    }
}

function Parse-Deuda {
    if (-not (Test-Path '_hilo/DEUDA_TECNICA.md')) { return @() }
    $content = Get-Content '_hilo/DEUDA_TECNICA.md' -Raw
    $items = @()

    # Helper: normalizar severidad libre -> schema server (alta|media|baja|null)
    function Normalize-Severidad($s) {
        if (-not $s) { return $null }
        $low = $s.ToLower()
        if ($low -match 'crit|alta|alto|high') { return 'alta' }
        if ($low -match 'media|medium|moderada?') { return 'media' }
        if ($low -match 'baja|low|menor') { return 'baja' }
        return $null
    }
    # Helper: normalizar estado libre -> schema server
    function Normalize-Estado($s) {
        if (-not $s) { return 'pendiente' }
        $low = $s.ToLower()
        if ($low -match 'progreso|wip|en_curso') { return 'en_progreso' }
        if ($low -match 'resuelt|cerrad|fix|done') { return 'resuelta' }
        if ($low -match 'descart|cancel|reject') { return 'descartada' }
        # 'aceptada' / 'pendiente' / 'identificada' -> pendiente (deuda activa)
        return 'pendiente'
    }

    # Patron PRIMARIO: bloque '### CODIGO: Titulo' con campos **Categoria/Criticidad/Estado**.
    # CODIGO = prefijo de area de 2-4 letras + numero. No solo DT-/TD-: tambien
    # SEC-, DEP-, BUG-, OBS-, RES-, COD-, TST-, PERF-, ARCH-, etc. (convencion por dominio,
    # auto-generada por /init y /analizar). TEC-005: antes solo casaba DT-/TD- -> deuda=0 silencioso.
    $pattern = '(?ms)^###\s+([A-Z]{2,4}-\d+)[:\s]+([^\r\n]+)(.*?)(?=^###\s+[A-Z]{2,4}-\d+|\Z)'
    foreach ($m in [regex]::Matches($content, $pattern)) {
        $codigo = $m.Groups[1].Value.Trim()
        $titulo = $m.Groups[2].Value.Trim()
        # Skip placeholders del template (ej. "[Titulo]")
        if ($titulo -match '^\[.+\]$') { continue }
        $body = $m.Groups[3].Value

        $severidad = $null
        # Probar Criticidad primero (estandar de la organización), luego Severidad
        if ($body -match '(?im)^\s*\*?\*?Criticidad\*?\*?\s*:\s*([^\r\n]+)') {
            $severidad = Normalize-Severidad $matches[1].Trim()
        } elseif ($body -match '(?im)^\s*\*?\*?Severidad\*?\*?\s*:\s*([^\r\n]+)') {
            $severidad = Normalize-Severidad $matches[1].Trim()
        }

        $estado = 'pendiente'
        if ($body -match '(?im)^\s*\*?\*?Estado\*?\*?\s*:\s*([^\r\n]+)') {
            $estado = Normalize-Estado $matches[1].Trim()
        }

        $items += @{
            codigo = $codigo
            titulo = $titulo
            severidad = $severidad
            estado = $estado
        }
    }

    # Si el patron primario no encontro nada, fallback al patron LEGACY tabla.
    if ($items.Count -eq 0) {
        foreach ($line in ($content -split "`n")) {
            if ($line -match '^\|?\s*([A-Z]{2,4}-\d+)\s*\|\s*([^|]+?)\s*\|\s*([^|]*?)\s*\|\s*([^|]*?)\s*\|') {
                $codigo = $matches[1]
                $titulo = $matches[2].Trim()
                if ($titulo -match '^\[.+\]$') { continue }
                $items += @{
                    codigo = $codigo
                    titulo = $titulo
                    severidad = Normalize-Severidad $matches[3].Trim()
                    estado = Normalize-Estado $matches[4].Trim()
                }
            }
        }
    }
    return $items
}

function Parse-Evolutivos {
    $items = @()
    $bloqueadores = @()
    if (-not $estado.evolutivos) { return @{evolutivos = @(); bloqueadores = @()} }

    # Iteracion por bucket: el ESTADO se infiere del bucket (pendientes/enProgreso/completados)
    # cuando el campo no esta explicito en el evolutivo - estandar Ovillo v3.7+.
    $buckets = @(
        @{ lista = $estado.evolutivos.pendientes;  estadoDefault = 'pendiente' },
        @{ lista = $estado.evolutivos.enProgreso;  estadoDefault = 'en_progreso' },
        @{ lista = $estado.evolutivos.completados; estadoDefault = 'completado' }
    )

    foreach ($b in $buckets) {
        if (-not $b.lista) { continue }
        foreach ($e in $b.lista) {
            if (-not $e -or -not $e.codigo) { continue }
            # Titulo: soporta 'titulo' o 'nombre' (esquemas distintos en el wild).
            # Si ambos vacios, derivar del codigo para nunca enviar null al server (SP requiere).
            $titulo = if ($e.titulo) { $e.titulo } elseif ($e.nombre) { $e.nombre } else { $e.codigo }
            $estadoFinal = if ($e.estado) { $e.estado } else { $b.estadoDefault }
            $items += @{
                codigo = $e.codigo
                titulo = $titulo
                estado = $estadoFinal
                asignadoA = $e.asignadoA
                prioridad = $e.prioridad
                fechaCreacion = $e.fechaCreacion
                fechaInicio = $e.fechaInicio
                fechaEstimada = $e.fechaEstimada
                fechaCompletado = $e.fechaCompletado
            }
        }
    }

    if ($estado.desarrollo -and $estado.desarrollo.bloqueadores) {
        foreach ($b in $estado.desarrollo.bloqueadores) {
            if (-not $b) { continue }
            $desc = if ($b -is [string]) { $b } else { $b.descripcion }
            if (-not $desc) { continue }
            $bloqueadores += @{
                descripcion = $desc
                estaResuelto = $false
            }
        }
    }

    return @{evolutivos = @($items); bloqueadores = @($bloqueadores)}
}

function Parse-Equipo {
    $items = @()
    if ($estado.equipo -and $estado.equipo.miembros) {
        foreach ($m in $estado.equipo.miembros) {
            if (-not $m -or -not $m.usuario -or $m.usuario.StartsWith('ejemplo_')) { continue }
            $roles = if ($m.roles) {
                if ($m.roles -is [array]) { $m.roles -join ',' } else { $m.roles }
            } elseif ($m.rol) { $m.rol } else { $null }
            $items += @{
                usuario = $m.usuario
                nombreCompleto = $m.nombre
                roles = $roles
                esActivo = $true
            }
        }
    }
    return $items
}

function Parse-Branching {
    # Devuelve siempre un hashtable (nunca $null) - el server rechaza branching=null
    # con HTTP 400. Si no hay config, se envia un hashtable con campos en ''.
    $empty = @{ estrategia = ''; mergeStrategy = ''; convencionRamas = ''; ramaBase = '' }
    if (-not $estado.configuracion) { return $empty }

    # 1. Nuevo esquema canonico: configuracion.branching.*
    if ($estado.configuracion.branching -and $estado.configuracion.branching.estrategia) {
        $b = $estado.configuracion.branching
        return @{
            estrategia = if ($b.estrategia) { $b.estrategia } else { '' }
            mergeStrategy = if ($b.mergeStrategy) { $b.mergeStrategy } else { '' }
            convencionRamas = if ($b.convencionRamas) { $b.convencionRamas } else { '' }
            ramaBase = if ($b.ramaBase) { $b.ramaBase } else { '' }
        }
    }

    # 2. Esquema legacy plano: configuracion.{convencionRamas,ramaBase}
    if ($estado.configuracion.convencionRamas -or $estado.configuracion.ramaBase) {
        return @{
            estrategia = ''
            mergeStrategy = ''
            convencionRamas = if ($estado.configuracion.convencionRamas) { $estado.configuracion.convencionRamas } else { '' }
            ramaBase = if ($estado.configuracion.ramaBase) { $estado.configuracion.ramaBase } else { '' }
        }
    }

    return $empty
}

function Parse-FeedbackEcosistema {
    # Canal feedback ecosistema (ADR-044 v3.13.0): bloques '### FB-NNN: Titulo' con campos
    # **Categoria/Severidad/Estado/VersionEcosistema/FechaDeteccion/Descripcion**.
    # Solo sincroniza codigos FB-<numerico> (FB-EJEMPLO y similares se ignoran).
    if (-not (Test-Path '_hilo/FEEDBACK_ECOSISTEMA.md')) { return @() }
    $content = Get-Content '_hilo/FEEDBACK_ECOSISTEMA.md' -Raw
    $items = @()

    $categoriasValidas = @('comando', 'skill', 'hook', 'regla', 'template', 'agent', 'docs', 'hub', 'otro')
    $severidadesValidas = @('alta', 'media', 'baja')
    $estadosValidos = @('abierto', 'en_analisis', 'resuelto', 'descartado', 'diferido')

    # Extrae el valor de un campo '- **Nombre**: valor' (tolerante a variantes sin '-' o sin '**')
    function Get-CampoFb($texto, $nombre) {
        if ($texto -match "(?im)^\s*-?\s*\*?\*?$nombre\*?\*?\s*:\s*([^\r\n]+)") { return $matches[1].Trim() }
        return $null
    }

    $pattern = '(?ms)^###\s+(FB-\d+)[:\s]+([^\r\n]+)(.*?)(?=^###\s+FB-|\Z)'
    foreach ($m in [regex]::Matches($content, $pattern)) {
        $codigo = $m.Groups[1].Value.Trim()
        $titulo = $m.Groups[2].Value.Trim()
        # Skip placeholders del template (ej. "[Titulo]")
        if ($titulo -match '^\[.+\]$') { continue }
        $body = $m.Groups[3].Value

        $categoria = Get-CampoFb $body 'Categoria'
        if ($categoria) { $categoria = $categoria.ToLower(); if ($categoria -notin $categoriasValidas) { $categoria = 'otro' } }
        $severidad = Get-CampoFb $body 'Severidad'
        if ($severidad) { $severidad = $severidad.ToLower(); if ($severidad -notin $severidadesValidas) { $severidad = $null } }
        $itemEstado = Get-CampoFb $body 'Estado'
        if ($itemEstado) { $itemEstado = $itemEstado.ToLower() -replace ' ', '_'; if ($itemEstado -notin $estadosValidos) { $itemEstado = 'abierto' } } else { $itemEstado = 'abierto' }
        $fecha = Get-CampoFb $body 'FechaDeteccion'
        if ($fecha -and $fecha -notmatch '^\d{4}-\d{2}-\d{2}$') { $fecha = $null }   # placeholders [YYYY-MM-DD]

        $items += @{
            codigo = $codigo
            titulo = $titulo
            descripcion = Get-CampoFb $body 'Descripcion'
            categoria = $categoria
            severidad = $severidad
            estado = $itemEstado
            versionEcosistema = Get-CampoFb $body 'VersionEcosistema'
            versionResolucion = Get-CampoFb $body 'VersionResolucion'
            fechaDeteccion = $fecha
        }
    }
    return $items
}

# ---------- Recolectar ----------

Write-Host "Recolectando datos del proyecto..." -ForegroundColor Cyan
# @(...) en el lado del call-site garantiza array (defensa contra PS unwrap de single-element).
$decisiones = @(if (ShouldSync 'decisiones') { Parse-Decisiones })
$lecciones  = @(if (ShouldSync 'lecciones')  { Parse-Lecciones })
$nugets     = @(if (ShouldSync 'nugets')     { Parse-Nugets })
if ($nugets.Count -gt 0) { Add-VulnerabilityInfo $nugets }   # h11 (CVE): marca esVulnerable/severidad/cve best-effort
$deuda      = @(if (ShouldSync 'deuda')      { Parse-Deuda })
$evolBloq   = if (ShouldSync 'evolutivos') { Parse-Evolutivos } else { @{evolutivos = @(); bloqueadores = @()} }
$equipo     = @(if (ShouldSync 'equipo')     { Parse-Equipo })
# Branching siempre se envia (es un hashtable, no un array). Parse-Branching nunca devuelve $null.
$branching  = if (ShouldSync 'equipo') { Parse-Branching } else { @{estrategia=''; mergeStrategy=''; convencionRamas=''; ramaBase=''} }
$feedbackEco = @(if (ShouldSync 'feedbackEcosistema') { Parse-FeedbackEcosistema })

# ---------- Resumen / dry-run ----------

Write-Host ""
Write-Host "Listo para sincronizar:" -ForegroundColor Cyan
Write-Host "  decisiones : $($decisiones.Count)"
Write-Host "  lecciones  : $($lecciones.Count)"
Write-Host "  nugets     : $($nugets.Count)"
Write-Host "  deuda      : $($deuda.Count)"
Write-Host "  evolutivos : $($evolBloq.evolutivos.Count) + $($evolBloq.bloqueadores.Count) bloqueadores"
Write-Host "  equipo     : $($equipo.Count)"
Write-Host "  branching  : $(if ($branching.estrategia) { $branching.estrategia } elseif ($branching.ramaBase) { "(legacy ramaBase=$($branching.ramaBase))" } else { '(no config)' })"
Write-Host "  feedback   : $($feedbackEco.Count) (ecosistema FB-XXX)"
Write-Host ""
Write-Host "Destino: $serverUrl"
Write-Host "ProjectId: $projectId"
Write-Host ""

if ($DryRun) {
    Write-Host "Dry-run - no se envia nada." -ForegroundColor Yellow
    exit 0
}

# ---------- Enviar ----------

$totalErrors = 0

function SendPost($url, $body, $label) {
    try {
        $resp = Invoke-RestMethod -Uri $url -Method Post -Headers $headers `
            -Body ($body | ConvertTo-Json -Depth 6 -Compress) `
            -ContentType 'application/json' -TimeoutSec 60
        Write-Host "  [OK] $label" -ForegroundColor Green
        return $resp
    } catch {
        $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        # Intentar leer el body de la respuesta de error (utiles para 4xx con detalle)
        $errBody = ''
        try {
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                $errBody = $_.ErrorDetails.Message
            } elseif ($_.Exception.Response) {
                $stream = $_.Exception.Response.GetResponseStream()
                if ($stream) {
                    $reader = New-Object System.IO.StreamReader($stream)
                    $errBody = $reader.ReadToEnd()
                }
            }
        } catch {}
        $shortBody = if ($errBody.Length -gt 300) { $errBody.Substring(0, 300) + '...' } else { $errBody }
        Write-Host "  [FAIL] $label (HTTP ${status})" -ForegroundColor Red
        if ($shortBody) { Write-Host "         Server: $shortBody" -ForegroundColor DarkRed }
        $script:totalErrors++
        return $null
    }
}

# Decisiones + lecciones via /v2/hilo/batch
if (($decisiones.Count + $lecciones.Count) -gt 0) {
    Write-Host "Enviando Hilo (decisiones + lecciones)..." -ForegroundColor Cyan
    # @(...) garantiza array JSON aunque haya 1 solo elemento (PS unwrap defense).
    $body = @{
        projectId = $projectId
        decisiones = @($decisiones)
        lecciones = @($lecciones)
    }
    SendPost "$serverUrl/v2/hilo/batch" $body "hilo/batch ($($decisiones.Count) decisiones + $($lecciones.Count) lecciones)" | Out-Null
}

# Nugets + deuda + evolutivos + equipo + branching via /v2/sync/f3-batch
$hasBranching = $branching.estrategia -or $branching.ramaBase
$f3Items = $nugets.Count + $deuda.Count + $evolBloq.evolutivos.Count + $evolBloq.bloqueadores.Count + $equipo.Count
if ($f3Items -gt 0 -or $hasBranching) {
    Write-Host "Enviando F3 (nugets + deuda + evolutivos + equipo + branching)..." -ForegroundColor Cyan
    $body = @{
        projectId = $projectId
        nugets = @($nugets)
        deuda = @($deuda)
        evolutivos = @($evolBloq.evolutivos)
        bloqueadores = @($evolBloq.bloqueadores)
        equipo = @($equipo)
        branching = $branching
    }
    $f3Label = "f3-batch (N=$($nugets.Count) D=$($deuda.Count) E=$($evolBloq.evolutivos.Count) B=$($evolBloq.bloqueadores.Count) Eq=$($equipo.Count) Br=$(if ($hasBranching) { 1 } else { 0 }))"
    SendPost "$serverUrl/v2/sync/f3-batch" $body $f3Label | Out-Null
}

# CI/CD pipelines via /v2/sync/cicd-batch (Sprint 3b ADR-042 v3.11.0)
#
# Filosofia best-effort: feature opt-in via schema. Si el proyecto no declara pipelines
# o esta en Fase 0 (deploy manual sin TFS), no se envia nada. Si envia y el endpoint
# todavia no esta desplegado (Sprint 4 pending) o devuelve error, se loguea SKIP
# pero NO incrementa $totalErrors - mcp-sync sigue marcando exito si el resto fue OK.
#
# Schemas soportados defensivamente:
#   Schemas soportados (HALLAZGO G - tolerancia, Opcion A):
#   - infraestructura.cicd = OBJETO {plataforma, ..., pipelines:[...]} (CANONICO; el objeto conserva
#     'plataforma' para devops-awareness Y el array 'pipelines[]' que consume mcp-sync).
#   - infraestructura.cicd = ARRAY de pipelines (compat schema directo).
#   - Objeto legacy sin 'pipelines' -> no hay pipelines que enviar.
#   Solo se envian entries con fase >= 1 (Fase 0 es local-only, sin pipeline TFS).
$cicdEntries = @()
try {
    if ($estado.infraestructura -and $estado.infraestructura.cicd) {
        $cicdRaw = $estado.infraestructura.cicd
        if ($cicdRaw -is [array]) {
            $list = $cicdRaw                                    # schema array directo
        } elseif ($cicdRaw -and $cicdRaw.pipelines -is [array]) {
            $list = $cicdRaw.pipelines                          # CANONICO: objeto + pipelines[] (HALLAZGO G)
        } else {
            $list = @()                                         # objeto legacy sin pipelines
        }
        $cicdEntries = @($list | Where-Object {
            $null -ne $_ -and $null -ne $_.fase -and [int]$_.fase -ge 1
        })
    }
} catch {
    # JSON malformado o estructura inesperada -> skip silencioso
}

# h7: enriquecer cada pipeline con su ultimo build + historial de deploys desde TFS.
# Best-effort (Negotiate via -UseDefaultCredentials + TLS 1.2 R2 + api-version 6.0): si TFS
# no responde o el dev no tiene acceso, se omite y el batch va igual (sin build/deploys).
# Deploys = builds con parametro DeployEnv in dev/pre/pro (modelo on-demand R20/branch-gated R24).
$buildInfoMap = @{}
if ($cicdEntries.Count -gt 0) {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.ServicePointManager]::SecurityProtocol } catch {}
    $azdoUrl = $null
    try { if ($estado.infraestructura.azureDevOps -and $estado.infraestructura.azureDevOps.url) { $azdoUrl = "$($estado.infraestructura.azureDevOps.url)".TrimEnd('/') } } catch {}
    foreach ($pe in $cicdEntries) {
        $defId = "$($pe.pipelineId)"
        if ($defId -notmatch '^\d+$') { continue }   # 'manual'/sin def TFS -> sin builds
        # base de API = parte del url del pipeline antes de /_build (collection/project); fallback azureDevOps.url
        $apiBase = $null
        if ($pe.url) {
            $u = "$($pe.url)"
            foreach ($m in @('/_build','/_apis','/_git')) {
                $i = $u.IndexOf($m); if ($i -gt 0) { $apiBase = $u.Substring(0, $i); break }
            }
        }
        if (-not $apiBase) { $apiBase = $azdoUrl }
        if (-not $apiBase) { continue }
        try {
            $bUrl = "$apiBase/_apis/build/builds?definitions=$defId&" + '$top=25&queryOrder=finishTimeDescending&api-version=6.0'
            $r = Invoke-RestMethod -Uri $bUrl -UseDefaultCredentials -TimeoutSec 30 -ErrorAction Stop
            $builds = @($r.value)
            if ($builds.Count -eq 0) { continue }
            # ultimo build: el mas reciente con finishTime; si ninguno acabado, el primero
            $last = $builds | Where-Object { $_.finishTime } | Select-Object -First 1
            if (-not $last) { $last = $builds[0] }
            $ub = $null; $ubs = $null
            if ($last) {
                $ub = if ($last.finishTime) { $last.finishTime } elseif ($last.queueTime) { $last.queueTime } else { $null }
                switch ("$($last.result)") {
                    'succeeded'          { $ubs = 'succeeded' }
                    'partiallySucceeded' { $ubs = 'succeeded' }
                    'failed'             { $ubs = 'failed' }
                    'canceled'           { $ubs = 'failed' }
                    default              { $ubs = $null }
                }
            }
            $deps = @()
            foreach ($b in $builds) {
                $denv = $null
                if ($b.parameters) { try { $pj = $b.parameters | ConvertFrom-Json; if ($pj.DeployEnv) { $denv = "$($pj.DeployEnv)".ToLower().Trim() } } catch {} }
                if ((-not $denv) -and $b.templateParameters -and $b.templateParameters.DeployEnv) { $denv = "$($b.templateParameters.DeployEnv)".ToLower().Trim() }
                if (@('dev','pre','pro') -contains $denv) {
                    $bf = if ($b.finishTime) { $b.finishTime } elseif ($b.queueTime) { $b.queueTime } else { $null }
                    $be = if ($b.result) { "$($b.result)" } else { "$($b.status)" }
                    $bw = $null; try { $bw = "$($b._links.web.href)" } catch {}
                    if ($bf) { $deps += @{ entorno = $denv; buildId = "$($b.id)"; fecha = $bf; estado = $be; url = $bw } }
                }
            }
            $buildInfoMap[$defId] = @{ ultimoBuild = $ub; ultimoBuildStatus = $ubs; deploys = $deps }
        } catch {
            # TFS inaccesible para este pipeline -> sin build/deploys (best-effort, no rompe el batch)
        }
    }
}

if ($cicdEntries.Count -gt 0) {
    Write-Host "Enviando CI/CD pipelines (fase>=1)..." -ForegroundColor Cyan
    try {
        # FB-003 (v3.15.0-h5): forzar serializacion como ARRAY. ConvertTo-Json desenvuelve los arrays
        # de 1 elemento a escalar -> un pipeline single-stage (Console CI-only / Fase 1: stages=['Build'])
        # salia como "stages":"Build" (string) y el Hub rechazaba TODO el batch con 400 (cuerpo vacio,
        # error de binding). List[T] NO se desenvuelve. Aplica a 'stages' Y al array externo 'pipelines'
        # (un proyecto de 1 pipeline tambien desenvolveria 'pipelines'). Validado en PS 5.1 y pwsh.
        $cicdBody = @{
            projectId = $projectId
            pipelines = [System.Collections.Generic.List[object]]@($cicdEntries | ForEach-Object {
                $bi = $buildInfoMap["$($_.pipelineId)"]   # h7: build/deploys recogidos de TFS (o $null)
                @{
                    pipelineId = "$($_.pipelineId)"   # string forzado (TFS devuelve numero)
                    nombre = "$($_.nombre)"
                    url = if ($_.url) { "$($_.url)" } else { $null }
                    fase = [int]$_.fase
                    stages = if ($_.stages) { [System.Collections.Generic.List[string]]@($_.stages) } else { [System.Collections.Generic.List[string]]::new() }
                    stack = if ($_.stack) { "$($_.stack)" } else { $null }
                    # h7: List[object] tambien aqui (1 deploy no debe desenvolverse a escalar, leccion FB-003)
                    ultimoBuild = if ($bi) { $bi.ultimoBuild } else { $null }
                    ultimoBuildStatus = if ($bi) { $bi.ultimoBuildStatus } else { $null }
                    deploys = if ($bi -and $bi.deploys) { [System.Collections.Generic.List[object]]@($bi.deploys) } else { [System.Collections.Generic.List[object]]::new() }
                }
            })
        }
        Invoke-RestMethod -Uri "$serverUrl/v2/sync/cicd-batch" -Method Post -Headers $headers `
            -Body ($cicdBody | ConvertTo-Json -Depth 8 -Compress) `
            -ContentType 'application/json' -TimeoutSec 60 -ErrorAction Stop | Out-Null
        Write-Host "  [OK] cicd-batch ($($cicdEntries.Count) pipelines registrados)" -ForegroundColor Green
    } catch {
        $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        # Best-effort: NO incrementar $totalErrors. El endpoint /v2/sync/cicd-batch ESTA desplegado en
        # demowww (v3.11.0+, GET->405 confirma la ruta). Un 404 indicaria Hub desactualizado; 401/timeout = red/credenciales.
        # FB-001/v3.15.0-h4: surface del cuerpo del error -> el 400 del Hub trae {"error":"..."} (ej. 'projectId
        # requerido' o 'fase debe ser 0/1/2'); imprimirlo convierte el 400 opaco en accionable. El payload local
        # ya es correcto (6 campos del modelo CicdBatchPipeline + pipelineId string + fase int); si hay 400, el
        # motivo esta en el cuerpo, no en este builder.
        $body = ''
        try {
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $body = "$($_.ErrorDetails.Message)" }
            elseif ($_.Exception.Response) {
                $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $body = $sr.ReadToEnd(); $sr.Dispose()
            }
        } catch {}
        if ($body.Length -gt 300) { $body = $body.Substring(0, 300) + '...' }
        $hint = if ($status -eq 404) { ' (endpoint no encontrado - Hub desactualizado?)' } else { '' }
        $detail = if ($body) { " -> $body" } else { '' }
        Write-Host "  [SKIP] cicd-batch HTTP $status$hint$detail" -ForegroundColor Yellow
    }
}

# Feedback ecosistema via /v2/sync/ecosystem-feedback (ADR-044 v3.13.0, hub v1.2.0+)
#
# Best-effort como cicd-batch: si el hub aun no esta en v1.2.0 (404) o hay error de red,
# se loguea SKIP pero NO incrementa $totalErrors - el resto de la sync sigue valida.
if ($feedbackEco.Count -gt 0) {
    Write-Host "Enviando feedback ecosistema (FB-XXX)..." -ForegroundColor Cyan
    try {
        $fbBody = @{
            projectId = $projectId
            feedback = @($feedbackEco)
        }
        Invoke-RestMethod -Uri "$serverUrl/v2/sync/ecosystem-feedback" -Method Post -Headers $headers `
            -Body ($fbBody | ConvertTo-Json -Depth 6 -Compress) `
            -ContentType 'application/json' -TimeoutSec 60 -ErrorAction Stop | Out-Null
        Write-Host "  [OK] ecosystem-feedback ($($feedbackEco.Count) items)" -ForegroundColor Green
    } catch {
        $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        $hint = if ($status -eq 404) { ' (endpoint no encontrado - Hub anterior a v1.2.0?)' } else { '' }
        Write-Host "  [SKIP] ecosystem-feedback HTTP $status$hint" -ForegroundColor Yellow
    }
}

# ---------- Actualizar ultimaSync ----------

if ($totalErrors -eq 0) {
    $estado.mcpSync.ultimaSync = (Get-Date).ToString('o')
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Resolve-Path $estadoPath), ($estado | ConvertTo-Json -Depth 10), $utf8NoBom)

    # Hotfix #17: enviar tambien heartbeat al hub para actualizar UltimoHeartbeat
    # tanto en mcp.Proyectos como en mcp.ProyectoDevs (dashboard inventory + tab Equipo).
    # Best-effort: si falla el heartbeat, NO marcar la sync como fallida.
    try {
        $versionStic = if ($estado.ecosistema -and $estado.ecosistema.version) { $estado.ecosistema.version } else { "3.9.0" }
        $hbBody = @{
            projectId = $projectId
            versionStic = $versionStic
        } | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri "$serverUrl/v2/heartbeat" -Method Post -Headers $headers `
            -Body $hbBody -ContentType 'application/json' -TimeoutSec 30 -ErrorAction Stop | Out-Null
    } catch {
        # Silencioso: el sync de contenido fue OK, el heartbeat es metadato secundario
    }

    Write-Host ""
    Write-Host "Sincronizacion completada. ultimaSync actualizado en ESTADO_PROYECTO.json" -ForegroundColor Green
    Write-Host "Dashboard: <distribution.baseUrl>/docs/dashboard/" -ForegroundColor Cyan
    exit 0
} else {
    Write-Host ""
    Write-Host "Sincronizacion incompleta ($totalErrors errores). ultimaSync NO actualizado." -ForegroundColor Yellow
    exit 1
}
