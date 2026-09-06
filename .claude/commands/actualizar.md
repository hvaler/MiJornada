---
description: Actualiza la plantilla Ovillo completa (comandos, skills, agents, hooks, rules, statusline, Documentos_Base) desde el servidor central
argument-hint: "[--check | --force | --commands-only | --structure-only | --rollback | --reorganizar]"
---

Actualiza la plantilla Ovillo completa (comandos, skills, agents, hooks, rules, statusline, Documentos_Base) desde el servidor central

# Actualizar paquete Ovillo

> Equivalente a ejecutar `iwr <distribution.baseUrl>/install.ps1 | iex` en modo update.
> Propaga los artefactos del ecosistema sin tocar los datos del proyecto.

## INVOCACIÓN CORRECTA (para Claude)

> ⚠️ **CRÍTICO para Claude**: cómo ejecutar `arranque.ps1` correctamente.
> Lee esta sección ANTES de intentar cualquier invocación del script.

### Parámetros reales de `arranque.ps1` (ESTOS son los únicos válidos)

| Parámetro | Valores | Por defecto |
|---|---|---|
| `-BaseUrl` | URL del servidor de distribución | `<distribution.baseUrl>` |
| `-Mode` | `auto`, `install`, `update`, `full` | `auto` |
| `-Force` | switch (sin valor) | `$false` |
| `-SkipSolution` | switch | `$false` |
| `-SkipMove` | switch | `$false` |
| `-ProjectName` | string | `""` |
| `-VerboseOutput` | switch | `$false` |
| `-RepairClaudeMd` | switch | `$false` |

**NO EXISTEN** (Claude nunca debe pasarlos): `-NoInteractive`, `-Quiet`, `-Silent`, `-NoConfirm`, `--force` (estilo POSIX).

### Forma recomendada de invocar desde Claude

**Opción A — en memoria sin archivo temporal** (preferida):

```powershell
& ([scriptblock]::Create((irm <distribution.baseUrl>/install.ps1))) -Mode update -Force
```

**Opción B — con archivo temporal** (si A falla):

```powershell
$tmp = "$env:TEMP\arranque.ps1"
Invoke-WebRequest -Uri "<distribution.baseUrl>/install.ps1" -OutFile $tmp
& $tmp -Mode update -Force
```

### Cuándo usar `pwsh` vs `powershell.exe`

- **Preferir `pwsh`** (PowerShell 7+) si está disponible: `where.exe pwsh` o `Test-Path "$env:ProgramFiles\PowerShell\7\pwsh.exe"`.
- **EVITAR `powershell.exe -File arranque.ps1`** (Windows PowerShell 5.1): interpreta caracteres del banner Unicode como cp1252 y produce mojibake. Si solo hay 5.1, usar la Opción A (ScriptBlock in-memory) que sí funciona porque el string descargado se decodifica como UTF-8.

### ⚠️ PROHIBIDO (Claude nunca debe hacer esto)

| Invocación | Por qué falla |
|---|---|
| `powershell.exe -File arranque.ps1` | PS 5.1 lee archivo como cp1252 → mojibake en banner/símbolos |
| `powershell.exe arranque.ps1 -NoInteractive -Quiet` | Flags inexistentes + mojibake |
| `pwsh -File /c/Users/.../arranque.ps1` | Forward-slash path no aceptado en Windows |
| `& arranque.ps1 -Force -NoInteractive` | Flag `-NoInteractive` no existe |

### Rutas en Windows

Dentro de `-Command`/`-File`, las rutas Windows requieren **backslashes reales** (`C:\Users\...`), no forward-slashes de bash (`/c/Users/...`). Si desde un shell bash/git, convierte con `cygpath -w` o usa `$env:TEMP` directamente desde PowerShell.

### Flujo completo recomendado desde Claude (/actualizar)

