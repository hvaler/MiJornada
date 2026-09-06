---
globs:
  - "**/*.razor"
  - "**/*.razor.cs"
  - "**/*.razor.css"
  - "**/Components/**/*.cs"
  - "**/Pages/**/*.cshtml"
  - "**/Areas/**/*.razor"
  - "**/_Imports.razor"
  - "**/App.razor"
  - "**/Routes.razor"
  - "**/BlazorWebAssembly*.csproj"
---

# Reglas para Blazor

> Este archivo aplica cuando Claude trabaja con proyectos Blazor.
> **Detecta automáticamente** el modo de renderizado del proyecto.

---

## DETECCIÓN DE MODO BLAZOR

```xml
<!-- En .csproj -->
<Project Sdk="Microsoft.NET.Sdk.BlazorWebAssembly">    <!-- Blazor WASM -->
<Project Sdk="Microsoft.NET.Sdk.Web">                  <!-- Blazor Server / SSR -->

<!-- Paquetes que indican el modo -->
<PackageReference Include="Microsoft.AspNetCore.Components.WebAssembly" />  <!-- WASM -->
<PackageReference Include="Microsoft.AspNetCore.Components.Web" />           <!-- Server/SSR -->
```

---

## MODOS DE RENDERIZADO (.NET 10)

| Modo | Descripción | Uso recomendado |
|------|-------------|-----------------|
| **Static SSR** | HTML estático sin interactividad | Contenido informativo, SEO |
| **Interactive Server** | WebSocket, estado en servidor | Apps internas, tiempo real |
| **Interactive WASM** | Ejecuta en navegador | Apps offline, cálculos cliente |
| **Interactive Auto** | Server primero, WASM después | Mejor de ambos mundos |

### Configuración en Program.cs (.NET 10)

```csharp
// Program.cs - Blazor Web App (.NET 10)
var builder = WebApplication.CreateBuilder(args);

// Añadir servicios Blazor
builder.Services.AddRazorComponents()
    .AddInteractiveServerComponents()     // Server-side
    .AddInteractiveWebAssemblyComponents(); // WASM

var app = builder.Build();

app.UseStaticFiles();
app.UseAntiforgery();

// Mapear componentes con modos de renderizado
app.MapRazorComponents<App>()
    .AddInteractiveServerRenderMode()
    .AddInteractiveWebAssemblyRenderMode()
    .AddAdditionalAssemblies(typeof(Client.Program).Assembly);

app.Run();
```

---

## PARTE 1: ESTRUCTURA DE PROYECTO

### Blazor Web App (.NET 10 - Recomendado)

```
MyCompany.MyApp/
├── MyCompany.MyApp/                 # Proyecto Server
│   ├── Components/
│   │   ├── App.razor
│   │   ├── Routes.razor
│   │   ├── Layout/
│   │   │   ├── MainLayout.razor
│   │   │   ├── NavMenu.razor
│   │   │   └── MainLayout.razor.css
│   │   └── Pages/
│   │       ├── Home.razor
│   │       ├── Scholarships/
│   │       │   ├── Index.razor
│   │       │   ├── Create.razor
│   │       │   └── Edit.razor
│   │       └── Error.razor
│   ├── Services/
│   │   └── ScholarshipService.cs
│   └── Program.cs
│
├── MyCompany.MyApp.Client/          # Proyecto WASM (componentes interactivos)
│   ├── Pages/
│   │   └── Counter.razor
│   ├── Services/
│   │   └── ClientScholarshipService.cs
│   └── Program.cs
│
└── MyCompany.MyApp.Shared/          # DTOs compartidos
    ├── DTOs/
    │   └── ScholarshipDto.cs
    └── Validators/
        └── CreateScholarshipValidator.cs
```

### Blazor Server Tradicional

```
MyCompany.MyApp.Server/
├── Components/
│   ├── App.razor
│   └── Pages/
│       └── Index.razor
├── Data/
│   └── ScholarshipService.cs
└── Program.cs
```

---

## PARTE 2: COMPONENTES BLAZOR

