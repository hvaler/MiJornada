---
description: Registra en el hub Ovillo el estado de la documentacion-de-agente del proyecto (DOC) y detecta drift respecto al codigo. NO deriva la doc (eso es /analisis-arquitectura --agente)
argument-hint: "[--dry-run] [--docs-dir <ruta>] [--budget <tokens>]"
---

# /docs-sync

Publica los **Registros de Documentacion de Agente (DOC)** del proyecto al hub Ovillo: descubre los
docs de agente en `docs/agente/`, recomputa el hash del subarbol de fuente de cada entrypoint, detecta
**drift** (fuente cambio → doc obsoleto), estima el coste de contexto (tokens) y hace el POST. Es lo que
da visibilidad de "contexto de agente fresco/podrido" en el portfolio.

> El comando **NO genera codigo ni documentacion**: orquesta la skill `docs-agente-sync` y su script
> estable `.claude/skills/docs-agente-sync/scripts/Sync-AgentDoc.ps1`. La **derivacion** del doc es de
> `/analisis-arquitectura --agente`; este comando solo **registra y vigila**.

---

## ALCANCE ESTRICTO (leer antes de actuar)

Este comando **solo REGISTRA y DETECTA DRIFT**. Mientras lo ejecutas:

- ❌ **NO** generes ni edites los docs de `docs/agente/` (eso es `/analisis-arquitectura --agente`).
- ❌ **NO** regeneres un doc porque salga `drift=stale`: el DOC refleja el **estado real**, que es justo
  lo que el portfolio debe mostrar. La decision de regenerar es del usuario, on-demand (R20).
- ❌ **NO** inlines contenido de los docs en `CLAUDE.md` (prohibido por `context-optimization`: el doc
  se referencia, nunca se incrusta).
- ❌ **NO** hagas commits ni toques codigo de produccion.
- ✅ Si `docs/agente/` esta vacia o un doc no tiene sello → **avisa** de que hay que correr
  `/analisis-arquitectura --agente` primero. No lo ejecutes tu por tu cuenta sin que lo pidan.

> Guarda heredada del patron de `/calidad-sync`: publicar un registro es una **foto**, no un disparador
> de cambios.

---

## Sintaxis

```
/docs-sync                       Registra el estado de docs/agente/ y publica los DOC
/docs-sync --dry-run             Calcula e imprime el payload (drift/tokens/gate), NO envia
/docs-sync --docs-dir <ruta>     Carpeta de docs de agente (default docs/agente)
/docs-sync --budget <tokens>     Umbral del gate de contexto (default 4000; WARN si se supera)
```

---

## Flujo

### Paso 0 — Pre-checks

1. Leer `_hilo/.mcp-project.json` → `projectId`. Si no existe → avisar (proyecto no registrado en el hub; `/mcp-register`).
2. Verificar que existe `docs/agente/`. Si no → avisar: "Genera el contexto primero con `/analisis-arquitectura --agente`." y parar (best-effort, no es error).

### Paso 1 — Invocar el script (la skill hace el trabajo)

```
pwsh .claude/skills/docs-agente-sync/scripts/Sync-AgentDoc.ps1 `
  -ProjectId <projectId> `
  -DocsDir <docs-dir> `
  -SourceRoot 03_Desarrollo `
  -TokenBudget <budget> `
  [-DryRun]
```

- **Autenticacion**: NO pasar `-ApiKey` (dev/agente en local). El script resuelve la service-key solo
  (ADR-045). El unico sitio con `-ApiKey` es CI (ver `references/ci-wiring.md`).
- El script es **best-effort**: si el hub no expone `/v2/sync/docs-batch` (tool `register_agentdoc` no
  desplegada) responde `[SKIP]` sin romper nada.

### Paso 2 — Interpretar y mostrar

Mostrar al usuario la tabla que emite el script (por entrypoint): `drift` (fresh/stale/orphan), `tokens`,
`gate` (PASS/WARN). Si hay `stale` o `WARN`, **informar** (no actuar):

```
2 DOC publicados. 1 en drift=stale (MyCompany.X.Web): el codigo cambio desde que se genero el doc.
Para refrescarlo (cuando quieras): /analisis-arquitectura --agente --solucion <sln>
```

---

## REGLAS CRITICAS

- **NUNCA** generar/editar docs de agente aqui (eso es `/analisis-arquitectura --agente`).
- **NUNCA** inlinar docs en CLAUDE.md (context-optimization).
- **NUNCA** pasar `-ApiKey` a mano fuera de CI (ADR-045; queda en PSReadLine/transcript).
- **SIEMPRE** best-effort: la doc no tumba nada; `[SKIP]` si el hub no tiene la tool aun.
- El registro es una **foto**; el re-generado es on-demand y lo decide el usuario (R20).

---

## REFERENCIAS

- Skill orquestada: `.claude/skills/docs-agente-sync/` (SKILL.md + scripts + references)
- Generador del doc: `/analisis-arquitectura --agente`
- Tool MCP consumida: `register_agentdoc` (Hub) · endpoints `/v2/sync/docs-batch`, `/v2/stats/docs/{id}`
- Cableado CI: `.claude/skills/docs-agente-sync/references/ci-wiring.md`
- Contrato server-side: `.claude/skills/docs-agente-sync/references/hub-contract.md`
- Hermano: `/calidad-sync` (QR) — mismo patron, distinto tipo de registro
- ADR: `_estado/DECISIONES.md` ADR de docs-agente (OpenWiki→nativo)

---

*Comando plantilla Ovillo — wrapper de docs-agente-sync. Registrar = foto del contexto de agente + drift; generar = /analisis-arquitectura --agente.*
