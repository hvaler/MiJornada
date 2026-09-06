Genera documentación técnica del código fuente

# Comando: /documentar

Genera documentación técnica del código fuente ubicado en `03_Desarrollo/`.

> **USE FOR**: documentación **TÉCNICA** del código (arquitectura, APIs, clases) para desarrolladores.
> **DO NOT USE FOR**: manuales **FUNCIONALES** para usuarios finales, QA o Product Owners → usar **`/documentar-uso`**.

## 🧠 Extended Thinking Mode

**think hard** - Analiza el código en profundidad para generar documentación precisa y útil.

---

## IMPORTANTE: Estructura de Carpetas

```
MiProyecto/
├── _hilo/                  ← Contexto del proyecto
│   ├── FUNCIONALIDADES.md
│   └── DEPENDENCIAS.md
├── 03_Desarrollo/              ← CÓDIGO FUENTE A DOCUMENTAR ⭐
│   ├── MiSolucion.sln|.slnx    ← .slnx solo .NET 8+
│   ├── MiProyecto.API/
│   └── ...
└── 06_Documentacion/           ← DOCUMENTACIÓN GENERADA ⭐
    ├── API/
    │   └── README_API.md
    ├── Arquitectura/
    │   └── ARQUITECTURA.md
    ├── Code/
    │   └── [Proyecto]/
    └── README.md
```

---

## Parámetros

| Parámetro | Descripción |
|-----------|-------------|
| `--api` | Documentar endpoints de la API |
| `--code` | Documentar clases y métodos principales |
| `--readme` | Generar README.md del proyecto |
| `--full` | Documentación completa (default) |
| `[ruta]` | Archivo o carpeta específica a documentar |

## Ejemplos de Uso

```bash
# Documentación completa
/documentar

# Solo documentar API
/documentar --api

# Documentar un archivo específico
/documentar 03_Desarrollo/MiProyecto.Domain/Services/ScholarshipService.cs

# Documentar un proyecto completo
/documentar 03_Desarrollo/MiProyecto.Domain/
```

---

## Tareas a Ejecutar

### 1. Analizar Código Fuente

```powershell
# Detectar proyectos en 03_Desarrollo/
$projects = Get-ChildItem -Path "03_Desarrollo" -Filter "*.csproj" -Recurse

# Contar archivos por tipo
$csFiles = Get-ChildItem -Path "03_Desarrollo" -Filter "*.cs" -Recurse |
    Where-Object { $_.FullName -notmatch "\\(bin|obj)\\" }
```

### 2. Generar Documentación de API (--api)

**Buscar Controllers en `03_Desarrollo/`:**

```powershell
$controllers = Get-ChildItem -Path "03_Desarrollo" -Filter "*Controller.cs" -Recurse
```

**Crear `06_Documentacion/API/README_API.md`:**

```markdown
# Documentación de API

## Resumen
- **Versión**: [detectada]
- **Base URL**: [detectada de launchSettings.json]
- **Autenticación**: [JWT/Azure AD/etc.]

## Endpoints

### 📋 ScholarshipsController
Base: `/api/scholarships`

| Método | Ruta | Descripción | Auth |
|--------|------|-------------|------|
| GET | `/` | Lista todas las scholarships | 🔒 |
| GET | `/{id}` | Obtiene scholarship por ID | 🔒 |
| POST | `/` | Crea nueva scholarship | 🔒 Admin |
| PUT | `/{id}` | Actualiza scholarship | 🔒 Admin |
| DELETE | `/{id}` | Elimina scholarship | 🔒 Admin |

#### GET /api/scholarships
**Descripción**: Obtiene listado paginado de scholarships.

**Parámetros Query**:
| Parámetro | Tipo | Requerido | Descripción |
|-----------|------|-----------|-------------|
| page | int | No | Página (default: 1) |
| pageSize | int | No | Tamaño (default: 10) |
| estado | string | No | Filtro por estado |

**Respuesta 200**:
```json
{
  "data": [...],
  "total": 100,
  "page": 1,
  "pageSize": 10
}
```

**Códigos de Error**:
| Código | Descripción |
|--------|-------------|
| 401 | No autenticado |
| 403 | Sin permisos |
| 500 | Error interno |

---

### 📋 [OtroController]
...
```

