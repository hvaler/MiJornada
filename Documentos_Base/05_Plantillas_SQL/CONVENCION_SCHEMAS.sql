-- =============================================
-- CONVENCIÓN DE SCHEMAS
-- {organizacion}
-- =============================================
-- Este documento define la estructura de schemas
-- recomendada para organizar objetos de BD
-- =============================================


-- #############################################
-- 1. PRINCIPIOS DE ORGANIZACIÓN
-- #############################################

/*
Los schemas en SQL Server permiten:
  ✓ Agrupar objetos por dominio funcional
  ✓ Aplicar permisos a nivel de schema
  ✓ Evitar colisiones de nombres
  ✓ Facilitar el mantenimiento
  ✓ Mejorar la documentación implícita

CONVENCIÓN DE NOMBRADO:
  - Usar lowercase
  - Nombres cortos y descriptivos
  - Sin prefijos ni sufijos
  - Representar dominio de negocio
*/


-- #############################################
-- 2. SCHEMAS RECOMENDADOS
-- #############################################

-- =============================================
-- SCHEMA: dbo (default)
-- Uso: Objetos comunes/compartidos entre dominios
-- =============================================
-- Ya existe por defecto
-- Contiene:
--   - Tablas de catálogo compartidas (DocumentType, Country, etc.)
--   - Funciones utilitarias (fn_CalculateAge, fn_GetCurrentUser)
--   - Stored procedures comunes
--   - Tablas de configuración de aplicación
--   - Tablas de auditoría/log

-- =============================================
-- SCHEMA: academico
-- Uso: Gestión académica
-- =============================================
CREATE SCHEMA [academic] AUTHORIZATION [dbo];
GO

/*
Contiene:
  - Student, Profesor, Degree, Facultad
  - Enrollment, Asignatura, Horario
  - Calificacion, Expediente
  - Period, CursoAcademico
*/

-- =============================================
-- SCHEMA: financiero
-- Uso: Gestión financiera y contable
-- =============================================
CREATE SCHEMA [finance] AUTHORIZATION [dbo];
GO

/*
Contiene:
  - Invoice, InvoiceLine
  - Payment, FormaPayment
  - Cuenta, Movimiento
  - Presupuesto, PartidaPresupuestaria
  - Scholarship, ScholarshipApplication
*/

-- =============================================
-- SCHEMA: rrhh
-- Uso: Recursos Humanos
-- =============================================
CREATE SCHEMA [rrhh] AUTHORIZATION [dbo];
GO

/*
Contiene:
  - Empleado, Contrato
  - Department, Puesto
  - Nomina, Ausencia
  - Evaluacion
*/

-- =============================================
-- SCHEMA: seguridad
-- Uso: Autenticación y autorización
-- =============================================
CREATE SCHEMA [seguridad] AUTHORIZATION [dbo];
GO

/*
Contiene:
  - User, Rol, Permiso
  - UserRol, RolPermiso
  - SesionUser, TokenAcceso
  - AuditLogin
*/

-- =============================================
-- SCHEMA: comunicacion
-- Uso: Notificaciones y mensajería
-- =============================================
CREATE SCHEMA [comunicacion] AUTHORIZATION [dbo];
GO

/*
Contiene:
  - Notificacion, PlantillaEmail
  - MessageInterno, Adjunto
  - ColaEnvio, LogEnvio
*/

-- =============================================
-- SCHEMA: integracion
-- Uso: Integración con sistemas externos
-- =============================================
CREATE SCHEMA [integracion] AUTHORIZATION [dbo];
GO

/*
Contiene:
  - LogIntegracion
  - MapeoCodigos
  - ColaSincronizacion
  - ConfiguracionExterna
*/

-- =============================================
-- SCHEMA: staging
-- Uso: Datos temporales de carga/ETL
-- =============================================
CREATE SCHEMA [staging] AUTHORIZATION [dbo];
GO

/*
Contiene:
  - Tablas temporales de importación
  - Datos en proceso de validación
  - Colas de procesamiento
  
⚠️ Los datos en staging son TEMPORALES
*/

-- =============================================
-- SCHEMA: archivo
-- Uso: Datos históricos/archivados
-- =============================================
CREATE SCHEMA [archivo] AUTHORIZATION [dbo];
GO

/*
Contiene:
  - Versiones archivadas de tablas principales
  - Datos antiguos que ya no están activos
  - Históricos para reportes
*/

-- =============================================
-- SCHEMA: reporte
-- Uso: Vistas y objetos para reportería
-- =============================================
CREATE SCHEMA [reporte] AUTHORIZATION [dbo];
GO

/*
Contiene:
  - Vistas desnormalizadas para reportes
  - Tablas agregadas/resumen
  - SPs específicos de reportes
  
💡 Separar reportes mejora el rendimiento
   al permitir optimizaciones específicas
*/


-- #############################################
-- 3. EJEMPLO DE ESTRUCTURA COMPLETA
-- #############################################

