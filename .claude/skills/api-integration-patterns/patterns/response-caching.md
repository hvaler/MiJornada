# Pattern: Response Caching

> **Pattern**: Response Caching
> **Problema**: Llamadas repetidas a datos que no cambian frecuentemente
> **Solución**: IMemoryCache / IDistributedCache con políticas de invalidación

---

## 🎯 Problema

Llamadas API repetidas para datos estáticos:
- **Catálogos** (países, universidades, asignaturas)
- **Configuración** (tarifas, convocatorias)
- **Datos de referencia** (códigos postales, monedas)

```csharp
// ❌ Sin caché - llama API cada vez
public async Task<List<UniversityDto>> GetUniversitiesAsync()
{
    // Llama SistemaA API en cada request (latencia 500ms)
    return await _externalApiClient.GetUniversitiesAsync();
}
```

---

## ✅ Solución: Response Caching

### Estrategias de Caché

| Estrategia | Uso | TTL típico |
|------------|-----|------------|
| **In-Memory** | Datos de configuración | 5-60 min |
| **Distributed (Redis)** | Multi-instancia, alta escala | 1-24 horas |
| **HTTP Cache-Control** | Browser/CDN caching | 5 min - 1 día |

---

## 1. In-Memory Cache (IMemoryCache)

### Configuración

```csharp
// Program.cs
builder.Services.AddMemoryCache();
```

### Implementación

```csharp
public class UniversityService : IUniversityService
{
    private readonly IExternalApiClient _externalApiClient;
    private readonly IMemoryCache _cache;
    private readonly ILogger<UniversityService> _logger;

    public UniversityService(
        IExternalApiClient externalApiClient,
        IMemoryCache cache,
        ILogger<UniversityService> logger)
    {
        _externalApiClient = externalApiClient;
        _cache = cache;
        _logger = logger;
    }

    public async Task<List<UniversityDto>> GetUniversitiesAsync(CancellationToken ct = default)
    {
        const string cacheKey = "universidades";

        // 1. Intentar obtener desde caché
        if (_cache.TryGetValue(cacheKey, out List<UniversityDto>? cachedData))
        {
            _logger.LogDebug("Universities obtenidas desde caché");
            return cachedData!;
        }

        _logger.LogInformation("Universities NO en caché, consultando SistemaA API");

        // 2. Si no está en caché, consultar API
        var universidades = await _externalApiClient.GetUniversitiesAsync(ct);

        // 3. Guardar en caché con expiración
        var cacheOptions = new MemoryCacheEntryOptions
        {
            AbsoluteExpirationRelativeToNow = TimeSpan.FromHours(1),
            SlidingExpiration = TimeSpan.FromMinutes(30)
        };

        _cache.Set(cacheKey, universidades, cacheOptions);

        _logger.LogInformation("{Count} universidades cacheadas por 1 hora", universidades.Count);

        return universidades;
    }

    // Invalidar caché cuando se actualiza una universidad
    public async Task UpdateUniversityAsync(int id, UpdateUniversityRequest request, CancellationToken ct)
    {
        await _externalApiClient.UpdateUniversityAsync(id, request, ct);

        // Invalidar caché
        _cache.Remove("universidades");
        _logger.LogInformation("Caché de universidades invalidado tras actualización");
    }
}
```

---

## 2. Distributed Cache (Redis)

### Configuración

```csharp
// Program.cs
builder.Services.AddStackExchangeRedisCache(options =>
{
    options.Configuration = builder.Configuration.GetConnectionString("Redis");
    options.InstanceName = "MyApp:";
});
```

### Implementación

```csharp
public class UniversityService : IUniversityService
{
    private readonly IExternalApiClient _externalApiClient;
    private readonly IDistributedCache _cache;
    private readonly ILogger<UniversityService> _logger;

    public async Task<List<UniversityDto>> GetUniversitiesAsync(CancellationToken ct = default)
    {
        const string cacheKey = "universidades";

        // 1. Intentar obtener desde Redis
        var cachedData = await _cache.GetStringAsync(cacheKey, ct);

        if (!string.IsNullOrEmpty(cachedData))
        {
            _logger.LogDebug("Universities obtenidas desde Redis");
            return JsonSerializer.Deserialize<List<UniversityDto>>(cachedData)!;
        }

        _logger.LogInformation("Universities NO en Redis, consultando SistemaA API");

        // 2. Consultar API
        var universidades = await _externalApiClient.GetUniversitiesAsync(ct);

        // 3. Guardar en Redis
        var cacheOptions = new DistributedCacheEntryOptions
        {
            AbsoluteExpirationRelativeToNow = TimeSpan.FromHours(24),
            SlidingExpiration = TimeSpan.FromHours(2)
        };

        await _cache.SetStringAsync(
            cacheKey,
            JsonSerializer.Serialize(universidades),
            cacheOptions,
            ct);

        _logger.LogInformation("{Count} universidades cacheadas en Redis por 24 horas", universidades.Count);

        return universidades;
    }
}
```

### appsettings.json

```json
{
  "ConnectionStrings": {
    "Redis": "localhost:6379,abortConnect=false"
  }
}
```

---

## 3. Cache Aside Pattern

### Helper Genérico

