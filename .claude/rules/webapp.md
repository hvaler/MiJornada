---
globs:
  - "**/Program.cs"
  - "**/Startup.cs"
  - "**/appsettings*.json"
  - "**/Views/**/*.cshtml"
  - "**/Pages/**/*.cshtml"
  - "**/Areas/**/*.cshtml"
  - "**/*.razor"
  - "**/Components/**/*.razor"
  - "**/wwwroot/**/*"
  - "**/*.css"
  - "**/*.scss"
  - "**/*.js"
  - "**/*.ts"
---

# Reglas para Aplicaciones Web ASP.NET

> Este archivo aplica cuando Claude trabaja con aplicaciones web.
> **Detecta automáticamente** la versión de .NET del proyecto.

---

## DETECCIÓN DE VERSIÓN

Antes de aplicar reglas, Claude debe identificar la versión:

```xml
<!-- En .csproj -->
<TargetFramework>net10.0</TargetFramework>  <!-- .NET 10 -->
<TargetFramework>net9.0</TargetFramework>   <!-- .NET 9 -->
<TargetFramework>net8.0</TargetFramework>   <!-- .NET 8 -->
<TargetFramework>net48</TargetFramework>    <!-- .NET Framework 4.8 -->
```

---

## PARTE 1: CONFIGURACIÓN POR VERSIÓN

### .NET 10 (LTS - Recomendado) ✅

```csharp
// Program.cs - .NET 10 con mejoras
var builder = WebApplication.CreateBuilder(args);

// ═══════════════════════════════════════════════════════════════
// SERVICIOS - .NET 10
// ═══════════════════════════════════════════════════════════════

// Configuración tipada con validación integrada (nuevo en .NET 10)
builder.Services.AddOptionsWithValidateOnStart<AppSettings>()
    .Bind(builder.Configuration.GetSection("AppSettings"))
    .ValidateDataAnnotations();

// OpenAPI nativo (reemplaza Swashbuckle) - .NET 10
builder.Services.AddOpenApi(options =>
{
    options.AddDocumentTransformer((document, context, ct) =>
    {
        document.Info.Title = "Mi API";
        document.Info.Version = "v1";
        return Task.CompletedTask;
    });
});

// Base de datos con mejoras EF Core 10
builder.Services.AddDbContext<ApplicationDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("DefaultConnection"),
        sqlOptions => sqlOptions.UseQuerySplittingBehavior(QuerySplittingBehavior.SplitQuery)));

// Autenticación mejorada
builder.Services.AddAuthentication()
    .AddCookie(options =>
    {
        options.LoginPath = "/Account/Login";
        options.ExpireTimeSpan = TimeSpan.FromDays(30);
        options.SlidingExpiration = true;
    });

// Health checks con tags
builder.Services.AddHealthChecks()
    .AddDbContextCheck<ApplicationDbContext>("database", tags: ["ready"])
    .AddCheck("self", () => HealthCheckResult.Healthy(), tags: ["live"]);

var app = builder.Build();

// ═══════════════════════════════════════════════════════════════
// PIPELINE HTTP - .NET 10
// ═══════════════════════════════════════════════════════════════

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error");
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseStaticFiles();
app.UseRouting();

app.UseAuthentication();
app.UseAuthorization();

// OpenAPI endpoints nativos (.NET 10)
app.MapOpenApi();

// Health checks con filtros
app.MapHealthChecks("/health/ready", new() { Predicate = check => check.Tags.Contains("ready") });
app.MapHealthChecks("/health/live", new() { Predicate = check => check.Tags.Contains("live") });

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}");

app.Run();
```

### .NET 8/9 (Migrar a .NET 10)

```csharp
// Program.cs - .NET 8/9
var builder = WebApplication.CreateBuilder(args);

// Configuración
builder.Services.Configure<AppSettings>(
    builder.Configuration.GetSection("AppSettings"));

// Swagger (reemplazar por OpenAPI nativo en .NET 10)
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// Base de datos
builder.Services.AddDbContext<ApplicationDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("DefaultConnection")));

builder.Services.AddControllersWithViews();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();
app.UseStaticFiles();
app.UseRouting();
app.UseAuthorization();

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}");

app.Run();
```

### .NET Framework 4.x (Legacy)

