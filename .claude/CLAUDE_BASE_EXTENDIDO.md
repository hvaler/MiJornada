# CLAUDE_BASE_EXTENDIDO.md

> **Proposito**: ejemplos de codigo y detalle extendido de los estandares de la organizacion.
> Este archivo **NO se importa en CLAUDE.md** (no consume contexto en cada sesion) — es el
> complemento de `.claude/CLAUDE_BASE.md`, que conserva las reglas siempre-en-contexto
> (§8.1 SQL, versiones .NET, nomenclatura) y apunta aqui para el detalle.
> Ademas, gran parte de estos patrones ya vive en las reglas condicionales por glob
> (`.claude/rules/api.md`, `application.md`, `domain.md`, `infrastructure.md`, `tests.md`),
> que se cargan solas al tocar los archivos correspondientes.
> Origen: dieta de contexto AUD-008.

---

## 4. PATRONES DE CÓDIGO

### Inyección de Dependencias

```csharp
// ✅ CORRECTO - Constructor injection
public class ScholarshipService : IScholarshipService
{
    private readonly IScholarshipRepository _repository;
    private readonly ILogger<ScholarshipService> _logger;

    public ScholarshipService(IScholarshipRepository repository, ILogger<ScholarshipService> logger)
    {
        _repository = repository;
        _logger = logger;
    }
}

// ❌ INCORRECTO - new directo
public class ScholarshipService
{
    private readonly ScholarshipRepository _repository = new ScholarshipRepository();
}
```

### Async/Await

```csharp
// ✅ CORRECTO - Async completo con CancellationToken
public async Task<ScholarshipDto?> GetByIdAsync(int id, CancellationToken ct = default)
{
    var scholarship = await _repository.GetByIdAsync(id, ct);
    return scholarship is null ? null : MapToDto(scholarship);
}

// ❌ INCORRECTO - .Result bloquea el hilo
public ScholarshipDto? GetById(int id)
{
    var scholarship = _repository.GetByIdAsync(id).Result; // ❌ Bloqueante
    return MapToDto(scholarship);
}
```

### Null Safety (C# 13 / .NET 10)

```csharp
// ✅ Nullable reference types
public async Task<ScholarshipDto?> GetByIdAsync(int id, CancellationToken ct)
{
    var scholarship = await _repository.GetByIdAsync(id, ct);
    return scholarship?.MapToDto();
}

// ✅ Pattern matching
if (scholarship is not null) { /* usar scholarship */ }

// ✅ Null coalescing
var name = scholarship?.Name ?? "Sin name";
```

---

## 5. LOGGING (Serilog)

```csharp
// Configuración en Program.cs (.NET 10)
builder.Host.UseSerilog((context, config) =>
    config.ReadFrom.Configuration(context.Configuration));

// Uso estructurado
_logger.LogInformation("Scholarship {ScholarshipId} creada por {User}", scholarship.Id, user);
_logger.LogWarning("Intento de acceso denegado a scholarship {ScholarshipId}", scholarshipId);
_logger.LogError(ex, "Error al procesar scholarship {ScholarshipId}", scholarshipId);
```

### Niveles de Log

| Nivel | Uso |
|-------|-----|
| **Debug** | Desarrollo, detalle técnico |
| **Information** | Operaciones normales importantes |
| **Warning** | Situaciones anómalas no críticas |
| **Error** | Errores que requieren atención |
| **Fatal** | Errores que impiden funcionamiento |

---

## 6. MANEJO DE ERRORES

### Excepciones Personalizadas

```csharp
// Jerarquía de excepciones de la aplicación
public class AppException : Exception { ... }
public class DomainException : AppException { ... }
public class NotFoundException : AppException { ... }
public class ValidationException : AppException { ... }
public class BusinessRuleException : AppException { ... }
```

### ProblemDetails (APIs .NET 10) — RFC 7807

```json
{
    "type": "https://example.org/errors/not-found",
    "title": "Recurso no encontrado",
    "status": 404,
    "detail": "No existe una scholarship con ID 123",
    "instance": "/api/scholarships/123"
}
```

---

## 7. SEGURIDAD — detalle de la política de secretos