```powershell
# 0. PRE-FLIGHT: saneo de git lock huerfano (v3.8.7)
#    Evita "fatal: Unable to create '.git/index.lock': File exists" durante
#    operaciones git posteriores cuando VS Code/GitLens corren en paralelo.
$lockPath = ".git/index.lock"
if (Test-Path $lockPath) {
    $age = ((Get-Date) - (Get-Item $lockPath).LastWriteTime).TotalSeconds
    if ($age -gt 30) {
        Write-Host "Removing stale git lock (age: $([int]$age)s)" -ForegroundColor Yellow
        Remove-Item $lockPath -Force
    } else {
        Write-Host "ABORT: git lock activo ($([int]$age)s). Cierra VS Code/IDE y reintenta." -ForegroundColor Red
        return
    }
}
# Para git read-only durante /actualizar, evitar crear locks que colisionen con IDE:
$env:GIT_OPTIONAL_LOCKS = '0'

# 1. Leer version + hash local e remoto
$local  = Get-Content "_hilo\VERSION.json" -Raw | ConvertFrom-Json
$remote = Invoke-RestMethod "<distribution.baseUrl>/VERSION.json"

# 2. Comparar en 3 niveles:
#    a) Version semantica (X.Y.Z) - release oficial
#    b) zipSha256 existe y difiere (retro-fix dentro de misma version)
#    c) Servidor tiene hash pero local NO (consumidor pre-hash, auditar)
$versionDiff = ($local.installedVersion -ne $remote.version)
$hashDiff    = ($remote.zipSha256 -and $local.installedZipSha256 -and
                $local.installedZipSha256 -ne $remote.zipSha256)
$hashMissing = ($remote.zipSha256 -and -not $local.installedZipSha256)

if ($versionDiff) {
    Write-Host "Nueva version disponible: v$($remote.version)"
} elseif ($hashDiff) {
    Write-Host "Hotfix disponible dentro de v$($remote.version) (retro-fix)"
    Write-Host "  Local:   $($local.installedZipSha256.Substring(0,12))..."
    Write-Host "  Remoto:  $($remote.zipSha256.Substring(0,12))..."
} elseif ($hashMissing) {
    Write-Host "Estas en v$($remote.version) pero sin hash registrado (instalaste antes del sistema de integridad)."
    Write-Host "Se recomienda reinstalar con -Force para auditar integridad y registrar hash local."
    # Considerar como si hubiera update para proponer reinstalacion
} else {
    Write-Host "Ya estas al dia (version y hash coinciden). Nada que hacer."
    return
}

# 3. Si hay update / hotfix / --force, ejecutar:
& ([scriptblock]::Create((irm <distribution.baseUrl>/install.ps1))) -Mode update -Force
```

### Detectar retro-fix por hash (nuevo en v3.8.6)

`Publicacion/VERSION.json` incluye desde v3.8.6 los campos `zipSha256` y `arranqueSha256`. Cuando se corrige un bug sin bumpear version (retro-fix), el ZIP cambia pero `version` sigue siendo la misma. Sin hash, `/actualizar` diria "ya al dia" erroneamente.

Con hash:
- `version` iguales + `zipSha256` iguales -> realmente al dia
- `version` iguales + `zipSha256` distintos -> hay retro-fix, proponer reinstalacion

Si el manifest remoto NO trae `zipSha256` (servidor con version antigua del VERSION.json), el flujo degrada grácilmente: solo compara `version` como antes.

## Parámetros del comando `/actualizar` (NO del script)

Estos son los parámetros que el USUARIO pasa al slash command, Claude los traduce a flags del script:

| Parámetro del usuario | Traducción a arranque.ps1 |
|-----------------------|---------------------------|
| `/actualizar --check` | NO ejecutar script, solo comparar VERSION.json local vs remoto |
| `/actualizar --force` | `arranque.ps1 -Mode update -Force` |
| `/actualizar --commands-only` | Solo sobrescribir `.claude/commands/` manualmente (no ejecutar arranque completo) |
| `/actualizar --structure-only` | Solo copiar `Documentos_Base/` |
| `/actualizar --rollback` | Restaurar desde `.claude/backups/` local (no tocar servidor) |
| `/actualizar --reorganizar` | `arranque.ps1 -Mode install -SkipMove:$false` |

## Estructura de la Plantilla Central (v3.8.6)

