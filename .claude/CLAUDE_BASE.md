# CLAUDE_BASE.md

> **Versión**: 1.0.0 (fork Ovillo — compacta, AUD-008)
> **Organización**: definida en `ecosystem.config.json` (raíz del proyecto). Sin ese archivo,
> aplican los **defaults neutrales** indicados en cada sección.

Estándares que Claude debe aplicar en **todos** los proyectos de la organización. Este archivo se
carga en cada sesión, por lo que conserva solo lo que debe estar **siempre en contexto**:

- **Ejemplos de código y detalle extendido** (DI, async, Serilog, errores, EF, testing AAA,
  git): `.claude/CLAUDE_BASE_EXTENDIDO.md` (leer bajo demanda).
- **Reglas condicionales por tipo de archivo** (`.claude/rules/*.md`: api, application,
  domain, infrastructure, tests, database, blazor, webapp, console): se cargan solas por glob.
- **Infraestructura y seguridad avanzada**: §14.

---

## 0. CONFIGURACIÓN DE ORGANIZACIÓN (ecosystem.config.json)

La identidad de la organización es **configuración, no código**. Precedencia al resolver
cualquier convención:

```
_hilo/ESTADO_PROYECTO.json   (proyecto)     ← gana siempre
ecosystem.config.json         (organización) ← raíz del proyecto; schema: .claude/schemas/
defaults neutrales            (este archivo)
```

Claves que usan estas reglas: `organization.namespacePrefix`, `organization.supportEmail`,
`identity.*` (IdP y roles), `cloud.*` (secretos/storage/telemetría), `database.*` (motor,
versión, naming SQL), `theme.*` (tokens de marca), `vcs.*` / `cicd.*` (branching y pipelines),
`workflow.taskTypes`. Validación: `node .claude/scripts/validate-config.js`.

**Regla para Claude**: si `ecosystem.config.json` no existe o no define una clave, usar el
default neutral — NUNCA fallar ni preguntar por su ausencia.

---

## 1. VERSIONES .NET SOPORTADAS

| Versión | Tipo | Soporte hasta | Recomendación |
|---------|------|---------------|---------------|
| **.NET 10** | LTS | Nov 2028 | ✅ **Usar para nuevos proyectos** |
| **.NET 9** | STS | **May 2026** | ⚠️ **Migrar a .NET 10 urgente** |
| **.NET 8** | LTS | **Nov 2026** | ⚠️ **Planificar migración a .NET 10** |
| **.NET 4.x** | Legacy | Mantenimiento | 📦 Mantener, migrar según prioridad |

```
NUEVOS PROYECTOS      → .NET 10 (obligatorio)
EVOLUTIVOS .NET 10    → Mantener en .NET 10
EVOLUTIVOS .NET 9     → Migrar a .NET 10 antes de trabajar
EVOLUTIVOS .NET 8     → Evaluar migración según size
EVOLUTIVOS .NET 4.x   → Mantener en 4.x (migración separada)
```

**Detectar la versión** antes de aplicar reglas: `<TargetFramework>` en el `.csproj`
(`net10.0` / `net9.0` / `net8.0` / `net48`).

---

## 2. NOMENCLATURA Y CONVENCIONES

**Namespaces**: `{prefix}.[Área].[Proyecto].[Capa]` — el `{prefix}` es
`organization.namespacePrefix` del `ecosystem.config` (default: `MyCompany`).
Ej. `MyCompany.HR.ScholarshipManagement.Domain`, `MyCompany.Academic.Enrollment.Api`.

| Tipo | Convención | Ejemplo |
|------|------------|---------|
| Entidad | Sustantivo singular | `Scholarship`, `Student` |
| Servicio | Sustantivo + Service | `ScholarshipService` |
| Repositorio | Sustantivo + Repository | `ScholarshipRepository` |
| Controlador | Sustantivo + Controller | `ScholarshipsController` |
| Validador | Nombre + Validator | `CreateScholarshipRequestValidator` |
| DTO / Request / Response | `ScholarshipDto` / `CreateScholarshipRequest` / `PaginatedResponse<T>` | |

