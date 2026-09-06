# Limitaciones TFS 2020 — RETIRADO en el fork Ovillo

> **Estado**: retirado. Ver `adr/ADR-F000` (decisión #4) del repo constructor.
>
> Esta guía humana documentaba las limitaciones de **Azure DevOps Server 2020 Update 1.2
> on-premise** (la instancia del ecosistema origen): tasks que fallan, keywords YAML no
> soportados, servicios inexistentes, APIs con peculiaridades y gotchas de PowerShell 5.1 en
> agentes Windows — todo validado empíricamente en pilotos reales.
>
> **En el fork**: la plataforma CI/CD se configura en `ecosystem.config.json → cicd.platform`
> + `cicd.variant`. Los invariantes portables viven en `.claude/rules/cicd-runtime.md`
> (G1-G14). Si tu organización usa Azure DevOps Server 2020 (`variant: "server-2020"`),
> recupera el contenido original del historial git de este repo
> (`git log -- plantilla/Documentos_Base/08_CICD/LIMITACIONES_TFS_2020.md`) y adáptalo a tu
> instancia como módulo propio.
