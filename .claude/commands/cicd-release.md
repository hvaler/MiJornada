# /cicd-release — Versionar y disparar el build de una release

> Crea un tag semver, lo empuja y **dispara el Build** del pipeline de esa versión. **NO despliega** — el deploy es un paso aparte on-demand (`/cicd-deploy`).
>
> Audiencia: desarrolladores con pipeline (Fase 1 o 2) generado por `/cicd-init`.
> Plataforma: Azure DevOps Server 2020 on-premise (`devops.example.org`).

---

## Extended Thinking Mode

**think hard**

`release` ≠ `deploy`. Liberar una versión = marcar un punto semver y construirlo (artefacto reproducible). Desplegarlo a un entorno es una decisión posterior y on-demand. Este comando NUNCA despliega por defecto — solo versiona + dispara el Build. Así "liberar" no acopla con "distribuir".

> Nota: este comando NO usa `/publicar` (que es del Constructor Ovillo, publica la plantilla del ecosistema). En un proyecto consumidor, "publicar el artefacto" lo hace el propio pipeline (stage Build → `dotnet publish` / `ArchiveFiles@2` → artefacto `drop`).

---

## Sintaxis

```
/cicd-release [--major | --minor | --patch | --version X.Y.Z] [--deploy <dev|pre|pro>] [--no-push] [--dry-run]
```

| Flag | Descripción |
|---|---|
| `--patch` | **Default**. Incrementa Z (vX.Y.Z → vX.Y.Z+1). |
| `--minor` | Incrementa Y, resetea Z. |
| `--major` | Incrementa X, resetea Y.Z. |
| `--version X.Y.Z` | Fuerza una versión concreta. |
| `--deploy <env>` | Opcional. **Atajo**: tras el release, encola `/cicd-deploy --env <env> --tag vX.Y.Z`. NUNCA es el comportamiento por defecto. |
| `--no-push` | Crea el tag local pero NO lo empuja (no dispara el build). Para revisar antes. |
| `--dry-run` | Muestra el tag/commit que crearía sin ejecutar. |

---

## CUÁNDO USAR

- Cuando una funcionalidad/fix está lista en la rama base y quieres **marcar una versión** y construirla.
- Como paso previo a un deploy on-demand (`/cicd-release` → luego `/cicd-deploy`).

**NO usar para**:
- Desplegar a un entorno → `/cicd-deploy` (release NO despliega).
- Generar el pipeline → `/cicd-init`.
- Publicar la plantilla Ovillo (eso es `/publicar`, comando del Constructor, no de consumidor).

---

## FASE 0 — Validaciones previas

### 0.1 Leer config

`_hilo/ESTADO_PROYECTO.json`: `configuracion.branching.ramaBase`, `infraestructura.cicd[]` (pipeline activo), `version_actual`.

### 0.2 Estado del repo (BLOQUEANTE)

- Working tree **limpio** (`git status --short` vacío). Si hay cambios sin commitear → abortar con mensaje.
- Estar en la **rama base** (`ramaBase`, típicamente `main`). Si no, avisar y pedir confirmación.

### 0.3 Calcular siguiente semver

- Leer el último tag: `git describe --tags --abbrev=0 --match 'v*'` (o `v0.0.0` si no hay ninguno).
- Aplicar el bump (`--patch` por defecto). Validar formato `vX.Y.Z`.
- Si `--version`, validar que es estrictamente mayor que el último tag.

### 0.4 (Opcional, recomendado) verificar build verde

Si el pipeline está registrado, consultar el último Build de la rama base. Si está **rojo**, advertir: *"El último build de `<rama>` está en `failed`. ¿Liberar de todas formas? (S/N)"*. No bloquea, pero avisa.

---

## FASE 1 — Crear tag y (opcional) commit de versión

1. Si el proyecto tiene archivos de versión (`*.csproj` con `<Version>`, `package.json`, `_hilo/VERSION.json`), bumpearlos a `X.Y.Z` y crear un commit `chore(release): vX.Y.Z`.
2. Crear **tag anotado**:

```bash
git tag -a vX.Y.Z -m "Release vX.Y.Z"
```

Con `--dry-run`: mostrar el tag y el commit que se crearían, sin ejecutar.

---

## FASE 2 — Push (dispara el Build)

> Salvo `--no-push`.

```bash
git push origin <ramaBase>           # si hubo commit de versión
git push origin vX.Y.Z               # el tag
```

El push a la rama base **dispara el trigger CI → stage Build** (compila + test + publica artefacto `drop`). **Los stages de deploy NO corren** (la variable `DeployEnv` está vacía en un push normal — modelo on-demand R20).

Confirmar al usuario que el build se disparó (mostrar link a la run si se puede resolver vía REST).

---

## FASE 3 — Cierre

```
✅ Release vX.Y.Z

   Tag creado y empujado → Build disparado.
   Artefacto en construcción (stage Build del pipeline).

   El deploy NO es automático. Para desplegar esta versión:
     /cicd-deploy --env dev --tag vX.Y.Z      (Dev)
     /cicd-deploy --env pre --tag vX.Y.Z      (Pre, con confirmación)
```

Actualizar `_hilo/ESTADO_PROYECTO.json.estado.version_actual = X.Y.Z`.

Si se pasó `--deploy <env>`: tras confirmar que el Build terminó verde, invocar el flujo de `/cicd-deploy --env <env> --tag vX.Y.Z` (con su confirmación para pre/pro). Esto es un atajo explícito, nunca el default.

---

## REGLAS CRÍTICAS

- **NUNCA** desplegar por defecto — `release` solo versiona + dispara build. El deploy es `/cicd-deploy`.
- **NUNCA** liberar con working tree sucio o fuera de la rama base sin confirmar.
- **SIEMPRE** tag anotado (`-a`), nunca lightweight.
- **NO** usar `/publicar` aquí (es del Constructor, no del consumidor).
- El build sí corre en push (build ≠ deploy); el deploy queda on-demand (R20).

---

## TROUBLESHOOTING

| Síntoma | Causa | Fix |
|---|---|---|
| `working tree no limpio` | Cambios sin commitear | Commitear o `git stash` antes de liberar |
| Tag ya existe | Versión repetida | Elegir siguiente semver o borrar el tag local mal creado |
| Build no se dispara tras push | Path filters TFS 2020 (R7) | Verificar trigger.paths con doble patrón `**` y `**/*` |
| `--deploy` no despliega | Build aún no verde | Esperar a que el Build termine; luego `/cicd-deploy` |

---

*Comando plantilla Ovillo v3.11.0 — release = tag semver + trigger build (sin deploy). Rescata `/release` del ADR-025 con semántica corregida (sin `/publicar`), formalizado en ADR-042.*
