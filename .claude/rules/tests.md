---
globs:
  - "tests/**/*.cs"
  - "**/*.Tests/**/*.cs"
  - "**/*.Test/**/*.cs"
  - "**/Tests/**/*.cs"
  - "**/*Tests.cs"
  - "**/*Test.cs"
---

# Reglas para Pruebas Unitarias

> Este archivo aplica cuando Claude trabaja con tests.
> **Detecta automáticamente** el framework de testing del proyecto.

---

## DETECCIÓN DE FRAMEWORK

```xml
<PackageReference Include="xunit" Version="2.*" />              <!-- xUnit (recomendado) -->
<PackageReference Include="NUnit" Version="4.*" />              <!-- NUnit -->
<PackageReference Include="MSTest.TestFramework" Version="3.*" /> <!-- MSTest -->
```

---

## PARTE 1: NOMENCLATURA

### Convención de Nombres

```
Method_Scenario_ExpectedResult

Ejemplos:
- GetById_ScholarshipExists_ReturnsScholarship
- GetById_ScholarshipDoesNotExist_ReturnsNull
- Create_ValidData_SavesToDatabase
- Create_EmptyName_ThrowsValidationException
- Delete_ScholarshipWithApplications_ThrowsBusinessException
```

### Estructura de Carpetas

```
tests/
├── MyCompany.MyApp.Domain.Tests/
│   ├── Entities/
│   │   ├── ScholarshipTests.cs
│   │   └── ScholarshipApplicationTests.cs
│   └── ValueObjects/
│       └── PeriodTests.cs
├── MyCompany.MyApp.Application.Tests/
│   ├── Services/
│   │   └── ScholarshipServiceTests.cs
│   └── Validators/
│       └── CreateScholarshipRequestValidatorTests.cs
└── MyCompany.MyApp.Integration.Tests/
    ├── Api/
    │   └── ScholarshipsControllerTests.cs
    └── Fixtures/
        └── WebApplicationFixture.cs
```

---

## PARTE 2: PATRÓN AAA (Arrange-Act-Assert)

### Ejemplo Completo - xUnit + FluentAssertions

```csharp
public class ScholarshipServiceTests
{
    private readonly Mock<IScholarshipRepository> _repositoryMock;
    private readonly Mock<ILogger<ScholarshipService>> _loggerMock;
    private readonly ScholarshipService _sut; // System Under Test

    public ScholarshipServiceTests()
    {
        _repositoryMock = new Mock<IScholarshipRepository>();
        _loggerMock = new Mock<ILogger<ScholarshipService>>();
        _sut = new ScholarshipService(_repositoryMock.Object, _loggerMock.Object);
    }

    [Fact]
    public async Task GetById_ScholarshipExists_ReturnsScholarshipDto()
    {
        // Arrange
        var scholarshipId = 1;
        var scholarship = new Scholarship 
        { 
            Id = scholarshipId, 
            Name = "Scholarship Test", 
            Amount = 5000m 
        };
        
        _repositoryMock
            .Setup(r => r.GetByIdAsync(scholarshipId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(scholarship);

        // Act
        var result = await _sut.GetByIdAsync(scholarshipId);

        // Assert
        result.Should().NotBeNull();
        result!.Id.Should().Be(scholarshipId);
        result.Name.Should().Be("Scholarship Test");
        result.Amount.Should().Be(5000m);
        
        _repositoryMock.Verify(
            r => r.GetByIdAsync(scholarshipId, It.IsAny<CancellationToken>()), 
            Times.Once);
    }

    [Fact]
    public async Task GetById_ScholarshipDoesNotExist_ReturnsNull()
    {
        // Arrange
        var scholarshipId = 999;
        _repositoryMock
            .Setup(r => r.GetByIdAsync(scholarshipId, It.IsAny<CancellationToken>()))
            .ReturnsAsync((Scholarship?)null);

        // Act
        var result = await _sut.GetByIdAsync(scholarshipId);

        // Assert
        result.Should().BeNull();
    }

    [Fact]
    public async Task Create_ValidData_SavesAndReturnsScholarship()
    {
        // Arrange
        var request = new CreateScholarshipRequest
        {
            Name = "New Scholarship",
            Amount = 3000m,
            StartDate = DateTime.Today.AddDays(1),
            EndDate = DateTime.Today.AddMonths(6)
        };

        _repositoryMock
            .Setup(r => r.AddAsync(It.IsAny<Scholarship>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync((Scholarship b, CancellationToken _) => 
            {
                b.Id = 1;
                return b;
            });

        // Act
        var result = await _sut.CreateAsync(request);

        // Assert
        result.Should().NotBeNull();
        result.Id.Should().Be(1);
        result.Name.Should().Be("New Scholarship");
        
        _repositoryMock.Verify(
            r => r.AddAsync(
                It.Is<Scholarship>(b => b.Name == "New Scholarship" && b.Amount == 3000m),
                It.IsAny<CancellationToken>()),
            Times.Once);
    }

    [Theory]
    [InlineData("")]
    [InlineData(null)]
    [InlineData("   ")]
    public async Task Create_InvalidName_ThrowsValidationException(string? name)
    {
        // Arrange
        var request = new CreateScholarshipRequest { Name = name!, Amount = 1000m };

        // Act
        var act = () => _sut.CreateAsync(request);

        // Assert
        await act.Should().ThrowAsync<ValidationException>()
            .WithMessage("*name*");
    }
}
```

