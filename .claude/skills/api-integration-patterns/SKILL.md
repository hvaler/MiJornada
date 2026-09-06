---
name: api-integration-patterns
description: >
  Implements REST API integration patterns for external systems from the
  configured catalog (ecosystem.config.json -> integrations[] and
  ESTADO_PROYECTO.json -> dominiosExternos[]) and custom APIs:
  HttpClientFactory, OAuth2 client credentials, retry, circuit breaker,
  response caching, API versioning.
  USE FOR: REST API integration, HttpClientFactory patterns, external
  systems integration, OAuth2 client implementation, integrar API,
  consumir API, conectar sistema externo, API de RRHH/academica/nominas.
  DO NOT USE FOR: security auditing (use security-audit), Postman collections
  (use postman-collection), API contract validation (use api-contract-validator agent).
---

> **Skill**: api-integration-patterns
> **Version**: 1.0.0
> **Categoria**: Integracion
> **Auto-invocacion**: Si

---

## Descripcion

Skill especializado en **patrones de integracion con APIs REST externas**. Proporciona patterns, templates y ejemplos para consumir:
- **Sistemas externos del catalogo configurado** (`ecosystem.config.json → integrations[]` a nivel organizacion; `ESTADO_PROYECTO.json → dominiosExternos[]` a nivel proyecto — vacios por defecto, el fork no asume ninguno)
- **APIs REST genericas** (autenticacion, retry, circuit breaker)

---

## Triggers de Auto-Invocacion

Este skill se auto-invoca cuando el usuario menciona:

### Keywords principales
- "integrar con [sistema externo del catalogo]"
- "consumir API de [proveedor]"
- "integracion REST"
- "HttpClient factory"
- "retry policy"
- "circuit breaker"
- "OAuth2 client credentials"
- "API externa"

### Contexto de integracion
- "necesito conectar con [sistema externo]"
- "como consumo la API de [proveedor]"
- "patron para llamadas HTTP"
- "gestionar tokens de autenticacion"
- "reintentos automaticos"
- "manejo de errores API"

### Escenarios tipicos
- **Nuevo proyecto con integracion**: "Crear proyecto que consuma la API externa X"
- **Refactorizar HttpClient**: "Mejorar llamadas HTTP actuales"
- **Añadir resiliencia**: "Añadir retry policy a llamadas API"
- **OAuth2 flow**: "Implementar autenticacion OAuth2"

---

## Estructura del Skill

```
api-integration-patterns/
├── SKILL.md                          ← Este archivo
├── references/
│   └── integration-examples.md       ← Detalle de patterns, templates, examples, casos de uso
├── patterns/
│   ├── httpclient-factory.md         ← Patron HttpClient typed/named
│   ├── retry-policy.md               ← Polly retry policies
│   ├── circuit-breaker.md            ← Circuit breaker pattern
│   ├── oauth2-client-credentials.md  ← OAuth2 flow
│   ├── response-caching.md           ← Cache de respuestas
│   └── api-versioning.md             ← Versionado de APIs
├── templates/
│   ├── ApiClient.cs.template         ← Cliente base generico
│   ├── ExternalApiClient.cs.template ← Cliente tipado de sistema externo (instanciar por cada entrada del catalogo)
│   ├── ApiOptions.cs.template        ← Configuracion IOptions
│   ├── ApiResponse.cs.template       ← Wrapper respuesta generica
│   └── DelegatingHandler.cs.template ← Handler logging/auth
├── examples/
│   ├── external-api-example.md       ← Ejemplo completo de integracion con sistema externo
│   └── polly-advanced.md             ← Polly avanzado (WaitAndRetry)
├── checklists/
│   ├── api-integration-checklist.md  ← Checklist integracion
│   └── security-checklist.md         ← Checklist seguridad APIs
└── scripts/
    ├── Test-ApiConnection.ps1        ← Script test conexion API
    └── Generate-ApiClient.ps1        ← Generator cliente desde OpenAPI
```

