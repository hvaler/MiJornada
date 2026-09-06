---
globs:
  - "src/**/Api/**/*.cs"
  - "**/Controllers/**/*.cs"
  - "**/*Controller.cs"
  - "**/Endpoints/**/*.cs"
  - "**/*Endpoint.cs"
  - "**/MinimalApi/**/*.cs"
---

# Reglas para APIs REST

> Este archivo aplica cuando Claude trabaja con controladores y endpoints API.
> **Detecta automáticamente** la versión de .NET del proyecto.

---

## DETECCIÓN DE VERSIÓN

```xml
<TargetFramework>net10.0</TargetFramework>  <!-- .NET 10 - OpenAPI nativo -->
<TargetFramework>net8.0</TargetFramework>   <!-- .NET 8 - Swashbuckle -->
<TargetFramework>net48</TargetFramework>    <!-- .NET 4.x - Web API 2 -->
```

---

## PARTE 1: CONTROLADORES POR VERSIÓN

### .NET 10 (Recomendado) - Controller con OpenAPI nativo

```csharp
/// <summary>
/// Gestión de scholarships
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public class ScholarshipsController : ControllerBase
{
    private readonly IScholarshipService _scholarshipService;
    private readonly ILogger<ScholarshipsController> _logger;

    public ScholarshipsController(IScholarshipService scholarshipService, ILogger<ScholarshipsController> logger)
    {
        _scholarshipService = scholarshipService;
        _logger = logger;
    }

    /// <summary>
    /// Obtiene todas las scholarships con paginación
    /// </summary>
    /// <param name="page">Número de página (1-based)</param>
    /// <param name="size">Elementos por página</param>
    /// <returns>Lista paginada de scholarships</returns>
    [HttpGet]
    [ProducesResponseType<PaginatedResult<ScholarshipDto>>(StatusCodes.Status200OK)]
    public async Task<ActionResult<PaginatedResult<ScholarshipDto>>> GetAll(
        [FromQuery] int page = 1,
        [FromQuery] int size = 10,
        CancellationToken ct = default)
    {
        var result = await _scholarshipService.GetPaginatedAsync(page, size, ct);
        return Ok(result);
    }

    /// <summary>
    /// Obtiene una scholarship por su ID
    /// </summary>
    [HttpGet("{id:int}")]
    [ProducesResponseType<ScholarshipDto>(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<ScholarshipDto>> GetById(int id, CancellationToken ct = default)
    {
        var scholarship = await _scholarshipService.GetByIdAsync(id, ct);
        
        if (scholarship is null)
        {
            return NotFound(new ProblemDetails
            {
                Title = "Scholarship not found",
                Detail = $"No scholarship exists with ID {id}",
                Status = StatusCodes.Status404NotFound
            });
        }
        
        return Ok(scholarship);
    }

    /// <summary>
    /// Crea una nueva scholarship
    /// </summary>
    [HttpPost]
    [Authorize(Roles = "Admin,Gestor")]
    [ProducesResponseType<ScholarshipDto>(StatusCodes.Status201Created)]
    [ProducesResponseType<ValidationProblemDetails>(StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<ScholarshipDto>> Create(
        [FromBody] CreateScholarshipRequest request,
        CancellationToken ct = default)
    {
        var scholarship = await _scholarshipService.CreateAsync(request, ct);
        
        _logger.LogInformation("Scholarship {ScholarshipId} creada por {User}", 
            scholarship.Id, User.Identity?.Name);
        
        return CreatedAtAction(nameof(GetById), new { id = scholarship.Id }, scholarship);
    }

    /// <summary>
    /// Actualiza una scholarship existente
    /// </summary>
    [HttpPut("{id:int}")]
    [Authorize(Roles = "Admin,Gestor")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> Update(
        int id,
        [FromBody] UpdateScholarshipRequest request,
        CancellationToken ct = default)
    {
        var exists = await _scholarshipService.ExistsAsync(id, ct);
        if (!exists)
        {
            return NotFound();
        }

        await _scholarshipService.UpdateAsync(id, request, ct);
        return NoContent();
    }

    /// <summary>
    /// Elimina una scholarship
    /// </summary>
    [HttpDelete("{id:int}")]
    [Authorize(Roles = "Admin")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> Delete(int id, CancellationToken ct = default)
    {
        var deleted = await _scholarshipService.DeleteAsync(id, ct);
        
        if (!deleted)
        {
            return NotFound();
        }

        _logger.LogInformation("Scholarship {ScholarshipId} eliminada por {User}", 
            id, User.Identity?.Name);
        
        return NoContent();
    }
}
```