```
Loom_v3.8.6/                         ← Repositorio central
├── VERSION.json                        ← Control de versión
├── arranque.ps1                        ← Script instalador/actualizador
│
└── Proyecto/                           ← Se copia/sobrescribe en cada consumidor
    ├── CLAUDE.md                       ← Punto de anclaje (merge inteligente)
    │
    ├── .claude/                        ← Artefactos Ovillo
    │   ├── CLAUDE_BASE.md     ← 📄 Estándares de la organización (SE ACTUALIZA)
    │   ├── settings.json               ← 📄 Hooks + statusLine (SOBRESCRIBE)
    │   ├── statusline.ps1              ← 📄 Barra inferior (SOBRESCRIBE)
    │   ├── estructura-plantilla.json   ← 📄 Config arranque.ps1 (SOBRESCRIBE)
    │   ├── commands/                   ← 📄 44 COMANDOS (SOBRESCRIBE)
    │   ├── rules/                      ← 📄 13 REGLAS condicionales (SOBRESCRIBE)
    │   ├── skills/                     ← 📄 15 SKILLS con auto-invocación (SOBRESCRIBE)
    │   ├── agents/                     ← 📄 16 AGENTS especializados (SOBRESCRIBE)
    │   ├── hooks/                      ← 📄 14 HOOKS (bash-guard, sql-*, secret-scanner...) (SOBRESCRIBE)
    │   └── smoke-tests/           ← 📄 Suites activación/compilación/convenciones (SOBRESCRIBE)
    │
    ├── _hilo/                         ← 🔒 MEMORIA DEL PROYECTO (NO se tocan datos)
    │   ├── ESTADO_PROYECTO.json        ← Datos del proyecto (NUNCA)
    │   ├── FUNCIONALIDADES.md          ← Datos del proyecto (NUNCA)
    │   ├── DEPENDENCIAS.md             ← Datos del proyecto (NUNCA)
    │   ├── DECISIONES.md               ← Datos del proyecto (NUNCA)
    │   ├── LECCIONES.md                ← Datos del proyecto (NUNCA)
    │   ├── HISTORIAL_CAMBIOS.md        ← Datos del proyecto (NUNCA)
    │   ├── SESION_ACTUAL.md            ← Datos del proyecto (NUNCA)
    │   ├── VERSION.json                ← 📄 Versión Ovillo instalada (SE ACTUALIZA)
    │   └── i18n/, reuniones/, specs/   ← Datos del proyecto (NUNCA)
    │
    ├── _patron/                         ← 📄 Base conocimiento Ovillo (SE ACTUALIZA)
    │   ├── INDICE_DOCUMENTOS.md
    │   └── tags/
    │
    ├── Documentos_Base/                ← 📄 Estándares OTD 17 docs (SE ACTUALIZA)
    │   ├── 01_Estructura_Tecnica/
    │   ├── 02_Diseño_Usabilidad/
    │   ├── 03_Consideraciones_Comunes/
    │   ├── 04_Plantillas_Documentacion/
    │   ├── 05_Plantillas_SQL/
    │   ├── 06_Observabilidad/
    │   └── 07_Resiliencia/
    │
    └── 00_Gestion/ ... 07_UAP/         ← 📁 Estructura carpetas (se crean si faltan)
```

> **Nota v3.8.6**: hooks/, skills/, agents/, rules/, statusline.ps1 y smoke-tests/ son parte del paquete central. Se sobrescriben en cada update con política `sobrescribir_siempre` definida en `estructura-plantilla.json`.

## Pre-condición: cerrar IDE durante actualización masiva

> **Importante (v3.8.7)**: durante `/actualizar` se escriben muchos archivos seguidos y se ejecutan operaciones git encadenadas (`git restore --staged`, `git checkout --`, `git add`). Si VS Code, GitLens, JetBrains u otro IDE está abierto en el mismo repo, sus consultas `git status` automáticas pueden colisionar y producir:
>
> ```
> fatal: Unable to create '.git/index.lock': File exists.
> ```
>
> **Mitigaciones automáticas (ya implementadas en v3.8.7):**
> - Pre-flight check: si existe `.git/index.lock` huérfano (>30s), se elimina antes de continuar
> - `GIT_OPTIONAL_LOCKS=0` activo durante el flujo (operaciones read-only no crean locks)
> - Hooks Ovillo (`banner.js`, `hilo-checkpoint.js`, `session-checkpoint.js`, `antipattern-guard.js`) usan la misma flag
>
> **Recomendación operativa:** para updates masivos (>50 archivos cambiando), cerrar el IDE antes de ejecutar `/actualizar`. Reduce al mínimo la ventana de colisión y acelera el proceso.

## Política de Actualización

### ✅ SE ACTUALIZA SIEMPRE (sobrescribe sin preguntar)

| Elemento | Ubicación | Motivo |
|----------|-----------|--------|
| Comandos | `.claude/commands/*.md` | 44 comandos Ovillo |
| Reglas condicionales | `.claude/rules/*.md` | 13 reglas (api, domain, database...) |
| Skills con auto-invocación | `.claude/skills/**/*` | 15 skills + evals + test-cases |
| Agents especializados | `.claude/agents/*.md` | 16 agents (security-auditor, etc.) |
| Hooks de protección | `.claude/hooks/*.ps1` | 14 hooks (bash-guard, sql-*, secret-scanner...) |
| Base | `.claude/CLAUDE_BASE.md` | Estándares .NET + SQL + seguridad |
| StatusLine | `.claude/statusline.ps1` | Barra inferior con rama + Ovillo version |
| Settings Claude Code | `.claude/settings.json` | Registro hooks + statusLine |
| Config plantilla | `.claude/estructura-plantilla.json` | Control arranque.ps1 |
| Smoke tests | `.claude/smoke-tests/**/*` | Suites de activación/compilación |
| Atlas | `_patron/**/*` | Índice documentos + tags |
| Documentos Base | `Documentos_Base/**/*` | 17 docs estándares OTD |
| VERSION.json instalado | `_hilo/VERSION.json` | Versión Ovillo actual (alimenta statusline) |