### Componente con Render Mode (.NET 10)

```razor
@* Scholarships/Index.razor *@
@page "/scholarships"
@rendermode InteractiveServer   @* Modo interactivo server-side *@
@inject IScholarshipService ScholarshipService
@inject NavigationManager Navigation

<PageTitle>Scholarship Management</PageTitle>

<h1>Listado de Scholarships</h1>

<div class="toolbar mb-3">
    <button class="btn btn-brand-primary" @onclick="CreateNew">
        <i class="bi bi-plus"></i> Nueva Scholarship
    </button>
    <input type="search"
           class="form-control d-inline-block w-auto ms-2"
           placeholder="Buscar..."
           @bind="filter"
           @bind:event="oninput"
           @bind:after="FilterScholarships" />
</div>

@if (loading)
{
    <div class="spinner-border text-primary" role="status">
        <span class="visually-hidden">Loading...</span>
    </div>
}
else if (scholarships is null || !scholarships.Any())
{
    <div class="alert alert-info">
        No scholarships found.
    </div>
}
else
{
    <QuickGrid Items="@filteredScholarships.AsQueryable()" Pagination="@pagination" Class="table">
        <PropertyColumn Property="@(b => b.Code)" Title="Code" Sortable="true" />
        <PropertyColumn Property="@(b => b.Name)" Title="Name" Sortable="true" />
        <PropertyColumn Property="@(b => b.Amount)" Title="Amount" Format="C" Sortable="true" />
        <PropertyColumn Property="@(b => b.Status)" Title="Status" />
        <TemplateColumn Title="Actions">
            <div class="btn-group btn-group-sm">
                <button class="btn btn-outline-primary" @onclick="() => Edit(context.Id)">
                    <i class="bi bi-pencil"></i>
                </button>
                <button class="btn btn-outline-danger" @onclick="() => Delete(context)">
                    <i class="bi bi-trash"></i>
                </button>
            </div>
        </TemplateColumn>
    </QuickGrid>

    <Paginator State="@pagination" />
}

@code {
    private List<ScholarshipDto>? scholarships;
    private IEnumerable<ScholarshipDto> filteredScholarships = [];
    private string filter = string.Empty;
    private bool loading = true;
    private PaginationState pagination = new() { ItemsPerPage = 10 };

    protected override async Task OnInitializedAsync()
    {
        await LoadScholarships();
    }

    private async Task LoadScholarships()
    {
        loading = true;
        try
        {
            scholarships = await ScholarshipService.GetAllAsync();
            filteredScholarships = scholarships;
        }
        finally
        {
            loading = false;
        }
    }

    private void FilterScholarships()
    {
        if (string.IsNullOrWhiteSpace(filter))
        {
            filteredScholarships = scholarships ?? [];
        }
        else
        {
            filteredScholarships = scholarships?.Where(b =>
                b.Name.Contains(filter, StringComparison.OrdinalIgnoreCase) ||
                b.Code.Contains(filter, StringComparison.OrdinalIgnoreCase)) ?? [];
        }
    }

    private void CreateNew() => Navigation.NavigateTo("/scholarships/create");

    private void Edit(int id) => Navigation.NavigateTo($"/scholarships/edit/{id}");

    private async Task Delete(ScholarshipDto scholarship)
    {
        // Usar componente de confirmación
        var confirmed = await ConfirmDelete(scholarship.Name);
        if (confirmed)
        {
            await ScholarshipService.DeleteAsync(scholarship.Id);
            await LoadScholarships();
        }
    }
}
```

### Componente de Formulario con Validación

