---
globs:
  - "**/*.sql"
  - "**/Scripts/**/*.sql"
  - "**/Migrations/**/*.sql"
  - "**/StoredProcedures/**/*.sql"
  - "**/Procedures/**/*.sql"
  - "**/Views/**/*.sql"
  - "**/Functions/**/*.sql"
  - "**/Triggers/**/*.sql"
  - "**/Tables/**/*.sql"
  - "**/Indexes/**/*.sql"
  - "**/Seeds/**/*.sql"
  - "**/Data/**/*.sql"
  - "**/*_Create.sql"
  - "**/*_Alter.sql"
  - "**/*_Drop.sql"
  - "**/*_Insert.sql"
  - "**/*_Update.sql"
  - "**/*_Migration.sql"
  - "**/Repositorios/**/*.cs"
  - "**/Repositories/**/*.cs"
  - "**/*Repository.cs"
  - "**/*Repositorio.cs"
  - "**/ProcedimientoAlmacenado.cs"
  - "**/StoredProcedures/**/*.cs"
  - "**/DbContext.cs"
  - "**/*DbContext.cs"
---

# Reglas para Base de Datos - SQL Server / Azure SQL

> Este archivo aplica cuando Claude trabaja con scripts T-SQL, stored procedures, vistas, funciones y objetos de base de datos **o con repositorios C# que invocan SPs**.
> **Entorno:** motor y versión según `ecosystem.config.database` (`engine` default `sqlserver`, `version` default `null` = sin gating de features); el proyecto puede sobrescribir en `_hilo/ESTADO_PROYECTO.json.baseDatos`. Las tablas de features por versión de abajo aplican SOLO si la versión está fijada.

---

## ERRORES COMUNES A EVITAR (lee esto PRIMERO)

Antes de crear CUALQUIER objeto SQL, verificar la nomenclatura configurada (`ecosystem.config.database.naming`; los ejemplos usan los defaults). Estas son las violaciones más frecuentes:

| ❌ KO | ✅ OK | Razón |
|---|---|---|
| `CREATE PROCEDURE [dbo].[int_ListaCarreras_leer]` (en SP **nuevo**) | `CREATE PROCEDURE academic.ListDegrees` | **Trampa BD cross-schema**: SP nuevo en BD con SPs legacy → seguir §8.1, NO imitar vecinos |
| `CREATE PROCEDURE usp_GetNomination` | `CREATE PROCEDURE scholarships.GetNomination` | Prohibidos los prefijos `usp_`, `sp_`, `pr_`, `proc_`, `pa_` |
| `CREATE PROCEDURE sales.Aliases_List` | `CREATE PROCEDURE sales.ListAliases` | Sufijos prohibidos si `naming.forbiddenSuffixes` los define (ej. `_Listar`, `_Guardar`, `_L`, `_G`) |
| `CREATE PROCEDURE scholarships.Get_Nomination` | `CREATE PROCEDURE scholarships.GetNomination` | Verbo + entidad **pegados** PascalCase, sin `_` |
| `CREATE PROCEDURE GetNomination` | `CREATE PROCEDURE scholarships.GetNomination` | Siempre con schema (incluso `dbo`) |
| `CREATE FUNCTION scholarships.CalculateRate(...)` | `CREATE FUNCTION scholarships.fn_CalculateRate(...)` | Funciones escalares con prefijo `fn_` |
| `CREATE FUNCTION scholarships.fn_ScholarshipsByYear() RETURNS TABLE` | `CREATE FUNCTION scholarships.fnt_ScholarshipsByYear() RETURNS TABLE` | TVFs con prefijo `fnt_`, no `fn_` |
| `CREATE VIEW scholarships.Active` | `CREATE VIEW scholarships.vw_Active` | Vistas con prefijo `vw_` |
| `CREATE TRIGGER trg_Student_Ins` | `CREATE TRIGGER academic.tr_Student_AfterInsert` | Triggers con prefijo `tr_` + `{Table}_{Event}` |
| `SELECT STRING_AGG(... ORDINAL)` | `STRING_AGG(...)` | `ORDINAL` es 2022+; en 2017 no existe |
| `SELECT * FROM GENERATE_SERIES(1, 10)` | CTE recursivo o tabla de números | `GENERATE_SERIES` es 2022+ |
| `a IS NOT DISTINCT FROM b` | `((a = b) OR (a IS NULL AND b IS NULL))` | `IS [NOT] DISTINCT FROM` es 2022+ |
| `GREATEST(a, b, c)` | `CASE WHEN …` o `(SELECT MAX(v) FROM (VALUES (a),(b),(c)) x(v))` | `GREATEST` / `LEAST` son 2022+ |
| Collation `*_UTF8` | Collation clásica `SQL_Latin1_General_CP1_CI_AI` | UTF-8 collations son 2019+ |