### ⚠️ SE ACTUALIZA CON CUIDADO

| Elemento | Política |
|----------|----------|
| `CLAUDE.md` | Merge inteligente (preserva personalizaciones del proyecto) |
| `_hilo/` templates | Solo se crean si no existen (nunca pisan datos) |
| `Documentos_Base/` archivos nuevos | Se añaden sin pisar los existentes |

### ❌ NUNCA SE TOCA (Datos del Proyecto)

| Archivo | Motivo |
|---------|--------|
| `_hilo/ESTADO_PROYECTO.json` | Estado y configuración del proyecto |
| `_hilo/FUNCIONALIDADES.md` | Documentación de funcionalidades |
| `_hilo/DEPENDENCIAS.md` | Mapa de dependencias |
| `_hilo/DECISIONES.md` | ADRs del proyecto |
| `_hilo/LECCIONES.md` | Patrones y errores aprendidos |
| `_hilo/HISTORIAL_CAMBIOS.md` | Historial de cambios |
| `_hilo/SESION_ACTUAL.md` | Contexto entre sesiones |
| `_hilo/reuniones/*` | Actas de reuniones |
| `_hilo/specs/*` | Especificaciones de evolutivos |
| `_hilo/sql-legacy-baseline.txt` | Baseline SQL legacy (si existe) |
| `00_Gestion/config_proyecto.json` | Configuración del proyecto |
| `03_Desarrollo/` | Código fuente |
| Cualquier dato real del proyecto | Información del cliente |

## Tareas a Ejecutar

### PASO 1: Detectar Entorno

```
🔍 DETECTANDO CONFIGURACIÓN
═══════════════════════════

📁 Proyecto detectado:
   Nombre: [Desde _hilo/ESTADO_PROYECTO.json]
   Ubicación: [Ruta actual]
   Versión Ovillo instalada: [Desde _hilo/VERSION.json → installedVersion]

🌐 Fuente de actualización:
   Servidor IIS central: <distribution.baseUrl>/
   Manifest: <distribution.baseUrl>/VERSION.json
   Paquete: <distribution.baseUrl>/Loom_vX.Y.Z.zip
   Script:  <distribution.baseUrl>/install.ps1

   Autenticación: red corporativa o VPN (sin credenciales extra)
```

### PASO 2: Comparar Versiones

**Leer VERSION.json local** (`_hilo/VERSION.json`):
```json
{
  "installedVersion": "3.8.6",
  "installedDate": "2026-04-22",
  "serverUrl": "<distribution.baseUrl>",
  "lastUpdate": "2026-04-22T13:53:27"
}
```

**Obtener VERSION.json remoto** (`{serverUrl}/VERSION.json`):
```json
{
  "version": "3.8.7",
  "releaseDate": "2026-05-...",
  "archivoPlantilla": "Loom_v3.8.7.zip"
}
```

**Comparar y mostrar:**

```
📊 COMPARACIÓN DE VERSIONES
═══════════════════════════

Versión instalada:  v3.8.6 (22/04/2026)
Versión disponible: v3.8.7 (...)

🆕 HAY ACTUALIZACIÓN DISPONIBLE
```

### PASO 3: Si --check, Mostrar Resumen y Terminar

```
📋 CAMBIOS EN v1.1.0
═══════════════════════

🆕 NUEVOS COMANDOS (11):
   + /analizar          Análisis completo (backend + frontend)
   + /re-analizar       Re-análisis rápido
   + /actualizar        Actualización desde central
   + /nuevo-evolutivo   Iniciar evolutivo
   + /finalizar-evolutivo  Cerrar evolutivo
   + /continuar         Retomar sesión
   + /pausar            Guardar estado
   + /sos              Emergencia
   + /cp               Checkpoint rápido
   + /recuperar         Recuperar contexto
   + /setup            Configuración

📝 COMANDOS MODIFICADOS (3):
   ~ /onboarding       Añadido análisis de frontend
   ~ /commit           Mejorada detección de secrets
   ~ /estado           Nuevo dashboard con evolutivos

📁 ESTRUCTURA:
   (sin cambios en carpetas)

📄 DOCUMENTOS_BASE:
   ~ ESTRUCTURA_TECNICA.md (actualizado)

═════════════════════════════════════
Para aplicar cambios: /actualizar
Solo comandos: /actualizar --commands-only
```

### PASO 4: Crear Backup