```razor
@* Scholarships/Create.razor *@
@page "/scholarships/create"
@page "/scholarships/edit/{Id:int}"
@rendermode InteractiveServer
@inject IScholarshipService ScholarshipService
@inject NavigationManager Navigation

<PageTitle>@(Id.HasValue ? "Edit" : "Create") Scholarship</PageTitle>

<h1>@(Id.HasValue ? "Edit" : "New") Scholarship</h1>

<EditForm Model="@model" OnValidSubmit="Save" FormName="scholarshipForm">
    <DataAnnotationsValidator />
    <FluentValidationValidator />

    <div class="row">
        <div class="col-md-6 mb-3">
            <label for="code" class="form-label">Código *</label>
            <InputText id="code"
                       @bind-Value="model.Code"
                       class="form-control"
                       disabled="@Id.HasValue" />
            <ValidationMessage For="@(() => model.Code)" class="text-danger" />
        </div>

        <div class="col-md-6 mb-3">
            <label for="name" class="form-label">Name *</label>
            <InputText id="name" @bind-Value="model.Name" class="form-control" />
            <ValidationMessage For="@(() => model.Name)" class="text-danger" />
        </div>
    </div>

    <div class="row">
        <div class="col-md-6 mb-3">
            <label for="amount" class="form-label">Amount *</label>
            <InputNumber id="amount"
                         @bind-Value="model.Amount"
                         class="form-control"
                         step="0.01" />
            <ValidationMessage For="@(() => model.Amount)" class="text-danger" />
        </div>

        <div class="col-md-6 mb-3">
            <label for="status" class="form-label">Status</label>
            <InputSelect id="status" @bind-Value="model.Status" class="form-select">
                @foreach (var status in Enum.GetValues<ScholarshipStatus>())
                {
                    <option value="@status">@status</option>
                }
            </InputSelect>
        </div>
    </div>

    <div class="row">
        <div class="col-md-6 mb-3">
            <label for="startDate" class="form-label">Fecha Inicio *</label>
            <InputDate id="startDate" @bind-Value="model.StartDate" class="form-control" />
            <ValidationMessage For="@(() => model.StartDate)" class="text-danger" />
        </div>

        <div class="col-md-6 mb-3">
            <label for="endDate" class="form-label">Fecha Fin *</label>
            <InputDate id="endDate" @bind-Value="model.EndDate" class="form-control" />
            <ValidationMessage For="@(() => model.EndDate)" class="text-danger" />
        </div>
    </div>

    <div class="mb-3">
        <label for="descripcion" class="form-label">Descripción</label>
        <InputTextArea id="descripcion" @bind-Value="model.Description" class="form-control" rows="3" />
    </div>

    <div class="d-flex gap-2">
        <button type="submit" class="btn btn-brand-primary" disabled="@saving">
            @if (saving)
            {
                <span class="spinner-border spinner-border-sm me-1"></span>
            }
            @(Id.HasValue ? "Save Changes" : "Create Scholarship")
        </button>
        <button type="button" class="btn btn-secondary" @onclick="Cancel">
            Cancel
        </button>
    </div>
</EditForm>

@code {
    [Parameter] public int? Id { get; set; }

    private ScholarshipFormModel model = new();
    private bool saving;

    protected override async Task OnParametersSetAsync()
    {
        if (Id.HasValue)
        {
            var scholarship = await ScholarshipService.GetByIdAsync(Id.Value);
            if (scholarship is not null)
            {
                model = new ScholarshipFormModel
                {
                    Code = scholarship.Code,
                    Name = scholarship.Name,
                    Amount = scholarship.Amount,
                    Status = scholarship.Status,
                    StartDate = scholarship.StartDate,
                    EndDate = scholarship.EndDate,
                    Description = scholarship.Description
                };
            }
        }
    }

    private async Task Save()
    {
        saving = true;
        try
        {
            if (Id.HasValue)
            {
                await ScholarshipService.UpdateAsync(Id.Value, model);
            }
            else
            {
                await ScholarshipService.CreateAsync(model);
            }
            Navigation.NavigateTo("/scholarships");
        }
        finally
        {
            saving = false;
        }
    }

    private void Cancel() => Navigation.NavigateTo("/scholarships");

    // Modelo del formulario
    public class ScholarshipFormModel
    {
        [Required(ErrorMessage = "Code is required")]
        [StringLength(20, MinimumLength = 3)]
        public string Code { get; set; } = string.Empty;

        [Required(ErrorMessage = "Name is required")]
        [StringLength(200, MinimumLength = 5)]
        public string Name { get; set; } = string.Empty;

        [Required]
        [Range(0.01, 100000, ErrorMessage = "Amount must be between 0.01 and 100,000")]
        public decimal Amount { get; set; }

        public ScholarshipStatus Status { get; set; } = ScholarshipStatus.Draft;

        [Required]
        public DateTime StartDate { get; set; } = DateTime.Today;

        [Required]
        public DateTime EndDate { get; set; } = DateTime.Today.AddMonths(6);

        [StringLength(2000)]
        public string? Description { get; set; }
    }
}
```