**Excepción legacy**: si el archivo está en `Legacy/`, `Obsoleto/`, `MigracionPendiente/` o tiene el comentario `-- LEGACY: no renombrar` al inicio, mantener la nomenclatura existente — NO corregir.

**Excepción schemas históricos**: los schemas listados en `database.naming.legacySchemas` se mantienen tal cual, NO normalizar (ejemplo de organización: `GesInter`, `PlazasIntercambio`). El resto de schemas nuevos siguen `database.naming.schemaCase` (default lowercase: `academic`, `finance`, `scholarships`).

> ⚠️ **Trampa común — BD cross-schema con muchos SPs legacy**
>
> Si creas un SP **nuevo** en una BD que ya tiene SPs con patrón antiguo (ej. `SecreBD` con `int_ListaTitulaciones_leer`, `int_ListaSemestres_leer`), **NO replicar ese patrón**. La regla "respetar legacy" SOLO aplica al **MODIFICAR** SPs existentes. Los SPs nuevos siempre siguen §8.1, incluso siendo el único moderno en su BD.
>
> Razonamiento defectuoso a evitar: "esta BD está llena de `int_*_leer` → coherencia → mi SP también". El estándar configurado prevalece sobre la inferencia visual de archivos vecinos.
>
> Antes de cualquier `CREATE PROCEDURE` en archivo nuevo: verificar contra la tabla §8.1. El hook `sql-nomenclatura-guard.js` detecta prefijos legacy en SPs nuevos según `database.naming.legacyPrefixes` (ej. `int_`, `aud_`, `tmp_`, `migr_`, `old_`, `bak_`).

> Ver también: `CLAUDE_BASE.md` §8.1 (siempre cargado en contexto) con la tabla de nomenclatura configurable.

---

## VERSIONES SOPORTADAS

**La versión objetivo la fija `ecosystem.config.database.version`** (o `baseDatos.versionSqlServer` en `_hilo/ESTADO_PROYECTO.json`, que gana). Si está fijada (ej. `"2017"`): NO usar features posteriores — ver tablas de abajo. Si es `null` (default): sin gating, usar las features actuales del motor.

| Versión | Estado | Notas |
|---------|--------|-------|
| **SQL Server 2017** | ✅ Soportado | Ejemplo típico de parque on-premise que fija `version: "2017"` — aplican las tablas de gating |
| SQL Server 2019 | ✅ Soportado | Solo si el proyecto lo indica |
| SQL Server 2022 | ✅ Soportado | Solo si el proyecto lo indica |
| Azure SQL | ✅ Soportado | Consideraciones especiales |
| SQL Server 2016 | ⚠️ Limitado | Evitar nuevos desarrollos; mantenimiento solamente |

### Features POST-2017 a NO usar por defecto

| Feature | Versión mínima | Alternativa en 2017 |
|---|---|---|
| `STRING_SPLIT` con `ordinal` | 2022 | Sólo `value` disponible en 2017 |
| `GENERATE_SERIES` | 2022 | Tabla de números o CTE recursivo |
| `DATE_BUCKET` | 2022 | Aritmética con `DATEADD` / `DATEDIFF` |
| `IS [NOT] DISTINCT FROM` | 2022 | `((a = b) OR (a IS NULL AND b IS NULL))` |
| `GREATEST` / `LEAST` | 2022 | `CASE` o subquery con `VALUES` |
| `BIT_COUNT`, `LEFT_SHIFT`, `RIGHT_SHIFT` | 2022 | Funciones bitwise manuales |
| `APPROX_PERCENTILE_CONT` | 2022 | `PERCENTILE_CONT` dentro de CTE |
| `OPENJSON WITH PATH strict` | 2022 | `PATH` sin `strict` |
| UTF-8 collations (`*_UTF8`) | 2019 | Collations clásicas `SQL_Latin1_General_*` |
| Inline TVF optimizaciones avanzadas | 2019 | Reescribir como Table Variable o temp table |
| Always Encrypted con enclaves | 2019 | Always Encrypted básico |

