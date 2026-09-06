# Cablear `calidad-codigo-sync` en el pipeline (F2)

Cómo conectar el productor de QR en CI para que **cada build publique su Registro de
Calidad** en el Hub (lo lee el dashboard `docs/dashboard/calidad.html`).

> Principio: la calidad **NO gatea el build** (eso es Mira / R18). Este paso es
> **best-effort** (`continueOnError: true` + el script sale 0 ante fallo). Solo .NET con tests.

## 1. El paso de tests debe emitir OpenCover (además de cobertura)

El productor necesita `coverage.opencover.xml` (lleva ciclomática + NPath por método).

> **Pipeline `fase2.dotnet` de `/cicd-init` (≥ v3.13.0-h12)**: el `dotnet test` del template **ya emite
> `Format=cobertura,opencover`** de serie → el `*.opencover.xml` está en `$(Agent.TempDirectory)` y **NO
> necesitas el `coverage.runsettings` de la skill** ni un step de tests aparte. Y desde **v3.13.0-h14** el
> step `quality-sync` viene **incluido por defecto** (opt-out) en `/cicd-init` Fase 2 .NET — solo tienes que
> añadir `HUB_SERVICE_KEY` al VG (paso 4). Esta sección §1 aplica a **pipelines hand-rolled** (o netfx) que
> aún no emitan opencover.

Para un pipeline hand-rolled, usar el runsettings de la skill en el `dotnet test` del stage Build:

```yaml
- task: DotNetCoreCLI@2
  displayName: 'Tests + coverage (cobertura + opencover)'
  inputs:
    command: test
    arguments: >-
      --collect:"XPlat Code Coverage"
      --settings $(Build.SourcesDirectory)/.claude/skills/calidad-codigo-sync/scripts/coverage.runsettings
    # NO anadir --results-directory: el task ya lo inyecta a $(Agent.TempDirectory) (R18 HALLAZGO H)
```

- `cobertura` → sigue alimentando el **gate de Mira (R18)** sin cambios.
- `opencover` → lo consume `Sync-QualityRecord.ps1`.

### 1-bis. Tests de integración `WebApplicationFactory` (D2/FB-008)

Coverlet (IL-rewrite) **cuelga** el testhost con `WebApplicationFactory`/TestServer, sobre todo a
nivel solución en paralelo. Si tu solución los tiene, **mide esos proyectos con `dotnet-coverage`**
(profiler out-of-process) **por-proyecto secuencial**, en un step aparte que deja el `cobertura.xml`
en el mismo `TestResults`; el productor lo descubre y **pliega** su cobertura (raise-only):

```yaml
- task: PowerShell@2
  displayName: 'Coverage integracion (dotnet-coverage, por-proyecto)'
  continueOnError: true
  inputs:
    targetType: inline
    script: |
      dotnet tool install -g dotnet-coverage 2>$null; $env:PATH += ";$env:USERPROFILE\.dotnet\tools"
      # un collect por proyecto de integracion (NO la solucion entera en paralelo)
      dotnet-coverage collect -f cobertura -o "$(Agent.TempDirectory)/int-WebApi.cobertura.xml" `
        "dotnet test 04_Pruebas/<Proyecto>.Integration.Tests/*.csproj --no-build"
```

Si tu pipeline **no** mide la integración, pasa `-CoberturaIntegracionMedida:$false` al productor
(en `quality-sync.yml`) para que el dashboard marque "integración no medida" en vez de leer el 0%.

## 2. Añadir el paso `quality-sync` tras los tests

Materializar `skills/cicd-architect/templates/steps/quality-sync.yml` en el stage Build,
**después** del paso de tests (y, si lo hay, del gate de Mira). Corre `continueOnError`.

## 3. Variables del pipeline

| Variable | Dónde | Valor |
|---|---|---|
| `qualityProjectId` | variables del pipeline (no secreto) | el GUID del proyecto en el hub (= `mcpSync.projectId` de `ESTADO_PROYECTO.json`) |
| `codeSearchBase` | variables del pipeline (no secreto) | `https://devops.example.org/<coleccion>/<proyecto>/_search?type=code&text=` |
| `HUB_SERVICE_KEY` | **Variable Group, `isSecret`** (R16) | la service-key per-proyecto (paso 4) |