---

## PARTE 3: COMPONENTES REUTILIZABLES

### Componente de Confirmación

```razor
@* Shared/ConfirmDialog.razor *@
<div class="modal @(visible ? "show d-block" : "")" tabindex="-1" role="dialog">
    <div class="modal-dialog" role="document">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title">@Title</h5>
                <button type="button" class="btn-close" @onclick="Cancel"></button>
            </div>
            <div class="modal-body">
                <p>@Message</p>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-secondary" @onclick="Cancel">
                    Cancel
                </button>
                <button type="button" class="btn btn-@ButtonColor" @onclick="Confirm">
                    @ConfirmText
                </button>
            </div>
        </div>
    </div>
</div>
@if (visible)
{
    <div class="modal-backdrop fade show"></div>
}

@code {
    [Parameter] public string Title { get; set; } = "Confirm";
    [Parameter] public string Message { get; set; } = "Are you sure?";
    [Parameter] public string ConfirmText { get; set; } = "Confirm";
    [Parameter] public string ButtonColor { get; set; } = "danger";
    [Parameter] public EventCallback<bool> OnClose { get; set; }

    private bool visible;

    public void Show() => visible = true;

    private async Task Confirm()
    {
        visible = false;
        await OnClose.InvokeAsync(true);
    }

    private async Task Cancel()
    {
        visible = false;
        await OnClose.InvokeAsync(false);
    }
}
```

### Componente de Notificación Toast

```razor
@* Shared/ToastContainer.razor *@
@implements IDisposable
@inject ToastService ToastService

<div class="toast-container position-fixed bottom-0 end-0 p-3">
    @foreach (var toast in toasts)
    {
        <div class="toast show" role="alert">
            <div class="toast-header bg-@toast.Type text-white">
                <strong class="me-auto">@toast.Title</strong>
                <button type="button" class="btn-close btn-close-white"
                        @onclick="() => Close(toast)"></button>
            </div>
            <div class="toast-body">
                @toast.Message
            </div>
        </div>
    }
</div>

@code {
    private List<ToastMessage> toasts = [];

    protected override void OnInitialized()
    {
        ToastService.OnShow += ShowToast;
    }

    private async Task ShowToast(ToastMessage toast)
    {
        toasts.Add(toast);
        StateHasChanged();

        await Task.Delay(5000);
        Close(toast);
    }

    private void Close(ToastMessage toast)
    {
        toasts.Remove(toast);
        StateHasChanged();
    }

    public void Dispose()
    {
        ToastService.OnShow -= ShowToast;
    }
}
```

### Servicio de Toast

```csharp
// Services/ToastService.cs
public class ToastService
{
    public event Func<ToastMessage, Task>? OnShow;

    public async Task Success(string mensaje, string titulo = "Éxito")
        => await Show(new ToastMessage(titulo, mensaje, "success"));

    public async Task Error(string mensaje, string titulo = "Error")
        => await Show(new ToastMessage(titulo, mensaje, "danger"));

    public async Task Warning(string mensaje, string titulo = "Aviso")
        => await Show(new ToastMessage(titulo, mensaje, "warning"));

    public async Task Info(string mensaje, string titulo = "Información")
        => await Show(new ToastMessage(titulo, mensaje, "info"));

    private async Task Show(ToastMessage toast)
    {
        if (OnShow is not null)
            await OnShow.Invoke(toast);
    }
}

public record ToastMessage(string Title, string Message, string Type);
```

---

## PARTE 4: STREAMING RENDERING (.NET 10)

