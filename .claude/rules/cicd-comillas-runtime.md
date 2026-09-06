---
globs: []
---

# Regla CI/CD runtime Comillas (R1-R25) — GENERALIZADA en el fork Ovillo

> **Estado**: generalizada → **`.claude/rules/cicd-runtime.md`** (sin globs aquí — este
> placeholder no se carga nunca). Ver `adr/ADR-F000` (decisión #4) y `adr/ADR-F002`.
>
> Las 25 reglas mezclaban dos naturalezas:
> - **Invariantes portables de CI/CD** (modelos de deploy, gates, rollback, secretos, retention,
>   runbook, idempotencia, routing por entrypoint) → reescritas neutralmente en `cicd-runtime.md`.
> - **Specifics de TFS 2020 + inventario de servidores Comillas** (pool BUILDERS, LADYADA,
>   trapster01/STRYFE/STORM, TLS PS 5.1, descarga REST de artefactos) → retiradas; el inventario
>   de entornos es ahora `cicd.environments[]` del `ecosystem.config.json`.
>
> El contenido original completo (con su validación empírica en pilotos) está en el historial
> git de este repo.