### Features SÍ disponibles en 2017 (usar con confianza)

`STRING_AGG`, `TRIM`, `TRANSLATE`, `CONCAT_WS`, `OPENJSON` básico, temporal tables system-versioned, columnstore actualizable, Graph tables, Adaptive Query Processing básico, Resumable online index rebuild.

---

## PARTE 1: CONVENCIONES DE NOMBRADO (configurables en `ecosystem.config.database.naming`)

### 1.1 Reglas Generales

| Elemento | Convención | Ejemplo | ❌ Evitar |
|----------|------------|---------|-----------| 
| **Tablas** | PascalCase, singular | `Student`, `ScholarshipApplication` | `estudiantes`, `tbl_Student` |
| **Columnas** | PascalCase | `BirthDate`, `DocumentNumber` | `fecha_nacimiento`, `fNac` |
| **Primary Key** | `Id` o `{Table}Id` | `Id`, `StudentId` | `ID`, `id_student` |
| **Foreign Key** | `{ReferencedTable}Id` | `StudentId`, `ScholarshipId` | `FK_Est`, `idStudent` |
| **Stored Procedures** | `{schema}.{Action}{Entity}` | `scholarships.GetNomination` | `usp_`, `sp_`, `pr_` |
| **Vistas** | `{schema}.vw_{Description}` | `scholarships.vw_ActiveNominations` | `Vista_`, `v_` |
| **Funciones Escalares** | `{schema}.fn_{Description}` | `scholarships.fn_CalculateRate` | `func_`, `f_` |
| **Funciones Tabla** | `{schema}.fnt_{Description}` | `scholarships.fnt_GetScholarshipsByYear` | `fn_tabla_` |
| **Triggers** | `{schema}.tr_{Table}_{Event}` | `academic.tr_Student_AfterInsert` | `trigger_`, `trg_` |
| **Índices** | `IX_{Table}_{Columns}` | `IX_Student_Email` | `idx1`, `index_email` |
| **Índices Únicos** | `UX_{Table}_{Columns}` | `UX_Student_DocumentNumber` | `unique_doc` |
| **Constraints PK** | `PK_{Table}` | `PK_Student` | `PrimaryKey_1` |
| **Constraints FK** | `FK_{ChildTable}_{ParentTable}` | `FK_ScholarshipApplication_Student` | `FK_1`, `fk_sol_est` |
| **Constraints Check** | `CK_{Table}_{Column}` | `CK_Student_Age` | `check_1` |
| **Constraints Default** | `DF_{Table}_{Column}` | `DF_Student_RegisteredAt` | `default_fecha` |
| **Schemas** | lowercase | `academic`, `finance`, `scholarships` | `Academic`, `FINANCE` |

### 1.2 Nomenclatura de Stored Procedures (SIN prefijo)

> ⚠️ **IMPORTANTE**: por defecto NO se usan prefijos `usp_`, `sp_`, `pr_` en procedimientos almacenados.
> Los procedimientos usan el formato: `{schema}.{Action}{Entity}`

```sql
-- =============================================
-- CONVENCIÓN (default): {schema}.{Action}{Entity}
-- ❌ NO usar prefijos usp_, sp_, pr_
-- =============================================

-- CRUD Básico
{schema}.Insert{Entity}        -- scholarships.InsertNomination
{schema}.Update{Entity}      -- scholarships.UpdateNomination  
{schema}.Delete{Entity}        -- scholarships.DeleteNomination
{schema}.Deactivate{Entity}      -- scholarships.DeactivateNomination (borrado lógico)

-- Consultas
{schema}.Get{Entity}         -- scholarships.GetNomination (por ID)
{schema}.Get{Entities}       -- scholarships.GetNominations (listado)
{schema}.Search{Entities}        -- scholarships.SearchNominations (con filtros)
{schema}.Exists{Entity}          -- scholarships.ExistsNomination

-- Operaciones de Negocio  
{schema}.{Action}{Entity}        -- scholarships.ApproveNomination
{schema}.Process{Process}        -- scholarships.ProcessExchange

-- Reportes
{schema}.Rpt{ReportName}       -- scholarships.RptNominationsByCountry
```

