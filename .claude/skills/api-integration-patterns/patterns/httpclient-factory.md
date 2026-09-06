# Pattern: HttpClient Factory

> **Pattern**: IHttpClientFactory
> **Problema**: Socket exhaustion, memory leaks, DNS issues
> **Solución**: Pool de HttpClient gestionado por DI

---

## 🎯 Problema

Crear HttpClient con `new HttpClient()` causa:

```csharp
// ❌ NUNCA hacer esto
public class MiServicio
{
    private readonly HttpClient _httpClient = new HttpClient();

    public async Task<string> LlamarApiAsync()
    {
        // Problema 1: Socket exhaustion (sockets no se liberan)
        // Problema 2: No respeta cambios DNS
        // Problema 3: Memory leak si se crea en cada request
        return await _httpClient.GetStringAsync("https://api.example.org");
    }
}
```

**Síntomas:**
- Excepción "Only one usage of each socket address"
- Alta latencia en llamadas HTTP
- Memory leaks en long-running apps

---

## ✅ Solución: IHttpClientFactory

### Tipos de Clients

| Tipo | Uso | Configuración |
|------|-----|---------------|
| **Typed Client** | API específica | Clase dedicada inyectable |
| **Named Client** | Múltiples configuraciones | Por nombre string |
| **Basic Client** | Ad-hoc simple | Sin configuración especial |

---

## 1. Typed Client (Recomendado)

### Configuración en Program.cs

```csharp
// Program.cs
builder.Services.AddHttpClient<IExternalApiClient, ExternalApiClient>(client =>
{
    client.BaseAddress = new Uri(builder.Configuration["SistemaAApi:BaseUrl"]!);
    client.Timeout = TimeSpan.FromSeconds(30);
    client.DefaultRequestHeaders.Add("Accept", "application/json");
    client.DefaultRequestHeaders.Add("User-Agent", "MyApp/1.0");
})
.ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler
{
    // Configuración avanzada si es necesaria
    AutomaticDecompression = System.Net.DecompressionMethods.All,
    MaxConnectionsPerServer = 10
})
.AddPolicyHandler(GetRetryPolicy())  // Polly policies
.AddPolicyHandler(GetCircuitBreakerPolicy());
```

### Implementación del Cliente

```csharp
public interface IExternalApiClient
{
    Task<StudentDto?> GetStudentAsync(string studentId, CancellationToken ct = default);
    Task<IReadOnlyList<CourseDto>> GetCoursesAsync(CancellationToken ct = default);
}

public class ExternalApiClient : IExternalApiClient
{
    private readonly HttpClient _httpClient;
    private readonly ILogger<ExternalApiClient> _logger;

    public ExternalApiClient(HttpClient httpClient, ILogger<ExternalApiClient> logger)
    {
        _httpClient = httpClient;
        _logger = logger;
    }

    public async Task<StudentDto?> GetStudentAsync(string studentId, CancellationToken ct = default)
    {
        try
        {
            _logger.LogInformation("Obteniendo student {StudentId} del sistema externo", studentId);

            var response = await _httpClient.GetAsync($"students/{studentId}", ct);

            if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
            {
                _logger.LogWarning("Student {StudentId} no encontrado en SistemaA", studentId);
                return null;
            }

            response.EnsureSuccessStatusCode();

            var student = await response.Content.ReadFromJsonAsync<StudentDto>(ct);

            _logger.LogInformation("Student {StudentId} obtenido correctamente", studentId);

            return student;
        }
        catch (HttpRequestException ex)
        {
            _logger.LogError(ex, "Error HTTP al obtener student {StudentId}", studentId);
            throw;
        }
        catch (TaskCanceledException ex)
        {
            _logger.LogError(ex, "Timeout al obtener student {StudentId}", studentId);
            throw;
        }
    }

    public async Task<IReadOnlyList<CourseDto>> GetCoursesAsync(CancellationToken ct = default)
    {
        var response = await _httpClient.GetAsync("courses", ct);
        response.EnsureSuccessStatusCode();

        var courses = await response.Content.ReadFromJsonAsync<List<CourseDto>>(ct);
        return courses ?? new List<CourseDto>();
    }
}
```

### Uso en Controller/Service

```csharp
public class StudentsController : ControllerBase
{
    private readonly IExternalApiClient _externalApiClient;

    public StudentsController(IExternalApiClient externalApiClient)
    {
        _externalApiClient = externalApiClient;
    }

    [HttpGet("{id}")]
    public async Task<ActionResult<StudentDto>> GetStudent(string id, CancellationToken ct)
    {
        var student = await _externalApiClient.GetStudentAsync(id, ct);
        return student is null ? NotFound() : Ok(student);
    }
}
```

