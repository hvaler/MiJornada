-- =============================================
-- PLANTILLA DE VISTA
-- {organizacion}
-- =============================================
-- Instrucciones:
--   1. Reemplazar {Placeholders} con valores reales
--   2. Ajustar JOINs según relaciones
--   3. Considerar si necesita ser indexada
-- =============================================

-- =============================================
-- Author:           {AuthorName}
-- Created:  {YYYY-MM-DD}
-- Description:     {ShortDescription}
-- Ticket/Evolutivo: {CodeEvolutivo}
-- =============================================

-- =============================================
-- VISTA ESTÁNDAR
-- =============================================
CREATE OR ALTER VIEW [{Schema}].[vw_{DescriptiveName}]
AS
    SELECT 
        -- Identificadores
        e.Id,
        e.Code,
        
        -- Campos principales
        e.Name,
        e.LastName,
        FullName = CONCAT(e.Name, ' ', e.LastName),
        e.Email,
        
        -- Campos calculados
        Age = DATEDIFF(YEAR, e.BirthDate, GETDATE()),
        
        -- Datos de relaciones
        r1.Name AS {Relacion1}Name,
        r1.Code AS {Relacion1}Code,
        r2.Description AS {Relacion2}Description,
        
        -- Campos de status
        e.Active,
        e.CreatedAt
        
    FROM [{Schema}].[{TablaBase}] e
    
    -- JOINs con tablas relacionadas
    INNER JOIN [{Schema}].[{TablaRelacion1}] r1 
        ON r1.Id = e.{Relacion1}Id
    
    LEFT JOIN [{Schema}].[{TablaRelacion2}] r2 
        ON r2.Id = e.{Relacion2}Id
    
    -- Filtro base (solo activos)
    WHERE e.Active = 1;
GO

-- =============================================
-- PERMISOS
-- =============================================
-- GRANT SELECT ON [{Schema}].[vw_{DescriptiveName}] TO [db_app_reader];
-- GO


-- =============================================
-- VISTA INDEXADA (para consultas frecuentes)
-- =============================================
/*
-- IMPORTANTE: Solo usar cuando:
--   1. La consulta se ejecuta MUCHAS veces
--   2. Los datos base cambian POCO
--   3. El beneficio de rendimiento justifica el costo de mantenimiento

CREATE VIEW [{Schema}].[vw_{DescriptiveName}Indexed]
WITH SCHEMABINDING  -- REQUERIDO para vistas indexadas
AS
    SELECT 
        e.Id,
        e.Code,
        e.Name,
        r.Name AS RelacionNombre,
        COUNT_BIG(*) AS TotalRegistros  -- COUNT_BIG requerido
    FROM [dbo].[{TablaBase}] e  -- Debe usar dbo, no alias de schema
    INNER JOIN [dbo].[{TablaRelacion}] r 
        ON r.Id = e.RelacionId
    WHERE e.Active = 1
    GROUP BY 
        e.Id,
        e.Code,
        e.Name,
        r.Name;
GO

-- Crear índice clustered único (convierte en vista indexada)
CREATE UNIQUE CLUSTERED INDEX IX_vw_{DescriptiveName}Indexed
    ON [{Schema}].[vw_{DescriptiveName}Indexed](Id);
GO
*/


-- =============================================
-- EJEMPLOS DE VISTAS COMUNES
-- =============================================

/*
-- EJEMPLO 1: Vista de Students con toda la información
CREATE OR ALTER VIEW [academic].[vw_StudentsComplete]
AS
    SELECT 
        e.Id,
        e.DocumentNumber,
        td.Name AS DocumentType,
        e.Name,
        e.LastName,
        FullName = CONCAT(e.LastName, ', ', e.Name),
        e.Email,
        e.Phone,
        e.BirthDate,
        Age = DATEDIFF(YEAR, e.BirthDate, GETDATE()) -
            CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, e.BirthDate, GETDATE()), e.BirthDate) > GETDATE() 
                 THEN 1 ELSE 0 END,
        c.Code AS DegreeCode,
        c.Name AS DegreeNombre,
        f.Name AS FacultadNombre,
        es.Name AS Status,
        es.Color AS EstadoColor,
        e.CreatedAt AS RegisteredAt,
        e.Active
    FROM academic.Student e
    INNER JOIN dbo.DocumentType td ON td.Id = e.DocumentTypeId
    INNER JOIN academic.Degree c ON c.Id = e.DegreeId
    INNER JOIN academic.Facultad f ON f.Id = c.FacultadId
    INNER JOIN dbo.EstadoStudent es ON es.Id = e.EstadoId
    WHERE e.Active = 1;
GO


-- EJEMPLO 2: Vista de resumen para dashboards
CREATE OR ALTER VIEW [academic].[vw_EnrollmentSummary]
AS
    SELECT 
        p.Id AS PeriodId,
        p.Name AS PeriodName,
        c.Id AS DegreeId,
        c.Name AS DegreeNombre,
        f.Name AS FacultadNombre,
        COUNT(m.Id) AS TotalEnrollments,
        SUM(CASE WHEN m.EstadoId = 1 THEN 1 ELSE 0 END) AS EnrollmentsActive,
        SUM(CASE WHEN m.EstadoId = 2 THEN 1 ELSE 0 END) AS EnrollmentsBaja,
        MIN(m.EnrollmentDate) AS FirstEnrollment,
        MAX(m.EnrollmentDate) AS LastEnrollment
    FROM academic.Enrollment m
    INNER JOIN academic.Period p ON p.Id = m.PeriodId
    INNER JOIN academic.Student e ON e.Id = m.StudentId
    INNER JOIN academic.Degree c ON c.Id = e.DegreeId
    INNER JOIN academic.Facultad f ON f.Id = c.FacultadId
    WHERE m.Active = 1
    GROUP BY 
        p.Id, p.Name,
        c.Id, c.Name,
        f.Name;
GO


-- EJEMPLO 3: Vista para exportación (formato plano)
CREATE OR ALTER VIEW [academic].[vw_StudentsExport]
AS
    SELECT 
        e.DocumentNumber AS [Número Documento],
        e.Name AS [Name],
        e.LastName AS [LastName],
        e.Email AS [Email],
        FORMAT(e.BirthDate, 'dd/MM/yyyy') AS [Birth Date],
        c.Name AS [Degree],
        f.Name AS [Facultad],
        es.Name AS [Status],
        FORMAT(e.CreatedAt, 'dd/MM/yyyy HH:mm') AS [Registration Date]
    FROM academic.Student e
    INNER JOIN academic.Degree c ON c.Id = e.DegreeId
    INNER JOIN academic.Facultad f ON f.Id = c.FacultadId
    INNER JOIN dbo.EstadoStudent es ON es.Id = e.EstadoId
    WHERE e.Active = 1;
GO
*/
