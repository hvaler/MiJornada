# Pattern: API Versioning

> **Pattern**: API Versioning
> **Problema**: Evolución de APIs sin romper clientes existentes
> **Solución**: Versionado URL, Header o Query String

---

## 🎯 Problema

APIs evolucionan con el tiempo:
- **Breaking changes** (campos eliminados, tipos cambiados)
- **Nuevos endpoints** (funcionalidad adicional)
- **Deprecación** (endpoints obsoletos)

```csharp
// ❌ Sin versionado - rompe clientes existentes
// v1: GET /api/students → { "name": "John", "age": 20 }
// v2: GET /api/students → { "fullName": "John Doe", "birthDate": "2005-01-01" }
// ❌ Los clientes v1 se rompen porque "name" ya no existe
```

---

## ✅ Solución: API Versioning

### Estrategias de Versionado

| Estrategia | Ejemplo | Ventajas | Desventajas |
|------------|---------|----------|-------------|
| **URL** | `/api/v1/students` | Clara, cacheable | Duplica rutas |
| **Header** | `X-API-Version: 1` | URLs limpias | Menos visible |
| **Query String** | `/api/students?v=1` | Simple | Mezcla semántica |
| **Media Type** | `Accept: application/vnd.api+json;version=1` | RESTful puro | Complejo |

---

## 1. URL Versioning (Recomendado)

### Configuración en Program.cs

```csharp
using Asp.Versioning;

builder.Services.AddApiVersioning(options =>
{
    options.DefaultApiVersion = new ApiVersion(1, 0);
    options.AssumeDefaultVersionWhenUnspecified = true;
    options.ReportApiVersions = true; // Header con versiones soportadas
    options.ApiVersionReader = new UrlSegmentApiVersionReader();
})
.AddApiExplorer(options =>
{
    options.GroupNameFormat = "'v'VVV"; // v1, v2, v3...
    options.SubstituteApiVersionInUrl = true;
});
```

### Controller v1

```csharp
[ApiController]
[Route("api/v{version:apiVersion}/[controller]")]
[ApiVersion("1.0")]
public class StudentsV1Controller : ControllerBase
{
    [HttpGet("{id}")]
    public ActionResult<StudentV1Dto> GetById(int id)
    {
        return Ok(new StudentV1Dto
        {
            Id = id,
            Name = "John",
            Age = 20
        });
    }
}

public record StudentV1Dto
{
    public int Id { get; init; }
    public string Name { get; init; } = string.Empty;
    public int Age { get; init; }
}
```

### Controller v2

```csharp
[ApiController]
[Route("api/v{version:apiVersion}/[controller]")]
[ApiVersion("2.0")]
public class StudentsV2Controller : ControllerBase
{
    [HttpGet("{id}")]
    public ActionResult<StudentV2Dto> GetById(int id)
    {
        return Ok(new StudentV2Dto
        {
            Id = id,
            FullName = "John Doe",
            BirthDate = new DateTime(2005, 1, 1)
        });
    }
}

public record StudentV2Dto
{
    public int Id { get; init; }
    public string FullName { get; init; } = string.Empty;
    public DateTime BirthDate { get; init; }
}
```

### Llamadas desde Cliente

```csharp
// Customer v1
var response = await _httpClient.GetAsync("https://api.example.org/api/v1/students/123");

// Customer v2
var response = await _httpClient.GetAsync("https://api.example.org/api/v2/students/123");
```

---

## 2. Header Versioning

### Configuración

```csharp
builder.Services.AddApiVersioning(options =>
{
    options.ApiVersionReader = new HeaderApiVersionReader("X-API-Version");
    options.DefaultApiVersion = new ApiVersion(1, 0);
    options.AssumeDefaultVersionWhenUnspecified = true;
});
```

### Controller (sin version en ruta)

```csharp
[ApiController]
[Route("api/[controller]")]
[ApiVersion("1.0")]
[ApiVersion("2.0")]
public class StudentsController : ControllerBase
{
    [HttpGet("{id}")]
    [MapToApiVersion("1.0")]
    public ActionResult<StudentV1Dto> GetByIdV1(int id)
    {
        return Ok(new StudentV1Dto { Id = id, Name = "John" });
    }

    [HttpGet("{id}")]
    [MapToApiVersion("2.0")]
    public ActionResult<StudentV2Dto> GetByIdV2(int id)
    {
        return Ok(new StudentV2Dto { Id = id, FullName = "John Doe" });
    }
}
```

### Cliente

```csharp
_httpClient.DefaultRequestHeaders.Add("X-API-Version", "2");
var response = await _httpClient.GetAsync("https://api.example.org/api/students/123");
```

---

## 3. Query String Versioning

### Configuración

```csharp
builder.Services.AddApiVersioning(options =>
{
    options.ApiVersionReader = new QueryStringApiVersionReader("v");
});
```

### Cliente

```csharp
var response = await _httpClient.GetAsync("https://api.example.org/api/students/123?v=2");
```

---

## 4. Deprecación de Versiones

### Marcar como Obsoleta

```csharp
[ApiController]
[Route("api/v{version:apiVersion}/[controller]")]
[ApiVersion("1.0", Deprecated = true)] // ⚠️ Marcada como deprecated
[ApiVersion("2.0")]
public class StudentsController : ControllerBase
{
    [HttpGet]
    [MapToApiVersion("1.0")]
    [Obsolete("Esta versión será eliminada el 2026-12-31. Usa v2.")]
    public ActionResult<IEnumerable<StudentV1Dto>> GetAllV1()
    {
        // Implementación v1 (deprecated)
    }

    [HttpGet]
    [MapToApiVersion("2.0")]
    public ActionResult<IEnumerable<StudentV2Dto>> GetAllV2()
    {
        // Implementación v2 (actual)
    }
}
```