### .NET 10 - Minimal APIs (Alternativa)

```csharp
// Program.cs - Minimal APIs .NET 10
app.MapGroup("/api/scholarships")
    .WithTags("Scholarships")
    .WithOpenApi()
    .MapScholarshipsEndpoints();

// ScholarshipsEndpoints.cs
public static class ScholarshipsEndpoints
{
    public static RouteGroupBuilder MapScholarshipsEndpoints(this RouteGroupBuilder group)
    {
        group.MapGet("/", GetAll)
            .WithName("GetAllScholarships")
            .WithSummary("Obtiene todas las scholarships")
            .Produces<PaginatedResult<ScholarshipDto>>();

        group.MapGet("/{id:int}", GetById)
            .WithName("GetScholarshipById")
            .Produces<ScholarshipDto>()
            .ProducesProblem(StatusCodes.Status404NotFound);

        group.MapPost("/", Create)
            .WithName("CreateScholarship")
            .RequireAuthorization("GestorPolicy")
            .Produces<ScholarshipDto>(StatusCodes.Status201Created)
            .ProducesValidationProblem();

        return group;
    }

    private static async Task<IResult> GetAll(
        IScholarshipService service,
        [AsParameters] PaginationRequest pagination,
        CancellationToken ct)
    {
        var result = await service.GetPaginatedAsync(pagination.Page, pagination.Size, ct);
        return Results.Ok(result);
    }

    private static async Task<IResult> GetById(
        int id,
        IScholarshipService service,
        CancellationToken ct)
    {
        var scholarship = await service.GetByIdAsync(id, ct);
        return scholarship is null 
            ? Results.NotFound() 
            : Results.Ok(scholarship);
    }

    private static async Task<IResult> Create(
        CreateScholarshipRequest request,
        IScholarshipService service,
        CancellationToken ct)
    {
        var scholarship = await service.CreateAsync(request, ct);
        return Results.CreatedAtRoute("GetScholarshipById", new { id = scholarship.Id }, scholarship);
    }
}
```

### .NET 8/9 (Migrar)

```csharp
// Similar a .NET 10 pero con Swashbuckle
// Diferencias para migración:
// - [SwaggerOperation] → Documentación XML nativa
// - app.UseSwagger() → app.MapOpenApi()
```

### .NET 4.x Web API 2 (Legacy)

```csharp
[RoutePrefix("api/scholarships")]
public class ScholarshipsController : ApiController
{
    private readonly IScholarshipService _scholarshipService;

    public ScholarshipsController(IScholarshipService scholarshipService)
    {
        _scholarshipService = scholarshipService;
    }

    [HttpGet]
    [Route("")]
    public IHttpActionResult GetAll()
    {
        var scholarships = _scholarshipService.GetAll();
        return Ok(scholarships);
    }

    [HttpGet]
    [Route("{id:int}")]
    public IHttpActionResult GetById(int id)
    {
        var scholarship = _scholarshipService.GetById(id);
        if (scholarship == null)
            return NotFound();
        return Ok(scholarship);
    }

    [HttpPost]
    [Route("")]
    [Authorize(Roles = "Admin")]
    public IHttpActionResult Create(CreateScholarshipRequest request)
    {
        if (!ModelState.IsValid)
            return BadRequest(ModelState);

        var scholarship = _scholarshipService.Create(request);
        return CreatedAtRoute("GetScholarshipById", new { id = scholarship.Id }, scholarship);
    }
}
```

---

## PARTE 2: OPENAPI / SWAGGER

### .NET 10 - OpenAPI Nativo

```csharp
// Program.cs
builder.Services.AddOpenApi(options =>
{
    options.AddDocumentTransformer((document, context, ct) =>
    {
        document.Info = new OpenApiInfo
        {
            Title = "API - Scholarship Management",
            Version = "v1",
            Description = "API para la gestión de scholarships universitarias",
            Contact = new OpenApiContact
            {
                Name = "Soporte",
                Email = "soporte@example.com" // organization.supportEmail (ecosystem.config)
            }
        };
        return Task.CompletedTask;
    });
    
    // Seguridad
    options.AddDocumentTransformer((document, context, ct) =>
    {
        document.Components ??= new OpenApiComponents();
        document.Components.SecuritySchemes["Bearer"] = new OpenApiSecurityScheme
        {
            Type = SecuritySchemeType.Http,
            Scheme = "bearer",
            BearerFormat = "JWT"
        };
        return Task.CompletedTask;
    });
});

// Mapear endpoints
app.MapOpenApi();                    // /openapi/v1.json
app.MapScalarApiReference();         // UI alternativa a Swagger UI
```