```
💾 CREANDO BACKUP
═════════════════

📂 Ubicación: .claude/backups/2025-01-16_v1.0.0/

Respaldando::
├── commands/           (7 archivos)
│   ├── onboarding.md
│   ├── commit.md
│   ├── estado.md
│   ├── revision.md
│   ├── sync.md
│   ├── test.md
│   └── prepara-entrega.md
├── Documentos_Base/    (15 archivos)
└── VERSION.json

✅ Backup completado (backup.manifest.json creado)
```

### PASO 5: Descargar y Aplicar

#### 5.1 comandos

```
📥 ACTUALIZANDO COMANDOS
══════════════════════

Destino: .claude/commands/

✅ NUEVOS (11):
   + analizar.md
   + re-analizar.md
   + actualizar.md
   + nuevo-evolutivo.md
   + finalizar-evolutivo.md
   + continuar.md
   + pausar.md
   + sos.md
   + cp.md
   + recuperar.md
   + setup.md

📝 ACTUALIZADOS (3):
   ~ onboarding.md      [hash cambiado]
   ~ commit.md          [hash cambiado]
   ~ estado.md          [hash cambiado]

⭐ SIN CAMBIOS (4):
   = revision.md
   = sync.md
   = test.md
   = prepara-entrega.md

Total: 18 comandos
```

#### 5.2 Documentos_Base

```
📥 ACTUALIZANDO DOCUMENTOS_BASE
══════════════════════════════

📝 ACTUALIZADOS:
   ~ 01_Estructura_Tecnica/ESTRUCTURA_TECNICA.md

⭐ SIN CAMBIOS:
   = 02_Diseño_Usabilidad/GUIA_ESTILOS.md
   = 03_Consideraciones_Comunes/CONSIDERACIONES.md
   = 04_Plantillas_Documentacion/*
```

#### 5.3 Estructura

```
📁 VERIFICANDO ESTRUCTURA
══════════════════════

✓ 00_Gestion/          existe
✓ 01_Diseño/           existe
✓ 02_Entorno/          existe
✓ 03_Desarrollo/       existe
✓ 04_Pruebas/          existe
✓ 05_CICD/             existe
✓ 06_Documentacion/    existe
✓ 07_UAP/              existe

Todas las carpetas presentes.
```

### PASO 6: Preservar Datos del Proyecto

```
🔒 DATOS DEL PROYECTO (preservados)
═══════════════════════════════════

Los siguientes archivos NO han sido modificados::

_hilo/
├── ESTADO_PROYECTO.json    ✓ Preservado
├── FUNCIONALIDADES.md      ✓ Preservado
├── DEPENDENCIAS.md         ✓ Preservado
├── DECISIONES.md           ✓ Preservado
├── HISTORIAL_CAMBIOS.md    ✓ Preservado
└── reuniones/              ✓ Preservado

00_Gestion/
└── config_proyecto.json    ✓ Preservado

CLAUDE.md                   ✓ Preservado (personalizado)
```

### PASO 7: Detectar Nuevos Campos (si aplica)

```
📋 NUEVOS CAMPOS DISPONIBLES EN ESTADO_PROYECTO.json
═══════════════════════════════════════════════════

La nueva versión de la plantilla incluye estos campos:

+ evolutivos.activos[]
+ evolutivos.completados[]
+ metricas.conformidad
+ metricas.deuda_tecnica.critica
+ metricas.deuda_tecnica.importante
+ metricas.deuda_tecnica.menor
+ plantilla.version
+ plantilla.ultima_actualizacion
+ ultimaSesion.fecha
+ ultimaSesion.proximoPaso

💡 Para añadirlos a tu proyecto:
   - Ejecuta /onboarding (añade campos automáticamente)
   - O edita ESTADO_PROYECTO.json manualmente
```

### PASO 8: Resumen Final

```
╔═══════════════════════════════════════════════════════════╗
║                   ACTUALIZACIÓN COMPLETADA                        ║
╚═══════════════════════════════════════════════════════════╝

📊 RESUMEN
══════════

Versión anterior:  v1.0.0 (Dic 2024)
Versión actual:    v1.1.0 (Ene 2025)

📝 Cambios aplicados::
   ✅ 11 comandos nuevos instalados
   ✅ 3 comandos actualizados
   ✅ 1 documento actualizado
   🔒 Todos los datos del proyecto preservados

💾 Backup disponible en::
   .claude/backups/2025-01-16_v1.0.0/

🆕 NOVEDADES DESTACADAS:
══════════════════════════

1. ANÁLISIS MEJORADO
   • /analizar con --backend y --frontend
   • Detección de librerías externas a excluir
   • Análisis de seguridad más completo

2. GESTIÓN DE EVOLUTIVOS
   • /nuevo-evolutivo, /finalizar-evolutivo
   • Seguimiento de progreso con checklist

3. CONTINUIDAD DE SESIÓN
   • /continuar, /pausar
   • Retoma donde lo dejaste

4. EMERGENCIA
   • /sos, /cp, /recuperar
   • Nunca pierdas contexto

💡 PRÓXIMOS PASOS:
═════════════════

1. Reinicia Claude Code para cargar nuevos comandos::
   > exit
   > claude

2. Explora los nuevos comandos::
   > /analizar --check
   > /estado

3. Si quieres los nuevos campos en ESTADO_PROYECTO.json::
   > /onboarding (actualiza estructura)
```

