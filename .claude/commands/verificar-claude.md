Analiza CLAUDE.md del proyecto para detectar problemas y ofrece corrección automática

Analiza el archivo CLAUDE.md del proyecto para detectar problemas de estructura y compatibilidad con la plantilla Ovillo, y ofrece correccion automatica.

> **USE FOR**: verificar/corregir el **archivo CLAUDE.md** (estructura, @imports, secciones, compatibilidad con la plantilla).
> **DO NOT USE FOR**: verificar el **CÓDIGO** antes de commit/PR (build+tests+lint) → usar **`/verify`**.

---

## Cuando usar

- Despues de actualizar la plantilla con `arranque.ps1`
- Cuando sospechas que el CLAUDE.md tiene problemas
- Para verificar que el proyecto aprovecha todas las funcionalidades del ecosistema
- Antes de compartir el proyecto con otro desarrollador

---

## Instrucciones para Claude

Al ejecutar `/verificar-claude`, Claude debe:

### 1. Leer y analizar CLAUDE.md

```
Leer: CLAUDE.md
```

### 2. Verificar estructura obligatoria

Comprobar que existen las siguientes secciones/elementos:

#### @imports (CRITICO)
```markdown
## @imports (Contexto Automatico)

@_hilo/ESTADO_PROYECTO.json
@_hilo/SESION_ACTUAL.md
@.claude/CLAUDE_BASE.md
```

**Problemas comunes:**
- @imports duplicados (aparecen 2 veces)
- @imports en posicion incorrecta (deben estar al principio)
- @imports incompletos (faltan archivos)
- @imports OBSOLETOS: `@_hilo/DEPENDENCIAS.md` y `@_hilo/FUNCIONALIDADES.md` se retiraron
  en la dieta de contexto (AUD-008) — se leen bajo demanda. Si aparecen, proponer quitarlos
  (NO re-anadirlos).

#### Secciones recomendadas
- `## Informacion del Proyecto` o `## Project Overview`
- `## Glosario del Dominio` o `## Domain Glossary`
- `## Comandos de Build` o `## Build Commands`
- `## Comandos Personalizados`
- `## Workflows`
- `## Estandares de Codigo`
- `## Reglas Criticas` o `## Critical Rules`

### 3. Detectar problemas

| Problema | Severidad | Descripcion |
|----------|-----------|-------------|
| @imports duplicados | ALTA | Los @imports aparecen mas de una vez |
| @imports incompletos | ALTA | Faltan archivos de contexto |
| @imports mal ubicados | MEDIA | No estan al principio del archivo |
| Tabla cortada | MEDIA | Tabla markdown incompleta (falta cierre) |
| Seccion del ecosistema duplicada | BAJA | "SECCIONES LOOM" aparece 2 veces |
| Sin Glosario | BAJA | No tiene seccion de glosario del dominio |
| Sin Workflows | BAJA | No tiene seccion de workflows |
| SQL sin referencia a §8.1 | MEDIA | CLAUDE.md no menciona ni apunta a CLAUDE_BASE.md §8.1 (nomenclatura SQL) |
| SQL version no declarada | BAJA | No hay campo `baseDatos.versionSqlServer` en ESTADO_PROYECTO.json (se asume default 2017) |
| database.md desactualizada | MEDIA | `.claude/rules/database.md` existe pero no tiene bloque "ERRORES COMUNES A EVITAR" (v3.8.5 o anterior) |
| hook sql-nomenclatura-guard ausente | MEDIA | `.claude/hooks/sql-nomenclatura-guard.js` no existe o no esta registrado en settings.json |
| Glosario SQL legacy sin marcar | BAJA | Si el proyecto tiene SPs `usp_*` o `_Listar`, deberia tener anotacion de legacy en CLAUDE.md |
| Hub Ovillo Convenciones ausente | MEDIA | CLAUDE.md no tiene la seccion "Hub Ovillo — Convenciones de configuracion" (ADR-037 + ADR-038). Otro Claude podria anadir `telemetryOptIn` en el lugar equivocado |
| telemetryOptIn en lugar equivocado | ALTA | `_hilo/ESTADO_PROYECTO.json.mcpSync.telemetryOptIn` NO debe existir — es per-dev, vive en `_hilo/.mcp-credentials.json` (gitignored) |
| regla mcp-config.md ausente | BAJA | `.claude/rules/mcp-config.md` no existe (defensa C contra bug telemetryOptIn) |

