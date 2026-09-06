# Fixtures para Tests de Integración

> Skill: testing-patterns
> Versión: 2.8.0

---

## Descripción

Configuración de fixtures para tests de integración con WebApplicationFactory,
Testcontainers y base de datos real en contenedor Docker.

> ⚠️ **Cobertura + WebApplicationFactory (FB-008)**: recolectar cobertura con Coverlet
> (`--collect "XPlat Code Coverage"`, IL-rewrite) sobre tests de integración con
> `WebApplicationFactory`/TestServer **cuelga** el testhost (CPU plana), sobre todo a nivel
> solución en paralelo. Para medir esos proyectos: usa **`dotnet-coverage`** (profiler
> out-of-process: `dotnet-coverage collect -f cobertura -o cov.xml "dotnet test <proj> --no-build"`)
> **por-proyecto y secuencial**, o `dotnet test --blame-hang-timeout 120s` + ejecución secuencial
> (`[assembly: CollectionBehavior(DisableTestParallelization=true)]`). Ver la skill
> `calidad-codigo-sync` (QR) para el pliegue de esa cobertura en las métricas.

---

## WebApplicationFactory Básica

```csharp
public class WebApplicationFixture : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            // Reemplazar servicios para tests
            var descriptor = services.SingleOrDefault(
                d => d.ServiceType == typeof(DbContextOptions<ApplicationDbContext>));

            if (descriptor != null)
                services.Remove(descriptor);

            // Usar base de datos en memoria
            services.AddDbContext<ApplicationDbContext>(options =>
                options.UseInMemoryDatabase("TestDb"));

            // Configurar autenticación de test
            services.AddAuthentication("Test")
                .AddScheme<AuthenticationSchemeOptions, TestAuthHandler>("Test", null);
        });

        builder.UseEnvironment("Testing");
    }
}
```

---

## Fixture con Testcontainers (SQL Server)

```csharp
public class SqlServerFixture : WebApplicationFactory<Program>, IAsyncLifetime
{
    private MsSqlContainer _sqlContainer = null!;

    public string ConnectionString => _sqlContainer.GetConnectionString();

    public async Task InitializeAsync()
    {
        _sqlContainer = new MsSqlBuilder()
            .WithImage("mcr.microsoft.com/mssql/server:2022-latest")
            .WithPassword("Test@123456")
            .WithWaitStrategy(Wait.ForUnixContainer()
                .UntilPortIsAvailable(1433))
            .Build();

        await _sqlContainer.StartAsync();
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            // Remover DbContext existente
            var descriptor = services.SingleOrDefault(
                d => d.ServiceType == typeof(DbContextOptions<ApplicationDbContext>));

            if (descriptor != null)
                services.Remove(descriptor);

            // Usar SQL Server en contenedor
            services.AddDbContext<ApplicationDbContext>(options =>
                options.UseSqlServer(_sqlContainer.GetConnectionString()));
        });
    }

    public new async Task DisposeAsync()
    {
        await _sqlContainer.DisposeAsync();
        await base.DisposeAsync();
    }
}
```

---

## Fixture con Múltiples Contenedores

```csharp
public class FullStackFixture : WebApplicationFactory<Program>, IAsyncLifetime
{
    private MsSqlContainer _sqlContainer = null!;
    private RedisContainer _redisContainer = null!;

    public async Task InitializeAsync()
    {
        // Iniciar contenedores en paralelo
        var sqlTask = StartSqlContainerAsync();
        var redisTask = StartRedisContainerAsync();

        await Task.WhenAll(sqlTask, redisTask);
    }

    private async Task StartSqlContainerAsync()
    {
        _sqlContainer = new MsSqlBuilder()
            .WithImage("mcr.microsoft.com/mssql/server:2022-latest")
            .Build();
        await _sqlContainer.StartAsync();
    }

    private async Task StartRedisContainerAsync()
    {
        _redisContainer = new RedisBuilder()
            .WithImage("redis:7-alpine")
            .Build();
        await _redisContainer.StartAsync();
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            // SQL Server
            services.RemoveAll<DbContextOptions<ApplicationDbContext>>();
            services.AddDbContext<ApplicationDbContext>(options =>
                options.UseSqlServer(_sqlContainer.GetConnectionString()));

            // Redis
            services.RemoveAll<IDistributedCache>();
            services.AddStackExchangeRedisCache(options =>
            {
                options.Configuration = _redisContainer.GetConnectionString();
            });
        });
    }

    public new async Task DisposeAsync()
    {
        await _sqlContainer.DisposeAsync();
        await _redisContainer.DisposeAsync();
        await base.DisposeAsync();
    }
}
```