### Componente con Streaming

```razor
@* Scholarships/Dashboard.razor *@
@page "/scholarships/dashboard"
@attribute [StreamRendering]   @* Habilita streaming *@
@inject IScholarshipService ScholarshipService

<PageTitle>Dashboard de Scholarships</PageTitle>

<h1>Dashboard</h1>

<div class="row">
    @if (stats is null)
    {
        <div class="col-12">
            <p><em>Loading stats...</em></p>
        </div>
    }
    else
    {
        <div class="col-md-3">
            <div class="card bg-primary text-white">
                <div class="card-body">
                    <h5 class="card-title">Total Scholarships</h5>
                    <p class="card-text display-4">@stats.TotalScholarships</p>
                </div>
            </div>
        </div>
        <div class="col-md-3">
            <div class="card bg-success text-white">
                <div class="card-body">
                    <h5 class="card-title">Active</h5>
                    <p class="card-text display-4">@stats.ActiveScholarships</p>
                </div>
            </div>
        </div>
        <div class="col-md-3">
            <div class="card bg-info text-white">
                <div class="card-body">
                    <h5 class="card-title">Applications</h5>
                    <p class="card-text display-4">@stats.TotalApplications</p>
                </div>
            </div>
        </div>
        <div class="col-md-3">
            <div class="card bg-warning">
                <div class="card-body">
                    <h5 class="card-title">Amount Total</h5>
                    <p class="card-text display-4">@stats.AmountTotal.ToString("C")</p>
                </div>
            </div>
        </div>
    }
</div>

@code {
    private DashboardStats? stats;

    protected override async Task OnInitializedAsync()
    {
        // El streaming mostrará "Loading..." mientras se obtienen los datos
        stats = await ScholarshipService.GetStatsAsync();
    }
}
```

---

## PARTE 5: AUTENTICACIÓN Y AUTORIZACIÓN

### Componente Protegido

```razor
@page "/admin/scholarships"
@attribute [Authorize(Roles = "Admin,Gestor")]
@inject AuthenticationStateProvider AuthProvider

<AuthorizeView Roles="Admin,Gestor">
    <Authorized>
        <h1>Administración de Scholarships</h1>
        <p>Bienvenido, @context.User.Identity?.Name</p>

        <AuthorizeView Roles="Admin">
            <Authorized>
                <div class="alert alert-info">
                    Tienes permisos de administrador.
                </div>
            </Authorized>
        </AuthorizeView>

        @* Contenido para Admin y Gestor *@
    </Authorized>
    <NotAuthorized>
        <div class="alert alert-danger">
            No tienes permisos para acceder a esta página.
        </div>
    </NotAuthorized>
</AuthorizeView>
```

### Configuración de Auth (.NET 10)

```csharp
// Program.cs
builder.Services.AddCascadingAuthenticationState();
builder.Services.AddScoped<AuthenticationStateProvider,
    PersistingRevalidatingAuthenticationStateProvider>();

// Microsoft Entra ID / Azure AD
builder.Services.AddAuthentication(OpenIdConnectDefaults.AuthenticationScheme)
    .AddMicrosoftIdentityWebApp(builder.Configuration.GetSection("AzureAd"));
```

---

## PARTE 6: SERVICIOS Y HTTP

### Servicio para Blazor Server

```csharp
// Services/ScholarshipService.cs (Server)
public class ScholarshipService : IScholarshipService
{
    private readonly ApplicationDbContext _context;

    public ScholarshipService(ApplicationDbContext context)
    {
        _context = context;
    }

    public async Task<List<ScholarshipDto>> GetAllAsync()
    {
        return await _context.Scholarships
            .AsNoTracking()
            .Select(b => new ScholarshipDto
            {
                Id = b.Id,
                Code = b.Code,
                Name = b.Name,
                Amount = b.Amount,
                Status = b.Status.ToString()
            })
            .ToListAsync();
    }
}
```

### Servicio para Blazor WASM (llamadas HTTP)

