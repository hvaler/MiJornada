-- =============================================
-- PLANTILLA DE FUNCIONES
-- {organizacion}
-- =============================================
-- Este archivo contiene plantillas para:
--   1. Funciones Escalares (fn_)
--   2. Funciones con Valores de Tabla Inline (fnt_)
--   3. Funciones Multi-Statement (fnt_ - evitar si es posible)
-- =============================================


-- #############################################
-- FUNCIÓN ESCALAR (fn_)
-- #############################################
-- Uso: Devuelve un único valor
-- Prefijo: fn_

-- =============================================
-- Author:           {AuthorName}
-- Created:  {YYYY-MM-DD}
-- Description:     {ShortDescription}
-- =============================================
CREATE OR ALTER FUNCTION [{Schema}].[fn_{DescriptiveName}]
(
    @Parametro1 {TipoDato},
    @Parametro2 {TipoDato} = NULL  -- Parámetro opcional
)
RETURNS {TipoDatoRetorno}
AS
BEGIN
    -- Validar parámetros
    IF @Parametro1 IS NULL
        RETURN NULL;
    
    -- Variables locales
    DECLARE @Result {TipoDatoRetorno};
    
    -- Lógica de la función
    SET @Result = {CalculoOLogica};
    
    RETURN @Result;
END
GO

-- Ejemplo de uso:
-- SELECT dbo.fn_{DescriptiveName}('valor1', 'valor2');
-- SELECT *, dbo.fn_{DescriptiveName}(Columna1, Columna2) AS Calculado FROM Tabla;


-- #############################################
-- FUNCIÓN CON VALORES DE TABLA INLINE (fnt_)
-- #############################################
-- Uso: Devuelve una tabla (mejor rendimiento)
-- Prefijo: fnt_
-- RECOMENDADA sobre Multi-Statement

-- =============================================
-- Author:           {AuthorName}
-- Created:  {YYYY-MM-DD}
-- Description:     {ShortDescription}
-- =============================================
CREATE OR ALTER FUNCTION [{Schema}].[fnt_{DescriptiveName}]
(
    @Parametro1 {TipoDato},
    @Parametro2 {TipoDato} = NULL
)
RETURNS TABLE
AS
RETURN
(
    SELECT 
        t.Id,
        t.Columna1,
        t.Columna2,
        r.Name AS RelacionNombre
    FROM [{Schema}].[{Table}] t
    INNER JOIN [{Schema}].[{TablaRelacion}] r ON r.Id = t.RelacionId
    WHERE t.Active = 1
      AND (@Parametro1 IS NULL OR t.Columna1 = @Parametro1)
      AND (@Parametro2 IS NULL OR t.Columna2 = @Parametro2)
);
GO

-- Ejemplo de uso:
-- SELECT * FROM dbo.fnt_{DescriptiveName}('valor1', NULL);
-- SELECT e.*, f.* FROM Empleado e CROSS APPLY dbo.fnt_{DescriptiveName}(e.Id, NULL) f;


-- #############################################
-- FUNCIÓN MULTI-STATEMENT (fnt_)
-- #############################################
-- ⚠️ EVITAR SI ES POSIBLE - Peor rendimiento
-- Usar solo cuando la lógica es muy compleja

-- =============================================
-- Author:           {AuthorName}
-- Created:  {YYYY-MM-DD}
-- Description:     {ShortDescription}
-- Nota:            Usar solo si TVF inline no es viable
-- =============================================
CREATE OR ALTER FUNCTION [{Schema}].[fnt_{DescriptiveName}Multi]
(
    @Parametro1 {TipoDato}
)
RETURNS @Result TABLE
(
    Id INT,
    Name NVARCHAR(100),
    Level INT,
    Path NVARCHAR(500)
)
AS
BEGIN
    -- Lógica compleja (ej: recursión con CTE)
    ;WITH CTE_Recursivo AS
    (
        -- Ancla
        SELECT 
            Id, 
            Name, 
            1 AS Level,
            CAST(Name AS NVARCHAR(500)) AS Path
        FROM [{Schema}].[{Table}]
        WHERE Id = @Parametro1
        
        UNION ALL
        
        -- Parte recursiva
        SELECT 
            t.Id, 
            t.Name, 
            cte.Level + 1,
            CAST(cte.Path + ' > ' + t.Name AS NVARCHAR(500))
        FROM [{Schema}].[{Table}] t
        INNER JOIN CTE_Recursivo cte ON t.PadreId = cte.Id
    )
    INSERT INTO @Result
    SELECT Id, Name, Level, Path
    FROM CTE_Recursivo
    OPTION (MAXRECURSION 10);
    
    RETURN;
