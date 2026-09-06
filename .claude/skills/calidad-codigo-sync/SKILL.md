---
name: calidad-codigo-sync
description: >
  Publica los Registros de Calidad (QR) del proyecto en el Hub Ovillo para que el
  dashboard de calidad del portfolio los muestre. USE FOR sincronizar metricas de
  calidad (cobertura linea/rama, CRAP, complejidad ciclomatica, NPath, risk hotspots,
  quality gate) al hub tras correr los tests con cobertura, normalmente como paso de
  CI; tambien para emitir un QR manual en local. DO NOT USE FOR el gate de cobertura
  del pipeline (eso es Mira / R18), ni para el analisis interactivo de CRAP de un dev
  (eso es el catalogo de patrones / crap-analysis), ni para recalcular metricas en el
  dashboard (el dashboard es solo-lectura). Keywords: calidad codigo, QR, registro de
  calidad, CRAP, cobertura, coverage, ciclomatica, NPath, risk hotspots, quality gate,
  ReportGenerator, OpenCover, dashboard calidad, mcp sync quality.
---

# calidad-codigo-sync

Productor de **Registros de Calidad (QR)** del ecosistema Ovillo. Calcula las metricas
de calidad del proyecto desde el coverage y las **publica en el Hub**
(`POST /v2/sync/quality-batch`), que es lo que lee el **dashboard de calidad del portfolio**
(`docs/dashboard/calidad.html`, hub v1.3.0+).

Es la **otra mitad** del dashboard: el dashboard LEE los QR; esta skill los PRODUCE.

## Cuando usar

- **En CI**, tras `dotnet test` con cobertura, para que cada build publique su QR.
- **En local**, para emitir un QR manual (con `-DryRun` para inspeccionar sin enviar).

## Cuando NO usar

- **Gate de cobertura del pipeline** -> es **Mira** (`mira summary`, R18). Esta skill NO gatea el build.
- **Analisis interactivo de CRAP** de un dev -> patron `crap-analysis` (inspeccionar, no publicar).
- **Recalcular metricas en el dashboard** -> el dashboard es solo-lectura; el verdict del gate
  lo computa ESTA skill (productor) y se almacena en el QR.

## Como funciona (verificado en el spike F0)

1. **Cobertura en 2 formatos** (una pasada). El coverage debe emitir `cobertura,opencover`:
   - `cobertura` -> sigue alimentando el gate de Mira (R18) **y** aporta CRAP.
   - `opencover` -> aporta complejidad ciclomatica + **NPath** por metodo.
   Usa el runsettings incluido:
   ```
   dotnet test --collect:"XPlat Code Coverage" \
     --settings .claude/skills/calidad-codigo-sync/scripts/coverage.runsettings \
     --results-directory ./TestResults
   ```
2. **Calcular + publicar**: el script parsea el `coverage.opencover.xml` (ciclomatica, NPath y
   cobertura por metodo), computa **CRAP = ciclomatica^2 x (1 - cobertura)^3 + ciclomatica**
   (formula estandar, la misma que ReportGenerator), agrega el QR
   (CRAP max, nº metodos CRAPpy, ciclomatica media, NPath max, cobertura linea/rama,
   top-N risk hotspots, desglose `clases[]` por clase/namespace), evalua el **quality gate**
   y hace el POST al hub:
   ```
   pwsh .claude/skills/calidad-codigo-sync/scripts/Sync-QualityRecord.ps1 `
     -ProjectId <GUID> `
     -CodeSearchBase 'https://devops.example.org/<col>/<proj>/_search?type=code&text=' `
     -CrapThreshold 30 -CoverageLineMin 75
   ```
   (la service-key se resuelve sola; ver Autenticacion)

## Autenticacion — por defecto NO pasas ninguna key (ADR-045)

> **REGLA (dev y agente IA que publica en su nombre): ejecuta el script SIN `-ApiKey`.**
> El script resuelve la credencial **solo**. Teclear/pegar la key a mano la deja en el
> historial PSReadLine y en el transcript del agente IA (eval-gap ErpSync 2026-06-11).
> El **unico** sitio donde se pasa `-ApiKey` es CI (recuadro de abajo). Si eres un agente:
> NO pases `-ApiKey`, NO pidas la key al usuario — limitate a `-ProjectId`.

**Caso normal (cero-config, lo que hace el 99%)** — cualquier miembro del equipo que haya
ejecutado `irm | iex` en su clon ya tiene su **apiKey per-dev** en `_hilo/.mcp-credentials.json`
(gitignored, ligada a su email). Publica directamente y el QR queda atribuido a **su devAlias**:
```
.\Sync-QualityRecord.ps1 -ProjectId <GUID>
```

**SOLO CI** (lo lanza el pipeline, no una persona) — la **service-key per-proyecto**
(credencial de automatizacion) viene de la Variable Group secreta (R16) y se pasa explicita.
El QR queda atribuido a `'ci'`:
```
.\Sync-QualityRecord.ps1 -ProjectId <GUID> -ApiKey $(HUB_SERVICE_KEY)
```

**Cadena de resolucion interna** (precedencia real del script; en local nunca necesitas las
2 primeras, deja que caiga a la per-dev): `-ApiKey` explicito (CI) > DPAPI por-proyecto >
DPAPI generico > **apiKey per-dev del repo** > env `HUB_SERVICE_KEY` > error accionable.

**Maquina sin per-dev** (raro: runner local, dev no registrado en el proyecto) — alta de la
service-key con prompt oculto, **nunca como argumento** (DPAPI per-user, una vez por maquina):
```
.\Sync-QualityRecord.ps1 -StoreKey                      # generica
.\Sync-QualityRecord.ps1 -StoreKey -ProjectId <GUID>    # variante por proyecto
```

**Emision/rotacion de la service-key (admin del hub)**:
- Emitir: `EXEC mcp.EmitirServiceKey @ProyectoId='<GUID>', @Label='ci-quality', @ServiceKey=@k OUTPUT, @Id=@id OUTPUT` (plaintext UNA vez -> al Variable Group, NUNCA al chat).
- Rotar/baja (sospecha de exposicion, baja de un miembro): `EXEC mcp.RevocarServiceKey @Id=<id>` + emitir nueva. Sintoma de key rotada/revocada: **401** en el POST -> en CI actualizar la VG; en local con DPAPI, re-`-StoreKey`.

## Cobertura multi-proyecto e integracion (D1/FB-009 + D2/FB-008)

- **Fusion multi-proyecto (D1)**: el script descubre **todos** los `coverage.opencover.xml` y
  **fusiona la cobertura por `(clase::metodo)`** tomando el **maximo** (cc/NPath son estaticos).
  Antes tomaba el valor por-fichero (el peor 0%) y un assembly compartido cargado por varios
  proyectos de test salia a 0% -> `crapMax`/`hotspots`/`clases[]` falsos. Ya no.
- **Integracion con `WebApplicationFactory` (D2)**: Coverlet (`XPlat Code Coverage`, IL-rewrite)
  **cuelga** el testhost con TestServer (FB-008), sobre todo a nivel solucion en paralelo. Mide esos
  proyectos con **`dotnet-coverage`** (profiler out-of-process) **por-proyecto SECUENCIAL**:
  ```
  **NO filtres a solo-integracion** (`--filter ~Integration`): aislar todos los `WebApplicationFactory`
  juntos reactiva el cuelgue (FB-008, EWP 2026-06-16). Mide el proyecto de test **entero** (la parte
  unit se remide en el Paso 3 -> inofensivo, el pliegue es raise-only). Si el proyecto entero aun
  cuelga: `--blame-hang-timeout 180s`.
  El producer descubre tambien `*.cobertura.xml` y **pliega su cobertura por metodo/clase en modo
  raise-only** (nunca baja; cc/NPath del opencover). Asi la integracion **medida** deja de salir a 0%.
