# Runbook — Actualizar el pipeline tras un refresco de plantilla

> **Cuándo usar**: tras ejecutar `irm | iex` (actualización de Ovillo) en un proyecto que **ya tiene
> CI/CD** (Fase 1/2). El `irm` refresca el *tooling* (`.claude/`, incluidas las plantillas de pipeline de
> la skill `cicd-architect`), **pero NO toca tu `azure-pipelines.yml`**, que es un artefacto ya generado.
> Para que tu pipeline recoja lo último (nuevas reglas R1-R25, gate de cobertura/Mira, gate de seguridad,
> reporte HTML, branch-gated, etc.) hay que **regenerarlo** con `/cicd-init` (modo edición idempotente).
>
> **Audiencia**: dev del proyecto consumidor. **Plataforma**: Azure DevOps Server 2020 (`devops.example.org`).

---

## 0. Pre-requisitos

- [ ] El `irm | iex` terminó OK (modo update; refresco no destructivo de `.claude/`).
- [ ] Versión del tooling al día: `_hilo/VERSION.json` (o el banner de sesión sin indicador `^update`).
- [ ] `git status` limpio (o solo cambios tuyos sin commitear) antes de regenerar.
- [ ] Sabes qué **stack** es tu proyecto: `.NET` (dotnet/SDK-style), `.NET Framework 4.8` (netfx),
      Vue+Vite (spa) o `.NET-tool`. Las mejoras de plantilla suelen ser por-stack.

## 1. Regenerar el pipeline

- [ ] Abrir Claude Code en la **raíz del proyecto** y ejecutar: **`/cicd-init`**.
- [ ] Debe detectar el pipeline existente → entra en **modo EDICIÓN** (FASE 0.5), no instalación nueva.
- [ ] Elegir **Opción 4 "Actualizar YAML completo a última plantilla"**. Esto **re-renderiza el YAML
      ENTERO** desde la plantilla (NO parchea línea a línea) y re-aplica tus bloques `# CUSTOM:`.
- [ ] Confirmar que detecta tu **stack** correctamente.

## 2. Revisar el DIFF antes de aceptar (PASO CLAVE)

Regenerar trae **todo lo acumulado** desde que generaste tu pipeline, no solo el último cambio. Revisa:

- [ ] El **gate de cobertura (R18)** instala Mira con `dotnet tool update --global dotnet-reportgenerator-globaltool
      --add-source <feed>` (SIN `--version` y SIEMPRE, no solo si falta) → usa **la última** de Mira.
- [ ] El gate R18 gatea por **línea/rama** (`mira summary --threshold-line/--threshold-branch`), **WARN-first**;
      **no** existe `--threshold-crap` (Mira muestra CRAP solo en el HTML, ver paso 4).
- [ ] (Stack .NET) `dotnet test` emite `Format=cobertura,opencover` + steps de **reporte HTML**
      (`mira generate`) y **Publish `CoverageReport`** (additivo, `continueOnError`, NO gatea).
- [ ] El **gate de seguridad (R22)** está cableado (scan en Build + verdict en deploy).
- [ ] **TUS personalizaciones** siguen presentes (rutas IIS/`iisPhysicalPath`, proyectos de test, secretos por
      Variable Group, etc.). Si no están dentro de bloques `# CUSTOM: ... # /CUSTOM`, **re-aplícalas**.
- [ ] NO se cuela nada prohibido (R1/tabla TFS): `deploymentGroup`, `Cache@2`, `DeployEnv` en `variables`,
      `pool.name` apuntando a Deployment Pool, etc.

## 2-bis. Self-check de completitud (PASO CLAVE — h13)

El comando corre `validate-pipeline-complete.ps1` (FASE 2.8) tras regenerar: verifica que el YAML
contiene **todos** los steps canónicos de la plantilla (deriva los markers del propio template). Esto
evita el fallo del edit-mode parcial (regenerar a medias y dejar fuera steps nuevos como el gate R18 o
el reporte HTML `CoverageReport`).

- [ ] El self-check sale **verde** (exit 0). Si sale **rojo** (exit 1) lista los steps ausentes →
      **NO aceptes el cambio**: re-renderiza (Opción 4 completa) hasta que pase. El comando **no debe
      cerrarse con el self-check en rojo**.