```csharp
// Global.asax.cs
public class MvcApplication : System.Web.HttpApplication
{
    protected void Application_Start()
    {
        AreaRegistration.RegisterAllAreas();
        FilterConfig.RegisterGlobalFilters(GlobalFilters.Filters);
        RouteConfig.RegisterRoutes(RouteTable.Routes);
        BundleConfig.RegisterBundles(BundleTable.Bundles);
    }
}

// Web.config para connection strings
<connectionStrings>
    <add name="DefaultConnection" 
         connectionString="Server=...;Database=...;" 
         providerName="System.Data.SqlClient" />
</connectionStrings>
```

---

## PARTE 2: COMPARATIVA DE CARACTERÍSTICAS

| Característica | .NET 4.x | .NET 8 | .NET 9 | .NET 10 |
|----------------|----------|--------|--------|---------|
| **Configuración** | Web.config | appsettings.json | appsettings.json | appsettings.json + validación |
| **DI** | Manual/Ninject | Built-in | Built-in | Built-in mejorado |
| **OpenAPI** | N/A | Swashbuckle | Swashbuckle | **Nativo** |
| **EF** | EF 6 | EF Core 8 | EF Core 9 | EF Core 10 |
| **Hosting** | IIS | Kestrel | Kestrel | Kestrel optimizado |
| **C#** | 7.3 | 12 | 13 | 13+ |

---

## PARTE 3: VISTAS RAZOR

### Blazor (.NET 10)

```razor
@* Componente Blazor .NET 10 con streaming rendering *@
@page "/scholarships"
@attribute [StreamRendering]
@inject IScholarshipService ScholarshipService

<PageTitle>Listado de Scholarships</PageTitle>

@if (scholarships is null)
{
    <p>Loading...</p>
}
else
{
    <QuickGrid Items="@scholarships.AsQueryable()" Pagination="@pagination">
        <PropertyColumn Property="@(b => b.Name)" Sortable="true" />
        <PropertyColumn Property="@(b => b.Amount)" Format="C" />
        <TemplateColumn>
            <a href="@($"/scholarships/{context.Id}")">View</a>
        </TemplateColumn>
    </QuickGrid>
    <Paginator State="@pagination" />
}

@code {
    private List<Scholarship>? scholarships;
    private PaginationState pagination = new() { ItemsPerPage = 10 };

    protected override async Task OnInitializedAsync()
    {
        scholarships = await ScholarshipService.GetAllAsync();
    }
}
```

### Razor Views MVC (Todas las versiones)

```html
@model ScholarshipViewModel

@{
    ViewData["Title"] = "Detalle de Scholarship";
}

<div class="container">
    <h1>@Model.Name</h1>
    
    <div class="card">
        <div class="card-body">
            <dl class="row">
                <dt class="col-sm-3">Amount</dt>
                <dd class="col-sm-9">@Model.Amount.ToString("C")</dd>
            </dl>
        </div>
    </div>
    
    @if (Model.CanEdit)
    {
        <a asp-action="Edit" asp-route-id="@Model.Id" class="btn btn-brand-primary">
            Editar
        </a>
    }
</div>
```

---

## PARTE 4: ESTILOS CSS - TOKENS DE TEMA

> Los valores salen de `ecosystem.config.theme` (`primaryColor`, `secondaryColor`); los de abajo son los defaults neutrales del fork.

```css
:root {
    /* Marca (theme.primaryColor / theme.secondaryColor del ecosystem.config) */
    --brand-primary: #33475B;
    --brand-primary-light: #4A6FA5;
    --brand-primary-hover: #24333F;
    
    /* Secundarios */
    --brand-neutral: #666666;
    --brand-neutral-light: #f5f5f5;
    --brand-white: #ffffff;
    
    /* Estados */
    --color-exito: #28a745;
    --color-error: #dc3545;
    --color-aviso: #ffc107;
    --color-info: #17a2b8;
    
    /* Tipografía */
    --font-family-base: 'Segoe UI', system-ui, sans-serif;
    --font-size-base: 1rem;
}

/* Botones de marca */
.btn-brand-primary {
    background-color: var(--brand-primary);
    color: var(--brand-white);
    padding: 0.5rem 1.5rem;
    border: none;
    border-radius: 4px;
    font-weight: 500;
    transition: all 0.2s ease;
}

.btn-brand-primary:hover {
    background-color: var(--brand-primary-hover);
    transform: translateY(-1px);
}

.btn-brand-primary:focus {
    outline: 3px solid var(--brand-primary-light);
    outline-offset: 2px;
}

/* Responsive */
@media (max-width: 768px) {
    .container { padding: 1rem; }
}

@media (min-width: 1024px) {
    .container { max-width: 1200px; margin: 0 auto; }
}
```

