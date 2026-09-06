---
globs:
  - "azure-pipelines.yml"
  - "**/azure-pipelines*.yml"
  - "**/.azure-pipelines/**/*.yml"
  - ".github/workflows/*.yml"
  - ".github/workflows/*.yaml"
  - ".gitlab-ci.yml"
  - "**/Jenkinsfile"
---

# Reglas runtime CI/CD (G1-G14)

> Este archivo aplica cuando Claude edita pipelines de CI/CD. La plataforma concreta se lee de
> `ecosystem.config.json` → `cicd.platform` (`github-actions | gitlab-ci | azure-pipelines |
> jenkins | none`), su `cicd.variant`, el inventario `cicd.environments[]` y el modelo
> `cicd.deployModel`; el proyecto puede sobrescribir en `_hilo/ESTADO_PROYECTO.json.infraestructura`.
> Si `cicd.platform` es `none` y el proyecto no define plataforma: avisar y no generar pipelines.
>
> Estas reglas son los **invariantes portables** heredados del runtime R1-R25 del ecosistema
> origen (validados empíricamente en pilotos reales); los specifics de plataforma/instancia se
> retiraron (ver ADR-F000/F002). El agent `cicd-pipeline-reviewer` audita pipelines contra estas
> reglas.

---

## G1 — Build ≠ Deploy: respetar el modelo de deploy configurado 🔴

Tres modelos (`cicd.deployModel`, wizard `/cicd-init`):

| Modelo | Gate del deploy | Cuándo |
|---|---|---|
| **auto** | ninguno en DEV; aprobación en PRE/PROD | CD continuo a DEV, una sola rama |
| **on-demand** (default) | variable de despliegue explícita (ej. `DeployEnv`) settable al encolar; **el push construye pero NUNCA despliega** | deploy 100% bajo demanda (`/cicd-deploy`) |
| **branch-gated** | variable explícita **+** rama origen correcta | bajo demanda CON ramas por entorno (gitlab-flow, gitflow) |

- En on-demand: push normal → variable vacía → ningún stage de deploy corre (solo Build).
  El deploy se dispara encolando con la variable (`/cicd-deploy --env <env>`); `/cicd-release`
  solo crea tag (NUNCA despliega).
- En branch-gated: cada stage de deploy exige ADEMÁS la rama origen correcta (un build de
  `develop` no puede ir a PROD). Derivar el mapeo entorno→rama de `configuracion.branching`,
  NUNCA hardcodear la rama base.
- ❌ NUNCA mezclar modelos: si el proyecto eligió on-demand, no dejar ningún deploy con trigger
  automático.

## G2 — Trigger CI + branch policies alineados con la estrategia de branching 🟡

Leer `configuracion.branching.estrategia` (ESTADO_PROYECTO) antes de generar triggers:

| Estrategia | Ramas del trigger CI | Policy/protección de build en PR |
|---|---|---|
| push directo (`github-flow-simplificado`, `trunk-based`, `developer-branch`) | `[ramaBase]` | **NO** (bloquearía el push directo) |
| `github-flow` | `[main]` | SÍ |
| `gitflow` | `[main, develop, release/*]` | SÍ |
| `release-flow` / `oneflow` | `[main, release/*]` | SÍ |
| `gitlab-flow` | ramas de entorno | SÍ + modelo branch-gated (G1) |

Las protecciones de rama son **gobierno**: recomendarlas, NUNCA activarlas silenciosamente.
Para estrategias de push directo, avisar EXPLÍCITAMENTE de no activar build-validation en PR.

## G3 — Un pipeline por entrypoint desplegable + routing por tipo de destino 🟡

1 repo = 1 solución con N entrypoints ⇒ **un pipeline por entrypoint desplegable** (web, api,
console/worker), NO uno por solución con jobs mezclados.

