---
name: docs-agente-sync
description: >
  Publica los Registros de Documentacion de Agente (DOC) del proyecto en el Hub Ovillo,
  y evalua su frescura contra el codigo fuente. USE FOR sincronizar al hub el estado de la
  documentacion-de-agente generada por /analisis-arquitectura --agente (contexto compacto que
  consumen los agentes de codigo, referenciado desde la jerarquia CLAUDE.md), normalmente como
  paso de CI; tambien para emitir un DOC manual en local y detectar drift (fuente cambio, doc
  quedo obsoleto). DO NOT USE FOR generar/derivar la documentacion en si (eso es
  /analisis-arquitectura, modo --agente), ni para docs de desarrollador tipo ADR/README/API-ref
  (eso es documentacion-tecnica), ni para docs de usuario final (user-documentation), ni para
  inlinar contenido dentro de CLAUDE.md (prohibido por context-optimization: el doc se referencia,
  no se incrusta). Keywords: doc de agente, DOC, registro de documentacion, contexto de agente,
  agent context, drift de documentacion, doc obsoleto, stale docs, source stamp, hash de fuente,
  presupuesto de contexto, token budget, CLAUDE.md pointer, AGENTS.md, mcp sync docs, docs-batch.
---

# docs-agente-sync

Productor de **Registros de Documentacion de Agente (DOC)** del ecosistema Ovillo. NO deriva la
documentacion: lee la que ya genero `/analisis-arquitectura --agente`, calcula su **frescura
respecto al codigo fuente** (drift) y su **coste de contexto** (tokens estimados), y **publica el
DOC en el Hub** (`POST /v2/sync/docs-batch`).

Es la **otra mitad** del flujo de contexto-de-agente: `/analisis-arquitectura --agente` PRODUCE el
doc; esta skill lo REGISTRA y vigila que no se pudra ni engorde.

> **Frontera con OpenWiki (langchain-ai/openwiki)**: la funcion de OpenWiki (derivar docs de agente
> + mantenerlas al dia + cablearlas a CLAUDE.md/AGENTS.md) se reparte aqui entre tres piezas nativas:
> `analisis-arquitectura --agente` (deriva), esta skill (registra + drift) y un puntero en la
> jerarquia CLAUDE.md (nunca inline; ver context-optimization). NO se adopta el CLI de OpenWiki.

## Que es un DOC (Registro de Documentacion de Agente)

El metadato + huella de un doc de contexto-de-agente para un **entrypoint** (R25). No es el texto del
doc: es su ficha en el Hub, con la que el portfolio ve que proyectos tienen contexto de agente fresco.

| Campo | Significado |
|---|---|
| `codigo` | `DOC-nnn` secuencial por proyecto (UPSERT por ProyectoId+Codigo) |
| `entrypoint` / `tipo` | slug del entrypoint (web/api/console, R25) que documenta el doc |
| `docPath` | ruta relativa del doc de agente (ej. `docs/agente/<slug>.md`) |
| `srcStamp` | hash del subarbol de **codigo fuente** del entrypoint (via Get-SourceStamp.ps1) |
| `srcStampDoc` | hash de fuente **sellado en la cabecera del doc** cuando se genero |
| `drift` | `fresh` (srcStamp == srcStampDoc) / `stale` (fuente cambio) / `orphan` (sin fuente) |
| `tokensEstimados` | coste de contexto del doc (bytes/4). Senal para el presupuesto (context-optimization) |
| `gate` | `PASS` / `WARN` (WARN si `stale`, `orphan`, o supera `-TokenBudget`) |
| `generadoCon` | version del ecosistema con que se genero (de `_hilo/VERSION.json`) |
| `adrRelacionados` | codigos ADR cruzados |

## Cuando usar

- **En CI**, tras `/analisis-arquitectura --agente` (o si el doc ya existe en el repo), para que cada
  build registre el estado del contexto de agente y **avise si quedo stale**.
- **En local**, para emitir un DOC manual o inspeccionar drift (`-DryRun` para ver sin enviar).

## Cuando NO usar

- **Generar/derivar el doc** -> `/analisis-arquitectura --agente` (esta skill NO llama al LLM ni
  escribe el contenido; solo lee, sella y publica — igual que calidad-codigo-sync no corre los tests).
- **Docs de desarrollador** (ADR, README, API-ref) -> `documentacion-tecnica`.
- **Docs de usuario final** -> `user-documentation`.
- **Meter el doc dentro de CLAUDE.md** -> PROHIBIDO (context-optimization). El doc vive aparte y
  CLAUDE.md solo lo **referencia** bajo demanda (progressive disclosure).

## Como funciona

1. **Descubrir** los docs de agente en `-DocsDir` (default `docs/agente`). Cada uno lleva en cabecera
   un sello puesto por `/analisis-arquitectura --agente`:
   ```
   <!-- Ovillo docs-agente <entrypoint> @ vX.Y.Z (src <hash12>) gen <fecha> -->
   ```
   (mismo patron que el sello de plantilla del YAML, ADR-047).
2. **Recomputar** el hash del subarbol de fuente del entrypoint con el **mismo helper** que el CI/CD,
   `Get-SourceStamp.ps1` (hermano del script, misma normalizacion EOL que Get-TemplateStamp
   pero sobre el subarbol de codigo del entrypoint). Comparar con el `src <hash12>` sellado -> `fresh` / `stale`.