---

## Handler de Autenticación para Tests

```csharp
public class TestAuthHandler : AuthenticationHandler<AuthenticationSchemeOptions>
{
    public const string TestScheme = "Test";
    public const string DefaultUserId = "test-user-id";
    public const string DefaultUserName = "test@example.com";

    public TestAuthHandler(
        IOptionsMonitor<AuthenticationSchemeOptions> options,
        ILoggerFactory logger,
        UrlEncoder encoder)
        : base(options, logger, encoder)
    {
    }

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        // Obtener claims del header (para tests con usuarios específicos)
        var userId = Context.Request.Headers["X-Test-UserId"].FirstOrDefault() ?? DefaultUserId;
        var userName = Context.Request.Headers["X-Test-UserName"].FirstOrDefault() ?? DefaultUserName;
        var roles = Context.Request.Headers["X-Test-Roles"].FirstOrDefault()?.Split(',') ?? ["User"];

        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, userId),
            new(ClaimTypes.Name, userName),
            new(ClaimTypes.Email, userName)
        };

        claims.AddRange(roles.Select(r => new Claim(ClaimTypes.Role, r.Trim())));

        var identity = new ClaimsIdentity(claims, TestScheme);
        var principal = new ClaimsPrincipal(identity);
        var ticket = new AuthenticationTicket(principal, TestScheme);

        return Task.FromResult(AuthenticateResult.Success(ticket));
    }
}
```

---

## Base Class para Tests de Integración

```csharp
[Collection("Integration")]
public abstract class IntegrationTestBase : IClassFixture<SqlServerFixture>, IAsyncLifetime
{
    protected readonly SqlServerFixture Factory;
    protected readonly HttpClient Client;
    protected readonly IServiceScope Scope;
    protected readonly ApplicationDbContext DbContext;

    protected IntegrationTestBase(SqlServerFixture factory)
    {
        Factory = factory;
        Client = factory.CreateClient();
        Scope = factory.Services.CreateScope();
        DbContext = Scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
    }

    public virtual async Task InitializeAsync()
    {
        // Limpiar y recrear DB para cada test
        await DbContext.Database.EnsureDeletedAsync();
        await DbContext.Database.EnsureCreatedAsync();

        // Seed de datos base si es necesario
        await SeedDataAsync();
    }

    protected virtual Task SeedDataAsync()
    {
        return Task.CompletedTask;
    }

    public virtual Task DisposeAsync()
    {
        Scope.Dispose();
        return Task.CompletedTask;
    }

    // Helpers para autenticación en tests
    protected void AuthenticateAs(string userId, string userName, params string[] roles)
    {
        Client.DefaultRequestHeaders.Add("X-Test-UserId", userId);
        Client.DefaultRequestHeaders.Add("X-Test-UserName", userName);
        Client.DefaultRequestHeaders.Add("X-Test-Roles", string.Join(",", roles));
    }

    protected void AuthenticateAsAdmin()
    {
        AuthenticateAs("admin-id", "admin@example.com", "Admin");
    }

    protected void AuthenticateAsGestor()
    {
        AuthenticateAs("gestor-id", "gestor@example.com", "Gestor");
    }

    protected void AuthenticateAsUser()
    {
        AuthenticateAs("user-id", "user@example.com", "User");
    }
}
```

---

## Tests de Integración Ejemplo