## Gestión de Conflictos

### Archivo modificado localmente

```
⚠️ CONFLICTO DETECTADO
══════════════════════

📄 .claude/commands/onboarding.md

Tu versión::
  Modificado: 10/01/2025 por ti
  Hash: abc123...

Versión nueva::
  Modificado: 15/01/2025 en plantilla
  Hash: def456...

Opciones::
  [1] Mantener mi versión (ignorar actualización)
  [2] Usar versión nueva (mis cambios se pierden, pero hay backup)
  [3] Guardar ambas (onboarding.md + onboarding.backup.md)
  [4] Ver diferencias

¿Qué prefieres? [1/2/3/4]: _
```

Con --force: automáticamente usa [2] y guarda backup.

### ERROR DE CONEXIÓN

```
❌ ERROR DE CONEXIÓN
══════════════════════

No se pudo conectar a ninguna fuente::
• MCP Server: Connection refused (puerto 3000)
• Azure DevOps: 401 Unauthorized

💡 Posibles soluciones::
1. Verifica conexión a red corporativa / VPN
2. Verifica credenciales de Azure DevOps
3. Contacta con Sistemas si persiste

📥 Alternativa manual::
1. Descarga Ovillo.zip del repositorio
2. Copia .claude/commands/*.md a tu proyecto
3. Copia Documentos_Base/ si necesitas actualizar reglas
```

## Rollback

Si algo sale mal::

```
/actualizar --rollback

🔄 RESTAURANDO VERSIÓN ANTERIOR
════════════════════════════════════

Buscando backups disponibles......

📂 Backups encontrados::
   [1] 2025-01-16_v1.0.0 (hace 2 horas)
   [2] 2025-01-10_v0.9.0 (hace 6 días)

¿Cuál restaurar? [1/2]: 1

Restaurando desde .claude/backups/2025-01-16_v1.0.0/

✅ commands/          (7 archivos restaurados)
✅ Documentos_Base/   (15 archivos restaurados)
✅ VERSION.json       (restaurado)

⚠️ Nota: Los datos del proyecto (_hilo/) no se modifican.

✅ Rollback completado. Versión actual: v1.0.0
```

## Reorganización de Código (--reorganizar)

> **Propósito**: Mover código existente de la raíz del proyecto a `03_Desarrollo/`.
> Este parámetro reemplaza la funcionalidad del comando /setup (deprecado en v2.9.0).

### Cuándo usar

- Proyecto existente con código en raíz (no en 03_Desarrollo/)
- Después de ejecutar arranque.ps1 en proyecto con código preexistente
- Para reorganizar estructura según estándares del ecosistema

### Flujo de ejecución

```
/actualizar --reorganizar

🔍 DETECTANDO CÓDIGO EN RAÍZ
══════════════════════════

Encontrado::
├── MiProyecto.sln (o .slnx)
├── MiProyecto.Api/
├── MiProyecto.Domain/
├── MiProyecto.Infrastructure/
├── MiProyecto.Tests/
├── .editorconfig
└── Directory.Build.props

¿Mover estos archivos a 03_Desarrollo/? [S/n]: S

📦 MOVIENDO CÓDIGO
════════════════

✅ MiProyecto.sln → 03_Desarrollo/
✅ MiProyecto.Api/ → 03_Desarrollo/
✅ MiProyecto.Domain/ → 03_Desarrollo/
✅ MiProyecto.Infrastructure/ → 03_Desarrollo/
✅ MiProyecto.Tests/ → 03_Desarrollo/
✅ .editorconfig → 03_Desarrollo/
✅ Directory.Build.props → 03_Desarrollo/

📋 ACTUALIZANDO REFERENCIAS
═══════════════════════════

✅ CLAUDE.md actualizado con nueva ubicación
✅ ESTADO_PROYECTO.json actualizado con nueva ubicación

⚠️ ACCIÓN MANUAL REQUERIDA::
   Actualizar rutas en Visual Studio si es necesario
```

