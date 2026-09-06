-- =============================================
-- PLANTILLA DE TABLA
-- {organizacion}
-- =============================================
-- Instrucciones:
--   1. Reemplazar {Placeholders} con valores reales
--   2. Ajustar columnas según necesidad
--   3. Agregar Foreign Keys correspondientes
--   4. Crear índices necesarios
-- =============================================

-- =============================================
-- Author:           {AuthorName}
-- Created:  {YYYY-MM-DD}
-- Description:     {ShortDescription}
-- Ticket/Evolutivo: {CodeEvolutivo}
-- =============================================

-- =============================================
-- CREAR TABLA
-- =============================================
CREATE TABLE [{Schema}].[{TableName}]
(
    -- ==========================================
    -- PRIMARY KEY
    -- ==========================================
    Id INT IDENTITY(1,1) NOT NULL,
    
    -- ==========================================
    -- COLUMNAS DE NEGOCIO
    -- ==========================================
    -- Ajustar según necesidades del negocio
    
    Code NVARCHAR(20) NOT NULL,               -- Código único de negocio
    Name NVARCHAR(100) NOT NULL,              -- Name descriptivo
    Description NVARCHAR(500) NULL,             -- Descripción opcional
    
    -- Ejemplo: Campos de texto
    -- Campo1 NVARCHAR(100) NOT NULL,
    -- Campo2 NVARCHAR(MAX) NULL,
    
    -- Ejemplo: Campos numéricos
    -- Amount INT NOT NULL DEFAULT 0,
    -- Monto DECIMAL(18,2) NOT NULL DEFAULT 0,
    -- Porcentaje DECIMAL(5,2) NULL,
    
    -- Ejemplo: Campos de fecha
    -- StartDate DATE NOT NULL,
    -- EndDate DATE NULL,
    -- EventTimestamp DATETIME2(3) NULL,
    
    -- Ejemplo: Campos booleanos
    -- EsPrincipal BIT NOT NULL DEFAULT 0,
    
    -- ==========================================
    -- FOREIGN KEYS (columnas)
    -- ==========================================
    -- {RelatedEntity}Id INT NOT NULL,
    -- {OtraEntidad}Id INT NULL,
    
    -- ==========================================
    -- CAMPOS DE AUDITORÍA (OBLIGATORIOS)
    -- ==========================================
    Active BIT NOT NULL 
        CONSTRAINT DF_{TableName}_Activo DEFAULT 1,
    
    CreatedAt DATETIME2(3) NOT NULL 
        CONSTRAINT DF_{TableName}_CreatedAt DEFAULT GETUTCDATE(),
    
    CreatedBy NVARCHAR(100) NOT NULL 
        CONSTRAINT DF_{TableName}_CreatedBy DEFAULT SYSTEM_USER,
    
    ModifiedAt DATETIME2(3) NULL,
    
    ModifiedBy NVARCHAR(100) NULL,
    
    -- ==========================================
    -- CONSTRAINTS
    -- ==========================================
    
    -- Primary Key
    CONSTRAINT PK_{TableName} 
        PRIMARY KEY CLUSTERED (Id),
    
    -- Unique constraints
    CONSTRAINT UX_{TableName}_Code 
        UNIQUE (Code)
    
    -- Foreign Keys (descomentar y ajustar)
    -- CONSTRAINT FK_{TableName}_{RelatedEntity}
    --     FOREIGN KEY ({RelatedEntity}Id) 
    --     REFERENCES {Schema}.{RelatedEntity}(Id),
    
    -- Check constraints (ejemplos)
    -- CONSTRAINT CK_{TableName}_Monto 
    --     CHECK (Monto >= 0),
    -- CONSTRAINT CK_{TableName}_Porcentaje 
    --     CHECK (Porcentaje BETWEEN 0 AND 100)
);
GO

-- =============================================
-- ÍNDICES
-- =============================================

-- Índice para búsquedas frecuentes
CREATE NONCLUSTERED INDEX IX_{TableName}_Code
    ON [{Schema}].[{TableName}](Code)
    WHERE Active = 1;
GO

-- Índice para Foreign Keys (SIEMPRE crear)
-- CREATE NONCLUSTERED INDEX IX_{TableName}_{RelatedEntity}Id
--     ON [{Schema}].[{TableName}]({RelatedEntity}Id);
-- GO

-- Índice covering para consultas frecuentes
-- CREATE NONCLUSTERED INDEX IX_{TableName}_Covering
--     ON [{Schema}].[{TableName}](Columna1, Columna2)
--     INCLUDE (Columna3, Columna4)
--     WHERE Active = 1;
-- GO

-- Índice para ordenamiento por fecha
CREATE NONCLUSTERED INDEX IX_{TableName}_CreatedAt
    ON [{Schema}].[{TableName}](CreatedAt DESC)
    WHERE Active = 1;
GO

-- =============================================
-- PERMISOS (ajustar según necesidad)
-- =============================================
-- GRANT SELECT ON [{Schema}].[{TableName}] TO [db_app_reader];
-- GRANT INSERT, UPDATE, DELETE ON [{Schema}].[{TableName}] TO [db_app_writer];
-- GO

-- =============================================
-- DOCUMENTACIÓN
-- =============================================
/*
Tabla: {Schema}.{TableName}
Descripción: {DescriptionDetallada}

Columnas principales:
- Id: Identificador único autoincremental
- Code: Código de negocio único
- Name: name descriptivo

Relaciones:
- {RelatedEntity}: FK hacia {Schema}.{RelatedEntity}

Índices:
- PK_{TableName}: Clustered en Id
- IX_{TableName}_Code: Para búsquedas por código
- IX_{TableName}_CreatedAt: Para ordenamiento cronológico
*/