## 4. Provisionar la service-key (`HUB_SERVICE_KEY`)

ADR-045: el build se autentica con una **service-key per-proyecto** (NO la apiKey per-dev). Dos vías:

### 4.a Zero-touch (recomendado, ADR-046 — Hub ≥ 1.7.0)

`/cicd-init` Fase 2 .NET ofrece configurarla sola (opción Auto). Materializa y ejecuta
`05_CICD/provision-quality-ci-key.ps1` (desde `cicd-architect/templates/Provision-QualityCiKey.ps1.template`):
usa tu **apiKey per-dev** para que el Hub emita/rote la key (`POST /v2/sync/emit-service-key`), la deja
`isSecret` en el Variable Group y autoriza el VG→canalización. **La key nunca se imprime ni la maneja el
agente** (fluye en memoria del script). Corre en la máquina del dev (Windows auth a TFS). Rotación:
re-ejecutar con `-Rotate` (revoca la `ci-quality` anterior y emite una nueva, atómico en el VG).

### 4.b Manual (sigue válido — sin Hub 1.7.0, o sin apiKey del dev)

El administrador la emite una vez y la guarda en el Variable Group:

```sql
-- en la BD del hub (Ladyada)
DECLARE @k VARCHAR(80), @id BIGINT;
EXEC mcp.EmitirServiceKey @ProyectoId='<GUID>', @Label='ci-quality', @ServiceKey=@k OUTPUT, @Id=@id OUTPUT;
SELECT @k AS ServiceKey;   -- copiar @k al Variable Group como HUB_SERVICE_KEY (isSecret)
```

Rotación/baja: `EXEC mcp.RevocarServiceKey @Id=<id>` y emitir una nueva (o `mcp.EmitirServiceKeyRotando`,
que revoca las del mismo label y emite). Tras rotar: actualizar el valor en el Variable Group.

> **Uso manual/local (fuera de CI)**: NO pasar la key con `-ApiKey` a mano — queda en
> el historial PSReadLine y en transcripts de agentes IA (eval-gap ErpSync 2026-06-11).
> Alta una vez por máquina con prompt oculto: `.\Sync-QualityRecord.ps1 -StoreKey`
> (DPAPI per-user en `%APPDATA%\Ovillo\`); después el script resuelve la key solo.
> Cadena de resolución completa en el SKILL.md § Autenticación.

## 5. Resultado

Cada build (incluso con tests en rojo, mientras haya coverage) publica un `QR-nnn`:
cobertura línea/rama, CRAP máx, métodos CRAPpy, ciclomática media, NPath máx, top-N
risk hotspots y el verdict del quality gate. El dashboard de calidad lo muestra en la
cartera + drill-down.

## Notas

- El productor **no necesita ReportGenerator** en el agente (parsea el OpenCover
  directamente) → no requiere internet ni instalar tool. ReportGenerator solo si quieres
  el HTML para humanos.
- Si el hub es < v1.3.0 (sin `/v2/sync/quality-batch`) el script loguea `[SKIP]` y no falla.
- **Integración automática en `/cicd-init` Fase 2 .NET: HECHA (v3.13.0-h14)** — el step `quality-sync` se
  incluye por defecto (opt-out) vía los marcadores `{{QUALITY_SYNC_STEP}}`/`{{QUALITY_SYNC_VARS}}` del template
  `fase2.dotnet`; el opencover ya lo emite el `dotnet test` del template (h12). Esta guía queda para pipelines
  hand-rolled, netfx, o para entender el detalle. Solo falta que el admin emita la `HUB_SERVICE_KEY` (paso 4).