- **Flag `-CoberturaIntegracionMedida`**: si el proyecto **tiene** integracion y **NO** se pudo medir
  (Coverlet colgo y no se hizo dotnet-coverage), pasa `-CoberturaIntegracionMedida:$false`. El QR lo
  lleva al hub y el dashboard muestra "integracion no medida" en vez de leer el 0% como deuda.
  Default `$true` (medida/no aplica).

## Parametros del script (Sync-QualityRecord.ps1)

| Param | Default | Uso |
|---|---|---|
| `-ProjectId` (req salvo `-StoreKey`) | — | GUID del proyecto en el hub |
| `-ApiKey` | — | service-key explicita (CI/VG). Si se omite: cadena de resolucion |
| `-StoreKey` | off | alta segura de la key en esta maquina (prompt oculto, DPAPI) y salir |
| `-ServerUrl` | `…` | base del hub |
| `-ResultsDir` | `./TestResults` | donde `dotnet test` dejo el coverage |
| `-CodeSearchBase` | null | base ADO Code Search (el dashboard concatena el fichero) |
| `-CrapThreshold` | 30 | umbral CRAP del gate (coincide con thresholds de ReportGenerator) |
| `-CoverageLineMin` / `-CoverageBranchMin` | 75 / 60 | minimos de cobertura del gate |
| `-TopHotspots` | 20 | nº de risk hotspots a publicar |
| `-AdrRelacionados` | @() | codigos ADR relacionados (referencias cruzadas) |
| `-CoberturaIntegracionMedida` | `$true` | D2/FB-008: `$false` si hay integracion (WebApplicationFactory) y NO se midio -> dashboard marca "integracion no medida" |
| `-DryRun` | off | calcula + imprime el payload, NO envia |

## Comportamiento

- **QR-nnn secuencial por proyecto**: consulta el ultimo via `GET /v2/stats/quality/{id}` y
  numera el siguiente. Idempotente en el hub (UPSERT por ProyectoId+Codigo).
- **Best-effort**: si el hub no expone `/v2/sync/quality-batch` (< v1.3.0) o el POST falla,
  loguea `[SKIP]`/`[FAIL]` y **no rompe el build** (la calidad no debe tumbar CI; eso es Mira).
- **Solo-lectura del codigo**: NO modifica fuentes; NO llama a Azure DevOps.

## Notas

- Requiere ReportGenerator solo si quieres el HTML para humanos; el productor NO lo necesita
  (parsea el OpenCover directamente). CRAP, ciclomatica y NPath salen del propio `opencover.xml`.
- CRAP > 30 = alto riesgo (umbral del gate). Escala de referencia: <5 bajo, 5-30 medio, >30 alto.
- El runsettings excluye tests/benchmarks/generado/migraciones (adoptado de `crap-analysis`).
- Origen: plan `calidad-codigo-sync` + spike F0 (EWP, 2026-06-10) + ADR-045 (service-keys).