- [ ] Excepción legítima: si quitaste pasos opcionales a propósito (sin proyecto de test → sin gate R18;
      sin `/health` → smoke best-effort), esos markers ausentes son esperables (el comando los exime
      con `-Allow`). Cualquier OTRO ausente sí es regeneración incompleta.
- [ ] El YAML lleva un **sello de plantilla** en la cabecera (`# Ovillo cicd-architect <stack> @ vX.Y.Z
      (tpl <hash12>) ...`). El token `tpl <hash12>` es el hash de contenido del template del stack (ADR-047):
      `/cicd-status` solo avisa de **drift** si ese template cambió de verdad (no en cada release). Si avisa,
      vuelve a este runbook. (Pipelines sellados antes de v3.14.0-h1 llevan `zip <sha12>`; un re-render los migra.)

## 3. Aplicar + publicar

- [ ] Aceptar el cambio (queda backup `.azure-pipelines.bak.<fecha>.yml` → tu rollback inmediato).
- [ ] `git add azure-pipelines.yml` (+ `steps/*.yml` si se regeneraron).
- [ ] `git commit -m "ci: pipeline al día con la última plantilla Ovillo"`.
- [ ] `git push` → dispara el Build.

## 4. Verificar en el Build

- [ ] Log del gate R18: `mira version -> X.Y.Z` (confirma que actualizó a la última).
- [ ] (Stack .NET) step de reporte HTML en verde; artefacto **`CoverageReport`** publicado (HTML con
      cobertura y, si hay OpenCover, **CRAP / complejidad / risk hotspots**).
- [ ] Gate R18 = WARN por línea/rama (no bloquea por defecto).
- [ ] Gate R22 (seguridad) según entorno (DEV WARN / PRE-PROD BLOCK, o WARN brownfield).
- [ ] Build global **verde**.

## 5. Si algo falla

| Síntoma | Causa probable | Acción |
|---|---|---|
| Reporte HTML sin CRAP/hotspots | El reporte se generó desde Cobertura (no OpenCover) | Verificar `Format=cobertura,opencover` y que `mira generate` recibe el `*.opencover.xml` |
| `mira` no actualiza / no encontrado | Feed `\\build01...\PaquetesNuget` no accesible desde el agente | Revisar permiso TEC-003 / conectividad del agente al share |
| Cobertura 0% falsa | HALLAZGO H: `$(Agent.TempDirectory)` no se limpia entre builds | El YAML regenerado ya limpia `*cobertura/*opencover.xml` antes del test + ordena por `LastWriteTime` |
| Build no encola (`notStarted`) | Canalización no autorizada al pool BUILDERS | "Permit" en el banner / pool admin (TEC-003) |
| `dotnet test` "No test result files" | Se añadió `--results-directory` a los args | NO añadirlo: el task ya lo inyecta (TRAMPA HALLAZGO H) |

- [ ] **Rollback**: restaurar `.azure-pipelines.bak.<fecha>.yml` + `git checkout azure-pipelines.yml`.
- [ ] Apuntar cualquier incidencia del **ecosistema** en `_hilo/FEEDBACK_ECOSISTEMA.md` (FB-XXX) → `/mcp-sync`.

---

## Notas

- **El reporte HTML de cobertura es additivo y `continueOnError`**: en el peor caso no aparece el artefacto,
  pero **nunca** tumba el build ni cambia el gate.
- Para **NO** regenerar todo (solo aplicar un cambio puntual), puedes editar el `azure-pipelines.yml` a mano y
  pedir al agent `cicd-pipeline-reviewer` que lo audite contra R1-R25. Pero `/cicd-init` (edición) es el camino
  canónico e idempotente.
- Ver también: `LIMITACIONES_TFS_2020.md`, `AUDITAR_PIPELINE.md`, `GUIA_FASES_ADOPCION.md` y la regla
  `cicd-runtime.md` (G1-G14).

---

*Documentos_Base/08_CICD — Ovillo. Runbook de actualización de pipeline tras refresco de plantilla.*