### 4. Mostrar informe

```
╔═══════════════════════════════════════════════════════════════╗
║  📋 VERIFICACION CLAUDE.md                                     ║
╚═══════════════════════════════════════════════════════════════╝

Proyecto: [Nombre del proyecto]
Archivo: CLAUDE.md
Tamaño: [X] lineas

┌─────────────────────────────────────────────────────────────┐
│ ESTRUCTURA                                                   │
├─────────────────────────────────────────────────────────────┤
│ ✅ @imports completos (5/5)                                  │
│ ✅ Informacion del proyecto                                  │
│ ✅ Glosario del dominio                                      │
│ ✅ Comandos de build                                         │
│ ⚠️  Tabla de comandos incompleta                             │
│ ✅ Workflows                                                  │
│ ✅ Estandares de codigo                                       │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ ESTANDARES SQL                                               │
├─────────────────────────────────────────────────────────────┤
│ ✅ Referencia a CLAUDE_BASE.md §8.1 presente        │
│ ⚠️  Campo baseDatos.versionSqlServer no declarado (asume 2017)│
│ ✅ .claude/rules/database.md con "ERRORES COMUNES A EVITAR"  │
│ ✅ Hook sql-nomenclatura-guard.js registrado                │
│ ⚠️  Detectados 3 SPs con nomenclatura legacy (usp_*, _Listar)│
│    → considera anotarlos en sección legacy de CLAUDE.md      │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ HUB Ovillo (ADR-037 + ADR-038)                              │
├─────────────────────────────────────────────────────────────┤
│ ✅ _hilo/.mcp-project.json presente (commiteable)           │
│ ✅ _hilo/.mcp-credentials.json presente (gitignored)        │
│ ✅ mcpSync.habilitado=true en ESTADO_PROYECTO.json           │
│ ⚠️  Seccion "Hub Ovillo — Convenciones" ausente en CLAUDE.md│
│    → fix: anadir seccion completa con tabla per-PROYECTO/DEV │
│ ❌ telemetryOptIn detectado en mcpSync (DEBE eliminarse)     │
│ ✅ .claude/rules/mcp-config.md presente                      │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ PROBLEMAS DETECTADOS                                         │
├─────────────────────────────────────────────────────────────┤
│ 🔴 [ALTA] @imports duplicados en linea 237                   │
│ 🟡 [MEDIA] Tabla "Comandos Personalizados" cortada           │
│ 🟡 [MEDIA] CLAUDE.md sin referencia a §8.1 (SQL nomenclatura)│
└─────────────────────────────────────────────────────────────┘

¿Deseas que corrija estos problemas automaticamente? (S/N)
```

### 5. Corregir automaticamente (si el usuario acepta)

**Para @imports duplicados:**
1. Identificar la seccion @imports correcta (la primera, al principio)
2. Eliminar las secciones duplicadas
3. Verificar que los 5 @imports obligatorios estan presentes

**Para tablas cortadas:**
1. Detectar tablas markdown incompletas
2. Cerrar la tabla correctamente o eliminar la linea incompleta

**Para secciones duplicadas:**
1. Mantener solo una seccion de cada tipo
2. Eliminar duplicados preservando el contenido mas completo

**Para @imports incompletos:**
1. Añadir los @imports faltantes
2. Ordenarlos correctamente

**Para estandares SQL:**

Los problemas SQL tienen dos rutas de fix distintas:

| Problema | Fix aplicable | Por que |
|---|---|---|
| CLAUDE.md raiz sin referencia a §8.1 | ✅ `/verificar-claude --fix` lo corrige | El CLAUDE.md raiz del proyecto lo conserva el usuario (arranque.ps1 NO lo pisa). Anadir un puntero corto a `CLAUDE_BASE.md §8.1` |
| `baseDatos.versionSqlServer` ausente en ESTADO_PROYECTO.json | ✅ `/verificar-claude --fix` pregunta version y la escribe | Default: ecosystem.config.database.version (null = sin gating) |
| `.claude/rules/database.md` desactualizada | ❌ fix NO copia archivos al `.claude/` | Arranque.ps1 update propaga estos artefactos con politica `sobrescribir_siempre`. Se sugiere al usuario ejecutar `arranque.ps1 -InstallMode update` |
| Hook `sql-nomenclatura-guard.js` ausente | ❌ fix NO copia archivos al `.claude/` | Mismo motivo — se sugiere update del ecosistema |
| SPs legacy detectados (`usp_*`, `_Listar`) | ❌ fix NO renombra SPs | Sugerir al usuario ejecutar `/clean --sql` en el futuro (cuando exista) o renombrar manualmente con `sp_rename` |
| Seccion "Hub Ovillo — Convenciones" ausente en CLAUDE.md | ✅ `/verificar-claude --fix` inserta seccion completa | Defensa B contra bug 'telemetryOptIn lugar equivocado'. CLAUDE.md no se pisa en update, por eso este check + auto-fix |
| `telemetryOptIn` presente en `mcpSync` de ESTADO_PROYECTO.json | ✅ `/verificar-claude --fix` lo elimina | Bug: ese campo es per-dev (vive en `.mcp-credentials.json`), no per-proyecto. Si esta aqui es residual pre-v3.9.0 |
| `.claude/rules/mcp-config.md` ausente | ❌ fix NO copia archivos al `.claude/` | Sugerir update del ecosistema con `arranque.ps1` (regla se desplega automaticamente) |

**Snippet que `--fix` inserta en CLAUDE.md raiz** (tras el glosario o antes de "Workflows"):

```markdown
---

## Estandares SQL

> La nomenclatura SQL configurada, version SQL configurada y features permitidas/prohibidas estan en `.claude/CLAUDE_BASE.md` §8.1 (siempre cargado en contexto). No duplicar aqui — solo apuntar.

- **Version SQL Server**: ver campo `baseDatos.versionSqlServer` en `_hilo/ESTADO_PROYECTO.json` (default: 2017).
- **Nomenclatura SPs**: `{schema}.{Action}{Entity}` · ejemplo: `ewp.GetNomination`.
- **Legacy**: SPs `usp_*`, `_Listar`, etc. se mantienen en archivos bajo `Legacy/`, `Obsoleto/` o con `-- LEGACY: no renombrar`.

Auditoria rapida: `/verificar-claude --sql`
```

**Snippet que `--fix` añade a ESTADO_PROYECTO.json** si falta el campo:

```json
"baseDatos": {
  "_comentario": "Configuracion de base de datos del proyecto",
  "versionSqlServer": "2017",
  "_versionSqlServer_opciones": ["2016", "2017", "2019", "2022", "AzureSQL"],
  "_notas": "Si se fija version (ej. 2017), aplicar gating de features posteriores. null = sin gating."
}
```

**Snippet que `--fix` INSERTA en CLAUDE.md** si falta la seccion Hub Ovillo (insertar tras "## Integraciones MCP" o antes de "## Reglas del Proyecto"):

```markdown
### Hub Ovillo — Convenciones de configuración (ADR-037 + ADR-038)

> **CRÍTICO**: estas convenciones evitan bugs de privacidad y duplicación de identidad. Aplican a cualquier edición que toque `_hilo/ESTADO_PROYECTO.json.mcpSync` o `_hilo/.mcp-credentials.json`.

**Dos fuentes de verdad separadas, NO mezclar**:

| Archivo | Scope | Commiteable | Contiene |
|---|---|---|---|
| `_hilo/.mcp-project.json` | **per-PROYECTO** | ✅ sí | `projectId`, `serverUrl` — para que otros devs se unan via `/v2/join` al clonar |
| `_hilo/ESTADO_PROYECTO.json.mcpSync` | **per-PROYECTO** | ✅ sí | `habilitado`, `categorias`, `projectId` (duplicado), `ultimaSync` |
| `_hilo/.mcp-credentials.json` | **per-DEV** | ❌ no (gitignored) | `apiKey`, `devAlias`, `devEmail`, `telemetryOptIn` |

**Reglas absolutas**:

1. **NUNCA añadir `telemetryOptIn` en `ESTADO_PROYECTO.json.mcpSync`**. Es per-dev. Vive solo en `.mcp-credentials.json` y `mcp.ProyectoDevs.TelemetryOptIn` (hub).
2. **NUNCA añadir `apiKey` o `devAlias` en `ESTADO_PROYECTO.json`**. Es per-dev.
3. **`habilitado` lo activa `arranque.ps1` automáticamente**. No tocar.
4. **Para cambiar opt-in de telemetría**: usar `/mcp-register` (privacy notice + 3 opciones).
5. **Para "right to be forgotten"**: usar `/mcp-forget` (proyecto entero) o `/v2/leave` API (solo el dev).

> Si encuentras `telemetryOptIn` en `ESTADO_PROYECTO.json.mcpSync`, **elimínalo** (residual <v3.9.0).

### `/mcp-register` — ¿cuándo es necesario?

**Casi nunca**. `arranque.ps1` ya hace silent register automático al ejecutar `irm | iex`. Esto basta para `/mcp-sync` + dashboard + heartbeat. Solo ejecuta `/mcp-register` si quieres activar **telemetría de agents** (opt-in con privacy notice).
```

