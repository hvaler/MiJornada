# 📁 Plantillas SQL - Base de Datos

## Descripción

Esta carpeta contiene plantillas estándar para objetos de base de datos SQL Server.
Estas plantillas siguen las convenciones de nombrado y estándares definidos por del ecosistema.

## Contenido

| Archivo | Descripción |
|---------|-------------|
| `PLANTILLA_STORED_PROCEDURE.sql` | Plantilla completa para Stored Procedures |
| `PLANTILLA_TABLA.sql` | Plantilla de tabla con campos de auditoría |
| `PLANTILLA_TABLA_CATALOGO.sql` | Plantilla para tablas de catálogo/lookup |
| `PLANTILLA_VISTA.sql` | Plantilla de vista estándar |
| `PLANTILLA_FUNCION.sql` | Plantillas de funciones (escalar y tabla) |
| `PLANTILLA_MIGRACION.sql` | Script de migración con rollback |
| `CONVENCION_SCHEMAS.sql` | Estructura de schemas recomendada |

## Uso

1. **Copiar** la plantilla correspondiente
2. **Renombrar** según el objeto a crear
3. **Reemplazar** los placeholders `{...}` con valores reales
4. **Eliminar** las secciones que no apliquen
5. **Revisar** antes de ejecutar en producción

## Convenciones de Nombrado

### Objetos de Base de Datos

| Objeto | Convención | Ejemplo |
|--------|------------|---------|
| Tabla | PascalCase, singular | `Student`, `ScholarshipApplication` |
| Tabla Catálogo | PascalCase, singular | `DocumentType`, `ApplicationStatus` |
| Columna | PascalCase | `BirthDate`, `DocumentNumber` |
| Stored Procedure | `usp_{Entity}_{Accion}` | `usp_Student_GetById` |
| Vista | `vw_{Description}` | `vw_ActiveStudents` |
| Función Escalar | `fn_{Description}` | `fn_CalculateEdad` |
| Función Tabla | `fnt_{Description}` | `fnt_ScholarshipsByStudent` |
| Trigger | `tr_{Table}_{Event}` | `tr_Student_AfterInsert` |
| Índice | `IX_{Table}_{Columns}` | `IX_Student_Email` |
| Índice Único | `UX_{Table}_{Columns}` | `UX_Student_DocumentNumber` |
| Primary Key | `PK_{Table}` | `PK_Student` |
| Foreign Key | `FK_{ChildTable}_{ParentTable}` | `FK_ScholarshipApplication_Student` |
| Check | `CK_{Table}_{Column}` | `CK_Student_Age` |
| Default | `DF_{Table}_{Column}` | `DF_Student_RegisteredAt` |
| Schema | lowercase | `academico`, `financiero` |

### Prefijos de Stored Procedures

| Prefijo | Uso | Ejemplo |
|---------|-----|---------|
| `usp_{Entity}_Insert` | Insertar | `usp_Student_Insert` |
| `usp_{Entity}_Update` | Actualizar | `usp_Student_Update` |
| `usp_{Entity}_Delete` | Eliminar físico | `usp_Student_Delete` |
| `usp_{Entity}_SoftDelete` | Eliminar lógico | `usp_Student_SoftDelete` |
| `usp_{Entity}_GetById` | Obtener por ID | `usp_Student_GetById` |
| `usp_{Entity}_GetAll` | Listar con paginación | `usp_Student_GetAll` |
| `usp_{Entity}_Search` | Búsqueda avanzada | `usp_Student_Search` |
| `usp_{Entity}_Exists` | Verificar existencia | `usp_Student_Exists` |
| `usp_Rpt_{Nombre}` | Reportes | `usp_Rpt_EnrollmentsByDegree` |

## Campos de Auditoría (OBLIGATORIOS)

Todas las tablas deben incluir estos campos:

```sql
-- Obligatorios
Active BIT NOT NULL DEFAULT 1,
CreatedAt DATETIME2(3) NOT NULL DEFAULT GETUTCDATE(),
CreatedBy NVARCHAR(100) NOT NULL DEFAULT SYSTEM_USER,
ModifiedAt DATETIME2(3) NULL,
ModifiedBy NVARCHAR(100) NULL
```

## Tipos de Datos Recomendados

| Uso | Tipo | Notas |
|-----|------|-------|
| Identificadores | `INT IDENTITY` | `BIGINT` si >2 mil millones |
| Texto | `NVARCHAR(n)` | Siempre Unicode |
| Texto largo | `NVARCHAR(MAX)` | No usar `TEXT` (deprecado) |
| Fechas | `DATETIME2(3)` | No usar `DATETIME` |
| Solo fecha | `DATE` | Sin hora |
| Money | `DECIMAL(18,2)` | No usar `MONEY` |
| Booleanos | `BIT` | 0/1 |

## Entornos

| Entorno | Versión |
|---------|---------|
| Producción principal | SQL Server 2017+ |
| Aplicaciones nuevas | SQL Server 2019/2022 |
| Cloud | Azure SQL |

## Referencia

- Regla completa: `.claude/rules/database.md`
- Documentación SQL Server: https://docs.microsoft.com/sql