### Archivos excluidos del movimiento

```powershell
# Nunca se mueven a 03_Desarrollo/
$excluidos = @(
    ".claude",
    "_hilo",
    ".git",
    ".vs",
    "node_modules",
    "00_Gestion",
    "01_Diseno",
    "02_Entorno",
    "03_Desarrollo",   # Ya está en su sitio
    "04_Pruebas",
    "05_CICD",
    "06_Documentacion",
    "07_UAP",
    "Documentos_Base",
    "CLAUDE.md",
    "README.md"
)
```

### Combinación con actualización

```bash
# Solo reorganizar, sin actualizar plantilla
/actualizar --reorganizar

# Reorganizar Y actualizar plantilla
/actualizar --reorganizar --force
```

---

## Verificación Post-Actualización

```
🔍 VERIFICACIÓN DE INTEGRIDAD
═══════════════════════════

comandos:
  ✅ 18/18 presentes
  ✅ Todos con formato válido

ESTRUCTURA:
  ✅ 8/8 carpetas de fase
  ✅ Documentos_Base completo
  ✅ _hilo/ intacto

VERSION.json:
  ✅ Versión: 1.1.0
  ✅ Fecha: 2025-01-16

🎉 Todo correcto. Reinicia Claude Code para aplicar.
```

## Smoke-test Hub Ovillo (Automático)

> **Propósito**: detectar regresiones en el flujo `/mcp-sync` justo despues del update,
> antes de que el usuario las descubra en su proxima sincronizacion.
> Lightweight: 4 checks (~3 segundos), sin red obligatoria, no bloquea.

**Cuando se ejecuta**: tras "Verificacion Post-Actualizacion", **solo si** el proyecto tiene
`mcpSync.habilitado=true` en `_hilo/ESTADO_PROYECTO.json`. Si esta en `false` o el campo no
existe, omitir esta seccion entera (proyecto no usa Hub Ovillo).

**No se ejecuta en** modos `--check` ni `--rollback`.

```powershell
# Pre-condicion: solo si el proyecto usa Hub Ovillo
$estadoPath = "_hilo/ESTADO_PROYECTO.json"
if (-not (Test-Path $estadoPath)) { return }
$estado = Get-Content $estadoPath -Raw | ConvertFrom-Json
if (-not $estado.mcpSync -or -not $estado.mcpSync.habilitado) {
    Write-Host "  Hub Ovillo no habilitado - smoke-test omitido" -ForegroundColor Gray
    return
}

Write-Host ""
Write-Host "🧪 SMOKE-TEST HUB Ovillo" -ForegroundColor Cyan
Write-Host "═════════════════════════" -ForegroundColor Cyan
$problems = @()

# Check 1: mcp-sync.ps1 presente en .claude/scripts/
$scriptPath = ".claude/scripts/mcp-sync.ps1"
if (Test-Path $scriptPath) {
    Write-Host "  [OK] $scriptPath presente" -ForegroundColor Green
} else {
    Write-Host "  [FALLO] $scriptPath no encontrado" -ForegroundColor Red
    $problems += "mcp-sync.ps1 ausente - el update no copio el script"
}

# Check 2: mcp-sync.ps1 parsea sin errores PowerShell
if (Test-Path $scriptPath) {
    $parseErrors = $null
    $null = [System.Management.Automation.PSParser]::Tokenize(
        (Get-Content $scriptPath -Raw), [ref]$parseErrors)
    if ($parseErrors.Count -eq 0) {
        Write-Host "  [OK] mcp-sync.ps1 parsea correctamente" -ForegroundColor Green
    } else {
        Write-Host "  [FALLO] mcp-sync.ps1 tiene $($parseErrors.Count) errores de parse" -ForegroundColor Red
        $problems += "mcp-sync.ps1 con errores de sintaxis - regresion en el update"
    }
}

# Check 3: mcpSync.habilitado preservado (true tras update)
if ($estado.mcpSync.habilitado -eq $true) {
    Write-Host "  [OK] mcpSync.habilitado=true preservado" -ForegroundColor Green
} else {
    Write-Host "  [FALLO] mcpSync.habilitado=false tras update" -ForegroundColor Red
    $problems += "mcpSync.habilitado se ha puesto a false durante el update"
}

# Check 4: si hay credenciales, dry-run del script (best-effort, no bloqueante)
$credPath = "_hilo/.mcp-credentials.json"
if ((Test-Path $credPath) -and (Test-Path $scriptPath)) {
    try {
        $null = & pwsh -NoProfile -File $scriptPath -DryRun 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [OK] /mcp-sync --dry-run completado (exit 0)" -ForegroundColor Green
        } else {
            Write-Host "  [WARN] /mcp-sync --dry-run exit $LASTEXITCODE (puede ser red, no bloqueante)" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [WARN] /mcp-sync --dry-run no se pudo ejecutar (no bloqueante)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  [SKIP] credenciales no presentes - dry-run omitido" -ForegroundColor Gray
}

# Resumen final del smoke-test
Write-Host ""
if ($problems.Count -eq 0) {
    Write-Host "  ✅ Hub Ovillo OPERATIVO tras update" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  PROBLEMAS DETECTADOS:" -ForegroundColor Yellow
    $problems | ForEach-Object { Write-Host "     - $_" -ForegroundColor Yellow }
    Write-Host ""
    Write-Host "  Sugerencias:" -ForegroundColor Cyan
    Write-Host "    - /verificar-claude --fix   (repara configuracion Hub)" -ForegroundColor Cyan
    Write-Host "    - irm ... | iex con -Force  (re-instalacion limpia del paquete)" -ForegroundColor Cyan
}
```

