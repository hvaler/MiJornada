# Snapshot Testing con Verify.NET

> Skill: testing-patterns | Version: 3.7.0

Patron para verificar que la salida de un metodo no cambia inesperadamente.
Verify.NET captura la primera salida como "snapshot verificado" y compara las siguientes ejecuciones contra ella.

---

## Cuando Usar Snapshot Testing

| Usar | No Usar |
|------|---------|
| Respuestas JSON de API complejas | Logica de negocio simple (usar assertions directas) |
| Transformaciones de datos (mapeos DTO) | Tests con datos dinamicos (fechas, GUIDs) |
| Salida de generadores de codigo | Tests de rendimiento |
| Configuraciones serializadas | Validaciones de dominio |
| Reportes y documentos generados | Tests que cambian frecuentemente |

---

## Paquetes NuGet

```xml
<ItemGroup>
  <PackageReference Include="Verify.Xunit" Version="26.*" />
  <PackageReference Include="Verify.DiffPlex" Version="3.*" />
  <!-- Opcional: soporte para tipos especificos -->
  <PackageReference Include="Verify.EntityFramework" Version="26.*" />
  <PackageReference Include="Verify.Http" Version="6.*" />
</ItemGroup>
```

---

## Configuracion Inicial

### ModuleInitializer (una vez por proyecto de tests)

```csharp
// ModuleInitializer.cs
using System.Runtime.CompilerServices;

public static class ModuleInitializer
{
    [ModuleInitializer]
    public static void Init()
    {
        // Habilitar diff visual en consola
        VerifyDiffPlex.Initialize();

        // Configuracion global
        VerifierSettings.DontScrubDateTimes();     // Mantener fechas exactas
        VerifierSettings.SortPropertiesAlphabetically(); // Orden consistente

        // Ignorar propiedades volatiles globalmente
        VerifierSettings.AddScrubber(scrubber =>
            scrubber.Replace(
                new Regex(@"""id""\s*:\s*\d+"),
                @"""id"": ""SCRUBBED"""));
    }
}
```

### .gitattributes

```
# Marcar snapshots como generados (no cuentan en diff reviews)
*.verified.txt linguist-generated
*.verified.json linguist-generated
*.verified.xml linguist-generated
```

### .gitignore

```
# Snapshots recibidos (no verificados aun)
*.received.*
```

---

## Patron 1: Snapshot de Respuesta API

```csharp
[UsesVerify]
public class ScholarshipsApiSnapshotTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public ScholarshipsApiSnapshotTests(WebApplicationFactory<Program> factory)
    {
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task GetScholarships_ResponseShape_MatchesSnapshot()
    {
        // Act
        var response = await _client.GetAsync("/api/scholarships?page=1&size=2");
        var json = await response.Content.ReadAsStringAsync();

        // Assert - Primera ejecucion crea el .verified.json
        await Verify(json)
            .ScrubMember("id")           // IDs cambian
            .ScrubMember("createdAt")    // Fechas cambian
            .UseMethodName("GetScholarships_ResponseShape");
    }

    [Fact]
    public async Task GetScholarshipById_ResponseShape_MatchesSnapshot()
    {
        // Act
        var response = await _client.GetFromJsonAsync<JsonElement>("/api/scholarships/1");

        // Assert
        await Verify(response)
            .ScrubMember("id")
            .ScrubMember("createdAt")
            .ScrubMember("modifiedAt");
    }
}
```

Snapshot generado (`GetScholarships_ResponseShape.verified.json`):
```json
{
  "items": [
    {
      "id": "SCRUBBED",
      "nombre": "Scholarship Excelencia",
      "amount": 5000.00,
      "estado": "Published",
      "createdAt": "SCRUBBED"
    }
  ],
  "totalItems": 10,
  "page": 1,
  "pageSize": 2
}
```

---

## Patron 2: Snapshot de Mapeo DTO

```csharp
[UsesVerify]
public class MappingSnapshotTests
{
    private readonly IMapper _mapper;

    public MappingSnapshotTests()
    {
        var config = new MapperConfiguration(cfg =>
            cfg.AddProfile<ScholarshipMappingProfile>());
        _mapper = config.CreateMapper();
    }

    [Fact]
    public async Task ScholarshipToDto_CompleteMapping_MatchesSnapshot()
    {
        // Arrange
        var scholarship = new Scholarship
        {
            Id = 1,
            Code = "BECA-001",
            Name = "Scholarship Excelencia",
            Amount = 5000m,
            Status = ScholarshipStatus.Published,
            Period = new Period(
                new DateTime(2026, 1, 1),
                new DateTime(2026, 12, 31))
        };

        // Act
        var dto = _mapper.Map<ScholarshipDto>(scholarship);

        // Assert - Verifica que el mapeo no cambia
        await Verify(dto);
    }

    [Fact]
    public async Task CreateScholarshipRequest_ToDomain_MatchesSnapshot()
    {
        // Arrange
        var request = new CreateScholarshipRequest
        {
            Name = "Scholarship Test",
            Amount = 3000m,
            StartDate = new DateTime(2026, 3, 1),
            EndDate = new DateTime(2026, 9, 30)
        };

        // Act
        var scholarship = _mapper.Map<Scholarship>(request);

        // Assert
        await Verify(scholarship)
            .ScrubMember("Id");  // No asignado aun
    }
}
```