**Total estimado**: ~17 archivos

---

## Como Usar Este Skill

### Invocacion manual
```bash
claude> Ayudame a integrar con el sistema externo usando OAuth2
```

### Invocacion automatica
```bash
# Usuario escribe:
"Necesito consumir la API de el SaaS de RRHH del catalogo para obtener empleados"

# Claude detecta y activa el skill automaticamente
# Proporciona:
# 1. Pattern OAuth2 client credentials
# 2. Template ExternalApiClient.cs
# 3. Ejemplo external-api-example.md
# 4. Checklist de seguridad
```

---

## Contenido Clave y Casos de Uso

> Detalle completo de patterns, templates, examples, checklists y casos de uso en `references/integration-examples.md`

### Resumen de recursos

| Tipo | Cantidad | Descripcion |
|------|----------|-------------|
| **Patterns** | 6 | HttpClientFactory, Retry, Circuit Breaker, OAuth2, Caching, Versioning |
| **Templates** | 5 | ApiClient, ExternalApiClient, Options, Response, DelegatingHandler |
| **Examples** | 2 | Integracion con sistema externo, Polly avanzado |
| **Checklists** | 2 | Integracion + Seguridad |
| **Scripts** | 2 | Test-ApiConnection + Generate-ApiClient |

---

## Configuracion Recomendada

### appsettings.json
```json
{
  "SistemaAApi": {
    "BaseUrl": "https://external-api.example.org/api",
    "ClientId": "myorg-app",
    "ClientSecret": "{{KeyVault}}",
    "TimeoutSeconds": 30,
    "RetryCount": 3,
    "CircuitBreakerThreshold": 5
  },
  "SistemaBApi": {
    "BaseUrl": "https://hcm.example.org/api",
    "ClientId": "{{KeyVault}}",
    "ClientSecret": "{{KeyVault}}",
    "TimeoutSeconds": 45,
    "CacheDurationMinutes": 60
  }
}
```

### Program.cs
```csharp
// HttpClient typed
builder.Services.AddHttpClient<IExternalApiClient, ExternalApiClient>()
    .ConfigureHttpClient(c => {
        c.BaseAddress = new Uri(builder.Configuration["SistemaAApi:BaseUrl"]);
        c.Timeout = TimeSpan.FromSeconds(30);
    })
    .AddPolicyHandler(GetRetryPolicy())
    .AddPolicyHandler(GetCircuitBreakerPolicy());

// Polly v8 resilience pipeline
static IAsyncPolicy<HttpResponseMessage> GetRetryPolicy()
{
    return HttpPolicyExtensions
        .HandleTransientHttpError()
        .WaitAndRetryAsync(3, retryAttempt =>
            TimeSpan.FromSeconds(Math.Pow(2, retryAttempt)));
}
```

---

## Metricas de Exito

- **Tiempo integracion**: Reduccion 60% (vs implementar desde cero)
- **Errores transitorios**: Manejo automatico con retry
- **Socket exhaustion**: Eliminado con HttpClientFactory
- **Seguridad**: 100% secretos en Key Vault
- **Cobertura tests**: >80% en clientes API
- **Documentacion**: Endpoints documentados en Patrón

---

## Skills Relacionados

- `cloud-config` - Configuracion Key Vault para secretos
- `testing-patterns` - Tests con MockHttpMessageHandler
- `observability-patterns` - Telemetria llamadas API
- `security-audit` - Validacion OWASP API Security

---

## Referencias

- [HttpClientFactory docs](https://learn.microsoft.com/en-us/dotnet/architecture/microservices/implement-resilient-applications/use-httpclientfactory-to-implement-resilient-http-requests)
- [Polly v8](https://www.pollydocs.org/)
- [OAuth2 Client Credentials](https://oauth.net/2/grant-types/client-credentials/)
- [OWASP API Security](https://owasp.org/www-project-api-security/)

---

*Version 1.0.0 - Skill creado como parte de Ovillo v3.7.0*