### 3. Generar Documentación de Código (--code)

**Analizar clases principales en `03_Desarrollo/`:**

```powershell
# Buscar servicios, repositorios, entidades
$services = Get-ChildItem -Path "03_Desarrollo" -Filter "*Service.cs" -Recurse
$repositories = Get-ChildItem -Path "03_Desarrollo" -Filter "*Repository.cs" -Recurse
$entities = Get-ChildItem -Path "03_Desarrollo" -Filter "*.cs" -Recurse |
    Where-Object { $_.Directory.Name -eq "Entities" -or $_.Directory.Name -eq "Models" }
```

**Crear `06_Documentacion/Codigo/[Proyecto]/README.md`:**

```markdown
# MiProyecto.Domain

## Descripción
Capa de dominio con entidades y lógica de negocio.

## Estructura
```
MiProyecto.Domain/
├── Entities/
│   ├── Scholarship.cs
│   └── Usuario.cs
├── Services/
│   └── ScholarshipService.cs
├── Interfaces/
│   └── IScholarshipRepository.cs
└── Exceptions/
    └── ScholarshipNotFoundException.cs
```

## Entidades

### Scholarship
**Ubicación**: `03_Desarrollo/MiProyecto.Domain/Entities/Scholarship.cs`

| Propiedad | Tipo | Descripción |
|-----------|------|-------------|
| Id | int | Identificador único |
| Nombre | string | Scholarship name |
| Estado | ScholarshipStatus | Estado actual |
| CreatedAt | DateTime | Fecha de creación |

### Usuario
...

## Servicios

### ScholarshipService
**Ubicación**: `03_Desarrollo/MiProyecto.Domain/Services/ScholarshipService.cs`

**Responsabilidad**: Gestión de scholarships y validaciones de negocio.

**Métodos**:
| Método | Parámetro | Retorno | Descripción |
|--------|------------|---------|-------------|
| GetByIdAsync | int id | Task<Scholarship> | Obtiene scholarship por ID |
| CreateAsync | ScholarshipDto dto | Task<Scholarship> | Crea nueva scholarship |
| ApproveAsync | int id | Task<bool> | Aprueba una scholarship |

**Dependencias**:
- `IScholarshipRepository`
- `ILogger<ScholarshipService>`
- `IValidator<ScholarshipDto>`
```

### 4. Generar README Principal (--readme)

**Crear `06_Documentacion/README.md`:**

```markdown
# [Nombre del Proyecto]

## Descripción
[Extraído de _hilo/FUNCIONALIDADES.md]

## Requisitos
- .NET [versión]
- SQL Server [versión]
- [Otros requisitos]

## Estructura del Proyecto

```
MiProyecto/
├── 03_Desarrollo/              ← Código fuente
│   ├── MiProyecto.sln|.slnx    ← .slnx solo .NET 8+
│   ├── MiProyecto.API/         ← Web API
│   ├── MiProyecto.Domain/      ← Dominio
│   ├── MiProyecto.Infrastructure/ ← Infraestructura
│   └── MiProyecto.Tests/       ← Tests
├── _hilo/                  ← Documentación de contexto
├── 01_Diseno/                  ← Diagramas
└── 06_Documentacion/           ← Esta documentación
```

## Instalación

```bash
# Clonar repositorio
git clone [url]

# Restaurar dependencias
cd 03_Desarrollo
dotnet restore

# Configurar base de datos
# [instrucciones]