**Default del fork: WARN-first.** Muchas organizaciones brownfield tienen secrets hardcoded en
`appsettings.json` commiteados — es **deuda técnica conocida** que se migra progresivamente al
servicio de secretos configurado (`cloud.secrets` del `ecosystem.config`). La política se eleva
con `hooks.policy: "block"` o por hook en `hooks.blockList` cuando la organización lo mandate.

### Patrón WARN-first vs BLOCK (cuándo aplicarlo)

| Caso | Política recomendada |
|---|---|
| Defecto crítico, daño irreversible (force push, DROP TABLE) | **BLOCK** (exit 2) — `bash-guard` |
| Convención que aún tiene deuda legacy masiva | **WARN-first** (exit 1) — `secret-scanner`, guard de nomenclatura SQL |
| Convención nueva sin deuda | **BLOCK** (exit 2) directamente |

**Regla**: un hook nunca debe romper trabajo legítimo de mantenimiento si la "violación" ya
existe en git history y no hay política organizacional que lo mandate. La defensa correcta es
**visibilidad** (warning visible en cada Edit), no **fricción**.

**Escalada de `secret-scanner` a BLOCK**: solo cuando la organización anuncie política oficial
"servicio de secretos obligatorio en todos los proyectos de producción" (vía `hooks.blockList`).

### Migración progresiva al servicio de secretos

1. Los warnings NO bloquean trabajo — editar normal.
2. Documentar en `_hilo/DEUDA_TECNICA.md` entradas `SEC-XXX: secretos en appsettings`.
3. Migrar cuando se pueda: la skill de configuración cloud tiene templates por proveedor
   (`cloud.secrets`: keyvault / secrets-manager / gsm / dotenv).
4. Sin deadline forzado — la organización anuncia cuándo entra enforcement.

### Buenas prácticas

```csharp
// ❌ Anti-patrón (genera AVISO, no bloquea)
var connectionString = "Server=prod;Password=123456";

// ✅ Desarrollo - User Secrets
// dotnet user-secrets set "ConnectionStrings:Default" "Server=..."

// ✅ Producción - servicio de secretos configurado (ejemplo: Azure Key Vault)
builder.Configuration.AddAzureKeyVault(...);
```

### Autenticación y Autorización

Según `identity.idp` del `ecosystem.config` (default `none` = no asumir auth). Ejemplo con
`entra` (Azure AD / Microsoft Entra ID):

```csharp
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddMicrosoftIdentityWebApi(builder.Configuration.GetSection("AzureAd"));
```

Para `keycloak` / `auth0` / `okta` / `oidc-generic`: `AddJwtBearer` con `Authority` =
`identity.authority` y validación estándar OIDC de issuer/audience.

```csharp
// Roles estándar: identity.defaultRoles (default Admin / Manager / User)
[Authorize(Roles = "Admin")]             // Administradores
[Authorize(Roles = "Manager")]           // Gestores funcionales
[Authorize(Roles = "User")]              // Users normales
[Authorize(Policy = "RequireManager")]   // Políticas personalizadas
```

---

## 8.2-8.4 ENTITY FRAMEWORK

### EF Core 10 (proyectos nuevos)

```csharp
builder.Services.AddDbContext<ApplicationDbContext>(options =>
    options.UseSqlServer(connectionString, sqlOptions =>
    {
        sqlOptions.EnableRetryOnFailure(3);
        sqlOptions.CommandTimeout(30);
        sqlOptions.UseQuerySplittingBehavior(QuerySplittingBehavior.SplitQuery);
    }));
// Con other motor (database.engine): UseNpgsql / UseMySql / UseSqlite equivalentes.
```

### EF 6 (legacy) — mantener patrones existentes

```csharp
public class MiDbContext : DbContext
{
    public MiDbContext() : base("name=DefaultConnection") { }
}
```

### Consultas optimizadas

```csharp
// ✅ Proyección - solo lo necesario
var dtos = await _context.Scholarships
    .Where(b => b.Status == ScholarshipStatus.Published)
    .Select(b => new ScholarshipDto { Id = b.Id, Name = b.Name })
    .ToListAsync(ct);

// ✅ AsNoTracking para lecturas
var scholarships = await _context.Scholarships.AsNoTracking().ToListAsync(ct);

// ✅ Paginación
var page = await _context.Scholarships
    .Skip((pageNumber - 1) * pageSize).Take(pageSize).ToListAsync(ct);
```

