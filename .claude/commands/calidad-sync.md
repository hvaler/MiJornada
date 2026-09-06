---
description: Mide la calidad de codigo (cobertura, CRAP, ciclomatica, NPath, hotspots, desglose por clase) y publica un Registro de Calidad (QR) al hub Ovillo para el dashboard de calidad
argument-hint: "[--dry-run] [--sln <ruta>]"
---

# /calidad-sync

Publica **UN** Registro de Calidad (QR) del proyecto al hub Ovillo: corre los tests con
cobertura, calcula las metricas (cobertura linea/rama, CRAP, complejidad ciclomatica, NPath,
risk hotspots, desglose por clase/namespace), evalua el quality gate y hace el POST. Es lo
que alimenta el **dashboard de calidad del portfolio** (`/ovillo-hub/docs/dashboard/calidad.html`).

> El comando **NO genera codigo ad-hoc**: orquesta la skill `calidad-codigo-sync` y su script
> estable `.claude/skills/calidad-codigo-sync/scripts/Sync-QualityRecord.ps1` (distribuido en
> la plantilla). El gate y las metricas las computa el script; el dashboard es solo-lectura.

---

## ALCANCE ESTRICTO (leer antes de actuar)

Este comando **solo MIDE y PUBLICA**. Mientras lo ejecutas:

- ❌ **NO** refactorices codigo de produccion ni de tests.
- ❌ **NO** crees tests nuevos ni modifiques los existentes "para subir la cobertura".
- ❌ **NO** hagas commits.
- ❌ **NO** interpretes un `gate=FAIL` ni una cobertura baja como algo a arreglar: el QR refleja
  el **estado real** del proyecto, que es justo lo que el dashboard debe mostrar.
- ✅ Si crees que falta algo, que el coverage no sale, o que se podria mejorar → **PARATE y
  pregunta**. No actues sin aprobacion explicita.

> Origen de estas guardas: en los primeros usos (pilotos ErpSync/EWP) el flujo "publica un QR"
> derivo en campanas de refactor de produccion no pedidas. El QR es una **foto**, no un disparador
> de cambios.

---

## Sintaxis

```
/calidad-sync                 Mide la solucion y publica el QR
/calidad-sync --dry-run       Calcula e imprime el payload, NO envia (inspeccion)
/calidad-sync --sln <ruta>    Fuerza una solucion concreta (proyectos multi-.sln)
```

---

## Flujo

### Paso 0 — Pre-checks

- Verificar que existe `.claude/skills/calidad-codigo-sync/scripts/Sync-QualityRecord.ps1`.
  Si no → la plantilla esta desactualizada: `irm | iex` (o `/actualizar`) y reintentar.
- Verificar que existe `_hilo/.mcp-project.json` (lo crea `irm | iex` al registrar el proyecto).
  Si no → el proyecto no esta registrado en el hub: ejecutar `irm | iex` primero.

### Paso 1 — Situarse en la RAIZ del repo

Ejecutar TODO desde la **raiz del repo** (donde estan `.claude/` y `_hilo/`), **NO** desde
`03_Desarrollo/`. Las rutas relativas (runsettings, credenciales, paths de hotspots) dependen
de ello. Si el `.sln` esta en `03_Desarrollo/`, se referencia con su ruta — pero el comando se
lanza desde la raiz.

### Paso 2 — Resolver ProjectId y solucion

- `ProjectId`: leer el campo `projectId` de `_hilo/.mcp-project.json`.
- Solucion: localizar el `.sln`. Si `--sln` viene dado, usarlo. Si hay **mas de un** `.sln` y
  no se especifico `--sln`, **preguntar** cual (no adivinar).

### Paso 3 — Coverage (PRIMER PLANO, nunca /background)

```powershell
Remove-Item ./TestResults -Recurse -Force -ErrorAction SilentlyContinue
dotnet test <ruta-al-.sln> --collect "XPlat Code Coverage" `
  --settings .claude/skills/calidad-codigo-sync/scripts/coverage.runsettings `
  --results-directory ./TestResults
```

- **En primer plano** (NO `/background`): el background deja el output ciego y entra en bucle.
- Si el test runner **se cuelga** (no termina en ~1-2 min, CPU plana): casi siempre son los
  **tests de integracion `WebApplicationFactory`** bajo Coverlet (IL-rewrite) — ver **Paso 3b**.
  Si NO es eso (otro recurso externo en el arranque), **PARATE** y reportalo (no parchees a ciegas).
- Multi proyecto de test → varios `coverage.opencover.xml`: el script los **agrega** y **fusiona la
  cobertura por (clase::metodo)** entre todos (D1/FB-009: un assembly compartido no penaliza).

### Paso 3b — Proyectos de integracion (WebApplicationFactory) [si Coverlet cuelga]

Coverlet (`XPlat Code Coverage`, IL-rewrite) **cuelga** el testhost con `WebApplicationFactory`/
TestServer, sobre todo a nivel solucion en paralelo (FB-008). Si te pasa, mide **esos** proyectos
por separado con **`dotnet-coverage`** (profiler out-of-process de Microsoft), **por-proyecto y
SECUENCIAL** (la solucion entera en paralelo vuelve a colgar):