# Ejecutar
dotnet run --project MiProyecto.API
```

## Configuración

### appsettings.json
```json
{
  "ConnectionStrings": {
    "DefaultConnection": "..."
  },
  "Jwt": {
    "Key": "...",
    "Issuer": "..."
  }
}
```

## API
Ver [documentación de API](./API/README_API.md)

## Arquitectura
Ver [documentación de arquitectura](./Arquitectura/ARQUITECTURA.md)

## Tests

```bash
cd 03_Desarrollo
dotnet test
```

## Equipo
[Extraído de _hilo/ESTADO_PROYECTO.json]

## Enlaces
- [Funcionalidades](_hilo/FUNCIONALIDADES.md)
- [Decisiones técnicas](_hilo/DECISIONES.md)
- [Diagramas](01_Diseno/Arquitectura/)
```

### 5. Documentación Completa (--full)

Ejecutar todos los anteriores:
1. Documentación de API
2. Documentación de código por proyecto
3. README principal
4. Generar índice

**Crear `06_Documentacion/INDEX.md`:**

```markdown
# Índice de Documentación

## 📚 Documentación General
- [README Principal](./README.md)
- [Arquitectura](./Arquitectura/ARQUITECTURA.md)

## 📌 API
- [Documentación de Endpoints](./API/README_API.md)
- [Autenticación](./API/AUTH.md)
- [Códigos de Error](./API/ERRORS.md)

## 💻 Código
- [MiProyecto.API](./Code/MiProyecto.API/README.md)
- [MiProyecto.Domain](./Code/MiProyecto.Domain/README.md)
- [MiProyecto.Infrastructure](./Code/MiProyecto.Infrastructure/README.md)

## 📊 Contexto del Proyecto
- [Funcionalidades](../_hilo/FUNCIONALIDADES.md)
- [Dependencias](../_hilo/DEPENDENCIAS.md)
- [Decisiones técnicas](../_hilo/DECISIONES.md)
- [Deuda Técnica](../_hilo/DEUDA_TECNICA.md)

## 📈 Diagramas
- [Componentes](../01_Diseno/Arquitectura/DIAGRAMA_COMPONENTES.md)
- [Dependencias](../01_Diseno/Arquitectura/DIAGRAMA_DEPENDENCIAS.md)
- [Entidades](../01_Diseno/Arquitectura/DIAGRAMA_ENTIDADES.md)
```

---

## 6. 6. Actualizar Contexto

**Actualizar `_hilo/ESTADO_PROYECTO.json`:**

```json
{
  "documentacion": {
    "ultimaGeneracion": "[FECHA]",
    "archivosGenerados": [N],
    "ubicacion": "06_Documentacion",
    "tiposGenerados": ["api", "code", "readme"]
  }
}
```

---

## Output Final

```
📚 DOCUMENTACIÓN GENERADA
═══════════════════════

📂 Ubicación: 06_Documentacion/

✅ Archivos creados:
   • README.md - Documentación principal
   • INDEX.md - Índice de navegación
   • API/README_API.md - [N] endpoints documentados
   • Code/MiProyecto.Domain/README.md
   • Code/MiProyecto.API/README.md
   • Arquitectura/ARQUITECTURA.md

📊 Estadísticas:
   • endpoints documentados: [N]
   • Clases documentadas: [N]
   • Proyectos cubiertos: [N]

💡 Próximos pasos:
   • Revisar documentación generada
   • /commit -m "docs: Actualizar documentación técnica"
   • Añadir ejemplos de uso donde falten
```

---

## Actualizar Visual Studio

**Después de crear la documentación, ejecutar:**

```powershell
.\.claude\commands\integracion-vs.ps1
```

Esto añadirá los nuevos archivos de documentación a los Solution Folders de Visual Studio.

---

## Relacionados

- /analizar - Análisis de código (genera diagramas)
- /nuevo-evolutivo - Crear evolutivo de documentación
- /commit - Guardar documentación generada