> Detalle completo (DbContext, repositorios, migraciones): `.claude/rules/infrastructure.md`
> (se carga sola al tocar `**/Infrastructure/**`, `**/*Repository.cs`, etc.).

---

## 9. TESTING — detalle

### Framework estándar

```xml
<PackageReference Include="xunit" Version="2.*" />
<PackageReference Include="FluentAssertions" Version="6.*" />
<PackageReference Include="Moq" Version="4.*" />
<PackageReference Include="Testcontainers.MsSql" Version="3.*" />
```

> ⚠️ FluentAssertions **fijar 6.x** — v8+ es licencia comercial (misma trampa que MediatR).
> Testcontainers: usar la imagen del motor configurado (`Testcontainers.MsSql` /
> `Testcontainers.PostgreSql` / `Testcontainers.MySql`).

### Nomenclatura

```
Method_Scenario_ExpectedResult

GetById_ScholarshipExists_ReturnsScholarship
GetById_ScholarshipDoesNotExist_ReturnsNull
Create_EmptyName_ThrowsValidationException
```

### Cobertura mínima

| Capa | Mínimo |
|------|--------|
| Domain | 90% |
| Application | 80% |
| Infrastructure | 60% |

> Patrones AAA, mocking y tests de integración: `.claude/rules/tests.md` (se carga sola al
> tocar `**/*Tests.cs`).

---

## 10. DOCUMENTACIÓN

### Comentarios XML (APIs públicas)

```csharp
/// <summary>
/// Obtiene una scholarship por su identificador.
/// </summary>
/// <param name="id">Identificador único de la scholarship.</param>
/// <param name="ct">Token de cancelación.</param>
/// <returns>La scholarship si existe, null en caso contrario.</returns>
/// <exception cref="ArgumentException">Si el id es menor o igual a 0.</exception>
public async Task<ScholarshipDto?> GetByIdAsync(int id, CancellationToken ct = default)
```

### README de proyecto

Todo proyecto debe tener README.md con: descripción, requisitos previos, instalación,
configuración necesaria y cómo ejecutar tests.

---

## 11. GIT Y COMMITS — detalle

### Conventional Commits

```
tipo(ámbito): descripción corta

Tipos: feat | fix | docs | style | refactor | test | chore

feat(scholarships): añadir filter por estado
fix(applications): corregir validación de fecha
docs(readme): actualizar instrucciones de instalación
```

### Ramas

> La nomenclatura y rama base se leen de `configuracion.branching` en
> `_hilo/ESTADO_PROYECTO.json` (ver `_hilo/ESTADO_PROYECTO.schema.md#branching`); el default
> de organización es `vcs.*` del `ecosystem.config`.

**Nomenclatura semántica** (default):
```
main              ← Producción
develop           ← Desarrollo (solo GitFlow)
feature/XXX-desc  ← Nuevas funcionalidades
bugfix/XXX-desc   ← Correcciones
hotfix/XXX-desc   ← Urgentes en producción
```

**Nomenclatura temporal** (developer-branch y otros; tipos de `workflow.taskTypes`, default EV/DT):
```
dev.{usuario}               ← Rama personal remota
yyyyMMdd-DT-nnn-desc        ← Deuda técnica (local)
yyyyMMdd-EV-nnn-desc        ← Evolutivo (local)
yyyyMMdd-BUG-nnn-desc       ← Corrección (local)
```

**Rama base configurable**: `main`, `master`, `develop`, `dev.{usuario}` — según
`configuracion.branching.ramaBase`.

---

## 12. CONSIDERACIONES ESPECIALES — detalle

### Migración a .NET 10

1. **Analizar dependencias** — verificar compatibilidad con .NET 10
2. **Migrar por capas** — Domain → Application → Infrastructure → Web
3. **Tests de regresión** — antes y después de cada capa
4. **No cambiar comportamiento** — solo migrar, no mejorar simultáneamente

---

*Complemento de CLAUDE_BASE.md — consultar bajo demanda, no se importa.*