### 1.3 Nomenclatura de Funciones (CON prefijo fn_)

> ✅ Las funciones SÍ llevan prefijo `fn_` o `fnt_`

```sql
-- Funciones Escalares (devuelven un valor)
{schema}.fn_{Description}         -- scholarships.fn_CalculateRate
                                  -- academic.fn_CalculateAge

-- Funciones con Valor de Tabla (TVF)
{schema}.fnt_{Description}        -- scholarships.fnt_GetScholarshipsByYear
```

### 1.4 Nomenclatura de Vistas (CON prefijo vw_)

> ✅ Las vistas SÍ llevan prefijo `vw_`

```sql
{schema}.vw_{Description}         -- scholarships.vw_ActiveNominations
                                  -- academic.vw_ActiveStudents
```

### 1.5 Ejemplos Completos por Schema

```sql
-- =============================================
-- SCHEMA: scholarships
-- =============================================
scholarships.GetNomination             -- SP: Obtener nominación por ID
scholarships.GetNominations           -- SP: Listar nominations
scholarships.InsertNomination            -- SP: Crear nueva nominación
scholarships.UpdateNomination          -- SP: Actualizar nominación
scholarships.ApproveNomination             -- SP: Operación de negocio
scholarships.fn_CalculateRate               -- Función: Calcular tasa
scholarships.fn_GetExchangeStatus   -- Función: Obtener status
scholarships.fnt_GetScholarshipsByYear       -- TVF: Scholarships por año
scholarships.vw_ActiveNominations        -- Vista: Nominations activas

-- =============================================
-- SCHEMA: academic
-- =============================================
academic.GetStudent       -- SP: Obtener student
academic.InsertEnrollment       -- SP: Crear matrícula
academic.fn_CalculateAge         -- Función: Calcular edad
academic.vw_ActiveStudents   -- Vista: Students activos

-- =============================================
-- SCHEMA: finance
-- =============================================
finance.ProcessPayment           -- SP: Procesar pago
finance.fn_CalculateDiscount   -- Función: Calcular descuento
finance.vw_OverduePayments       -- Vista: Payments vencidos
```

### 1.6 Tipos de Datos Recomendados

| Uso | Tipo Recomendado | ❌ Evitar | Notas |
|-----|------------------|-----------|-------|
| Identificadores | `INT IDENTITY` o `BIGINT` | `UNIQUEIDENTIFIER` como PK clustered | GUID como PK causa fragmentación |
| GUIDs | `UNIQUEIDENTIFIER` | - | Solo cuando se requiere unicidad global |
| Texto corto (<100) | `NVARCHAR(n)` | `VARCHAR`, `CHAR` | Soporte Unicode |
| Texto largo | `NVARCHAR(MAX)` | `TEXT` | TEXT está deprecado |
| Fechas | `DATETIME2(3)` | `DATETIME` | Mayor precisión, menor espacio |
| Solo fecha | `DATE` | `DATETIME` | Sin componente de hora |
| Solo hora | `TIME(0)` | `DATETIME` | Sin componente de fecha |
| Money | `DECIMAL(18,2)` | `MONEY`, `FLOAT` | Evita errores de redondeo |
| Booleanos | `BIT` | `INT`, `CHAR(1)` | Valores 0/1 |
| Porcentajes | `DECIMAL(5,2)` | `FLOAT` | Ej: 99.99% |
| JSON | `NVARCHAR(MAX)` con CHECK | - | SQL 2016+: `ISJSON()` |

---

## PARTE 2: PLANTILLA DE STORED PROCEDURES

### 2.1 Plantilla Estándar Completa