### Response Header

```http
HTTP/1.1 200 OK
api-supported-versions: 2.0
api-deprecated-versions: 1.0
Sunset: Mon, 31 Dec 2026 23:59:59 GMT
```

---

## 5. OpenAPI / Swagger con Múltiples Versiones

### Configuración

```csharp
using Asp.Versioning.ApiExplorer;

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.ConfigureOptions<ConfigureSwaggerOptions>();

public class ConfigureSwaggerOptions : IConfigureOptions<SwaggerGenOptions>
{
    private readonly IApiVersionDescriptionProvider _provider;

    public ConfigureSwaggerOptions(IApiVersionDescriptionProvider provider)
    {
        _provider = provider;
    }

    public void Configure(SwaggerGenOptions options)
    {
        foreach (var description in _provider.ApiVersionDescriptions)
        {
            options.SwaggerDoc(
                description.GroupName,
                new OpenApiInfo
                {
                    Title = $"Mi API {description.ApiVersion}",
                    Version = description.ApiVersion.ToString(),
                    Description = description.IsDeprecated
                        ? "⚠️ Esta versión está deprecada"
                        : "Versión actual"
                });
        }
    }
}

// Middleware
app.UseSwagger();
app.UseSwaggerUI(options =>
{
    var descriptions = app.Services.GetRequiredService<IApiVersionDescriptionProvider>()
        .ApiVersionDescriptions;

    foreach (var description in descriptions)
    {
        options.SwaggerEndpoint(
            $"/swagger/{description.GroupName}/swagger.json",
            description.GroupName.ToUpperInvariant());
    }
});
```

### Resultado

```
Swagger UI mostrará:
- v1 (deprecated)
- v2 (current)
- v3 (beta)
```

---

## 6. Versionado de DTOs

### Namespace por Versión

```csharp
namespace MyApp.Api.V1.Models
{
    public record StudentDto
    {
        public int Id { get; init; }
        public string Name { get; init; } = string.Empty;
    }
}

namespace MyApp.Api.V2.Models
{
    public record StudentDto
    {
        public int Id { get; init; }
        public string FullName { get; init; } = string.Empty;
        public DateTime BirthDate { get; init; }
    }
}
```

---

## 7. Políticas de Versionado

### Política de la organización

| Aspecto | Regla |
|---------|-------|
| **Formato** | Major.Minor (1.0, 2.0) |
| **Breaking changes** | Incrementan Major (1.0 → 2.0) |
| **Nuevas features** | Pueden añadirse a versión existente si compatibles |
| **Deprecación** | Mínimo 12 meses de aviso |
| **Soporte** | Últimas 2 versiones Major |

### Ejemplo Timeline

```
2025-01-01: v1.0 lanzada
2025-06-01: v2.0 lanzada (v1.0 marcada deprecated)
2026-01-01: v3.0 lanzada (v2.0 soportada, v1.0 deprecated)
2026-06-01: v1.0 eliminada (tras 12 meses deprecated)
```

---

## 📊 Comparativa Estrategias

| Aspecto | URL | Header | Query String |
|---------|-----|--------|--------------|
| **Claridad** | ⭐⭐⭐ | ⭐⭐ | ⭐⭐ |
| **Cacheabilidad** | ⭐⭐⭐ | ⭐ | ⭐⭐ |
| **Simplicidad** | ⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ |
| **SEO** | ⭐⭐⭐ | ⭐ | ⭐ |
| **Recomendado para** | APIs públicas | APIs internas | Prototipos |

---

## ⚠️ Errores Comunes

### ❌ NO hacer

```csharp
// ❌ Modificar DTOs existentes (rompe v1)
public record StudentDto
{
    public string Name { get; init; } // Eliminado en v2
    public string FullName { get; init; } // Añadido en v2
}

// ❌ Eliminar versiones sin aviso
[ApiVersion("1.0")] // Eliminada repentinamente

// ❌ Versionado inconsistente
/api/v1/students
/api/2.0/scholarships // Formato diferente
```

### ✅ Hacer

```csharp
// ✅ DTOs separados por versión
namespace Api.V1.Models { public record StudentDto { ... } }
namespace Api.V2.Models { public record StudentDto { ... } }

// ✅ Deprecar con aviso
[ApiVersion("1.0", Deprecated = true)]
[Obsolete("Usa v2. Eliminación prevista: 2026-12-31")]

// ✅ Formato consistente
/api/v1/students
/api/v2/students
```

---

## 🧪 Testing

```csharp
[Fact]
public async Task GetStudent_V1_ReturnsV1Schema()
{
    // Arrange
    var client = _factory.CreateClient();
    client.DefaultRequestHeaders.Add("X-API-Version", "1");

    // Act
    var response = await client.GetAsync("/api/students/123");

    // Assert
    response.StatusCode.Should().Be(HttpStatusCode.OK);

    var content = await response.Content.ReadFromJsonAsync<StudentV1Dto>();
    content.Should().NotBeNull();
    content!.Name.Should().NotBeNullOrEmpty(); // Campo solo en v1
}
```

---

## 📚 Referencias

- [ASP.NET Core API Versioning](https://github.com/dotnet/aspnet-api-versioning)
- [REST API Versioning Best Practices](https://www.freecodecamp.org/news/rest-api-best-practices-rest-endpoint-design-examples/)

---

*Pattern: api-versioning - Ovillo v3.7.0*