---

## PARTE 3: MOCKING CON MOQ

### Setup Básico

```csharp
// Retornar valor
_mockRepo.Setup(r => r.GetByIdAsync(1, It.IsAny<CancellationToken>()))
    .ReturnsAsync(new Scholarship { Id = 1 });

// Retornar según parámetro
_mockRepo.Setup(r => r.GetByIdAsync(It.IsAny<int>(), It.IsAny<CancellationToken>()))
    .ReturnsAsync((int id, CancellationToken _) => new Scholarship { Id = id });

// Lanzar excepción
_mockRepo.Setup(r => r.GetByIdAsync(999, It.IsAny<CancellationToken>()))
    .ThrowsAsync(new NotFoundException("Scholarship not found"));

// Callback para inspeccionar
_mockRepo.Setup(r => r.AddAsync(It.IsAny<Scholarship>(), It.IsAny<CancellationToken>()))
    .Callback<Scholarship, CancellationToken>((b, _) => savedScholarship = b)
    .ReturnsAsync((Scholarship b, CancellationToken _) => b);
```

### Verificaciones

```csharp
// Verificar que se llamó
_mockRepo.Verify(r => r.GetByIdAsync(1, It.IsAny<CancellationToken>()), Times.Once);

// Verificar que NO se llamó
_mockRepo.Verify(r => r.DeleteAsync(It.IsAny<Scholarship>(), It.IsAny<CancellationToken>()), Times.Never);

// Verificar con condición
_mockRepo.Verify(
    r => r.AddAsync(
        It.Is<Scholarship>(b => b.Name == "Test" && b.Amount > 0),
        It.IsAny<CancellationToken>()),
    Times.Once);
```

---

## PARTE 4: FLUENT ASSERTIONS

### Aserciones Comunes

```csharp
// Valores
result.Should().Be(expected);
result.Should().NotBe(unexpected);
result.Should().BeNull();
result.Should().NotBeNull();

// Strings
name.Should().Be("Test");
name.Should().StartWith("Scholarship");
name.Should().Contain("excelencia");
name.Should().BeEmpty();
name.Should().HaveLength(10);

// Números
amount.Should().Be(5000m);
amount.Should().BeGreaterThan(0);
amount.Should().BeInRange(1000, 10000);
amount.Should().BeApproximately(5000m, 0.01m);

// Colecciones
scholarships.Should().NotBeEmpty();
scholarships.Should().HaveCount(5);
scholarships.Should().Contain(b => b.Name == "Test");
scholarships.Should().BeInAscendingOrder(b => b.Name);
scholarships.Should().OnlyContain(b => b.Status == ScholarshipStatus.Published);

// Excepciones
var act = () => _sut.Delete(999);
await act.Should().ThrowAsync<NotFoundException>();
await act.Should().ThrowAsync<ValidationException>()
    .WithMessage("*required*");

// Objetos
scholarship.Should().BeEquivalentTo(expected, options => 
    options.Excluding(b => b.Id)
           .Excluding(b => b.CreatedAt));

// Tiempo de ejecución
var act = () => _sut.ProcessAsync();
await act.Should().CompleteWithinAsync(TimeSpan.FromSeconds(5));
```

---

## PARTE 5: TESTS DE INTEGRACIÓN - .NET 10

### WebApplicationFactory