**Fix para `telemetryOptIn` residual en ESTADO_PROYECTO.json**: eliminar la propiedad del objeto `mcpSync`. Ejemplo PowerShell:

```powershell
$path = "_hilo/ESTADO_PROYECTO.json"
$estado = Get-Content $path -Raw | ConvertFrom-Json
if ($estado.mcpSync.PSObject.Properties['telemetryOptIn']) {
    $estado.mcpSync.PSObject.Properties.Remove('telemetryOptIn')
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, ($estado | ConvertTo-Json -Depth 12), $utf8)
}
```

### 6. Crear backup antes de modificar

```
Creando backup: CLAUDE.md.bak.20260204_143022
```

### 6b. Version Ovillo correcta

Cuando la firma/footer del CLAUDE.md incluya una version de Ovillo (ej: `*Archivo generado por Ovillo vX.X.X*`), la fuente de verdad para la version es `_hilo/VERSION.json` (campo `installedVersion`), NO `_hilo/ESTADO_PROYECTO.json` (que puede estar desactualizado si se actualizo con `arranque.ps1 -Mode update`).

```
Prioridad para determinar version:
1. _hilo/VERSION.json → installedVersion (fuente de verdad, escrita por arranque.ps1)
2. _hilo/ESTADO_PROYECTO.json → ecosistema.version (puede estar desactualizada)
```

### 7. Mostrar resumen de cambios

```
╔═══════════════════════════════════════════════════════════════╗
║  ✅ CLAUDE.md CORREGIDO                                        ║
╚═══════════════════════════════════════════════════════════════╝

Cambios realizados:
- Eliminados @imports duplicados (lineas 237-244)
- Completada tabla de comandos personalizados
- Backup guardado: CLAUDE.md.bak.20260204_143022

El archivo CLAUDE.md ahora cumple con la estructura Ovillo
```

### 8. Mostrar flags disponibles al final

Siempre incluir al final del informe los flags disponibles:

```
┌─────────────────────────────────────────────────────────────┐
│ FLAGS DISPONIBLES                                           │
├─────────────────────────────────────────────────────────────┤
│ /verificar-claude          Analisis completo (este modo)    │
│ /verificar-claude --fix    Corregir sin preguntar           │
│ /verificar-claude --check  Solo verificar, no corregir      │
│ /verificar-claude --verbose Mostrar detalles de cada check  │
│ /verificar-claude --sql    Solo checks de estandares SQL    │
└─────────────────────────────────────────────────────────────┘
```

Si al terminar quedan problemas SQL detectados (legacy SPs, artefactos del `.claude/` desactualizados), mostrar tambien este mensaje:

```
+---------------------------------------------------------------+
| Para proyectos donde Claude ha generado SPs con nomenclatura  |
| incorrecta (ej: _Listar, usp_), considera:                    |
|                                                               |
|   1. Ejecutar arranque.ps1 -InstallMode update                |
|      -> actualiza rules/database.md + hook SQL                |
|                                                               |
|   2. Anotar SPs legacy en seccion "## Estandares SQL" de      |
|      CLAUDE.md con marcador "-- LEGACY: no renombrar" en los  |
|      archivos .sql correspondientes                           |
|                                                               |
|   3. Los objetos ya desplegados en BD deben renombrarse con   |
|      sp_rename manualmente (no automatizable desde Claude)    |
+---------------------------------------------------------------+
```

---

## Parametros opcionales

- `/verificar-claude` - Analisis completo con opcion de correccion
- `/verificar-claude --fix` - Corregir automaticamente sin preguntar
- `/verificar-claude --check` - Solo verificar, no corregir
- `/verificar-claude --verbose` - Mostrar detalles de cada verificacion
- `/verificar-claude --sql` - Solo ejecuta los 5 checks de estandares SQL (rapido)

