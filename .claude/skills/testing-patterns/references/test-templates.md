# Plantillas de Tests

> Plantillas completas de tests para diferentes capas y patrones.
> Incluye: test unitario de service, test de entidad, test de value object, test de integración.

---

## Test Unitario - Service

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
        var scholarship = new Scholarship { Id = scholarshipId, Name = "Test", Amount = 5000m };

        _repositoryMock
            .Setup(r => r.GetByIdAsync(scholarshipId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(scholarship);

        // Act
        var result = await _sut.GetByIdAsync(scholarshipId);

        // Assert
        result.Should().NotBeNull();
        result!.Id.Should().Be(scholarshipId);
        result.Name.Should().Be("Test");

        _repositoryMock.Verify(
            r => r.GetByIdAsync(scholarshipId, It.IsAny<CancellationToken>()),
            Times.Once);
    }

    [Fact]
    public async Task GetById_ScholarshipDoesNotExist_ReturnsNull()
    {
        // Arrange
        _repositoryMock
            .Setup(r => r.GetByIdAsync(It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync((Scholarship?)null);

        // Act
        var result = await _sut.GetByIdAsync(999);

        // Assert
        result.Should().BeNull();
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

## Test de Entidad (Domain)

```csharp
public class ScholarshipTests
{
    [Fact]
    public void Crear_ValidData_CreatesScholarshipEnDraft()
    {
        // Arrange
        var period = new Period(
            DateTime.Today.AddDays(1),
            DateTime.Today.AddMonths(6));

        // Act
        var scholarship = Scholarship.Create("BECA-001", "Test", 5000m, period);

        // Assert
        scholarship.Should().NotBeNull();
        scholarship.Status.Should().Be(ScholarshipStatus.Draft);
        scholarship.DomainEvents.Should().ContainSingle()
            .Which.Should().BeOfType<ScholarshipCreatedEvent>();
    }

    [Fact]
    public void Publicar_EstadoDraft_CambiaAPublished()
    {
        // Arrange
        var scholarship = CreateScholarshipValida();

        // Act
        scholarship.Publish();

        // Assert
        scholarship.Status.Should().Be(ScholarshipStatus.Published);
    }

    [Fact]
    public void Publicar_YaPublished_ThrowsExcepcion()
    {
        // Arrange
        var scholarship = CreateScholarshipValida();
        scholarship.Publish();

        // Act
        var act = () => scholarship.Publish();

        // Assert
        act.Should().Throw<DomainException>()
            .WithMessage("*borrador*");
    }

    private static Scholarship CreateScholarshipValida()
    {
        var period = new Period(
            DateTime.Today.AddDays(1),
            DateTime.Today.AddMonths(6));
        return Scholarship.Create("BECA-001", "Test", 5000m, period);
    }
}
```

---

## Test de Value Object

```csharp
public class PeriodTests
{
    [Fact]
    public void Constructor_ValidDates_CreatesPeriod()
    {
        // Arrange
        var start = DateTime.Today;
        var end = DateTime.Today.AddMonths(6);

        // Act
        var period = new Period(start, end);

        // Assert
        period.StartDate.Should().Be(start);
        period.EndDate.Should().Be(end);
    }

    [Fact]
    public void Constructor_EndDateAnterior_ThrowsExcepcion()
    {
        // Arrange
        var start = DateTime.Today;
        var end = DateTime.Today.AddDays(-1);

        // Act
        var act = () => new Period(start, end);

        // Assert
        act.Should().Throw<DomainException>()
            .WithMessage("*posterior*");
    }

    [Theory]
    [InlineData(0, true)]   // Hoy, dentro
    [InlineData(90, true)]  // Dentro
    [InlineData(-1, false)] // Antes
    [InlineData(200, false)] // Después
    public void Contiene_VariasFechas_ReturnsEsperado(int diasDesdeInicio, bool expected)
    {
        // Arrange
        var start = DateTime.Today;
        var end = DateTime.Today.AddMonths(6);
        var period = new Period(start, end);
        var date = start.AddDays(diasDesdeInicio);

        // Act
        var result = period.Contains(date);

        // Assert
        result.Should().Be(expected);
    }

    [Fact]
    public void Equals_MismoValor_SonIguales()
    {
        // Arrange
        var start = DateTime.Today;
        var end = DateTime.Today.AddMonths(6);
        var periodo1 = new Period(start, end);
        var periodo2 = new Period(start, end);

        // Act & Assert
        periodo1.Should().Be(periodo2);
        (periodo1 == periodo2).Should().BeTrue();
    }
}
```

---

## Test de Integración

```csharp
public class WebApplicationFixture : WebApplicationFactory<Program>, IAsyncLifetime
{
    private MsSqlContainer _sqlContainer = null!;

    public async Task InitializeAsync()
    {
        _sqlContainer = new MsSqlBuilder()
            .WithImage("mcr.microsoft.com/mssql/server:2022-latest")
            .Build();

        await _sqlContainer.StartAsync();
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            // Reemplazar DbContext
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

    public ScholarshipsControllerTests(WebApplicationFixture factory)
    {
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task GetAll_ReturnsOk()
    {
        // Act
        var response = await _client.GetAsync("/api/scholarships");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task Create_ValidRequest_ReturnsCreated()
    {
        // Arrange
        var request = new { Name = "Test", Amount = 5000m };

        // Act
        var response = await _client.PostAsJsonAsync("/api/scholarships", request);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.Created);
        response.Headers.Location.Should().NotBeNull();
    }

    [Fact]
    public async Task Create_InvalidRequest_ReturnsBadRequest()
    {
        // Arrange
        var request = new { Name = "", Amount = -100m };

        // Act
        var response = await _client.PostAsJsonAsync("/api/scholarships", request);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }
}
```