---

## PARTE 5: JAVASCRIPT MODERNO

```javascript
// Namespace de la aplicacion - Compatible ES2022+
const App = globalThis.App ?? {};

App.Scholarships = (() => {
    'use strict';
    
    const init = () => {
        bindEvents();
    };
    
    const bindEvents = () => {
        document.querySelectorAll('[data-action="delete"]')
            .forEach(btn => btn.addEventListener('click', handleDelete));
    };
    
    const handleDelete = async (event) => {
        event.preventDefault();
        
        if (!confirm('Are you sure you want to delete?')) return;
        
        const id = event.target.dataset.id;
        
        try {
            const response = await fetch(`/api/scholarships/${id}`, {
                method: 'DELETE',
                headers: {
                    'RequestVerificationToken': getAntiForgeryToken()
                }
            });
            
            if (response.ok) {
                event.target.closest('tr')?.remove();
                showNotification('Deleted successfully', 'success');
            } else {
                throw new Error(`HTTP ${response.status}`);
            }
        } catch (error) {
            console.error('Error:', error);
            showNotification('Delete failed', 'error');
        }
    };
    
    const getAntiForgeryToken = () => 
        document.querySelector('input[name="__RequestVerificationToken"]')?.value;
    
    const showNotification = (message, type) => {
        // Implementar notificación toast
    };
    
    return { init };
})();

document.addEventListener('DOMContentLoaded', App.Scholarships.init);
```

---

## PARTE 6: ACCESIBILIDAD (WCAG 2.1 AA)

### Contraste de Colores

| Elemento | Color | Fondo | Ratio | Estado |
|----------|-------|-------|-------|--------|
| Texto normal | #33475B | #ffffff | 9.7:1 | ✅ |
| Texto sobre primario | #ffffff | #33475B | 9.7:1 | ✅ |
| Links | #4A6FA5 | #ffffff | 5.0:1 | ✅ |

### Formularios Accesibles

```html
<form id="scholarshipForm" novalidate>
    <div class="form-group">
        <label for="name" class="form-label">
            Scholarship name <span aria-label="required">*</span>
        </label>
        <input type="text" 
               id="name" 
               name="name"
               class="form-control"
               required 
               minlength="3" 
               maxlength="200"
               aria-describedby="name-help name-error">
        <small id="name-help" class="form-text">
            Between 3 and 200 characters
        </small>
        <div id="name-error" class="invalid-feedback" role="alert">
            Name is required
        </div>
    </div>
    
    <button type="submit" class="btn-brand-primary">
        Guardar
    </button>
</form>
```

---

## PARTE 7: SEGURIDAD

### Secretos - NUNCA en código

```csharp
// ❌ NUNCA
"ConnectionStrings": {
    "Default": "Server=prod;Password=123456"
}

// ✅ Desarrollo - User Secrets
dotnet user-secrets set "ConnectionStrings:Default" "Server=..."

// ✅ Producción - Azure Key Vault (.NET 10)
builder.Configuration.AddAzureKeyVault(
    new Uri(builder.Configuration["KeyVault:Url"]!),
    new DefaultAzureCredential());
```

### Validación Anti-Forgery

```csharp
// .NET 10 - Automático en formularios
builder.Services.AddAntiforgery(options =>
{
    options.HeaderName = "X-XSRF-TOKEN";
    options.Cookie.SecurePolicy = CookieSecurePolicy.Always;
});
```

---

## CHECKLIST POR VERSIÓN

### .NET 10 ✅
- [ ] OpenAPI nativo (no Swashbuckle)
- [ ] AddOptionsWithValidateOnStart
- [ ] EF Core 10 features
- [ ] Health checks con tags
- [ ] Blazor streaming rendering

### .NET 8/9 (Preparar migración)
- [ ] Identificar Swashbuckle → OpenAPI
- [ ] Revisar breaking changes
- [ ] Actualizar NuGets

### .NET 4.x (Mantener)
- [ ] No introducir dependencias modernas
- [ ] Respetar Web.config
- [ ] Entity Framework 6

---

*Regla condicional v3.7.0 - Multi-versión .NET*