```csharp
// Services/ClientScholarshipService.cs (WASM)
public class ClientScholarshipService : IScholarshipService
{
    private readonly HttpClient _http;

    public ClientScholarshipService(HttpClient http)
    {
        _http = http;
    }

    public async Task<List<ScholarshipDto>> GetAllAsync()
    {
        return await _http.GetFromJsonAsync<List<ScholarshipDto>>("api/scholarships") ?? [];
    }

    public async Task<ScholarshipDto?> GetByIdAsync(int id)
    {
        return await _http.GetFromJsonAsync<ScholarshipDto?>($"api/scholarships/{id}");
    }

    public async Task CreateAsync(CreateScholarshipRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/scholarships", request);
        response.EnsureSuccessStatusCode();
    }
}
```

---

## PARTE 7: CSS ISOLATION

### Estilos de Componente

```css
/* Scholarships/Index.razor.css */
.toolbar {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 1rem 0;
}

.toolbar input[type="search"] {
    max-width: 250px;
}

/* Usar ::deep para afectar hijos */
::deep .table th {
    background-color: var(--brand-primary);
    color: white;
}

::deep .table tr:hover {
    background-color: var(--brand-neutral-light);
}
```

---

## PARTE 8: PRUEBAS DE COMPONENTES

### Test con bUnit

```csharp
// Tests/Components/ScholarshipListTests.cs
public class ScholarshipListTests : TestContext
{
    [Fact]
    public void ShowsSpinner_WhenLoading()
    {
        // Arrange
        var mockService = new Mock<IScholarshipService>();
        mockService.Setup(s => s.GetAllAsync())
            .Returns(new TaskCompletionSource<List<ScholarshipDto>>().Task);

        Services.AddSingleton(mockService.Object);

        // Act
        var cut = RenderComponent<ScholarshipList>();

        // Assert
        cut.Find(".spinner-border").Should().NotBeNull();
    }

    [Fact]
    public void ShowsScholarships_WhenDataExists()
    {
        // Arrange
        var scholarships = new List<ScholarshipDto>
        {
            new() { Id = 1, Name = "Scholarship Test", Amount = 5000 }
        };

        var mockService = new Mock<IScholarshipService>();
        mockService.Setup(s => s.GetAllAsync()).ReturnsAsync(scholarships);

        Services.AddSingleton(mockService.Object);

        // Act
        var cut = RenderComponent<ScholarshipList>();

        // Assert
        cut.Markup.Should().Contain("Scholarship Test");
        cut.Markup.Should().Contain("5.000");
    }
}
```

---

## CHECKLIST

### Componentes
- [ ] Modo de renderizado apropiado (`@rendermode`)
- [ ] Streaming para datos lentos (`@attribute [StreamRendering]`)
- [ ] Validación con DataAnnotations o FluentValidation
- [ ] Manejo de estados (cargando, vacío, error)
- [ ] CSS isolation para estilos

### Seguridad
- [ ] `[Authorize]` en páginas protegidas
- [ ] `<AuthorizeView>` para UI condicional
- [ ] Validación en servidor (no confiar en cliente)
- [ ] CSRF con `[ValidateAntiForgeryToken]`

### Rendimiento
- [ ] QuickGrid para tablas grandes
- [ ] Virtualización para listas largas
- [ ] Lazy loading de componentes
- [ ] Evitar re-renders innecesarios

### Accesibilidad
- [ ] `aria-label` en elementos interactivos
- [ ] `role="alert"` en notificaciones
- [ ] Focus visible en formularios
- [ ] Contraste de colores WCAG 2.1 AA

---

## PAQUETES NUGET RECOMENDADOS

```xml
<ItemGroup>
  <PackageReference Include="Microsoft.AspNetCore.Components.QuickGrid" Version="10.*" />
  <PackageReference Include="Blazored.FluentValidation" Version="2.*" />
  <PackageReference Include="Blazored.LocalStorage" Version="4.*" />
  <PackageReference Include="Microsoft.AspNetCore.Components.WebAssembly.Authentication" Version="10.*" />
</ItemGroup>
```

---

*Regla condicional v3.7.0 - Blazor (.NET 10)*