---

## 2. Named Client

### Configuración

```csharp
// Program.cs
builder.Services.AddHttpClient("SistemaAApi", client =>
{
    client.BaseAddress = new Uri(builder.Configuration["SistemaAApi:BaseUrl"]!);
    client.Timeout = TimeSpan.FromSeconds(30);
});

builder.Services.AddHttpClient("SistemaBApi", client =>
{
    client.BaseAddress = new Uri(builder.Configuration["SistemaBApi:BaseUrl"]!);
    client.Timeout = TimeSpan.FromSeconds(45);
});
```

### Uso

```csharp
public class IntegrationService
{
    private readonly IHttpClientFactory _httpClientFactory;

    public IntegrationService(IHttpClientFactory httpClientFactory)
    {
        _httpClientFactory = httpClientFactory;
    }

    public async Task<string> CallSistemaAAsync()
    {
        var client = _httpClientFactory.CreateClient("SistemaAApi");
        return await client.GetStringAsync("students");
    }
}
```

---

## 3. Basic Client

### Configuración

```csharp
// Program.cs
builder.Services.AddHttpClient();
```

### Uso

```csharp
public class MiServicio
{
    private readonly IHttpClientFactory _httpClientFactory;

    public MiServicio(IHttpClientFactory httpClientFactory)
    {
        _httpClientFactory = httpClientFactory;
    }

    public async Task<string> CallApiAsync()
    {
        var client = _httpClientFactory.CreateClient();
        return await client.GetStringAsync("https://api.example.org/data");
    }
}
```

---

## 🔧 Configuración Avanzada

### Headers Personalizados

```csharp
builder.Services.AddHttpClient<IExternalApiClient, ExternalApiClient>(client =>
{
    client.DefaultRequestHeaders.Add("X-API-Key", builder.Configuration["SistemaAApi:ApiKey"]);
    client.DefaultRequestHeaders.Add("X-Tenant-Id", "myorg");
});
```

### Delegating Handlers

```csharp
public class AuthenticationHandler : DelegatingHandler
{
    private readonly ITokenService _tokenService;

    public AuthenticationHandler(ITokenService tokenService)
    {
        _tokenService = tokenService;
    }

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        var token = await _tokenService.GetAccessTokenAsync(cancellationToken);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);

        return await base.SendAsync(request, cancellationToken);
    }
}

// Registro
builder.Services.AddTransient<AuthenticationHandler>();

builder.Services.AddHttpClient<IExternalApiClient, ExternalApiClient>()
    .AddHttpMessageHandler<AuthenticationHandler>();
```

---

## 📊 Beneficios

| Aspecto | Sin Factory | Con Factory |
|---------|-------------|-------------|
| **Socket Exhaustion** | ❌ Común | ✅ Evitado |
| **DNS Updates** | ❌ No detecta | ✅ Detecta automáticamente |
| **Memory** | ❌ Leaks | ✅ Pool gestionado |
| **Lifecycle** | ❌ Manual | ✅ Automático |
| **Testability** | ⚠️ Difícil | ✅ Fácil (mock IHttpClientFactory) |

---

## 🧪 Testing

### Mock del Cliente Typed

```csharp
public class ExternalApiClientTests
{
    [Fact]
    public async Task GetStudent_Success_ReturnsStudent()
    {
        // Arrange
        var mockHandler = new Mock<HttpMessageHandler>();
        mockHandler
            .Protected()
            .Setup<Task<HttpResponseMessage>>(
                "SendAsync",
                ItExpr.IsAny<HttpRequestMessage>(),
                ItExpr.IsAny<CancellationToken>())
            .ReturnsAsync(new HttpResponseMessage
            {
                StatusCode = HttpStatusCode.OK,
                Content = new StringContent(JsonSerializer.Serialize(new StudentDto { Id = "123" }))
            });

        var httpClient = new HttpClient(mockHandler.Object)
        {
            BaseAddress = new Uri("https://api.test/")
        };

        var logger = new Mock<ILogger<ExternalApiClient>>();
        var sut = new ExternalApiClient(httpClient, logger.Object);

        // Act
        var result = await sut.GetStudentAsync("123");

        // Assert
        result.Should().NotBeNull();
        result!.Id.Should().Be("123");
    }
}
```

---

## 📚 Referencias

- [HttpClientFactory docs](https://learn.microsoft.com/en-us/dotnet/core/extensions/httpclient-factory)
- [Best practices](https://learn.microsoft.com/en-us/dotnet/architecture/microservices/implement-resilient-applications/use-httpclientfactory-to-implement-resilient-http-requests)

---

*Pattern: httpclient-factory - Ovillo v3.7.0*