---

## Checklist de verificacion

### @imports (3 obligatorios)
- [ ] `@_hilo/ESTADO_PROYECTO.json`
- [ ] `@_hilo/SESION_ACTUAL.md`
- [ ] `@.claude/CLAUDE_BASE.md`
- [ ] Sin obsoletos: `@_hilo/DEPENDENCIAS.md` / `@_hilo/FUNCIONALIDADES.md` retirados (AUD-008; lectura bajo demanda)

### Secciones del proyecto
- [ ] Informacion/Overview del proyecto
- [ ] Glosario del dominio
- [ ] Comandos de build/ejecucion
- [ ] Arquitectura o estructura

### Secciones del ecosistema
- [ ] Comandos personalizados (tabla completa, debe incluir 43 comandos v3.8.2)
- [ ] Workflows (API, Nueva funcionalidad, Bug fix, Pre-commit)
- [ ] Estandares de codigo (C#, Tests, Commits)
- [ ] Reglas criticas

### Comandos v3.8.2 que deben estar en la tabla
- [ ] `/optimizar` — Diagnostico de contexto y tokens
- [ ] `/devops-sync` — Sincronizar con Azure DevOps (DRY-RUN)
- [ ] `/verify` — Pipeline verificacion pre-commit 7 fases
- [ ] `/clean` — Limpieza sistematica 7 pasos
- [ ] `/health-check`, `/add-telemetry`, `/add-resilience`
- [ ] `/lang`, `/mcp-sync`, `/analisis-arquitectura`

### Verificacion tras salto de version
Si el CLAUDE.md fue generado por una version anterior (ej: v3.1.0), verificar:
- [ ] Tabla de comandos tiene los 43 comandos actuales (no 36 o 41)
- [ ] Seccion de Integraciones MCP existe (Context7)
- [ ] Seccion de Orquestacion del Trabajo existe
- [ ] Footer dice v3.8.2 (no una version anterior)
- [ ] Seccion Ecosistema Ovillo (Ovillo + Hilo + Patrón) existe

### Formato
- [ ] No hay tablas cortadas
- [ ] No hay secciones duplicadas
- [ ] Separadores `---` correctos
- [ ] Ultima actualizacion al final

### Estandares SQL (v3.8.5+)
- [ ] CLAUDE.md raiz tiene seccion `## Estandares SQL` con referencia a `CLAUDE_BASE.md §8.1` (no contenido duplicado, solo puntero)
- [ ] `_hilo/ESTADO_PROYECTO.json` tiene campo `baseDatos.versionSqlServer` (default: "2017")
- [ ] `.claude/rules/database.md` contiene bloque "ERRORES COMUNES A EVITAR" al inicio (v3.8.5+)
- [ ] `.claude/hooks/sql-nomenclatura-guard.js` existe y esta registrado en `.claude/settings.json` (PostToolUse[Write|Edit])
- [ ] Si hay SPs legacy (`usp_*`, `sp_*`, `_Listar`, `_Guardar`): estan bajo `Legacy/`, `Obsoleto/` o con comentario `-- LEGACY: no renombrar`

---

## Ejemplo de CLAUDE.md correcto

```markdown
# CLAUDE.md

This file provides guidance to Claude Code...

---

## @imports (Contexto Automatico)

@_hilo/ESTADO_PROYECTO.json
@_hilo/SESION_ACTUAL.md
@.claude/CLAUDE_BASE.md

---

## Informacion del Proyecto

| Campo | Valor |
|-------|-------|
| **Nombre** | MiProyecto |
| **Framework** | .NET 10.0 |
...

---

## Glosario del Dominio

| Termino | Definicion |
|---------|------------|
| ... | ... |

---

## Comandos de Build

```bash
dotnet build
```

---

## Comandos Personalizados

| Comando | Description |
|---------|-------------|
| `/onboarding` | Configuracion guiada |
| `/analizar` | Analisis de codigo |
...

---

## Workflows

### Crear/Modificar Endpoint API
...

### Nueva Funcionalidad
...

---

## Estandares de Code
...

---

## Reglas Criticas
...

---

*Ultima actualizacion: YYYY-MM-DD - Estructura Ovillo vX.X.X*
```

---

## Errores comunes y soluciones

| Error | Causa | Solucion |
|-------|-------|----------|
| @imports no funcionan | Estan duplicados o mal ubicados | Ejecutar `/verificar-claude --fix` |
| Contexto incompleto | Faltan @imports | Añadir los 5 @imports obligatorios |
| Merge fallido | arranque.ps1 añadio secciones duplicadas | Eliminar duplicados manualmente o con este comando |
| Tabla rota | Edicion manual incorrecta | Completar o eliminar la tabla incompleta |

---

---

## Algoritmo de deteccion (checks SQL)

Los 5 checks SQL se ejecutan en este orden. Cada uno imprime `OK`, `WARN` o `FAIL`:

### SQL-1: referencia a §8.1 en CLAUDE.md raiz

```
1. Leer CLAUDE.md (raiz del proyecto, no el de .claude/).
2. Buscar una de estas keywords (case-insensitive):
     - "## Estandares SQL"
     - "SQL Nomenclatura"
     - "CLAUDE_BASE.md §8.1"
     - "CLAUDE_BASE.md seccion 8.1"
3. Si NO encuentra ninguna -> WARN [MEDIA]
4. Si encuentra pero no menciona version ni nomenclatura -> WARN [BAJA]
```

### SQL-2: version SQL Server declarada

```
1. Leer _hilo/ESTADO_PROYECTO.json.
2. Buscar baseDatos.versionSqlServer.
3. Si no existe -> WARN [BAJA] + sugerir default 2017.
4. Si existe y es "2017" -> OK.
5. Si es "2019", "2022", "AzureSQL", "2016" -> OK (pero mencionar en el output que las features permitidas cambian).
6. Valor no reconocido -> WARN [MEDIA].
```

### SQL-3: `.claude/rules/database.md` actualizada

```
1. Verificar que existe .claude/rules/database.md.
2. Si no existe -> FAIL [ALTA] (arranque.ps1 update falta).
3. Si existe: grep por "ERRORES COMUNES A EVITAR" (case-insensitive).
4. Si NO encuentra -> WARN [MEDIA] (version v3.8.4 o anterior).
5. Si encuentra + tiene globs de Repositorios/*.cs -> OK.
```

### SQL-4: hook `sql-nomenclatura-guard.js` registrado

```
1. Verificar que existe .claude/hooks/sql-nomenclatura-guard.js.
2. Leer .claude/settings.json.
3. Buscar en hooks.PostToolUse[Write|Edit] una entrada que contenga "sql-nomenclatura-guard.js".
4. Si archivo existe + esta registrado -> OK.
5. Si archivo existe pero NO registrado -> WARN [MEDIA].
6. Si archivo NO existe -> WARN [MEDIA] (arranque.ps1 update falta).
```

### SQL-5: SPs legacy detectados

```
1. grep en **/*.sql + **/Repositorio*.cs:
     - CREATE PROCEDURE con prefijo usp_, sp_, pr_, proc_, pa_
     - CREATE PROCEDURE con sufijo _Listar, _Guardar, _Eliminar, _Leer, _L, _G
2. Cargar .claude/sql-legacy-baseline.txt si existe (lista de rutas relativas).
3. Para cada match:
     a. Verificar si la ruta relativa esta en sql-legacy-baseline.txt.
     b. Verificar si el archivo esta bajo Legacy/, Obsoleto/, MigracionPending/.
     c. Verificar si tiene el comentario "-- LEGACY: no renombrar".
     d. Si cumple alguna -> OK (legacy marcado correctamente).
     e. Si NO cumple -> WARN [BAJA]: "SP legacy sin marcar".
4. Si hay N SPs legacy sin marcar, sugerir:
     a. Generar baseline masivo: `node .claude/hooks/sql-baseline-generate.js`
     b. O anotar individualmente con comentario inline `-- LEGACY: no renombrar`.
```

### Con `--sql`

Solo ejecuta SQL-1 a SQL-5. Salta @imports, tablas cortadas, glosario, workflows, etc.
Util para verificacion rapida tras `arranque.ps1 update`:

```bash
/verificar-claude --sql
# tiempo: ~5 seg
# output: solo bloque "ESTANDARES SQL"
```

---

*Comando actualizado v3.8.6 - Verificacion CLAUDE.md + soporte salto de version + checks SQL nomenclatura (5 nuevos)*