```sql
-- =============================================
-- Author:           {AuthorName}
-- Created:          {CreationDate}
-- Description:     {ShortDescription}
-- =============================================
-- Change History:
-- Date $1| Author $2| Description
-- -------------|----------------|------------------------------------------
-- {Date} $1| {Author} $2| Initial creation
-- =============================================
CREATE OR ALTER PROCEDURE [{schema}].[{Action}{Entity}]
    -- Parámetros de entrada
    @Id INT,
    @Parametro1 NVARCHAR(100),
    @Parametro2 INT = NULL,              -- Parámetro opcional con default
    
    -- Parámetros de salida
    @RowsAffected INT = 0 OUTPUT,
    @ErrorMessage NVARCHAR(500) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;  -- Rollback automático en errores
    
    -- Variables locales
    DECLARE @Result INT = 0;
    DECLARE @TransactionStarted BIT = 0;
    
    BEGIN TRY
        -- Iniciar transacción si no hay una activa
        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @TransactionStarted = 1;
        END
        
        -- =============================================
        -- VALIDACIONES
        -- =============================================
        IF @Id IS NULL
        BEGIN
            SET @ErrorMessage = 'El parámetro @Id es requerido';
            RAISERROR(@ErrorMessage, 16, 1);
            RETURN -1;
        END
        
        -- =============================================
        -- LÓGICA PRINCIPAL
        -- =============================================
        
        -- Tu código aquí...
        
        -- =============================================
        -- COMMIT Y RETORNO
        -- =============================================
        IF @TransactionStarted = 1
            COMMIT TRANSACTION;
            
        SET @RowsAffected = @@ROWCOUNT;
        RETURN 0;
        
    END TRY
    BEGIN CATCH
        -- Rollback si iniciamos la transacción
        IF @TransactionStarted = 1 AND @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
            
        -- Capturar información del error
        SET @ErrorMessage = ERROR_MESSAGE();
        
        -- Re-lanzar el error
        THROW;
    END CATCH
END
GO
```

### 2.2 Ejemplo: Stored Procedure de Consulta

```sql
-- =============================================
-- Author:           {team}
-- Created:  2026-01-24
-- Description:     Obtiene nominations con paginación y filtros
-- =============================================
CREATE OR ALTER PROCEDURE [scholarships].[GetNominations]
    @Status NVARCHAR(50) = NULL,
    @FromDate DATE = NULL,
    @ToDate DATE = NULL,
    @PageNumber INT = 1,
    @PageSize INT = 20,
    @TotalCount INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Calcular total
    SELECT @TotalCount = COUNT(*)
    FROM scholarships.Nomination n
    WHERE (@Status IS NULL OR n.Status = @Status)
      AND (@FromDate IS NULL OR n.CreatedAt >= @FromDate)
      AND (@ToDate IS NULL OR n.CreatedAt <= @ToDate);
    
    -- Obtener página
    SELECT 
        n.Id,
        n.StudentId,
        e.Name AS StudentName,
        n.Status,
        n.CreatedAt,
        n.ModifiedAt
    FROM scholarships.Nomination n
    INNER JOIN academic.Student e ON n.StudentId = e.Id
    WHERE (@Status IS NULL OR n.Status = @Status)
      AND (@FromDate IS NULL OR n.CreatedAt >= @FromDate)
      AND (@ToDate IS NULL OR n.CreatedAt <= @ToDate)
    ORDER BY n.CreatedAt DESC
    OFFSET (@PageNumber - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY;
END
GO
```

---

## PARTE 3: PLANTILLA DE FUNCIONES

### 3.1 Función Escalar

```sql
-- =============================================
-- Author:           {team}
-- Created:  2026-01-24
-- Description:     Calcula la tasa aplicable
-- =============================================
CREATE OR ALTER FUNCTION [scholarships].[fn_CalculateRate]
(
    @ExchangeType NVARCHAR(50),
    @Duration INT
)
RETURNS DECIMAL(18,2)
AS
BEGIN
    DECLARE @Rate DECIMAL(18,2);
    
    SELECT @Rate = CASE 
        WHEN @ExchangeType = 'ERASMUS' AND @Duration <= 3 THEN 250.00
        WHEN @ExchangeType = 'ERASMUS' AND @Duration <= 6 THEN 200.00
        WHEN @ExchangeType = 'ERASMUS' THEN 150.00
        WHEN @ExchangeType = 'BILATERAL' THEN 300.00
        ELSE 0.00
    END;
    
    RETURN @Rate;
END
GO
```

### 3.2 Función con Valor de Tabla (TVF)

```sql
-- =============================================
-- Author:           {team}
-- Created:  2026-01-24
-- Description:     Obtiene scholarships por año académico
-- =============================================
CREATE OR ALTER FUNCTION [scholarships].[fnt_GetScholarshipsByYear]
(
    @AcademicYear INT
)
RETURNS TABLE
AS
RETURN
(
    SELECT 
        b.Id,
        b.StudentId,
        e.Name AS StudentName,
        b.Amount,
        b.Status
    FROM scholarships.Scholarship b
    INNER JOIN academic.Student e ON b.StudentId = e.Id
    WHERE b.AcademicYear = @AcademicYear
);
GO
```

