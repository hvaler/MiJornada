-- =============================================
-- CATALOG TABLE TEMPLATE (LOOKUP)
-- {organizacion}
-- =============================================
-- Use: Master tables for predefined values
-- Examples: DocumentType, ApplicationStatus, Country, etc.
-- =============================================

-- =============================================
-- Author:           {AuthorName}
-- Creation Date:    {YYYY-MM-DD}
-- Description:      Catalog of {CatalogDescription}
-- Ticket/Feature:   {FeatureCode}
-- =============================================

-- =============================================
-- NAMING CONVENTION FOR CATALOGS
-- =============================================
/*
Use descriptive singular names without prefix:

✅ CORRECT:
   - DocumentType
   - ApplicationStatus
   - EducationLevel
   - Country
   - Provincia
   - MotivoBaja

❌ AVOID:
   - Cat_DocumentType    (unnecessary prefix)
   - Lkp_Estado           (unnecessary prefix)
   - TiposDocumentos      (plural)
   - tbl_DocumentType    (Hungarian prefix)
   - TIPO_DOCUMENTO       (uppercase)
*/

-- =============================================
-- STANDARD CATALOG STRUCTURE
-- =============================================
CREATE TABLE [{Schema}].[{CatalogName}]
(
    -- Primary Key (INT for small catalogs)
    Id INT IDENTITY(1,1) NOT NULL,

    -- ==========================================
    -- STANDARD CATALOG FIELDS
    -- ==========================================

    -- Short code (for use in code/reports)
    Code NVARCHAR(20) NOT NULL,

    -- Name to display in UI
    Name NVARCHAR(100) NOT NULL,

    -- Extended description (tooltips, help)
    Description NVARCHAR(500) NULL,

    -- Display order in lists
    SortOrder INT NOT NULL DEFAULT 0,

    -- ==========================================
    -- OPTIONAL FIELDS (as needed)
    -- ==========================================

    -- Associated value (for calculations)
    -- Valor DECIMAL(18,2) NULL,

    -- External code (integration with other systems)
    -- CodeExterno NVARCHAR(50) NULL,

    -- Icon or CSS class (for UI)
    -- Icono NVARCHAR(50) NULL,

    -- Color (for badges, visual states)
    -- Color NVARCHAR(7) NULL,  -- Format: #RRGGBB

    -- JSON configuration (flexible data)
    -- Configuracion NVARCHAR(MAX) NULL,

    -- Parent category (for hierarchical catalogs)
    -- CategoryId INT NULL,

    -- ==========================================
    -- AUDIT FIELDS
    -- ==========================================
    Active BIT NOT NULL
        CONSTRAINT DF_{CatalogName}_Activo DEFAULT 1,

    CreatedAt DATETIME2(3) NOT NULL
        CONSTRAINT DF_{CatalogName}_CreatedAt DEFAULT GETUTCDATE(),

    CreatedBy NVARCHAR(100) NOT NULL
        CONSTRAINT DF_{CatalogName}_CreatedBy DEFAULT SYSTEM_USER,

    ModifiedAt DATETIME2(3) NULL,

    ModifiedBy NVARCHAR(100) NULL,

    -- ==========================================
    -- CONSTRAINTS
    -- ==========================================
    CONSTRAINT PK_{CatalogName}
        PRIMARY KEY CLUSTERED (Id),

    CONSTRAINT UX_{CatalogName}_Code
        UNIQUE (Code),

    CONSTRAINT UX_{CatalogName}_Nombre
        UNIQUE (Name)

    -- For hierarchical catalogs:
    -- CONSTRAINT FK_{CatalogName}_Category
    --     FOREIGN KEY (CategoryId)
    --     REFERENCES [{Schema}].[{CatalogName}](Id)
);
GO

-- =============================================
-- INDEXES
-- =============================================

-- Index for code search
CREATE NONCLUSTERED INDEX IX_{CatalogName}_Code
    ON [{Schema}].[{CatalogName}](Code)
    WHERE Active = 1;
GO

-- Index for ordered listings
CREATE NONCLUSTERED INDEX IX_{CatalogName}_Orden
    ON [{Schema}].[{CatalogName}](SortOrder, Name)
    WHERE Active = 1;
GO

-- =============================================
-- INITIAL DATA (SEED)
-- =============================================
/*
-- Insert initial catalog values
INSERT INTO [{Schema}].[{CatalogName}] (Code, Name, Description, SortOrder)
VALUES
    ('COD1', 'Value 1', 'Description of value 1', 1),
    ('COD2', 'Value 2', 'Description of value 2', 2),
    ('COD3', 'Value 3', 'Description of value 3', 3);
*/

-- =============================================
-- COMMON CATALOG EXAMPLES
-- =============================================