```csharp
public static class CacheHelper
{
    public static async Task<T> GetOrCreateAsync<T>(
        this IMemoryCache cache,
        string key,
        Func<Task<T>> factory,
        TimeSpan? absoluteExpiration = null,
        TimeSpan? slidingExpiration = null)
    {
        if (cache.TryGetValue(key, out T? cachedValue))
            return cachedValue!;

        var value = await factory();

        var options = new MemoryCacheEntryOptions();

        if (absoluteExpiration.HasValue)
            options.AbsoluteExpirationRelativeToNow = absoluteExpiration.Value;

        if (slidingExpiration.HasValue)
            options.SlidingExpiration = slidingExpiration.Value;

        cache.Set(key, value, options);

        return value;
    }
}

// Uso
public async Task<List<UniversityDto>> GetUniversitiesAsync(CancellationToken ct = default)
{
    return await _cache.GetOrCreateAsync(
        "universidades",
        () => _externalApiClient.GetUniversitiesAsync(ct),
        absoluteExpiration: TimeSpan.FromHours(1));
}
```

---

## 4. HTTP Response Caching

### Configuración en Program.cs

```csharp
// Program.cs
builder.Services.AddResponseCaching();

var app = builder.Build();

app.UseResponseCaching();
app.UseHttpCacheHeaders(); // Opcional: Marvin.Cache.Headers
```

### Controller con Cache

```csharp
[ApiController]
[Route("api/[controller]")]
public class UniversitiesController : ControllerBase
{
    [HttpGet]
    [ResponseCache(Duration = 600)] // Cache 10 minutos
    public async Task<ActionResult<List<UniversityDto>>> GetAll(CancellationToken ct)
    {
        var universidades = await _service.GetUniversitiesAsync(ct);
        return Ok(universidades);
    }

    [HttpGet("{id}")]
    [ResponseCache(VaryByHeader = "User-Agent", Duration = 300)]
    public async Task<ActionResult<UniversityDto>> GetById(int id, CancellationToken ct)
    {
        var universidad = await _service.GetByIdAsync(id, ct);
        return universidad is null ? NotFound() : Ok(universidad);
    }
}
```

---

## 5. Cache-Control Headers

### Configuración Personalizada

```csharp
[HttpGet]
public async Task<ActionResult<List<UniversityDto>>> GetAll()
{
    var universidades = await _service.GetUniversitiesAsync();

    // Cache-Control personalizado
    Response.Headers.CacheControl = "public, max-age=600, s-maxage=1800";
    Response.Headers.Expires = DateTime.UtcNow.AddMinutes(10).ToString("R");
    Response.Headers.ETag = GenerateETag(universidades);

    return Ok(universidades);
}

private string GenerateETag(object data)
{
    var json = JsonSerializer.Serialize(data);
    var hash = MD5.HashData(Encoding.UTF8.GetBytes(json));
    return Convert.ToBase64String(hash);
}
```

---

## 6. Invalidación de Caché

### Estrategias

#### Por Tiempo (TTL)

```csharp
// Automático con AbsoluteExpiration
var options = new MemoryCacheEntryOptions
{
    AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(30)
};
```

#### Por Evento (Manual)

```csharp
public async Task UpdateUniversityAsync(int id, UpdateRequest request, CancellationToken ct)
{
    await _externalApiClient.UpdateAsync(id, request, ct);

    // Invalidar caché específico
    _cache.Remove($"universidad:{id}");

    // Invalidar caché de lista
    _cache.Remove("universidades");
}
```

#### Por Patrón (Redis)

```csharp
public async Task InvalidarCachePorPatronAsync(string pattern)
{
    // Ejemplo: invalidar "universidad:*"
    var redis = ConnectionMultiplexer.Connect(connectionString);
    var server = redis.GetServer(redis.GetEndPoints().First());

    foreach (var key in server.Keys(pattern: $"MyApp:{pattern}"))
    {
        await _cache.RemoveAsync(key.ToString());
    }
}
```

---

## 📊 Comparativa

| Tipo | Latencia | Persistencia | Multi-instancia | Uso |
|------|----------|--------------|-----------------|-----|
| **IMemoryCache** | <1ms | En proceso | ❌ | Datos temporales, single instance |
| **Redis** | ~5ms | Sí | ✅ | Producción, multi-instance |
| **HTTP Cache** | ~0ms (browser) | No | ✅ | Datos públicos, CDN |

---

## ⚠️ Consideraciones

### ✅ Cachear

- Datos de catálogo (países, monedas)
- Configuración estática
- Resultados de cálculos pesados
- Listados con paginación

### ❌ NO Cachear

- Datos sensibles (usuarios, contraseñas)
- Datos en tiempo real (stock, precios)
- Datos personalizados por usuario (sin VaryBy)
- Respuestas con datos dinámicos

---

## 🧪 Testing

```csharp
[Fact]
public async Task GetUniversities_CachesResponse()
{
    // Arrange
    var mockClient = new Mock<IExternalApiClient>();
    mockClient
        .Setup(c => c.GetUniversitiesAsync(It.IsAny<CancellationToken>()))
        .ReturnsAsync(new List<UniversityDto> { new() { Id = 1, Name = "Test" } });

    var cache = new MemoryCache(new MemoryCacheOptions());
    var sut = new UniversityService(mockClient.Object, cache, Mock.Of<ILogger<UniversityService>>());

    // Act - Primera llamada
    var result1 = await sut.GetUniversitiesAsync();

    // Act - Segunda llamada
    var result2 = await sut.GetUniversitiesAsync();

    // Assert
    mockClient.Verify(c => c.GetUniversitiesAsync(It.IsAny<CancellationToken>()), Times.Once); // Solo 1 llamada API
    result1.Should().BeEquivalentTo(result2);
}
```

---

## 📚 Referencias

- [Response Caching](https://learn.microsoft.com/en-us/aspnet/core/performance/caching/response)
- [Distributed Caching](https://learn.microsoft.com/en-us/aspnet/core/performance/caching/distributed)

---

*Pattern: response-caching - Ovillo v3.7.0*