/*
Base de datos: MiOrganizacionDB
├── dbo (compartido)
│   ├── Tablas
│   │   ├── DocumentType
│   │   ├── Country
│   │   ├── Provincia
│   │   ├── EstadoGenerico
│   │   ├── ConfiguracionApp
│   │   └── ErrorLog
│   ├── Funciones
│   │   ├── fn_CalculateAge
│   │   ├── fn_GetCurrentUser
│   │   └── fn_FullName
│   └── Procedimientos
│       ├── usp_Error_Registrar
│       └── usp_Config_Obtener
│
├── academico
│   ├── Tablas
│   │   ├── Student
│   │   ├── Profesor
│   │   ├── Degree
│   │   ├── Facultad
│   │   ├── Asignatura
│   │   ├── Enrollment
│   │   ├── EnrollmentDetalle
│   │   ├── Calificacion
│   │   └── Period
│   ├── Vistas
│   │   ├── vw_ActiveStudents
│   │   ├── vw_EnrollmentsByPeriod
│   │   └── vw_CompleteTranscript
│   └── Procedimientos
│       ├── usp_Student_GetById
│       ├── usp_Student_Search
│       ├── usp_Enrollment_Procesar
│       └── usp_Calificacion_Registrar
│
├── financiero
│   ├── Tablas
│   │   ├── Invoice
│   │   ├── InvoiceLine
│   │   ├── Payment
│   │   ├── Scholarship
│   │   └── ScholarshipApplication
│   ├── Vistas
│   │   ├── vw_PendingInvoices
│   │   └── vw_PaymentSummary
│   └── Procedimientos
│       ├── usp_Invoice_Generar
│       ├── usp_Payment_Registrar
│       └── usp_Scholarship_Asignar
│
├── seguridad
│   ├── Tablas
│   │   ├── User
│   │   ├── Rol
│   │   ├── Permiso
│   │   ├── UserRol
│   │   └── AuditLogin
│   └── Procedimientos
│       ├── usp_User_Autenticar
│       ├── usp_User_GetPermisos
│       └── usp_Audit_RegistrarLogin
│
└── reporte
    ├── Vistas
    │   ├── vw_Rpt_EnrollmentsByDegree
    │   ├── vw_Rpt_RevenueByPeriod
    │   └── vw_Rpt_ActiveStudents
    └── Procedimientos
        ├── usp_Rpt_ResumenAcademico
        └── usp_Rpt_EstadoFinanciero
*/


-- #############################################
-- 4. PERMISOS POR SCHEMA
-- #############################################

-- Crear roles de base de datos
CREATE ROLE [db_academico_reader];
CREATE ROLE [db_academico_writer];
CREATE ROLE [db_financiero_reader];
CREATE ROLE [db_financiero_writer];
CREATE ROLE [db_reporte_reader];
GO

-- Asignar permisos a schemas
GRANT SELECT ON SCHEMA::[academic] TO [db_academico_reader];
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::[academic] TO [db_academico_writer];
GRANT EXECUTE ON SCHEMA::[academic] TO [db_academico_writer];

GRANT SELECT ON SCHEMA::[finance] TO [db_financiero_reader];
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::[finance] TO [db_financiero_writer];
GRANT EXECUTE ON SCHEMA::[finance] TO [db_financiero_writer];

GRANT SELECT ON SCHEMA::[reporte] TO [db_reporte_reader];
GO

-- Permisos de lectura en dbo para todos
GRANT SELECT ON SCHEMA::[dbo] TO [db_academico_reader];
GRANT SELECT ON SCHEMA::[dbo] TO [db_financiero_reader];
GRANT SELECT ON SCHEMA::[dbo] TO [db_reporte_reader];
GO


-- #############################################
-- 5. BUENAS PRÁCTICAS
-- #############################################

/*
✅ HACER:
   - Usar schemas para separar dominios funcionales
   - Aplicar permisos a nivel de schema (no tabla)
   - Mantener dbo para objetos compartidos
   - Crear schema de staging para ETL
   - Documentar el propósito de cada schema

❌ EVITAR:
   - Un schema por desarrollador
   - Schemas con nombres de aplicación (app1, app2)
   - Mezclar dominios en un solo schema
   - Schemas vacíos o sin uso
   - Cambiar objetos de schema frecuentemente

💡 TIPS:
   - Al crear objetos, SIEMPRE especificar schema:
     CREATE TABLE [academic].[Student]  ✓
     CREATE TABLE Student                ✗
   
   - Los schemas facilitan migraciones parciales
   - Usar schema [archivo] para datos históricos
   - Schema [staging] se puede limpiar periódicamente
*/


-- #############################################
-- 6. SCRIPT DE VERIFICACIÓN
-- #############################################

-- Ver todos los schemas y sus objetos
SELECT 
    s.name AS [Schema],
    o.type_desc AS TipoObjeto,
    COUNT(*) AS Amount
FROM sys.objects o
INNER JOIN sys.schemas s ON s.schema_id = o.schema_id
WHERE o.type IN ('U', 'V', 'P', 'FN', 'IF', 'TF')  -- Tablas, Vistas, SPs, Funciones
  AND s.name NOT IN ('sys', 'INFORMATION_SCHEMA')
GROUP BY s.name, o.type_desc
ORDER BY s.name, o.type_desc;
GO

-- Ver permisos por schema
SELECT 
    p.state_desc AS Status,
    p.permission_name AS Permiso,
    s.name AS [Schema],
    dp.name AS Principal
FROM sys.database_permissions p
INNER JOIN sys.schemas s ON s.schema_id = p.major_id
INNER JOIN sys.database_principals dp ON dp.principal_id = p.grantee_principal_id
WHERE p.class_desc = 'SCHEMA'
ORDER BY s.name, dp.name;
GO
