-- =============================================
-- PLANTILLA DE TABLA DE CATÁLOGO (LOOKUP)
-- {organizacion}
-- =============================================
-- Uso: Tablas maestras de valores predefinidos
-- Ejemplos: DocumentType, ApplicationStatus, Country, etc.
-- =============================================

-- =============================================
-- Author:           {AuthorName}
-- Created:  {YYYY-MM-DD}
-- Description:     Catálogo de {DescriptionCatalogo}
-- Ticket/Evolutivo: {CodeEvolutivo}
-- =============================================

-- =============================================
-- CONVENCIÓN DE NOMBRADO PARA CATÁLOGOS
-- =============================================
/*
Usar nombres descriptivos en singular sin prefijo:

✅ CORRECTO:
   - DocumentType
   - ApplicationStatus
   - EducationLevel
   - Country
   - Provincia
   - MotivoBaja

❌ EVITAR:
   - Cat_DocumentType    (prefijo innecesario)
   - Lkp_Estado           (prefijo innecesario)
   - TiposDocumentos      (plural)
   - tbl_DocumentType    (prefijo húngaro)
   - TIPO_DOCUMENTO       (mayúsculas)
*/

-- =============================================
-- ESTRUCTURA ESTÁNDAR DE CATÁLOGO
-- =============================================
CREATE TABLE [{Schema}].[{CatalogName}]
(
    -- Primary Key (INT para catálogos pequeños)
    Id INT IDENTITY(1,1) NOT NULL,
    
    -- ==========================================
    -- CAMPOS ESTÁNDAR DE CATÁLOGO
    -- ==========================================
    
    -- Código corto (para uso en código/reportes)
    Code NVARCHAR(20) NOT NULL,
    
    -- Name para mostrar en UI
    Name NVARCHAR(100) NOT NULL,
    
    -- Descripción extendida (tooltips, ayuda)
    Description NVARCHAR(500) NULL,
    
    -- SortOrder de visualización en listas
    SortOrder INT NOT NULL DEFAULT 0,
    
    -- ==========================================
    -- CAMPOS OPCIONALES (según necesidad)
    -- ==========================================
    
    -- Valor asociado (para cálculos)
    -- Valor DECIMAL(18,2) NULL,
    
    -- Código externo (integración con otros sistemas)
    -- CodeExterno NVARCHAR(50) NULL,
    
    -- Ícono o clase CSS (para UI)
    -- Icono NVARCHAR(50) NULL,
    
    -- Color (para badges, estados visuales)
    -- Color NVARCHAR(7) NULL,  -- Formato: #RRGGBB
    
    -- Configuración JSON (datos flexibles)
    -- Configuracion NVARCHAR(MAX) NULL,
    
    -- Categoría padre (para catálogos jerárquicos)
    -- CategoryId INT NULL,
    
    -- ==========================================
    -- CAMPOS DE AUDITORÍA
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
    
    -- Para catálogos jerárquicos:
    -- CONSTRAINT FK_{CatalogName}_Category
    --     FOREIGN KEY (CategoryId) 
    --     REFERENCES [{Schema}].[{CatalogName}](Id)
);
GO

-- =============================================
-- ÍNDICES
-- =============================================

-- Índice para búsqueda por código
CREATE NONCLUSTERED INDEX IX_{CatalogName}_Code
    ON [{Schema}].[{CatalogName}](Code)
    WHERE Active = 1;
GO

-- Índice para listados ordenados
CREATE NONCLUSTERED INDEX IX_{CatalogName}_Orden
    ON [{Schema}].[{CatalogName}](SortOrder, Name)
    WHERE Active = 1;
GO

-- =============================================
-- DATOS INICIALES (SEED)
-- =============================================
/*
-- Insertar valores iniciales del catálogo
INSERT INTO [{Schema}].[{CatalogName}] (Code, Name, Description, SortOrder)
VALUES 
    ('COD1', 'Valor 1', 'Descripción del valor 1', 1),
    ('COD2', 'Valor 2', 'Descripción del valor 2', 2),
    ('COD3', 'Valor 3', 'Descripción del valor 3', 3);
*/

-- =============================================
-- EJEMPLOS DE CATÁLOGOS COMUNES
-- =============================================

/*
-- EJEMPLO 1: Tipo de Documento
CREATE TABLE [dbo].[DocumentType]
(
    Id INT IDENTITY(1,1) NOT NULL,
    Code NVARCHAR(20) NOT NULL,      -- 'DNI', 'NIE', 'PASAPORTE'
    Name NVARCHAR(100) NOT NULL,      -- 'DNI', 'NIE', 'Pasaporte'
    Description NVARCHAR(500) NULL,
    SortOrder INT NOT NULL DEFAULT 0,
    RequiresValidation BIT NOT NULL DEFAULT 0,  -- Campo específico
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
    ('OTRO', 'Otro documento', 99, 0);


-- EJEMPLO 2: Status de ScholarshipApplication (con colores)
CREATE TABLE [dbo].[ApplicationStatus]
(
    Id INT IDENTITY(1,1) NOT NULL,
    Code NVARCHAR(20) NOT NULL,       -- 'PEND', 'APROB', 'RECH'
    Name NVARCHAR(100) NOT NULL,       -- 'Pending', 'Approved', 'Rechazada'
    Description NVARCHAR(500) NULL,
    SortOrder INT NOT NULL DEFAULT 0,
    Color NVARCHAR(7) NULL,              -- '#FFC107', '#28A745', '#DC3545'
    EsFinal BIT NOT NULL DEFAULT 0,      -- Indica si es status terminal
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
    ('PENDIENTE', 'Pending de revisión', '#FFC107', 2, 0),
    ('EN_REVISION', 'En revisión', '#17A2B8', 3, 0),
    ('APROBADA', 'Approved', '#28A745', 4, 1),
    ('RECHAZADA', 'Rechazada', '#DC3545', 5, 1),
    ('CANCELADA', 'Cancelled', '#6C757D', 6, 1);


-- EJEMPLO 3: Catálogo jerárquico (Categorías)
CREATE TABLE [dbo].[Category]
(
    Id INT IDENTITY(1,1) NOT NULL,
    CategoryPadreId INT NULL,           -- NULL = categoría raíz
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
-- SP PARA OBTENER CATÁLOGO (patrón recomendado)
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
-- VISTA PARA CATÁLOGO (alternativa)
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
