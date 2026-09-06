---
globs: []
---

# Regla TFVC — RETIRADA en el fork Ovillo

> **Estado**: retirada (sin globs — no se carga nunca). Ver `adr/ADR-F000` (decisión #3) del
> repo constructor.
>
> **Por qué**: TFVC (Team Foundation Version Control) era idiosincrático del parque
> Comillas/TFS on-premise. El fork asume **Git** (`vcs.type: "git"` en `ecosystem.config.json`).
>
> **Si tu organización no usa Git**: configura `vcs.type: "other"` — los comandos `/commit` y
> `/git-sync` degradan a instrucciones manuales en lugar de ejecutar comandos Git (el mismo
> patrón que aplicaba esta regla). El contenido original (comandos `tf`, shelvesets, mapeo de
> funcionalidades) está en el historial git de este repo (`git log -- plantilla/.claude/rules/tfvc.md`).