END
GO


-- #############################################
-- EJEMPLOS DE FUNCIONES COMUNES
-- #############################################

/*
-- EJEMPLO 1: Calcular edad (escalar)
CREATE OR ALTER FUNCTION [dbo].[fn_CalculateAge]
(
    @BirthDate DATE
)
RETURNS INT
AS
BEGIN
    IF @BirthDate IS NULL OR @BirthDate > GETDATE()
        RETURN NULL;
    
    RETURN DATEDIFF(YEAR, @BirthDate, GETDATE()) -
        CASE 
            WHEN DATEADD(YEAR, DATEDIFF(YEAR, @BirthDate, GETDATE()), @BirthDate) > GETDATE()
            THEN 1 
            ELSE 0 
        END;
END
GO

-- Uso: SELECT dbo.fn_CalculateAge('1990-05-15');  -- Devuelve: 35


-- EJEMPLO 2: Formatear name completo (escalar)
CREATE OR ALTER FUNCTION [dbo].[fn_FullName]
(
    @Name NVARCHAR(100),
    @LastName NVARCHAR(100),
    @Formato NVARCHAR(10) = 'NA'  -- 'NA' = Name LastName, 'AN' = LastName, Name
)
RETURNS NVARCHAR(250)
AS
BEGIN
    IF @Name IS NULL AND @LastName IS NULL
        RETURN NULL;
    
    RETURN CASE @Formato
        WHEN 'AN' THEN CONCAT(LTRIM(RTRIM(@LastName)), ', ', LTRIM(RTRIM(@Name)))
        ELSE CONCAT(LTRIM(RTRIM(@Name)), ' ', LTRIM(RTRIM(@LastName)))
    END;
END
GO

-- Uso: SELECT dbo.fn_FullName('Juan', 'García López', 'AN');  -- Devuelve: García López, Juan


-- EJEMPLO 3: Obtener user actual (compatible Azure SQL)
CREATE OR ALTER FUNCTION [dbo].[fn_GetCurrentUser]()
RETURNS NVARCHAR(100)
AS
BEGIN
    RETURN COALESCE(
        NULLIF(SUSER_SNAME(), ''),
        NULLIF(SYSTEM_USER, ''),
        'SYSTEM'
    );
END
GO

-- Uso: SELECT dbo.fn_GetCurrentUser();


-- EJEMPLO 4: Obtener scholarships por student (TVF inline)
CREATE OR ALTER FUNCTION [academic].[fnt_ScholarshipsByStudent]
(
    @StudentId INT
)
RETURNS TABLE
AS
RETURN
(
    SELECT 
        b.Id AS ScholarshipId,
        b.Code AS ScholarshipCode,
        b.Name AS ScholarshipNombre,
        b.Porcentaje,
        sb.AssignedDate,
        sb.DueDate,
        eb.Name AS Status,
        eb.Color AS EstadoColor,
        CASE 
            WHEN sb.DueDate < GETDATE() THEN 1 
            ELSE 0 
        END AS Vencida
    FROM academic.ScholarshipApplication sb
    INNER JOIN academic.Scholarship b ON b.Id = sb.ScholarshipId
    INNER JOIN dbo.ScholarshipStatus eb ON eb.Id = sb.EstadoId
    WHERE sb.StudentId = @StudentId
      AND sb.Active = 1
);
GO

-- Uso: 
-- SELECT * FROM academic.fnt_ScholarshipsByStudent(123);
-- SELECT e.Name, b.* FROM Student e CROSS APPLY academic.fnt_ScholarshipsByStudent(e.Id) b;


-- EJEMPLO 5: Validar formato de email (escalar)
CREATE OR ALTER FUNCTION [dbo].[fn_IsValidEmail]
(
    @Email NVARCHAR(256)
)
RETURNS BIT
AS
BEGIN
    IF @Email IS NULL OR LEN(@Email) < 5
        RETURN 0;
    
    -- Validación básica de formato email
    IF @Email LIKE '%_@_%.__%'
       AND @Email NOT LIKE '%[^a-zA-Z0-9.@_-]%'
       AND @Email NOT LIKE '%..%'
       AND @Email NOT LIKE '.%'
       AND @Email NOT LIKE '%.'
        RETURN 1;
    
    RETURN 0;
END
GO

-- Uso: SELECT dbo.fn_IsValidEmail('user@dominio.com');  -- Devuelve: 1


-- EJEMPLO 6: Obtener jerarquía de departamentos (Multi-Statement - necesario para recursión)
CREATE OR ALTER FUNCTION [rrhh].[fnt_DepartmentHierarchy]
(
    @DepartmentId INT
)
RETURNS @Result TABLE
(
    Id INT,
    Name NVARCHAR(100),
    Level INT,
    Path NVARCHAR(500),
    IsRoot BIT
)
AS
BEGIN
    ;WITH CTE_Jerarquia AS
    (
        -- Ancla: departamento raíz
        SELECT 
            d.Id, 
            d.Name, 
            1 AS Level,
            CAST(d.Name AS NVARCHAR(500)) AS Path,
            CAST(1 AS BIT) AS IsRoot
        FROM rrhh.Department d
        WHERE d.Id = @DepartmentId
          AND d.Active = 1
        
        UNION ALL
        
        -- Recursivo: subdepartamentos
        SELECT 
            d.Id, 
            d.Name, 
            cte.Level + 1,
            CAST(cte.Path + ' > ' + d.Name AS NVARCHAR(500)),
            CAST(0 AS BIT)
        FROM rrhh.Department d
        INNER JOIN CTE_Jerarquia cte ON d.DepartmentPadreId = cte.Id
        WHERE d.Active = 1
    )
    INSERT INTO @Result (Id, Name, Level, Path, IsRoot)
    SELECT Id, Name, Level, Path, IsRoot
    FROM CTE_Jerarquia
    OPTION (MAXRECURSION 20);
    
    RETURN;
END
GO

-- Uso: SELECT * FROM rrhh.fnt_DepartmentHierarchy(1) ORDER BY Level, Name;
*/


-- =============================================
-- BUENAS PRÁCTICAS PARA FUNCIONES
-- =============================================
/*
✅ HACER:
   - Usar fn_ para escalares, fnt_ para tablas
   - Preferir TVF inline sobre Multi-Statement
   - Validar parámetros NULL al start
   - Documentar con cabecera estándar
   - Usar funciones para cálculos reutilizables

❌ EVITAR:
   - Funciones Multi-Statement para queries simples
   - Acceso a datos externos en funciones escalares
   - Funciones con efectos secundarios (INSERT, UPDATE)
   - Funciones con lógica muy compleja (mejor usar SP)
   - Usar funciones en WHERE de columnas indexadas
     -- ❌ WHERE dbo.fn_Algo(Columna) = 'valor'  -- No usa índice
     -- ✅ WHERE Columna = dbo.fn_Algo('valor')  -- Puede usar índice

⚠️ RENDIMIENTO:
   Las funciones escalares en SELECT se ejecutan una vez por fila.
   Para grandes volúmenes, considerar:
   - Calcular en la query directamente
   - Usar CROSS APPLY con TVF inline
   - Pre-calcular y almacenar el valor
*/