/*
-- EXAMPLE 1: Document Type
CREATE TABLE [dbo].[DocumentType]
(
    Id INT IDENTITY(1,1) NOT NULL,
    Code NVARCHAR(20) NOT NULL,      -- 'DNI', 'NIE', 'PASAPORTE'
    Name NVARCHAR(100) NOT NULL,      -- 'DNI', 'NIE', 'Pasaporte'
    Description NVARCHAR(500) NULL,
    SortOrder INT NOT NULL DEFAULT 0,
    RequiresValidation BIT NOT NULL DEFAULT 0,  -- Specific field
    Active BIT NOT NULL DEFAULT 1,
    CreatedAt DATETIME2(3) NOT NULL DEFAULT GETUTCDATE(),
    CreatedBy NVARCHAR(100) NOT NULL DEFAULT SYSTEM_USER,
    ModifiedAt DATETIME2(3) NULL,
    ModifiedBy NVARCHAR(100) NULL,
    CONSTRAINT PK_DocumentType PRIMARY KEY CLUSTERED (Id),
    CONSTRAINT UX_DocumentType_Code UNIQUE (Code)
);

INSERT INTO dbo.DocumentType (Code, Name, SortOrder, RequiresValidation)
VALUES
    ('DNI', 'DNI', 1, 1),
    ('NIE', 'NIE', 2, 1),
    ('PASAPORTE', 'Pasaporte', 3, 0),
    ('OTRO', 'Other document', 99, 0);


-- EXAMPLE 2: Application Status (with colors)
CREATE TABLE [dbo].[ApplicationStatus]
(
    Id INT IDENTITY(1,1) NOT NULL,
    Code NVARCHAR(20) NOT NULL,       -- 'PEND', 'APROB', 'RECH'
    Name NVARCHAR(100) NOT NULL,       -- 'Pending', 'Approved', 'Rejected'
    Description NVARCHAR(500) NULL,
    SortOrder INT NOT NULL DEFAULT 0,
    Color NVARCHAR(7) NULL,              -- '#FFC107', '#28A745', '#DC3545'
    EsFinal BIT NOT NULL DEFAULT 0,      -- Indicates if it's a terminal state
    Active BIT NOT NULL DEFAULT 1,
    CreatedAt DATETIME2(3) NOT NULL DEFAULT GETUTCDATE(),
    CreatedBy NVARCHAR(100) NOT NULL DEFAULT SYSTEM_USER,
    ModifiedAt DATETIME2(3) NULL,
    ModifiedBy NVARCHAR(100) NULL,
    CONSTRAINT PK_ApplicationStatus PRIMARY KEY CLUSTERED (Id),
    CONSTRAINT UX_ApplicationStatus_Code UNIQUE (Code)
);

INSERT INTO dbo.ApplicationStatus (Code, Name, Color, SortOrder, EsFinal)
VALUES
    ('BORRADOR', 'Draft', '#6C757D', 1, 0),
    ('PENDIENTE', 'Pending review', '#FFC107', 2, 0),
    ('EN_REVISION', 'Under review', '#17A2B8', 3, 0),
    ('APROBADA', 'Approved', '#28A745', 4, 1),
    ('RECHAZADA', 'Rejected', '#DC3545', 5, 1),
    ('CANCELADA', 'Canceled', '#6C757D', 6, 1);


-- EXAMPLE 3: Hierarchical catalog (Categories)
CREATE TABLE [dbo].[Category]
(
    Id INT IDENTITY(1,1) NOT NULL,
    CategoryPadreId INT NULL,           -- NULL = root category
    Code NVARCHAR(20) NOT NULL,
    Name NVARCHAR(100) NOT NULL,
    Description NVARCHAR(500) NULL,
    Level INT NOT NULL DEFAULT 1,
    SortOrder INT NOT NULL DEFAULT 0,
    Active BIT NOT NULL DEFAULT 1,
    CreatedAt DATETIME2(3) NOT NULL DEFAULT GETUTCDATE(),
    CreatedBy NVARCHAR(100) NOT NULL DEFAULT SYSTEM_USER,
    ModifiedAt DATETIME2(3) NULL,
    ModifiedBy NVARCHAR(100) NULL,
    CONSTRAINT PK_Category PRIMARY KEY CLUSTERED (Id),
    CONSTRAINT UX_Category_Code UNIQUE (Code),
    CONSTRAINT FK_Category_CategoryPadre
        FOREIGN KEY (CategoryPadreId) REFERENCES dbo.Category(Id)
);
*/

-- =============================================
-- SP TO GET CATALOG (recommended pattern)
-- =============================================
/*
CREATE OR ALTER PROCEDURE [dbo].[usp_{CatalogName}_GetAll]
    @SoloActive BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        Id,
        Code,
        Name,
        Description,
        SortOrder,
        Active
    FROM [{Schema}].[{CatalogName}]
    WHERE (@SoloActive = 0 OR Active = 1)
    ORDER BY SortOrder, Name;
END
GO
*/

-- =============================================
-- VIEW FOR CATALOG (alternative)
-- =============================================
/*
CREATE OR ALTER VIEW [dbo].[vw_{CatalogName}Active]
AS
    SELECT
        Id,
        Code,
        Name,
        Description,
        SortOrder
    FROM [{Schema}].[{CatalogName}]
    WHERE Active = 1;
GO
*/
