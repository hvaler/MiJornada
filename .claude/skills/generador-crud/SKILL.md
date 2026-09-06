---
name: generador-crud
description: >
  Generates complete CRUD operations following the organization coding standards:
  Controller, Service, Repository, DTOs, Validators, and Entity configurations.
  Supports both traditional Controllers and Minimal API endpoints.
  USE FOR: creating CRUD operations, generating controllers/services/repositories,
  scaffolding entities, standardizing existing CRUD to the ecosystem patterns,
  crear CRUD, generar controlador, crear entidad.
  DO NOT USE FOR: security audits (use security-audit),
  architecture analysis (use analisis-arquitectura),
  test generation (use testing-patterns).
---

# Generador CRUD - Plantillas de Código

Este skill genera código CRUD completo siguiendo los estándares de la organización.

---

## Cuándo Usar Este Skill

1. **Nueva entidad** - Crear todas las capas para una nueva entidad
2. **API endpoints** - Generar Controller + Service + Repository
3. **Refactorizar** - Estandarizar CRUD existente al patrón del ecosistema

---

## Estructura Generada

```
src/
├── Domain/
│   └── Entities/
│       └── {Entity}.cs
├── Application/
│   ├── DTOs/
│   │   ├── {Entity}Dto.cs
│   │   ├── Create{Entity}Request.cs
│   │   └── Update{Entity}Request.cs
│   ├── Validators/
│   │   ├── Create{Entity}RequestValidator.cs
│   │   └── Update{Entity}RequestValidator.cs
│   └── Services/
│       ├── I{Entity}Service.cs
│       └── {Entity}Service.cs
├── Infrastructure/
│   └── Repositories/
│       ├── I{Entity}Repository.cs
│       └── {Entity}Repository.cs
└── Web/
    └── Controllers/
        └── {Entity}sController.cs
```

---

## Plantillas Disponibles

| Archivo | Descripción |
|---------|-------------|
| `templates/Entity.cs.template` | Entidad de dominio base |
| `templates/Controller.cs.template` | Controlador API REST |
| `templates/Service.cs.template` | Servicio de aplicación |
| `templates/Repository.cs.template` | Repositorio EF Core |
| `templates/Dto.cs.template` | DTOs (Response, Create, Update) |
| `templates/Validator.cs.template` | Validadores FluentValidation |
| `templates/Configuration.cs.template` | Configuración EF Core Fluent API |

---

## Uso Rápido

### Solicitar un CRUD

```
"Crea un CRUD completo para la entidad Scholarship con los campos:
- Id (int, PK)
- Nombre (string, 200 chars, requerido)
- Description (string, opcional)
- Amount (decimal, requerido, > 0)
- Estado (enum: Draft, Published, Closed)
- CreatedAt (datetime)"
```

### Claude generará:

1. **Entidad** con validaciones de dominio
2. **DTOs** con mapeo AutoMapper
3. **Validadores** FluentValidation
4. **Servicio** con operaciones CRUD
5. **Repositorio** optimizado
6. **Controller** con documentación OpenAPI
7. **Configuración** EF Core

---

## Patrones Aplicados

### Controller

```csharp
[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public class ScholarshipsController : ControllerBase
{
    [HttpGet]
    [ProducesResponseType<PaginatedResult<ScholarshipDto>>(200)]
    public async Task<ActionResult<PaginatedResult<ScholarshipDto>>> GetAll(...)

    [HttpGet("{id:int}")]
    [ProducesResponseType<ScholarshipDto>(200)]
    [ProducesResponseType(404)]
    public async Task<ActionResult<ScholarshipDto>> GetById(int id, ...)

    [HttpPost]
    [ProducesResponseType<ScholarshipDto>(201)]
    [ProducesResponseType<ValidationProblemDetails>(400)]
    public async Task<ActionResult<ScholarshipDto>> Create(...)

    [HttpPut("{id:int}")]
    [ProducesResponseType(204)]
    [ProducesResponseType(404)]
    public async Task<IActionResult> Update(int id, ...)

    [HttpDelete("{id:int}")]
    [ProducesResponseType(204)]
    [ProducesResponseType(404)]
    public async Task<IActionResult> Delete(int id, ...)
}
```

### Service Interface

```csharp
public interface IScholarshipService
{
    Task<ScholarshipDto?> GetByIdAsync(int id, CancellationToken ct = default);
    Task<PaginatedResult<ScholarshipDto>> GetPaginatedAsync(int page, int size, CancellationToken ct = default);
    Task<ScholarshipDto> CreateAsync(CreateScholarshipRequest request, CancellationToken ct = default);
    Task UpdateAsync(int id, UpdateScholarshipRequest request, CancellationToken ct = default);
    Task<bool> DeleteAsync(int id, CancellationToken ct = default);
    Task<bool> ExistsAsync(int id, CancellationToken ct = default);
}
```

---

## Validaciones Estándar

| Campo | Validación |
|-------|------------|
| Strings requeridos | NotEmpty, MaxLength |
| Strings opcionales | MaxLength |
| Números positivos | GreaterThan(0) |
| Fechas futuras | GreaterThanOrEqualTo(Today) |
| Enums | IsInEnum |
| Emails | EmailAddress |
| Unicidad | MustAsync + repository check |

---

## Checklist Post-Generación

- [ ] Revisar entidad de dominio
- [ ] Verificar validaciones de negocio
- [ ] Registrar servicios en DI
- [ ] Añadir configuración EF Core
- [ ] Crear migración si es necesario
- [ ] Añadir tests unitarios

---

*Skill generador-crud v3.7.0*
