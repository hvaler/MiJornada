# Example: Integración Completa con ExternalApi API

> **Caso de uso**: Matricular estudiante en un curso desde aplicación de la organización
> **API**: ExternalApi (Ellucian)
> **Autenticación**: OAuth2 Client Credentials
> **Resiliencia**: Retry + Circuit Breaker

---

## 📋 Requisitos

- ExternalApi API endpoint: `https://external-api.example.org/api`
- OAuth2 Token URL: `https://auth.example.org/oauth/token`
- Client ID / Client Secret (solicitar al equipo de integraciones)
- Scopes: `students:read`, `courses:read`, `enrollments:write`

---

## 1. Configuración (appsettings.json)

```json
{
  "ExternalApiApi": {
    "BaseUrl": "https://external-api.example.org/api",
    "TimeoutSeconds": 30,
    "MaxRetries": 3,
    "ClientId": "myorg-app",
    "ClientSecret": "{{KeyVault}}",
    "TokenUrl": "https://auth.example.org/oauth/token",
    "Scope": "students:read courses:read enrollments:write"
  }
}
```

---

## 2. Registro en Program.cs

```csharp
using Polly;
using Polly.Extensions.Http;

// Opciones con validación
builder.Services.AddExternalApiApiOptions(builder.Configuration);

// Token Service
builder.Services.AddHttpClient<ITokenService, TokenService>();
builder.Services.AddMemoryCache();

// Handlers
builder.Services.AddTransient<BearerTokenHandler>();
builder.Services.AddTransient<CorrelationIdHandler>();
builder.Services.AddTransient<LoggingHandler>();

// ExternalApi Client con handlers y políticas
builder.Services.AddHttpClient<IExternalApiClient, ExternalApiClient>((sp, client) =>
{
    var options = sp.GetRequiredService<IOptions<ExternalApiApiOptions>>().Value;
    client.BaseAddress = new Uri(options.BaseUrl);
    client.Timeout = TimeSpan.FromSeconds(options.TimeoutSeconds);
})
.AddHttpMessageHandler<CorrelationIdHandler>()
.AddHttpMessageHandler<BearerTokenHandler>()
.AddHttpMessageHandler<LoggingHandler>()
.AddPolicyHandler(GetRetryPolicy())
.AddPolicyHandler(GetCircuitBreakerPolicy());

static IAsyncPolicy<HttpResponseMessage> GetRetryPolicy()
{
    return HttpPolicyExtensions
        .HandleTransientHttpError()
        .Or<TimeoutException>()
        .WaitAndRetryAsync(
            retryCount: 3,
            sleepDurationProvider: retryAttempt => TimeSpan.FromSeconds(Math.Pow(2, retryAttempt)),
            onRetry: (outcome, timespan, retryCount, context) =>
            {
                Console.WriteLine($"Reintento {retryCount} tras {timespan.TotalSeconds}s");
            });
}

static IAsyncPolicy<HttpResponseMessage> GetCircuitBreakerPolicy()
{
    return HttpPolicyExtensions
        .HandleTransientHttpError()
        .CircuitBreakerAsync(
            handledEventsAllowedBeforeBreaking: 5,
            durationOfBreak: TimeSpan.FromSeconds(30));
}
```

---

## 3. Implementación del Cliente

```csharp
// Ver ExternalApiClient.cs.template
```

---

## 4. Service de Application

```csharp
public interface IEnrollmentService
{
    Task<EnrollmentResult> EnrollStudentAsync(string studentId, string courseId, string term);
}

public class EnrollmentService : IEnrollmentService
{
    private readonly IExternalApiClient _externalApiClient;
    private readonly ILogger<EnrollmentService> _logger;

    public EnrollmentService(IExternalApiClient externalApiClient, ILogger<EnrollmentService> logger)
    {
        _externalApiClient = externalApiClient;
        _logger = logger;
    }

    public async Task<EnrollmentResult> EnrollStudentAsync(
        string studentId,
        string courseId,
        string term)
    {
        try
        {
            // 1. Verificar que el student existe
            var student = await _externalApiClient.GetStudentAsync(studentId);
            if (student is null)
            {
                return EnrollmentResult.Failure($"Student {studentId} no encontrado");
            }

            // 2. Verificar que el curso existe
            var courses = await _externalApiClient.GetCoursesAsync(term);
            var course = courses.FirstOrDefault(c => c.Id == courseId);
            if (course is null)
            {
                return EnrollmentResult.Failure($"Curso {courseId} no encontrado para el término {term}");
            }

            // 3. Matricular
            var enrollmentRequest = new EnrollmentRequestDto(studentId, courseId, term);
            var enrollmentResponse = await _externalApiClient.EnrollStudentAsync(enrollmentRequest);

            _logger.LogInformation(
                "Student {StudentId} matriculado en {CourseId}. Enrollment ID: {EnrollmentId}",
                studentId,
                courseId,
                enrollmentResponse.EnrollmentId);

            return EnrollmentResult.Success(enrollmentResponse.EnrollmentId);
        }
        catch (HttpRequestException ex)
        {
            _logger.LogError(ex, "Error HTTP al matricular student {StudentId}", studentId);
            return EnrollmentResult.Failure("Error de comunicación con ExternalApi");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error inesperado al matricular student {StudentId}", studentId);
            return EnrollmentResult.Failure("Error inesperado");
        }
    }
}

public record EnrollmentResult(bool Success, string? EnrollmentId, string? ErrorMessage)
{
    public static EnrollmentResult Success(string enrollmentId)
        => new(true, enrollmentId, null);

    public static EnrollmentResult Failure(string errorMessage)
        => new(false, null, errorMessage);
}
```