---

## Patron 3: Snapshot de Configuracion

```csharp
[UsesVerify]
public class ConfigurationSnapshotTests
{
    [Fact]
    public async Task ServiceCollection_RegisteredServices_MatchSnapshot()
    {
        // Arrange
        var builder = WebApplication.CreateBuilder();
        builder.Services.AddApplication();
        builder.Services.AddInfrastructure(builder.Configuration);

        // Act - Capturar servicios registrados
        var services = builder.Services
            .Where(s => s.ServiceType.Namespace?.StartsWith("MyCompany") == true)
            .Select(s => new
            {
                Service = s.ServiceType.Name,
                Implementation = s.ImplementationType?.Name,
                Lifetime = s.Lifetime.ToString()
            })
            .OrderBy(s => s.Service);

        // Assert
        await Verify(services);
    }

    [Fact]
    public async Task OpenApiDocument_Schema_MatchesSnapshot()
    {
        // Arrange
        var factory = new WebApplicationFactory<Program>();
        var client = factory.CreateClient();

        // Act
        var openApi = await client.GetStringAsync("/openapi/v1.json");

        // Assert - El contrato de API no cambia sin intencion
        await Verify(openApi);
    }
}
```

---

## Patron 4: Snapshot con Scrubbers Personalizados

```csharp
[UsesVerify]
public class AdvancedSnapshotTests
{
    [Fact]
    public async Task ErrorResponse_ProblemDetails_MatchesSnapshot()
    {
        // Act
        var response = await _client.GetAsync("/api/scholarships/99999");
        var content = await response.Content.ReadAsStringAsync();

        // Assert con scrubbers encadenados
        await Verify(content)
            .ScrubInlineGuids()          // Reemplaza GUIDs por placeholders
            .ScrubMember("traceId")      // Trace IDs cambian
            .ScrubMember("instance")     // Path especifico
            .AddScrubber(s => s.Replace(
                DateTime.Today.ToString("yyyy-MM-dd"),
                "TODAY"));               // Scrubber custom para fechas
    }

    [Fact]
    public async Task AuditLog_Entry_MatchesSnapshot()
    {
        // Act
        var entry = new AuditLogEntry
        {
            UserId = "user123",
            Action = "CreateScholarship",
            Timestamp = DateTime.UtcNow,
            Details = new { ScholarshipId = 1, Name = "Test" }
        };

        // Assert - Ignorar campos volatiles
        await Verify(entry)
            .IgnoreMember("Timestamp")
            .IgnoreMember("UserId");
    }
}
```

---

## Flujo de Trabajo con Snapshots

```
1. Escribir test con await Verify(result)
2. Primera ejecucion → FALLA (no hay snapshot)
   → Genera archivo .received.json
3. Revisar .received.json
   → Si es correcto: renombrar a .verified.json (o usar tool)
4. Commit del .verified.json al repositorio
5. Siguientes ejecuciones → PASA si salida == snapshot
6. Si cambia la salida → FALLA con diff visual
   → Revisar cambio: ¿intencionado? → Actualizar snapshot
   → ¿Bug? → Corregir codigo
```

### Comando para aceptar snapshots

```bash
# Aceptar todos los snapshots pendientes
dotnet verify accept

# Aceptar un snapshot especifico
dotnet verify accept --filter "ScholarshipsApiSnapshotTests"
```

---

## Anti-Patrones

| Anti-Patron | Problema | Solucion |
|---|---|---|
| Snapshot de entidades completas | Fragil, cambia con cada campo nuevo | Usar `.ScrubMember()` o mapear a DTO |
| Sin scrubbers para IDs/fechas | Tests fallan aleatoriamente | SIEMPRE scrub datos volatiles |
| Snapshots enormes (>100 lineas) | Dificil de revisar en PR | Dividir en tests mas pequenos |
| Snapshot como unico test | No valida logica, solo forma | Complementar con assertions directas |
| No commitear `.verified.*` | Tests fallan en CI | Incluir en `.gitattributes` y repo |

---

## CI/CD Configuration

```yaml
# Azure Pipelines
- task: DotNetCoreCLI@2
  displayName: 'Run Snapshot Tests'
  inputs:
    command: test
    projects: '**/*Tests.csproj'
  env:
    # Verify.NET detecta CI y genera mejor output
    CI: true
    Verify_DiffTool: false  # No abrir diff tool en CI
```

---

*Pattern snapshot-testing v3.7.0*