3. **Estimar** el coste de contexto (bytes/4) y **evaluar el gate**: `WARN` si `stale`, `orphan`, o
   `tokensEstimados > -TokenBudget`.
4. **Numerar + publicar**: pedir el ultimo DOC via `GET /v2/stats/docs/{id}`, numerar el siguiente,
   armar el payload y `POST /v2/sync/docs-batch`.
   ```
   pwsh .claude/skills/docs-agente-sync/scripts/Sync-AgentDoc.ps1 `
     -ProjectId <GUID> `
     -DocsDir docs/agente -SourceRoot 03_Desarrollo -TokenBudget 4000
   ```
   (la service-key se resuelve sola; ver Autenticacion)

## Autenticacion — por defecto NO pasas ninguna key (ADR-045)

Identico a `calidad-codigo-sync` (mismo ADR, misma cadena, misma credencial per-dev):

> **REGLA (dev y agente IA): ejecuta el script SIN `-ApiKey`.** El script resuelve la credencial solo.
> Teclear/pegar la key la deja en PSReadLine y en el transcript del agente (eval-gap ErpSync 2026-06-11).
> El **unico** sitio donde se pasa `-ApiKey` es CI. Si eres un agente: NO pases `-ApiKey`, limitate a
> `-ProjectId`.

- **Local (cero-config)**: usa la `apiKey` per-dev de `_hilo/.mcp-credentials.json` (gitignored). El
  DOC queda atribuido a tu `devAlias`. `.\Sync-AgentDoc.ps1 -ProjectId <GUID>`
- **CI**: service-key per-proyecto (R16, Variable Group) explicita. DOC atribuido a `'ci'`.
  `.\Sync-AgentDoc.ps1 -ProjectId <GUID> -ApiKey $(HUB_SERVICE_KEY)`
- **Cadena de resolucion** (misma que QR): `-ApiKey` (CI) > DPAPI por-proyecto > DPAPI generico >
  apiKey per-dev del repo > env `HUB_SERVICE_KEY` > error accionable. Alta segura: `-StoreKey`.

## Parametros del script (Sync-AgentDoc.ps1)

| Param | Default | Uso |
|---|---|---|
| `-ProjectId` (req salvo `-StoreKey`) | — | GUID del proyecto en el hub |
| `-ApiKey` | — | service-key explicita (CI/VG). Si se omite: cadena de resolucion |
| `-StoreKey` | off | alta segura de la key en esta maquina (prompt oculto, DPAPI) y salir |
| `-ServerUrl` | `…` | base del hub |
| `-DocsDir` | `docs/agente` | carpeta con los docs de agente sellados |
| `-SourceRoot` | `03_Desarrollo` | raiz del codigo fuente (para recomputar el srcStamp) |
| `-StampHelper` | autodetect | ruta a `Get-SourceStamp.ps1` (autodetect: hermano del script) |
| `-TokenBudget` | 4000 | umbral de tokens del gate (WARN si el doc lo supera) |
| `-CodeSearchBase` | null | base ADO Code Search (el dashboard concatena el fichero) |
| `-AdrRelacionados` | @() | codigos ADR relacionados (referencias cruzadas) |
| `-DryRun` | off | calcula + imprime el payload, NO envia |

## Comportamiento

- **DOC-nnn secuencial por proyecto**: `GET /v2/stats/docs/{id}` para el ultimo, numera el siguiente.
  Idempotente en el hub (UPSERT por ProyectoId+Codigo).
- **Best-effort**: si el hub no expone `/v2/sync/docs-batch` (tool `register_agentdoc` no desplegada,
  ver `references/hub-contract.md`) o el POST falla, loguea `[SKIP]`/`[FAIL]` y **no rompe el build**.
- **Solo-lectura del codigo**: NO modifica fuentes ni el doc; NO llama a Azure DevOps.
- **NO deriva**: si `-DocsDir` esta vacia, avisa de que hay que correr `/analisis-arquitectura --agente`
  primero y sale 0 (best-effort). Nunca genera el doc por su cuenta.

## Notas

- El `drift=stale` es informativo, no bloquea: el objetivo es **visibilidad** de contexto podrido, no
  gatear CI. El re-generado lo decides tu (`/analisis-arquitectura --agente`), doctrina on-demand (R20).
- `tokensEstimados` conecta con `context-optimization`: un doc de agente que crece sin control envenena
  cada sesion. El gate `WARN` por `-TokenBudget` es la alarma temprana.
- Usa `Get-SourceStamp.ps1` (hermano, ADR-047): misma normalizacion EOL que Get-TemplateStamp, fichero
  aparte para no tocar el helper critico de cicd. Generacion (--agente) y sync llaman al MISMO helper.
- Depende de la tool de Hub `register_agentdoc` + endpoints `/v2/sync/docs-batch` y `/v2/stats/docs/{id}`
  (ver `references/hub-contract.md`). Sin esa pieza server-side, la skill corre en modo `[SKIP]`.
- Origen: analisis OpenWiki/DeepWiki 2026-07 + patron de calidad-codigo-sync (ADR-045 service-keys).
