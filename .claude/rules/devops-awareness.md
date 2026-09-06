# Regla: DevOps / Issue-Tracker Awareness

> Se aplica SIEMPRE en proyectos con una plataforma de DevOps/issue-tracking configurada
> (`ecosystem.config.json` → `vcs.platform` / `cicd.platform`, o `_hilo/ESTADO_PROYECTO.json`
> → `infraestructura` / `jira`). Plataformas: Azure DevOps (Server/Services), GitHub, GitLab,
> Jira.
> 2 modos: **pasivo** (default, solo sugiere) y **activo** (opt-in, sincroniza automaticamente).
> Modo: `_hilo/ESTADO_PROYECTO.json → infraestructura.azureDevOps.autoSync` (u homologo de la
> plataforma).
>
> **Detalle tecnico del modo activo** (payloads REST, estados por proceso, gotchas de instancias
> on-premises, pendingOps): leer bajo demanda las referencias de la skill `issue-tracker-sync`
> (`.claude/skills/issue-tracker-sync/references/` hasta su generalizacion en FASE 2b).

---

## Deteccion

Activa cuando: `infraestructura.cicd.plataforma != null`, O el remoto git apunta a la
plataforma configurada en `vcs.platform`, O `jira.habilitado`, O el usuario menciona
Boards/PBIs/issues/work items. Si nada de eso aplica, esta regla no aplica.

## Modos

| `autoSync` | Modo | Comportamiento |
|---|---|---|
| `false`/ausente | **Pasivo** (default) | Solo recordatorios. NO ejecuta nada contra la plataforma. |
| `true` | **Activo** (opt-in) | Crea/actualiza work items al usar /nuevo-evolutivo, /finalizar-evolutivo, etc. Requiere ademas el id del contenedor raiz (epic/milestone) configurado; si falta, caer a pasivo. |

Activar el modo activo requiere `/devops-sync` previo + `autoSync: true` (manual o
`/devops-sync --enable-auto`).

## Modo pasivo — recordatorios (una linea, al final de la respuesta)

| Tras... | Sugerencia |
|---|---|
| `/finalizar-evolutivo` | "¿Actualizar el work item? → `/devops-sync --update-pbi {CODIGO}` o moverlo a Done en la plataforma" |
| `/commit` conventional | "Si hay issue/PBI asociado, referencia `#ID` en el mensaje (la plataforma asocia commits automaticamente)" |
| Crear endpoint nuevo | "¿Existe work item para esta funcionalidad? Considera `/devops-sync` (wiki de endpoints)" |
| `/analizar` o `/analisis-arquitectura` | "`/devops-sync` genera work items desde hallazgos (seguridad, deuda tecnica...)" |
| Inicio de sesion con contenedor raiz configurado | Mostrar: epic/milestone activo, items en progreso, ultima sync, "modo pasivo — activar con /devops-sync --enable-auto" |

## Trazabilidad Git ↔ plataforma (ambos modos)

- Commits con work item: `feat(scholarships): añadir filtro por estado #1234` (asociacion por `#ID`).
- Ramas: si `convencionRamas` incluye `{codigo}`, usar el ID del issue/PBI cuando sea posible
  (`feature/1234-filtro-becas`).

## Invariantes al llamar a la API de la plataforma

1. **Estados por proceso**: detectar el proceso/workflow real ANTES de crear/transicionar
   items (ej. Azure DevOps Scrum usa New → Approved → **Committed** → Done, NUNCA "In
   Progress"; Basic usa To Do → Doing → Done; GitHub/GitLab/Jira tienen workflows propios).
2. **Asignaciones con la identidad EXACTA** que la plataforma espera (displayName de
   directorio, username u email segun plataforma — de `equipo.miembros[]`). Sin match →
   omitir el campo, nunca inventar.
3. **Fijar la api-version/endpoint soportado por la instancia** (`cicd.variant` puede limitar
   la version de API disponible en instancias on-premise).
4. **NO bloquear el trabajo** por error de conectividad — warning + encolar en
   `_hilo/devops_pending_ops.json` (graceful degradation).

## NO hacer (ambos modos)

- NO crear work items en modo pasivo (solo sugerir); NO activar modo activo sin configuracion
  explicita del usuario; NO asumir conectividad.

---

*Regla condicional v1.0.0 (fork Ovillo) — awareness de plataforma DevOps configurable
(generalizada desde Azure DevOps/TFS, ADR-F002).*