**Variables** camelCase · **Métodos** PascalCase verbo+sustantivo · **async** sufijo `Async` ·
**booleanos** prefijo `Is/Has/Can` (en ingles; una organizacion puede anadir los suyos via convencion propia) · **campos privados** `_camelCase` ·
**interfaces** `IPrefijo`.

---

## 3. ESTRUCTURA DE PROYECTOS

**Nuevos (.NET 10) — Clean Architecture**: `src/{prefix}.MyApp.{Domain|Application|Infrastructure|Web}` + `tests/{prefix}.MyApp.{Domain|Application|Integration}.Tests`.

**Legacy (.NET 4.x)**: **respetar** la estructura existente (`.Web`/`.Business`/`.Data`/`.Entities`).
**No imponer Clean Architecture** en legacy.

---

## 7. SEGURIDAD

**Política de secretos (WARN-first, default del fork)**: los hooks defensivos **avisan pero no
bloquean** (exit 1) salvo que la organización eleve la política (`hooks.policy: "block"` o
`hooks.blockList` en `ecosystem.config`). Al detectar un secreto hardcoded: registrar `SEC-XXX`
en `_hilo/DEUDA_TECNICA.md` y migrar al servicio de secretos configurado cuando se pueda.

- ✅ User Secrets / `.env` en desarrollo · en producción, el servicio de `cloud.secrets`:
  `keyvault` (Azure Key Vault) · `secrets-manager` (AWS) · `gsm` (Google) · `dotenv` (default:
  variables de entorno gestionadas fuera del repo)
- ✅ Autenticación estándar: el IdP de `identity.idp` (`entra`, `auth0`, `keycloak`, `okta`,
  `oidc-generic`; default `none` = no asumir auth). Con `entra`: `AddMicrosoftIdentityWebApi`.
- ✅ Roles estándar: `identity.defaultRoles` (default `Admin`, `Manager`, `User`) + policies
  personalizadas

> Detalle (patrón WARN-first vs BLOCK, escalada, ejemplos por IdP):
> `CLAUDE_BASE_EXTENDIDO.md §7`.

---

## 8. BASE DE DATOS

### 8.1 SQL — motor y nomenclatura (OBLIGATORIO · aplica en archivos Y chat)

> **Esta sección siempre está en contexto** (CLAUDE.md siempre cargado) para que la nomenclatura
> se aplique también cuando Claude propone SPs en chat sin editar un archivo `.sql`.

#### Motor y versión: desde `ecosystem.config.database`

- **Motor** (`database.engine`): `sqlserver` (default) · `postgres` · `mysql` · `sqlite`.
  El proyecto puede sobrescribirlo en `_hilo/ESTADO_PROYECTO.json` (campo `baseDatos`).
- **Versión** (`database.version`): si la organización fija una versión (ej. SQL Server
  `"2017"`), aplicar **feature-gating**: no usar features posteriores a esa versión. La tabla
  de features por versión de SQL Server vive en `.claude/rules/database.md` (se carga sola al
  tocar `.sql`). Si `version` es `null` (default): sin gating, usar features actuales del motor.

#### Nomenclatura — patrón configurable (`database.naming`)

| Tipo | Patrón (default) | OK | KO |
|---|---|---|---|
| **Stored Procedure** | `{schema}.{Verb}{Entity}` (pegados, PascalCase) | `scholarships.GetNomination` | `usp_GetNomination`, `scholarships.Nomination_Get`, `sp_GetNomination` |
| **Función escalar** | `{schema}.fn_{Description}` | `scholarships.fn_CalculateRate` | `scholarships.CalculateRate` (falta prefijo) |
| **Función tabla (TVF)** | `{schema}.fnt_{Description}` | `scholarships.fnt_ScholarshipsByYear` | `scholarships.fn_ScholarshipsByYear` (usa `fn_`) |
| **Vista** | `{schema}.vw_{Description}` | `scholarships.vw_ActiveNominations` | `scholarships.View_Active`, `scholarships.Active` |
| **Trigger** | `{schema}.tr_{Table}_{Event}` | `academic.tr_Student_AfterInsert` | `academic.trg_Student` |
| **Índice** | `IX_{Table}_{Columns}` | `IX_Student_Email` | `idx1`, `index_email` |
| **Constraint PK/FK** | `PK_{Table}` / `FK_{Child}_{Parent}` | `PK_Student`, `FK_ScholarshipApplication_Student` | `PrimaryKey_1`, `FK_1` |