- Trigger de paths acotado al subárbol del entrypoint (un cambio no dispara los demás).
- El destino se enruta por `cicd.environments[].kind` (`app` = servidores de aplicaciones,
  `svc` = servidores de servicios) y la etiqueta `deployTarget` del inventario: web/API pública
  → `app`; API privada (default) → `svc`; console/worker → mecanismo según patrón de ejecución
  (tarea programada para sync periódico, servicio del SO para always-on).
- ❌ El valor de routing se deriva del inventario configurado, NUNCA se hardcodea un hostname.

## G4 — Jobs de deploy sin checkout 🟡

Un stage de deploy solo necesita el artefacto, no el código: `checkout: none` (Azure Pipelines)
/ omitir `actions/checkout` (GitHub Actions) / `GIT_STRATEGY: none` (GitLab). Menos overhead y
sin exponer credenciales Git en agentes de deploy.

## G5 — Secretos SOLO en el secret store de la plataforma + fail-fast 🔴

- ❌ NUNCA valores secretos inline en el YAML/Jenkinsfile commiteado.
- ✅ Variable Groups (AzDO) / Secrets (GitHub) / CI Variables enmascaradas (GitLab) /
  Credentials (Jenkins) — o el servicio de `cloud.secrets`.
- ✅ **Fail-fast pre-build**: primer step valida que los secretos requeridos existen y no están
  vacíos; si falta alguno, abortar con mensaje accionable (caso típico: store recién creado sin
  rellenar).

## G6 — Configuración por entorno: nunca hornear la config de UN entorno para todos 🟡

Si hay >1 entorno, el mismo paquete no puede llevar la config de uno solo:

- **Con servicio de secretos/config cloud**: la app lee su config al arrancar; el deploy no
  inyecta nada (preferido).
- **Sin él**: inyección en el stage de deploy ANTES de publicar, con fail-fast si falta un
  valor; o build-por-configuración (transforms) cuando el stack lo requiere (netfx).
- ❌ NUNCA dejar que el deploy machaque la config por-entorno que vive en el servidor destino
  (excluirla del borrado/sync).

## G7 — Gate de cobertura WARN-first 🟡

Stage Build: publicar cobertura y evaluar umbrales configurables (`coverageLineThreshold`,
`coverageBranchThreshold`). **WARN-first por defecto** (avisa sin tumbar el build); el equipo
sube a BLOCK cuando su cobertura supera el umbral de forma estable — coherente con
`hooks.policy` del ecosistema.

⚠️ En agentes self-hosted el directorio temporal **persiste entre builds**: nunca localizar el
XML de cobertura con un glob global + "primer resultado" (coge uno obsoleto → cobertura falsa).
Limpiar antes de `test` y/o ordenar por fecha de modificación descendente.

## G8 — Gate de ciberseguridad multi-capa (patrón verdict-file) 🟡

El análisis corre **una sola vez** en Build (`continueOnError`) y publica un artefacto
`security-report` (json+md); cada stage de deploy decide según ese verdict:

- **DEV** → WARN: vuelca findings y despliega igual.
- **PRE/PROD** → BLOCK: aborta antes del deploy si severidad ≥ umbral configurado o hay secretos.

4 checks: deps vulnerables (`dotnet list package --vulnerable` / `npm audit`; sin red →
`inconclusive`, NUNCA un falso `ok`) · secretos en config versionada (ignorando placeholders) ·
hardening (`AllowedHosts='*'`, CORS abierto, bypass de certs) · SAST del compilador.

- Excepciones con `owner` + `target_date` en un archivo versionado, descontadas del cómputo.
- **Brownfield**: si hay secretos preexistentes (deuda conocida), generar el gate en WARN
  también para PRE/PROD + registrar `SEC-XXX` + plan de subida a BLOCK.
- ❌ NUNCA emitir un verdict sintético "0 findings" cuando el scan falló; si un deploy de
  PRE/PROD no encuentra verdict real → **bloquear**.