```powershell
# 1) Asegurar la herramienta (una vez por maquina)
dotnet tool install -g dotnet-coverage 2>$null; dotnet tool update -g dotnet-coverage 2>$null
$env:PATH += ";$env:USERPROFILE\.dotnet\tools"

# 2) Los proyectos de integracion (WebApplicationFactory) -> cobertura.xml, uno a uno
dotnet-coverage collect -f cobertura -o ./TestResults/int-<Proyecto>.cobertura.xml `
  "dotnet test <ruta-al-proyecto-integracion>.csproj --no-build"

# 3) El resto (unit puros) como en el Paso 3 (Coverlet -> opencover + cobertura)
```

> ⚠️ **Mide el PROYECTO de test ENTERO, NO filtres a solo-integracion.** Pasar
> `--filter "FullyQualifiedName~Integration"` al `dotnet test` de dentro del `dotnet-coverage`
> **reactiva el cuelgue** (FB-008, validado en EWP 2026-06-16): aislar todos los `WebApplicationFactory`
> juntos arranca N TestServers seguidos y satura el profiler. El proyecto entero (unit + integracion
> mezclados) va limpio. La parte unit se mide dos veces (tambien en el Paso 3) -> inofensivo, el
> pliegue es raise-only. Si AUN asi cuelga el proyecto entero, anade `--blame-hang-timeout 180s`.

El producer descubre **tanto** `coverage.opencover.xml` (cc/NPath) **como** `*.cobertura.xml`
(cobertura de dotnet-coverage) y **pliega** la cobertura por metodo/clase en modo **raise-only**
(nunca baja; cc/NPath siguen del opencover). Asi los metodos de integracion **medidos** dejan de
salir a 0%/CRAP falso.

### Paso 4 — Publicar el QR (sin pasar la key)

```powershell
.\.claude\skills\calidad-codigo-sync\scripts\Sync-QualityRecord.ps1 -ProjectId <GUID>
```

- **SIN `-ApiKey`** y **SIN pedir la service-key**: el script resuelve sola tu **apiKey per-dev**
  de `_hilo/.mcp-credentials.json` (la creo `irm | iex`). El QR queda atribuido a **tu devAlias**.
  Pasar la key a mano la dejaria en el historial / transcript (NO hacerlo). El `-ApiKey` explicito
  es **solo para CI** (Variable Group), no para uso interactivo.
- Si `--dry-run`: anadir `-DryRun` (calcula + imprime el payload, no envia).
- **Cobertura de integracion (D2/FB-008)**: si el proyecto **tiene** tests de integracion
  (`WebApplicationFactory`) y **NO** se pudieron medir (Coverlet colgo y NO se hizo el Paso 3b con
  dotnet-coverage), anadir **`-CoberturaIntegracionMedida:$false`**. Asi el dashboard marca
  "integracion no medida" en vez de leer el 0% como deuda. Si SI se midio (o no hay integracion),
  el default `$true` es correcto y no hay que pasar nada.
- `CodeSearchBase` (opcional): si el proyecto lo tiene configurado, el script ya lo usa; el
  comando no necesita pasarlo a mano salvo que el usuario lo pida.

### Paso 5 — Confirmar

Reportar al usuario, de la salida del script:

- La linea `[calidad-sync] Usando la apiKey per-dev de _hilo/.mcp-credentials.json`
  (confirma que se resolvio la credencial sin exponerla).
- La linea `[calidad-sync] [OK] publicado: created=1 ...` y el **codigo QR-nnn**.
- El resumen (gate PASS/FAIL, cobertura, CRAPmax, nº clases) tal cual, **sin** proponer cambios.

Indicar que el resultado ya es visible en el dashboard de calidad (cartera + drill-down:
charts con umbral, desglose por clase, treemap de riesgo, diff vs el QR anterior).

---

## Errores comunes

| Sintoma | Causa / fix |
|---|---|
| `No se encontro coverage.opencover.xml` | el `dotnet test` no emitio opencover → falta `--settings ...coverage.runsettings` o se ejecuto desde `03_Desarrollo` |
| El runner se cuelga (CPU plana) | casi siempre tests de integracion `WebApplicationFactory` bajo Coverlet (FB-008) → medir esos proyectos con `dotnet-coverage` por-proyecto secuencial (Paso 3b). Si es otro recurso externo del arranque → PARARSE y diagnosticar |
| `401` al publicar | la apiKey per-dev no resolvio / fue revocada → re-`irm | iex`; en CI, revisar el Variable Group |
| `[SKIP] el hub no expone /v2/sync/quality-batch` | hub < v1.3.0 → no bloquea; avisar para actualizar el hub |
| El `--settings` no se encuentra | se ejecuto desde `03_Desarrollo/` en vez de la raiz del repo (Paso 1) |

---

## Relacion con otros comandos / skills

- **skill `calidad-codigo-sync`**: el conocimiento tecnico (parseo opencover, CRAP estandar,
  resolucion de credenciales, POST). Este comando es el disparador acotado.
- **Mira / R18** (`mira summary`): es el **gate de cobertura del pipeline** (tumba el build). Este
  comando NO gatea CI; produce el QR del dashboard. Complementarios, no se solapan.
- **`/cicd-init` Fase 2.7**: cablea este mismo flujo como **paso de CI** (con la service-key del
  Variable Group), para que cada build publique su QR automaticamente.

---

*Comando de la plantilla Ovillo. Disparador acotado de la skill `calidad-codigo-sync`.*