Los prefijos (`fn_`, `fnt_`, `vw_`, `tr_`) y el patrón de SP se leen de `database.naming`
(los de la tabla son los defaults neutrales).

#### Verbos para SPs

Si `database.naming.allowedVerbs` define una lista, usar SOLO esos verbos. Si está vacía
(default): cualquier verbo, siempre en forma `{Verb}{Entity}` PascalCase pegado.

#### Schemas

- Convención de casing: `database.naming.schemaCase` (default **lowercase**: `academic`,
  `finance`, `scholarships`).
- **Excepciones legacy** (`database.naming.legacySchemas`, default vacío): schemas históricos
  que se mantienen tal cual, NO normalizar.
- **Nombres sin schema prohibidos**: siempre prefijar, incluso en `dbo` (`dbo.Insert…`).

#### Prohibido (configurable)

- **Prefijos** (`naming.forbiddenPrefixes`, default): `usp_`, `sp_`, `pr_`, `proc_`, `pa_`.
- **Sufijos** (`naming.forbiddenSuffixes`, default vacío; ejemplo de organización: `_Listar`,
  `_Guardar`, `_L`, `_G`).
- **Separador `_` entre verbo y sustantivo**: `GetNomination`, no `Get_Nomination`.
- **Funciones sin prefijo**: `fn_` para escalares, `fnt_` para tabla.

#### Excepciones — código legacy

Si se toca código migrado que ya tiene convención vieja, **mantener los nombres existentes**.
NO renombrar en el mismo commit donde se toca la lógica — provoca conflictos en `sqlproj` y
referencias cruzadas. Marcadores del modo "legacy respetar":

- El archivo está en `Legacy/`, `Obsoleto/`, `MigracionPendiente/`.
- Comentario `-- LEGACY: no renombrar` al inicio del archivo.
- El nombre actual empieza por un prefijo prohibido (asumir código migrado).
- La ruta está en el baseline (`database.naming.legacyBaselineFile`, default
  `.claude/sql-legacy-baseline.txt`).