```csharp
public class WebApplicationFixture : WebApplicationFactory<Program>, IAsyncLifetime
{
    private MsSqlContainer _sqlContainer = null!;

    public async Task InitializeAsync()
    {
        // Testcontainers - SQL Server en Docker
        _sqlContainer = new MsSqlBuilder()
            .WithImage("mcr.microsoft.com/mssql/server:2022-latest")
            .Build();
        
        await _sqlContainer.StartAsync();
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            // Reemplazar DbContext con conexión a contenedor
            var descriptor = services.SingleOrDefault(
                d => d.ServiceType == typeof(DbContextOptions<ApplicationDbContext>));
            
            if (descriptor != null)
                services.Remove(descriptor);

            services.AddDbContext<ApplicationDbContext>(options =>
                options.UseSqlServer(_sqlContainer.GetConnectionString()));
        });
    }

    public new async Task DisposeAsync()
    {
        await _sqlContainer.DisposeAsync();
    }
}

[Collection("Integration")]
public class ScholarshipsControllerTests : IClassFixture<WebApplicationFixture>
{
    private readonly HttpClient _client;
    private readonly WebApplicationFixture _factory;

    public ScholarshipsControllerTests(WebApplicationFixture factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task GetAll_ReturnsOk()
    {
        // Act
        var response = await _client.GetAsync("/api/scholarships");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        
        var content = await response.Content.ReadFromJsonAsync<PaginatedResult<ScholarshipDto>>();
        content.Should().NotBeNull();
    }

    [Fact]
    public async Task Create_ValidRequest_ReturnsCreated()
    {
        // Arrange
        var request = new CreateScholarshipRequest
        {
            Name = "Scholarship Test Integration",
            Amount = 5000m
        };

        // Act
        var response = await _client.PostAsJsonAsync("/api/scholarships", request);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.Created);
        response.Headers.Location.Should().NotBeNull();
    }
}
```

---

## PARTE 6: TESTS DE DOMINIO

### Testing Value Objects

```csharp
public class PeriodTests
{
    [Fact]
    public void Constructor_ValidDates_CreatesPeriod()
    {
        // Arrange
        var start = new DateTime(2025, 1, 1);
        var end = new DateTime(2025, 12, 31);

        // Act
        var period = new Period(start, end);

        // Assert
        period.StartDate.Should().Be(start);
        period.EndDate.Should().Be(end);
    }

    [Fact]
    public void Constructor_EndDateBeforeStartDate_ThrowsException()
    {
        // Arrange
        var start = new DateTime(2025, 12, 31);
        var end = new DateTime(2025, 1, 1);

        // Act
        var act = () => new Period(start, end);

        // Assert
        act.Should().Throw<DomainException>()
            .WithMessage("*end date*before*");
    }

    [Theory]
    [InlineData("2025-06-15", true)]  // Dentro del period
    [InlineData("2024-12-31", false)] // Antes
    [InlineData("2026-01-01", false)] // Después
    public void Contains_VariousDates_ReturnsExpected(string dateStr, bool expected)
    {
        // Arrange
        var period = new Period(
            new DateTime(2025, 1, 1),
            new DateTime(2025, 12, 31));
        var date = DateTime.Parse(dateStr);

        // Act
        var result = period.Contains(date);

        // Assert
        result.Should().Be(expected);
    }
}
```

---

## PARTE 7: COBERTURA

### Cobertura Mínima Recomendada

| Capa | Cobertura mínima |
|------|------------------|
| Domain | 90% |
| Application | 80% |
| Infrastructure | 60% |
| Presentation | 40% |

### Ejecutar con Cobertura

```bash
# .NET 10 con coverlet
dotnet test --collect:"XPlat Code Coverage"

# Generar reporte HTML
reportgenerator -reports:**/coverage.cobertura.xml -targetdir:coverage-report
```

---

## CHECKLIST

### Cada test debe
- [ ] Nombre descriptivo (Método_Escenario_Resultado)
- [ ] Seguir patrón AAA
- [ ] Probar UN solo comportamiento
- [ ] Ser independiente de otros tests
- [ ] Ejecutar rápido (<1 segundo unitarios)

### Proyecto de tests debe
- [ ] xUnit + FluentAssertions + Moq
- [ ] Estructura espejo del proyecto principal
- [ ] Tests de integración separados
- [ ] Cobertura mínima por capa

---

*Regla condicional v3.7.0 - Multi-versión .NET*
