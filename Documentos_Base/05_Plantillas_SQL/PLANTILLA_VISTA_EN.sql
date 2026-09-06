-- =============================================
-- VIEW TEMPLATE
-- {organizacion}
-- =============================================
-- Instructions:
--   1. Replace {Placeholders} with actual values
--   2. Adjust JOINs according to relationships
--   3. Consider if it needs to be indexed
-- =============================================

-- =============================================
-- Author:           {AuthorName}
-- Creation Date:    {YYYY-MM-DD}
-- Description:      {BriefDescription}
-- Ticket/Feature:   {FeatureCode}
-- =============================================

-- =============================================
-- STANDARD VIEW
-- =============================================
CREATE OR ALTER VIEW [{Schema}].[vw_{DescriptiveName}]
AS
    SELECT
        -- Identifiers
        e.Id,
        e.Code,

        -- Main fields
        e.Name,
        e.LastName,
        FullName = CONCAT(e.Name, ' ', e.LastName),
        e.Email,

        -- Calculated fields
        Age = DATEDIFF(YEAR, e.BirthDate, GETDATE()),

        -- Related data
        r1.Name AS {Relation1}Name,
        r1.Code AS {Relation1}Code,
        r2.Description AS {Relation2}Description,

        -- State fields
        e.Active,
        e.CreatedAt

    FROM [{Schema}].[{BaseTable}] e

    -- JOINs with related tables
    INNER JOIN [{Schema}].[{RelationTable1}] r1
        ON r1.Id = e.{Relation1}Id

    LEFT JOIN [{Schema}].[{RelationTable2}] r2
        ON r2.Id = e.{Relation2}Id

    -- Base filter (only active)
    WHERE e.Active = 1;
GO

-- =============================================
-- PERMISSIONS
-- =============================================
-- GRANT SELECT ON [{Schema}].[vw_{DescriptiveName}] TO [db_app_reader];
-- GO


-- =============================================
-- INDEXED VIEW (for frequent queries)
-- =============================================
/*
-- IMPORTANT: Only use when:
--   1. The query is executed VERY frequently
--   2. Base data changes RARELY
--   3. Performance benefit justifies maintenance cost

CREATE VIEW [{Schema}].[vw_{DescriptiveName}Indexed]
WITH SCHEMABINDING  -- REQUIRED for indexed views
AS
    SELECT
        e.Id,
        e.Code,
        e.Name,
        r.Name AS RelacionNombre,
        COUNT_BIG(*) AS TotalRegistros  -- COUNT_BIG required
    FROM [dbo].[{BaseTable}] e  -- Must use dbo, not schema alias
    INNER JOIN [dbo].[{RelationTable}] r
        ON r.Id = e.RelacionId
    WHERE e.Active = 1
    GROUP BY
        e.Id,
        e.Code,
        e.Name,
        r.Name;
GO

-- Create unique clustered index (converts to indexed view)
CREATE UNIQUE CLUSTERED INDEX IX_vw_{DescriptiveName}Indexed
    ON [{Schema}].[vw_{DescriptiveName}Indexed](Id);
GO
*/


-- =============================================
-- COMMON VIEW EXAMPLES
-- =============================================

/*
-- EXAMPLE 1: Students view with full information
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


-- EXAMPLE 2: Summary view for dashboards
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


-- EXAMPLE 3: View for export (flat format)
CREATE OR ALTER VIEW [academic].[vw_StudentsExport]
AS
    SELECT
        e.DocumentNumber AS [Document Number],
        e.Name AS [First Name],
        e.LastName AS [Last Name],
        e.Email AS [Email],
        FORMAT(e.BirthDate, 'dd/MM/yyyy') AS [Birth Date],
        c.Name AS [Program],
        f.Name AS [Faculty],
        es.Name AS [Status],
        FORMAT(e.CreatedAt, 'dd/MM/yyyy HH:mm') AS [Registration Date]
    FROM academic.Student e
    INNER JOIN academic.Degree c ON c.Id = e.DegreeId
    INNER JOIN academic.Facultad f ON f.Id = c.FacultadId
    INNER JOIN dbo.EstadoStudent es ON es.Id = e.EstadoId
    WHERE e.Active = 1;
GO
*/
