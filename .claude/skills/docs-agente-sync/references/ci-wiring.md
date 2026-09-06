# Cablear `docs-agente-sync` en el pipeline

Cómo conectar el productor de DOC en CI para que **cada build registre el estado de la
documentación-de-agente** en el Hub y **avise si quedó stale** respecto al código.

> Principio: la documentación **NO gatea el build** (best-effort, `continueOnError: true` + el
> script sale 0 ante fallo). Mismo contrato que `calidad-codigo-sync`. La doctrina de re-generado
> es **on-demand** (R20): el build *avisa* del drift, tú decides regenerar con
> `/analisis-arquitectura --agente`.

## Dónde encaja en el flujo

```
/analisis-arquitectura --agente   ->  genera docs/agente/<slug>.md  (sellados)   [on-demand, tú]
        |
        v
docs-agente-sync (este paso CI)   ->  lee docs, recomputa srcStamp, publica DOC   [cada build]
        |
        v
Hub  register_agentdoc            ->  dashboard del portfolio ve drift + tokens    [server-side]
```

El paso CI **no genera** nada: si `docs/agente/` está vacía, sale 0 con un aviso. Solo registra y
detecta drift de lo que ya existe en el repo.

## 1. Step best-effort en el stage Build (tras los tests)

```yaml
- task: PowerShell@2
  displayName: 'Sync docs de agente (DOC) al Hub Ovillo'
  continueOnError: true          # best-effort: la doc no tumba el build
  inputs:
    targetType: filePath
    filePath: '$(Build.SourcesDirectory)/.claude/skills/docs-agente-sync/scripts/Sync-AgentDoc.ps1'
    arguments: >-
      -ProjectId $(SticProjectId)
      -DocsDir docs/agente
      -SourceRoot 03_Desarrollo
      -TokenBudget 4000
      -ApiKey $(HUB_SERVICE_KEY)
      -BuildId $(Build.BuildId)
      -CodeSearchBase 'https://devops.example.org/$(System.TeamProject)/_search?type=code&text='
  env:
    HUB_SERVICE_KEY: $(HUB_SERVICE_KEY)   # R16: secreto del Variable Group
```

- `-ApiKey $(HUB_SERVICE_KEY)`: **solo en CI** (la ejecuta el pipeline, no una persona). El DOC
  queda atribuido a `'ci'`. En local **no** se pasa (cadena de resolución ADR-045).
- El helper `Get-SourceStamp.ps1` (hermano de este script en `scripts/`) se autodetecta y calcula el
  hash del subarbol de fuente. Misma normalizacion EOL que `Get-TemplateStamp` (ADR-047) pero fichero
  aparte, para NO tocar el helper critico de cicd. Generacion y sync llaman al MISMO helper.

## 2. Variables / prerrequisitos

| Requisito | Cómo |
|---|---|
| `HUB_SERVICE_KEY` en el Variable Group secreto | R16. Emisión: `EXEC mcp.EmitirServiceKey @Label='ci-docs'` (una vez, plaintext → VG, nunca al chat). Reutiliza la misma service-key del proyecto que ya usa `calidad-codigo-sync`. |
| `SticProjectId` | GUID del proyecto en el Hub (de `_hilo/.mcp-project.json`). |
| Tool `register_agentdoc` desplegada en el Hub | Ver `hub-contract.md`. Sin ella, el step corre en modo `[SKIP]` (404) — inofensivo. |

## 3. Opt-in vs opt-out

A diferencia de `quality-sync` (incluido por defecto en `/cicd-init` Fase 2 .NET desde v3.13.0-h14),
`docs-agente-sync` es **opt-in** hasta que exista un proyecto piloto con `docs/agente/` poblada. Cuando
se valide, `cicd-architect` puede hornear el step en el template `fase2.dotnet` igual que hizo con el de
calidad. **No** lo metas en el scaffolding hasta tener el piloto (misma prudencia que tuvo el
placeholder `cicd-classic-migrator`, retirado en v3.18.0/ADR-053 precisamente porque su piloto
no llegó nunca).

## 4. Interpretar la salida

```
[docs-sync] MyCompany.X.Api          drift=fresh  tokens=2180  gate=PASS
[docs-sync] MyCompany.X.Web          drift=stale  tokens=3990  gate=WARN
[docs-sync] Publicados 2 DOC en el Hub. (respuesta: ok)
```

- `drift=stale` → el código del entrypoint cambió desde que se generó el doc. Regenera on-demand:
  `/analisis-arquitectura --agente` sobre ese entrypoint.
- `gate=WARN` por `tokens > TokenBudget` → el doc de agente engordó; poda o divide (context-optimization).
- `[SKIP]` (404) → falta la tool de Hub; no es un fallo del proyecto.