```csharp
public class ScholarshipsControllerTests : IntegrationTestBase
{
    public ScholarshipsControllerTests(SqlServerFixture factory) : base(factory) { }

    protected override async Task SeedDataAsync()
    {
        // Datos de prueba
        DbContext.Scholarships.AddRange(
            new Scholarship { Id = 1, Code = "BECA-001", Name = "Scholarship Test 1", Amount = 5000 },
            new Scholarship { Id = 2, Code = "BECA-002", Name = "Scholarship Test 2", Amount = 3000 }
        );
        await DbContext.SaveChangesAsync();
    }

    [Fact]
    public async Task GetAll_ReturnsAllScholarships()
    {
        // Arrange
        AuthenticateAsUser();

        // Act
        var response = await Client.GetAsync("/api/scholarships");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var content = await response.Content.ReadFromJsonAsync<PaginatedResult<ScholarshipDto>>();
        content.Should().NotBeNull();
        content!.Items.Should().HaveCount(2);
    }

    [Fact]
    public async Task GetById_ExistingScholarship_ReturnsScholarship()
    {
        // Arrange
        AuthenticateAsUser();

        // Act
        var response = await Client.GetAsync("/api/scholarships/1");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var scholarship = await response.Content.ReadFromJsonAsync<ScholarshipDto>();
        scholarship.Should().NotBeNull();
        scholarship!.Code.Should().Be("BECA-001");
    }

    [Fact]
    public async Task Create_AsAdmin_ReturnsCreated()
    {
        // Arrange
        AuthenticateAsAdmin();
        var request = new CreateScholarshipCommand
        {
            Code = "BECA-NEW",
            Name = "New Scholarship",
            Amount = 4000m,
            StartDate = DateTime.Today,
            EndDate = DateTime.Today.AddMonths(6)
        };

        // Act
        var response = await Client.PostAsJsonAsync("/api/scholarships", request);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.Created);
        response.Headers.Location.Should().NotBeNull();

        // Verificar en BD
        var becaEnBd = await DbContext.Scholarships.FirstOrDefaultAsync(b => b.Code == "BECA-NEW");
        becaEnBd.Should().NotBeNull();
    }

    [Fact]
    public async Task Create_AsUser_ReturnsForbidden()
    {
        // Arrange
        AuthenticateAsUser();
        var request = new CreateScholarshipCommand { Code = "BECA-NEW", Name = "Test" };

        // Act
        var response = await Client.PostAsJsonAsync("/api/scholarships", request);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task Delete_ScholarshipWithApplications_ReturnsConflict()
    {
        // Arrange
        AuthenticateAsAdmin();

        // Añadir application a la scholarship
        DbContext.Applications.Add(new ScholarshipApplication { ScholarshipId = 1, StudentId = 1 });
        await DbContext.SaveChangesAsync();

        // Act
        var response = await Client.DeleteAsync("/api/scholarships/1");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }
}
```

---

## Collection Fixture (Compartir entre Tests)

```csharp
// Definir colección
[CollectionDefinition("Integration")]
public class IntegrationCollection : ICollectionFixture<SqlServerFixture>
{
    // Esta clase no tiene código, solo define la colección
}

// Usar en tests
[Collection("Integration")]
public class ScholarshipsControllerTests : IntegrationTestBase
{
    // Los tests comparten el mismo contenedor SQL Server
}

[Collection("Integration")]
public class ApplicationsControllerTests : IntegrationTestBase
{
    // También comparte el mismo contenedor
}
```

---

## Packages Necesarios

```xml
<ItemGroup>
  <PackageReference Include="Microsoft.AspNetCore.Mvc.Testing" Version="10.*" />
  <PackageReference Include="Testcontainers.MsSql" Version="3.*" />
  <PackageReference Include="Testcontainers.Redis" Version="3.*" />
  <PackageReference Include="xunit" Version="2.*" />
  <PackageReference Include="FluentAssertions" Version="6.*" />
</ItemGroup>
```

---

## Checklist para Tests de Integración

- [ ] Fixture implementa `IAsyncLifetime`
- [ ] Base de datos se limpia entre tests
- [ ] Autenticación configurada para diferentes roles
- [ ] Contenedores se detienen en `DisposeAsync`
- [ ] Tests usan `[Collection]` para compartir fixtures
- [ ] Seeds de datos reutilizables

---

*Pattern v1.0 - testing-patterns skill*