---

## PARTE 4: PLANTILLA DE VISTAS

```sql
-- =============================================
-- Author:           {team}
-- Created:  2026-01-24
-- Description:     Vista de nominations activas con información completa
-- =============================================
CREATE OR ALTER VIEW [scholarships].[vw_ActiveNominations]
AS
SELECT 
    n.Id,
    n.StudentId,
    e.Name AS StudentName,
    e.Email AS StudentEmail,
    n.DestinationUniversityId,
    u.Name AS DestinationUniversity,
    n.Status,
    n.CreatedAt,
    n.ModifiedAt,
    scholarships.fn_CalculateRate(n.ExchangeType, n.DurationMonths) AS ApplicableRate
FROM scholarships.Nomination n
INNER JOIN academic.Student e ON n.StudentId = e.Id
INNER JOIN scholarships.University u ON n.DestinationUniversityId = u.Id
WHERE n.Status IN ('Pending', 'InProgress', 'Approved');
GO
```

---

## PARTE 5: PALABRAS CLAVE T-SQL

### 5.1 Convención: MAYÚSCULAS

> ✅ Las palabras clave de T-SQL deben escribirse en **MAYÚSCULAS**

```sql
-- ✅ CORRECTO
SELECT Id, Name, CreatedAt
FROM scholarships.Nomination
WHERE Status = 'Activo'
ORDER BY CreatedAt DESC;

-- ❌ INCORRECTO
select id, name, fechacreacion
from scholarships.nomination
where status = 'Activo'
order by fechacreacion desc;
```

### 5.2 Lista de Palabras Clave Principales

```sql
-- DDL (Data Definition Language)
CREATE, ALTER, DROP, TRUNCATE, RENAME

-- DML (Data Manipulation Language)  
SELECT, INSERT, UPDATE, DELETE, MERGE

-- Cláusulas
FROM, WHERE, JOIN, INNER, LEFT, RIGHT, OUTER, FULL
ON, AND, OR, NOT, IN, EXISTS, BETWEEN, LIKE
GROUP BY, HAVING, ORDER BY, ASC, DESC
UNION, INTERSECT, EXCEPT

-- Funciones de agregación
COUNT, SUM, AVG, MIN, MAX, STRING_AGG

-- Control de flujo
IF, ELSE, BEGIN, END, WHILE, BREAK, CONTINUE
CASE, WHEN, THEN, ELSE, END
TRY, CATCH, THROW, RAISERROR

-- Transacciones
BEGIN TRANSACTION, COMMIT, ROLLBACK, SAVE TRANSACTION

-- Otros
DECLARE, SET, PRINT, RETURN
NULL, IS NULL, IS NOT NULL, COALESCE, ISNULL
TOP, OFFSET, FETCH, NEXT, ROWS, ONLY
WITH, AS, OVER, PARTITION BY, ROW_NUMBER
```

---

## PARTE 6: BUENAS PRÁCTICAS

### 6.1 Rendimiento

```sql
-- ✅ Usar EXISTS en lugar de IN para subconsultas
SELECT * FROM scholarships.Nomination n
WHERE EXISTS (SELECT 1 FROM academic.Student e WHERE e.Id = n.StudentId AND e.Active = 1);

-- ✅ Evitar SELECT *
SELECT Id, Name, Status FROM scholarships.Nomination;

-- ✅ Usar índices apropiados
CREATE NONCLUSTERED INDEX IX_Nomination_Status 
ON scholarships.Nomination(Status) INCLUDE (StudentId, CreatedAt);
```

### 6.2 Seguridad

```sql
-- ✅ Usar parámetros, nunca concatenar strings
EXEC scholarships.GetNomination @Id = @InputId;

-- ❌ NUNCA hacer esto (SQL Injection)
EXEC('SELECT * FROM Nomination WHERE Id = ' + @InputId);
```

### 6.3 Manejo de NULL

```sql
-- ✅ Usar COALESCE o ISNULL
SELECT COALESCE(n.Notes, 'No notes') AS Notes
FROM scholarships.Nomination n;

-- ✅ Comparar NULL correctamente
WHERE Campo IS NULL
WHERE Campo IS NOT NULL
```