### .NET 8/9 - Swashbuckle (Migrar a OpenAPI)

```csharp
// Program.cs - A reemplazar
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo { Title = "Mi API", Version = "v1" });
});

app.UseSwagger();
app.UseSwaggerUI();
```

---

## PARTE 3: VALIDACIÓN

### FluentValidation (Todas las versiones modernas)

```csharp
public class CreateScholarshipRequestValidator : AbstractValidator<CreateScholarshipRequest>
{
    public CreateScholarshipRequestValidator()
    {
        RuleFor(x => x.Name)
            .NotEmpty().WithMessage("Name is required")
            .MaximumLength(200).WithMessage("Maximum 200 characters");

        RuleFor(x => x.Amount)
            .GreaterThan(0).WithMessage("Amount must be positive")
            .LessThanOrEqualTo(50000).WithMessage("Maximum amount is 50,000");

        RuleFor(x => x.StartDate)
            .GreaterThanOrEqualTo(DateTime.Today)
            .WithMessage("Start date must be in the future");

        RuleFor(x => x.EndDate)
            .GreaterThan(x => x.StartDate)
            .WithMessage("End date must be after start date");
    }
}

// Registro en Program.cs (.NET 10)
builder.Services.AddValidatorsFromAssemblyContaining<CreateScholarshipRequestValidator>();
builder.Services.AddFluentValidationAutoValidation();
```

---

## PARTE 4: MANEJO DE ERRORES

### Global Exception Handler (.NET 10)

```csharp
// Program.cs
app.UseExceptionHandler(errorApp =>
{
    errorApp.Run(async context =>
    {
        var exception = context.Features.Get<IExceptionHandlerFeature>()?.Error;
        var logger = context.RequestServices.GetRequiredService<ILogger<Program>>();
        
        logger.LogError(exception, "Error no controlado");

        var problemDetails = exception switch
        {
            ValidationException ve => new ValidationProblemDetails(
                ve.Errors.GroupBy(e => e.PropertyName)
                    .ToDictionary(g => g.Key, g => g.Select(e => e.ErrorMessage).ToArray()))
            {
                Status = StatusCodes.Status400BadRequest,
                Title = "Error de validación"
            },
            
            NotFoundException nf => new ProblemDetails
            {
                Status = StatusCodes.Status404NotFound,
                Title = "Recurso no encontrado",
                Detail = nf.Message
            },
            
            UnauthorizedAccessException => new ProblemDetails
            {
                Status = StatusCodes.Status403Forbidden,
                Title = "Acceso denegado"
            },
            
            _ => new ProblemDetails
            {
                Status = StatusCodes.Status500InternalServerError,
                Title = "Error interno del servidor",
                Detail = context.RequestServices
                    .GetRequiredService<IHostEnvironment>().IsDevelopment() 
                        ? exception?.Message 
                        : null
            }
        };

        context.Response.StatusCode = problemDetails.Status ?? 500;
        context.Response.ContentType = "application/problem+json";
        await context.Response.WriteAsJsonAsync(problemDetails);
    });
});
```

---

## PARTE 5: VERBOS HTTP

| Verbo | Uso | Respuesta exitosa |
|-------|-----|-------------------|
| **GET** | Obtener recursos | 200 OK |
| **POST** | Crear recurso | 201 Created + Location |
| **PUT** | Reemplazar recurso | 204 No Content |
| **PATCH** | Actualización parcial | 200 OK o 204 |
| **DELETE** | Eliminar recurso | 204 No Content |

---

## CHECKLIST

### Antes de cada endpoint
- [ ] Atributo de verbo HTTP correcto
- [ ] Ruta con restricciones de tipo (`{id:int}`)
- [ ] [Authorize] si requiere autenticación
- [ ] [ProducesResponseType] para documentación
- [ ] Validación de entrada
- [ ] CancellationToken en métodos async
- [ ] Logging de operaciones importantes

### .NET 10 específico
- [ ] OpenAPI nativo (no Swashbuckle)
- [ ] ProblemDetails para errores
- [ ] Minimal APIs donde sea apropiado

---

*Regla condicional v3.7.0 - Multi-versión .NET*