**Diseño**: el smoke-test es **best-effort y no bloqueante**. Su trabajo es informar, no
abortar el flujo. Los CHECKS 1-3 son deterministas (siempre fiables); el CHECK 4 requiere
conectividad al hub y se marca como `[WARN]` si falla por red — no como `[FALLO]`. Si el
usuario ve problemas reales (FALLO en 1/2/3), tiene 2 caminos sugeridos: `/verificar-claude
--fix` o re-instalacion con `-Force`.

## Integración Visual Studio (Automática)

**Después de actualizar, si existe un archivo .sln o .slnx en 03_Desarrollo/:**

```
🔧 INTEGRACIÓN VISUAL STUDIO
══════════════════════════

Detectado:: 03_Desarrollo/MiProyecto.sln (o .slnx para .NET 8+)

Ejecutando integracion-vs.ps1......
```

**Claude Code debe ejecutar automáticamente:**
```powershell
.\.claude\commands\integracion-vs.ps1
```

El script es idempotente: detecta carpetas existentes y solo añade las nuevas.

```
┌─────────────────────────────────────────────────────────────┐
│ 📂 ACTUALIZANDO SOLUTION FOLDERS                                │
├─────────────────────────────────────────────────────────────┤
│ ⚠️  Contexto Claude       ya existe                             │
│ ⚠️  Especificaciones      ya existe                             │
│ ⚠️  Diagramas             ya existe                             │
│ ⚠️  Gestion               ya existe                             │
│ ⚠️  Pruebas               ya existe                             │
│ ⚠️  CI-CD                 ya existe                             │
│ ⚠️  Documentacion         ya existe                             │
│ ⚠️  UAP                   ya existe                             │
└─────────────────────────────────────────────────────────────┘

✅ Solution Folders verificados (sin cambios necesarios)
```

**Si hay nuevas carpetas en la plantilla, el script las añadirá automáticamente.**

**Si el script falla o no se ejecuta, informar al usuario:**
```
💡 Para actualizar manualmente la integración con Visual Studio::
   .\.claude\commands\integracion-vs.ps1
```

---

## POST-STEP: revisar estrategia branching si la version saltó ≥1 MINOR

Tras completar la actualización, **comparar la version previa vs la nueva** (leer la version previa del backup en `_hilo/.update-check.json` si existe, o del primer commit del HISTORIAL_CAMBIOS.md):

- Si delta MINOR ≥ 1 (ej. v3.8.x → v3.9.0, o v3.6.0 → v3.9.0):
  - Comprobar si `_estrategias_disponibles` en `_hilo/ESTADO_PROYECTO.json` ha cambiado vs la version local previa (puede haberse añadido `gitlab-flow`, `developer-branch`, etc.).
  - **Mostrar recordatorio NO bloqueante**:

```
💡 Estrategias de branching ampliadas en esta version

La actualización trae nuevas opciones de branching disponibles que tu proyecto NO tenia.
Tu estrategia actual sigue siendo válida; revisa si alguna nueva encaja mejor.

  Estrategia actual:    {estrategia_actual}
  Estrategias nuevas:   {lista_diff}

Para ver el estado actual:  /branching --show
Para reconfigurar:          /branching   (o /branching --estrategia <nombre>)
```

- Si delta es PATCH solo (ej. v3.9.0 → v3.9.1): NO mostrar este recordatorio (las estrategias no cambian en PATCH).
- Si no se puede determinar version previa: omitir recordatorio (mejor silencio que falso positivo).

El recordatorio es informativo, no obliga a nada. El usuario decide si invocar `/branching` o seguir con su flujo.