## G9 — Triple rollback en entornos críticos (NUNCA en DEV) 🟡

1. **Backup pre-deploy** del destino (etiquetado con el id del build).
2. **Deploy no destructivo** cuando la herramienta lo soporte (no borrar lo no gestionado).
3. **Step de rollback automático** condicionado a fallo del smoke post-deploy, que restaura el
   backup (excluyendo la config por-entorno, G6).

Si el rollback automático falla, seguir el procedimiento manual del RUNBOOK (G11).

## G10 — Retention rules obligatorias 🟡

Sin retención, el almacenamiento de artefactos crece sin límite. Defaults del fork: rama
principal 30 días / mínimo 5 builds / conservar registro (auditoría); otras ramas 7 días /
mínimo 1 / borrar todo.

## G11 — Runbook obligatorio con 6 secciones 🟡

Generar `05_CICD/RUNBOOK.md` adaptado al proyecto (legible bajo presión, ≤1 página por sección):
1. Build falla en CI · 2. Deploy a PRE falla · 3. Deploy a PROD falla (incl. rollback manual) ·
4. App caída tras deploy verde · 5. Contactos y escalado (de `cicd.environments[].approvers` +
`organization.supportEmail`) · 6. Backups (ubicación, retención, restauración).
NUNCA dejarlo con placeholders sin rellenar.

## G12 — Anti-patterns de código que rompen el build (warning-only)

1. Paths absolutos en build configs (`vite.config`, etc.) — falla en CI silenciosamente.
2. `.csproj` con `HintPath` absoluto — no portable.
3. Credenciales reales en `appsettings.json` commiteado 🔴.
4. Tests con `localhost:puerto` hardcoded — usar `WebApplicationFactory`.
5. Env vars sin default en tests.
6. `TargetFramework` no instalado en el agente — coordinar antes de bumpear.
7. Tests contra BD/Redis reales 🔴 — Testcontainers para integración, mocks para unit.

## G13 — Idempotencia de `/cicd-init` (garantías) 🔴

Re-invocarlo en un proyecto con CI/CD existente no debe romper nada: detección de instalación
previa · backup automático del pipeline actual · diff visible · confirmación explícita ·
preservación de bloques `# CUSTOM:`…`# /CUSTOM` y de variables custom · preservación de la fase
de adopción · modo edición · re-registro idempotente (UPSERT) en el Hub si está habilitado.
Si una garantía falla, ABORTAR con mensaje claro.

## G14 — Smoke post-deploy: estricto para APIs, best-effort para SPAs 🟡

- **API .NET**: smoke estricto contra el endpoint de health local del destino; fallo → rollback (G9).
- **SPA estática**: smoke **best-effort** (warning + diagnóstico, sin fallar el job) — el smoke
  desde el propio servidor destino es frágil (hairpin NAT, SNI); el deploy real ya lo verificó
  la herramienta de publicación. NUNCA `throw` en smoke de SPA.

---

## Política para el LLM al editar pipelines

1. **NUNCA emitir** patrones marcados ❌/🔴. Si el usuario lo pide, RECHAZAR citando la regla y
   proponer la alternativa.
2. **AVISAR** en los 🟡 (validar empíricamente en la plataforma configurada).
3. **CITAR la regla** (G1-G14) en warnings y sugerencias.
4. **DETECTAR DRIFT**: si hay violaciones previas, proponer fix en el próximo cambio relacionado
   — NO refactorizar masivamente sin que lo pidan.
5. Con `cicd.variant` definido (ej. instancias on-premise antiguas), esperar limitaciones
   adicionales de la instancia: verificar features no estándar antes de emitirlas y documentar
   las limitaciones en un módulo de reglas propio de la organización.

---

*Regla condicional v1.0.0 (fork Ovillo) — invariantes portables derivados del runtime R1-R25 del
ecosistema origen (ADR-F002); plataforma e inventario de entornos en `ecosystem.config.cicd`.*
