---
name: cloud-config
description: >
  Configures cloud services for .NET applications according to the
  configured provider (ecosystem.config.json -> cloud.provider:
  azure|aws|gcp|none): secrets management (Key Vault / Secrets Manager /
  GSM), file storage (Blob / S3 / GCS), Redis distributed cache,
  telemetry (App Insights / CloudWatch / OTLP), managed identities,
  messaging and serverless. Deep-dive provider currently documented: Azure.
  USE FOR: cloud service setup, Azure Key Vault setup, AWS Secrets Manager,
  Blob Storage / S3 configuration, Application Insights, IdP app
  registration, configurar cloud, configurar Azure, Key Vault, secretos en
  produccion, App Insights.
  DO NOT USE FOR: security auditing (use security-audit),
  IdP deep audit (use identity-auditor agent),
  RBAC policy design (use rbac-designer agent).
---

# Configuración Cloud

Este skill ayuda a configurar los servicios cloud del proveedor definido en
`ecosystem.config.json → cloud.*` (default `none` = sin asunción cloud). El contenido de
referencia detallado cubre el provider **azure**; para `aws`/`gcp` aplicar los mismos patrones
con los servicios homólogos (`cloud.secrets`/`cloud.storage`/`cloud.telemetry` indican cuáles).

---

## Servicios Cubiertos

| Servicio (provider azure) | Uso | Obligatoriedad |
|----------|-----|----------------|
| **Azure Key Vault** | Secretos y certificados | Si `cloud.secrets=keyvault`: objetivo en producción |
| **Azure Blob Storage** | Almacenamiento de archivos | Si `cloud.storage=blob` e infra balanceada: no usar disco local |
| **Redis Cache** | Caché distribuida y sesiones | Recomendado |
| **Application Insights** | Telemetría y logging | Recomendado |

---

## 1. Azure Key Vault

### Configuración Program.cs

```csharp
// .NET 10
var builder = WebApplication.CreateBuilder(args);

// Cargar Key Vault en producción
if (!builder.Environment.IsDevelopment())
{
    var keyVaultUrl = builder.Configuration["KeyVault:Url"];
    if (!string.IsNullOrEmpty(keyVaultUrl))
    {
        builder.Configuration.AddAzureKeyVault(
            new Uri(keyVaultUrl),
            new DefaultAzureCredential());
    }
}
```

### appsettings.Production.json

```json
{
  "KeyVault": {
    "Url": "https://kv-myorg-[proyecto].vault.azure.net/"
  }
}
```

### Secretos a Almacenar

| Secreto | Nombre en Key Vault | Ejemplo |
|---------|---------------------|---------|
| Connection string BD | `ConnectionStrings--DefaultConnection` | Server=... |
| API keys externas | `ExternalApi--ApiKey` | sk-... |
| Certificados | `Certificates--[Nombre]` | Base64 |

---

## 2. Azure Blob Storage

### Servicio de Almacenamiento

```csharp
public interface IBlobStorageService
{
    Task<string> UploadAsync(Stream stream, string fileName, string container, CancellationToken ct = default);
    Task<Stream?> DownloadAsync(string blobName, string container, CancellationToken ct = default);
    Task DeleteAsync(string blobName, string container, CancellationToken ct = default);
    Task<bool> ExistsAsync(string blobName, string container, CancellationToken ct = default);
}

public class BlobStorageService : IBlobStorageService
{
    private readonly BlobServiceClient _blobServiceClient;
    private readonly ILogger<BlobStorageService> _logger;

    public BlobStorageService(
        BlobServiceClient blobServiceClient,
        ILogger<BlobStorageService> logger)
    {
        _blobServiceClient = blobServiceClient;
        _logger = logger;
    }

    public async Task<string> UploadAsync(
        Stream stream,
        string fileName,
        string container,
        CancellationToken ct = default)
    {
        var containerClient = _blobServiceClient.GetBlobContainerClient(container);
        await containerClient.CreateIfNotExistsAsync(cancellationToken: ct);

        var blobName = $"{Guid.NewGuid()}/{fileName}";
        var blobClient = containerClient.GetBlobClient(blobName);

        await blobClient.UploadAsync(stream, overwrite: true, cancellationToken: ct);

        _logger.LogInformation("Archivo {FileName} subido a {Container}/{BlobName}",
            fileName, container, blobName);

        return blobName;
    }

    public async Task<Stream?> DownloadAsync(
        string blobName,
        string container,
        CancellationToken ct = default)
    {
        var containerClient = _blobServiceClient.GetBlobContainerClient(container);
        var blobClient = containerClient.GetBlobClient(blobName);

        if (!await blobClient.ExistsAsync(ct))
            return null;

        var response = await blobClient.DownloadStreamingAsync(cancellationToken: ct);
        return response.Value.Content;
    }

    public async Task DeleteAsync(
        string blobName,
        string container,
        CancellationToken ct = default)
    {
        var containerClient = _blobServiceClient.GetBlobContainerClient(container);
        var blobClient = containerClient.GetBlobClient(blobName);

        await blobClient.DeleteIfExistsAsync(cancellationToken: ct);

        _logger.LogInformation("Archivo {BlobName} eliminado de {Container}",
            blobName, container);
    }

    public async Task<bool> ExistsAsync(
        string blobName,
        string container,
        CancellationToken ct = default)
    {
        var containerClient = _blobServiceClient.GetBlobContainerClient(container);
        var blobClient = containerClient.GetBlobClient(blobName);

        return await blobClient.ExistsAsync(ct);
    }
}
```

