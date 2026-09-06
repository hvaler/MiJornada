---
description: Sincroniza datos del proyecto (decisiones, lecciones, nugets, deuda, evolutivos, equipo) con el hub Ovillo
argument-hint: "[--dry-run] [--categoria <nombre>]"
---

# /mcp-sync

Sincroniza datos del proyecto con el MCP Server Ovillo v2 (hub central del ecosistema).

> **Pre-requisito**: el proyecto debe estar registrado (`/mcp-register` previo).
> Credenciales en `_hilo/.mcp-credentials.json`. Config en `_hilo/ESTADO_PROYECTO.json.mcpSync`.

---

## Sintaxis

```
/mcp-sync                    Sincroniza TODAS las categorias habilitadas
/mcp-sync --categoria X      Solo una (decisiones | lecciones | nugets | deuda | evolutivos | equipo | feedbackEcosistema)
/mcp-sync --dry-run          Muestra que se enviaria sin enviar
```

---

## Flujo

El comando **NO genera código ad-hoc**. Simplemente invoca el script estable
`.claude/scripts/mcp-sync.ps1` que viene distribuido en la plantilla.

### Paso 1: Detectar argumentos

Parsear los argumentos del usuario:
- `--dry-run` → flag bool
- `--categoria <nombre>` → uno de: `decisiones`, `lecciones`, `nugets`, `deuda`, `evolutivos`, `equipo`, `feedbackEcosistema`

### Paso 2: Pre-checks rapidos

Antes de invocar el script:
- Verificar que `.claude/scripts/mcp-sync.ps1` existe (sino: actualizar Ovillo con `/actualizar`)
- Verificar que `_hilo/.mcp-credentials.json` existe (sino: sugerir `/mcp-register`)
- Verificar que `_hilo/ESTADO_PROYECTO.json.mcpSync.habilitado == true`

### Paso 3: Invocar script

Ejecutar via `pwsh` (cross-platform) o `powershell` (Windows fallback):

```bash
# Todas las categorias
pwsh -NoProfile -ExecutionPolicy Bypass -File .claude/scripts/mcp-sync.ps1

# Dry-run
pwsh -NoProfile -ExecutionPolicy Bypass -File .claude/scripts/mcp-sync.ps1 -DryRun

# Solo una categoria
pwsh -NoProfile -ExecutionPolicy Bypass -File .claude/scripts/mcp-sync.ps1 -Category nugets
```

El script:
1. Lee credentials + config
2. Parsea fuentes locales (DECISIONES.md, LECCIONES.md, DEUDA_TECNICA.md, *.csproj+CPM, ESTADO_PROYECTO.json)
3. Construye batches por categoria
4. Llama a `POST /v2/hilo/batch` (decisiones + lecciones), `POST /v2/sync/f3-batch` (nugets + deuda + evolutivos + bloqueadores + equipo + branching) y `POST /v2/sync/ecosystem-feedback` (feedback ecosistema FB-XXX, best-effort)
5. Si todo OK: actualiza `mcpSync.ultimaSync` en ESTADO_PROYECTO.json (con UTF-8 sin BOM)
6. Devuelve resumen al stdout

### Paso 4: Mostrar resumen al usuario

Capturar el stdout del script y pasarlo tal cual al usuario. NO añadir texto extra.

---

## Decision de diseño: script estable vs codigo ad-hoc

**Anterior (frágil)**: el comando `/mcp-sync` pedia a Claude generar un script PowerShell completo cada vez. Resultado: cada ejecucion reinventaba el codigo, susceptible a bugs de parsing (ej. `$status:` en lugar de `${status}:`).

**Actual (hotfix #8)**: el script `mcp-sync.ps1` vive en la plantilla, se distribuye con cada release. Claude solo lo invoca con los argumentos correctos. Si hay un bug, se arregla en una sola version del script y todas las apps lo reciben en la siguiente actualizacion via `/actualizar`.

---

## Categorias soportadas

| Categoria | Origen local | Endpoint MCP |
|---|---|---|
| decisiones | `_hilo/DECISIONES.md` | `/v2/hilo/batch` |
| lecciones | `_hilo/LECCIONES.md` | `/v2/hilo/batch` |
| nugets | `*.csproj` + `Directory.Packages.props` | `/v2/sync/f3-batch` |
| deuda | `_hilo/DEUDA_TECNICA.md` | `/v2/sync/f3-batch` |
| evolutivos | `ESTADO_PROYECTO.json.evolutivos` + bloqueadores | `/v2/sync/f3-batch` |
| equipo | `ESTADO_PROYECTO.json.equipo` + branching | `/v2/sync/f3-batch` |
| feedbackEcosistema | `_hilo/FEEDBACK_ECOSISTEMA.md` (items FB-XXX, ADR-044) | `/v2/sync/ecosystem-feedback` |

Telemetria de agents NO se gestiona por este comando — la maneja el hook
`agent-telemetry.js` automaticamente (con cooldown 24h).

---

## Manejo de errores

El script:
- Devuelve `exit 0` si todo OK
- Devuelve `exit 1` si hubo errores HTTP (pero no aborta — sigue intentando otras categorias)
- Si red caida o servidor 5xx: el `ultimaSync` NO se actualiza (reintento en la siguiente ejecucion)

---

## Anti-patrones

- **NO regenerar el script cada vez** que el usuario ejecute `/mcp-sync`. Usar el distribuido.
- **NO enviar contenido sensible** — los parsers ya filtran (PII, secrets quedan en local).
- **NO commitear** `_hilo/.mcp-credentials.json` ni `_hilo/.mcp-telemetry-state.json` (ya en `.gitignore`).