---

## 5. Controller

```csharp
[ApiController]
[Route("api/[controller]")]
public class EnrollmentsController : ControllerBase
{
    private readonly IEnrollmentService _enrollmentService;

    public EnrollmentsController(IEnrollmentService enrollmentService)
    {
        _enrollmentService = enrollmentService;
    }

    [HttpPost]
    [ProducesResponseType<EnrollmentResponseDto>(StatusCodes.Status201Created)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status500InternalServerError)]
    public async Task<ActionResult> EnrollStudent([FromBody] EnrollStudentRequest request)
    {
        var result = await _enrollmentService.EnrollStudentAsync(
            request.StudentId,
            request.CourseId,
            request.Term);

        if (!result.Success)
        {
            return BadRequest(new ProblemDetails
            {
                Title = "Error al matricular",
                Detail = result.ErrorMessage,
                Status = StatusCodes.Status400BadRequest
            });
        }

        return CreatedAtAction(
            nameof(GetEnrollment),
            new { id = result.EnrollmentId },
            new { EnrollmentId = result.EnrollmentId });
    }

    [HttpGet("{id}")]
    public async Task<ActionResult<EnrollmentResponseDto>> GetEnrollment(string id)
    {
        // Implementar
        return NotFound();
    }
}

public record EnrollStudentRequest(string StudentId, string CourseId, string Term);
```

---

## 6. Tests Unitarios

```csharp
public class EnrollmentServiceTests
{
    private readonly Mock<IExternalApiClient> _externalApiClientMock;
    private readonly Mock<ILogger<EnrollmentService>> _loggerMock;
    private readonly EnrollmentService _sut;

    public EnrollmentServiceTests()
    {
        _externalApiClientMock = new Mock<IExternalApiClient>();
        _loggerMock = new Mock<ILogger<EnrollmentService>>();
        _sut = new EnrollmentService(_externalApiClientMock.Object, _loggerMock.Object);
    }

    [Fact]
    public async Task EnrollStudent_ValidData_ReturnsSuccess()
    {
        // Arrange
        var studentId = "12345";
        var courseId = "CS101";
        var term = "202501";

        _externalApiClientMock
            .Setup(c => c.GetStudentAsync(studentId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new StudentDto(studentId, "John", "Doe", "john@test.com", "Active"));

        _externalApiClientMock
            .Setup(c => c.GetCoursesAsync(term, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new List<CourseDto>
            {
                new(courseId, "CS-101", "Intro to CS", 6, term)
            });

        _externalApiClientMock
            .Setup(c => c.EnrollStudentAsync(
                It.Is<EnrollmentRequestDto>(r =>
                    r.StudentId == studentId && r.CourseId == courseId),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(new EnrollmentResponseDto(
                "ENR-001",
                studentId,
                courseId,
                DateTime.UtcNow,
                "Enrolled"));

        // Act
        var result = await _sut.EnrollStudentAsync(studentId, courseId, term);

        // Assert
        result.Success.Should().BeTrue();
        result.EnrollmentId.Should().Be("ENR-001");
        result.ErrorMessage.Should().BeNull();
    }

    [Fact]
    public async Task EnrollStudent_StudentNotFound_ReturnsFailure()
    {
        // Arrange
        _externalApiClientMock
            .Setup(c => c.GetStudentAsync(It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync((StudentDto?)null);

        // Act
        var result = await _sut.EnrollStudentAsync("99999", "CS101", "202501");

        // Assert
        result.Success.Should().BeFalse();
        result.ErrorMessage.Should().Contain("no encontrado");
    }
}
```

---

## 7. Ejecución y Logs

### Request HTTP

```http
POST https://external-api.example.org/api/enrollments
Authorization: Bearer eyJhbGc...
X-Correlation-ID: 550e8400-e29b-41d4-a716-446655440000
Content-Type: application/json

{
  "studentId": "12345",
  "courseId": "CS101",
  "term": "202501"
}
```

### Logs Generados

```
[2026-02-16 10:30:00] INFO - Matriculando student 12345 en curso CS101
[2026-02-16 10:30:00] DEBUG - Correlation ID: 550e8400-e29b-41d4-a716-446655440000
[2026-02-16 10:30:00] INFO - HTTP GET https://external-api.example.org/api/students/12345
[2026-02-16 10:30:00] DEBUG - Bearer token inyectado en request
[2026-02-16 10:30:00] INFO - HTTP GET responded 200 in 245ms
[2026-02-16 10:30:01] INFO - HTTP POST https://external-api.example.org/api/enrollments
[2026-02-16 10:30:01] INFO - HTTP POST responded 201 in 512ms
[2026-02-16 10:30:01] INFO - Student 12345 matriculado en CS101. Enrollment ID: ENR-001
```

---

## 📚 Referencias

- [ExternalApi API Documentation](https://external-api.example.org/api/docs)
- Pattern: oauth2-client-credentials.md
- Pattern: retry-policy.md
- Pattern: circuit-breaker.md

---

*Example: external-api-example - Ovillo v3.7.0*