> ⚠️ **TRAMPA — BD cross-schema con SPs legacy mayoritarios**
>
> La regla "respetar legacy" **SOLO aplica al MODIFICAR SPs existentes**. Al crear un SP
> **nuevo** en una BD llena de SPs con patrón antiguo (ej. `int_ListaDegrees_leer`),
> **NO replicar ese patrón**: los SPs nuevos siempre siguen §8.1, incluso siendo el único
> moderno en su BD. El sesgo de imitación visual ("toda la BD usa `int_*_leer`, el mío también
> por coherencia") es razonamiento defectuoso: la coherencia se logra **migrando los legacy
> progresivamente**, no clonando el patrón viejo.
>
> **Antes de cualquier `CREATE PROCEDURE [schema].[Nombre]` en archivo nuevo:** verificar la
> tabla §8.1. NO inferir nomenclatura por archivos vecinos. El hook de nomenclatura SQL detecta
> esta trampa con los prefijos de `database.naming.legacyPrefixes` (ej. `int_`, `aud_`, `tmp_`,
> `migr_`).

#### Baseline legacy

Para proyectos con mucho SQL preexistente que incumple la convención, generar un **baseline**
(una ruta relativa por línea, forward-slashes) que el hook de nomenclatura respetará.
Generación: `node .claude/hooks/sql-baseline-generate.js` (`--dry-run` para previsualizar).
Archivos en baseline se editan sin bloqueo (nota no bloqueante); archivos NUEVOS o fuera del
baseline siguen sujetos a la convención estricta. Commitear el baseline al repo.

#### Plantilla mínima de SP correcta (SQL Server)

```sql
-- =============================================
-- Author:           {team}
-- Created:  YYYY-MM-DD
-- Description:     {what it does}
-- Engine:           {database.engine} {database.version}
-- =============================================
CREATE OR ALTER PROCEDURE [scholarships].[GetNomination]
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT Id, StudentId, Status, CreatedAt
    FROM scholarships.Nomination
    WHERE Id = @Id;
END
GO
```

### 8.2+ Entity Framework

EF Core 10 en nuevos (retry-on-failure, SplitQuery, AsNoTracking, proyecciones, paginación);
EF 6 en legacy (mantener patrones). Snippets: `CLAUDE_BASE_EXTENDIDO.md §8` y regla
`.claude/rules/infrastructure.md` (auto-carga por glob).

---

## 9. TESTING

**xUnit + FluentAssertions 6.x (fijar — v8+ comercial) + Moq + Testcontainers.**
Nomenclatura `Method_Scenario_ExpectedResult`, patrón AAA.
Cobertura mínima: Domain 90% · Application 80% · Infrastructure 60%.
Detalle: `CLAUDE_BASE_EXTENDIDO.md §9` y `.claude/rules/tests.md`.

---

## 11. GIT Y COMMITS

**Conventional Commits**: `tipo(ámbito): descripción` — tipos `feat|fix|docs|style|refactor|test|chore`.
**Ramas**: la nomenclatura y rama base se leen de `configuracion.branching` en
`_hilo/ESTADO_PROYECTO.json`; el default de organización es `vcs.branchingStrategy` +
`vcs.branchNamingConvention` del `ecosystem.config` (semántica `feature/XXX-desc` por defecto;
temporal `yyyyMMdd-{tipo}-{codigo}-desc` en developer-branch). Detalle:
`CLAUDE_BASE_EXTENDIDO.md §11`.

---

## 12. CONSIDERACIONES ESPECIALES — proyectos .NET 4.x

1. **Respetar arquitectura existente** — no imponer Clean Architecture
2. **Mantener patrones del proyecto**
3. **No introducir dependencias incompatibles**
4. **Entity Framework 6** — no usar EF Core
5. **Web.config** — no usar appsettings.json

Migración a .NET 10 (por capas, tests de regresión): `CLAUDE_BASE_EXTENDIDO.md §12`.

---

## 13. CONTACTO

Soporte del ecosistema: `organization.supportEmail` del `ecosystem.config` (si está vacío,
omitir referencias de contacto en docs generadas).

---

## 14. REFERENCIAS A DOCUMENTACIÓN COMPLEMENTARIA

Este documento define **cómo escribir código**. Para **infraestructura, seguridad avanzada y
entorno de desarrollo**, consultar **`Documentos_Base/01_Estructura_Tecnica/ESTRUCTURA_TECNICA.md`**:

| Sección | Tema | Cuándo consultar |
|---------|------|------------------|
| **3. Seguridad** | OWASP Top 10, checklist obligatorio | Código que maneje datos |
| **3.2** | Servicio de secretos (`cloud.secrets`) | Cualquier secreto o credencial |
| **3.4** | Validación de inputs (FluentValidation) | Cualquier entrada de usuario |
| **4. Infraestructura Balanceada** | Principio "sin estado local" | Diseño de cualquier servicio |
| **4.2** | Storage configurado (`cloud.storage`) — en infra balanceada NUNCA disco local/wwwroot/uploads | Almacenamiento de archivos |
| **4.3** | Caché distribuida (Redis) — en infra balanceada NUNCA MemoryCache/Session en memoria | Caché, sesiones |
| **5. Proyectos Legacy** | WebForms, Web.config, hardening | Proyectos .NET 4.x |
| **6. Docker Compose** | BD, Redis, emuladores, Mailhog | Entorno de desarrollo |
| **10. Telemetría** (`cloud.telemetry`) | NUNCA loguear contraseñas/tokens/documentos de identidad/emails | Telemetría avanzada |

**Otras referencias**: `.claude/rules/*.md` (reglas por tipo de archivo) ·
`_hilo/ESTADO_PROYECTO.json` + `_hilo/ESTADO_PROYECTO.schema.md` (estado y schema) ·
`_hilo/DEPENDENCIAS.md` · `Documentos_Base/05_Plantillas_SQL/` ·
`Documentos_Base/01_Estructura_Tecnica/GUIA_ARQUITECTURA.md` (perfiles + Mediator vs MediatR).

---

*Base de estándares para todos los proyectos. Ejemplos extendidos en CLAUDE_BASE_EXTENDIDO.md;
las reglas condicionales en `.claude/rules/` complementan por tipo de archivo. La identidad de
la organización vive en `ecosystem.config.json` (ADR-F001).*
