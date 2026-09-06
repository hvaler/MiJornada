---
globs: []
---

# Regla Limitaciones TFS 2020 — RETIRADA en el fork Ovillo

> **Estado**: retirada (sin globs — no se carga nunca). Ver `adr/ADR-F000` (decisión #4) del
> repo constructor.
>
> **Por qué**: las tablas A-F de limitaciones eran específicas de **Azure DevOps Server 2020
> Update 1.2 on-premise** (instancia Comillas). El fork abstrae la plataforma CI/CD en
> `ecosystem.config.json` → `cicd.platform` + `cicd.variant`; los invariantes portables viven
> ahora en `.claude/rules/cicd-runtime.md`.
>
> **Si tu organización usa Azure DevOps Server 2020**: configura `cicd.platform:
> "azure-pipelines"` + `cicd.variant: "server-2020"` y añade un módulo de reglas propio con las
> limitaciones de tu instancia. El contenido original (tablas A-F completas, validadas
> empíricamente en pilotos) está en el historial git de este repo.