### Registro en DI

```csharp
// Program.cs
builder.Services.AddAzureClients(clientBuilder =>
{
    clientBuilder.AddBlobServiceClient(
        builder.Configuration.GetConnectionString("BlobStorage"));
});

builder.Services.AddScoped<IBlobStorageService, BlobStorageService>();
```

---

## 3. Redis Cache

### Configuración

```csharp
// Program.cs
builder.Services.AddStackExchangeRedisCache(options =>
{
    options.Configuration = builder.Configuration.GetConnectionString("Redis");
    options.InstanceName = "MyApp_";
});

// Uso como caché distribuida
builder.Services.AddSession(options =>
{
    options.IdleTimeout = TimeSpan.FromMinutes(30);
    options.Cookie.HttpOnly = true;
    options.Cookie.IsEssential = true;
});
```

### Uso del Cache

```csharp
public class ScholarshipService
{
    private readonly IDistributedCache _cache;
    private readonly IScholarshipRepository _repository;

    public async Task<ScholarshipDto?> GetByIdAsync(int id, CancellationToken ct)
    {
        var cacheKey = $"scholarship:{id}";

        // Intentar obtener de caché
        var cached = await _cache.GetStringAsync(cacheKey, ct);
        if (cached != null)
        {
            return JsonSerializer.Deserialize<ScholarshipDto>(cached);
        }

        // Obtener de BD
        var scholarship = await _repository.GetByIdAsync(id, ct);
        if (scholarship == null) return null;

        var dto = MapToDto(scholarship);

        // Guardar en caché (5 minutos)
        await _cache.SetStringAsync(
            cacheKey,
            JsonSerializer.Serialize(dto),
            new DistributedCacheEntryOptions
            {
                AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(5)
            },
            ct);

        return dto;
    }
}
```

---

## 4. Application Insights

### Configuración

```csharp
// Program.cs
builder.Services.AddApplicationInsightsTelemetry(options =>
{
    options.ConnectionString = builder.Configuration["ApplicationInsights:ConnectionString"];
});

// Telemetría personalizada
builder.Services.AddSingleton<ITelemetryInitializer, CustomTelemetryInitializer>();
```

### Telemetría Personalizada

```csharp
public class CustomTelemetryInitializer : ITelemetryInitializer
{
    public void Initialize(ITelemetry telemetry)
    {
        telemetry.Context.Cloud.RoleName = "MyCompany.MyApp";
        telemetry.Context.GlobalProperties["Environment"] =
            Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") ?? "Unknown";
    }
}
```

### Tracking de Eventos

```csharp
public class ScholarshipService
{
    private readonly TelemetryClient _telemetry;

    public async Task<ScholarshipDto> CreateAsync(CreateScholarshipRequest request, CancellationToken ct)
    {
        // ... crear scholarship ...

        _telemetry.TrackEvent("ScholarshipCreated", new Dictionary<string, string>
        {
            ["ScholarshipId"] = scholarship.Id.ToString(),
            ["Name"] = scholarship.Name,
            ["Amount"] = scholarship.Amount.ToString("F2")
        });

        return dto;
    }
}
```

---

## Entorno de Desarrollo (Docker)

### docker-compose.yml

```yaml
version: '3.8'

services:
  sqlserver:
    image: mcr.microsoft.com/mssql/server:2022-latest
    ports:
      - "1433:1433"
    environment:
      - ACCEPT_EULA=Y
      - MSSQL_SA_PASSWORD=YourStrong@Passw0rd
      - MSSQL_PID=Developer
      - MSSQL_COLLATION=SQL_Latin1_General_CP1250_CI_AS

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"

  azurite:
    image: mcr.microsoft.com/azure-storage/azurite
    ports:
      - "10000:10000"  # Blob
      - "10001:10001"  # Queue
      - "10002:10002"  # Table
    command: "azurite --blobHost 0.0.0.0 --queueHost 0.0.0.0 --tableHost 0.0.0.0"

  mailhog:
    image: mailhog/mailhog
    ports:
      - "1025:1025"  # SMTP
      - "8025:8025"  # Web UI
```

### appsettings.Development.json

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Server=localhost;Database=MyApp;User=sa;Password=YourStrong@Passw0rd;TrustServerCertificate=True",
    "Redis": "localhost:6379",
    "BlobStorage": "UseDevelopmentStorage=true"
  }
}
```

---

## Checklist de Configuración

### Key Vault
- [ ] URL configurada en appsettings.Production.json
- [ ] Managed Identity habilitada
- [ ] Secretos migrados a Key Vault
- [ ] Sin secretos en código

### Blob Storage
- [ ] IBlobStorageService implementado
- [ ] Contenedores creados
- [ ] Sin uso de disco local
- [ ] Cleanup de archivos temporales

### Redis
- [ ] Connection string configurada
- [ ] Sesiones usando Redis
- [ ] Cache de consultas frecuentes
- [ ] TTL configurado

### Application Insights
- [ ] Connection string configurada
- [ ] Eventos personalizados
- [ ] Métricas de negocio
- [ ] Alertas configuradas

---

*Skill cloud-config v3.7.0*
