# Fase 3: Desarrollo

## Objetivo

Construir los módulos de negocio y endpoints del proyecto.

## Herramientas
- **GitHub Copilot** (Principal): Autocompletado y generación de código
- **Claude Code** (Revisión): Análisis y refactorización

---

## Estructura del Código (.NET)

```
03_Desarrollo/
├── MiProyecto.sln
├── MiProyecto.API/           # WebAPI - Controllers, Middleware
├── MiProyecto.Application/   # Casos de uso - Services, DTOs
├── MiProyecto.Domain/        # Entidades - Entities, ValueObjects
├── MiProyecto.Infrastructure/ # Implementaciones - Repositories, BlobStorage
└── MiProyecto.Tests/         # Pruebas
```

---

## Checklist

- [ ] Implementar controllers
- [ ] Desarrollar servicios de negocio
- [ ] Crear repositorios con Dapper
- [ ] Implementar validaciones
- [ ] Configurar inyección de dependencias
- [ ] Configurar Azure Key Vault
- [ ] Configurar Azure Blob Storage
- [ ] Configurar Redis para caché
- [ ] Revisión de código con Claude
- [ ] Tests unitarios básicos

---

## Uso de Copilot

- Escribir firma de método → Copilot sugiere implementación
- Escribir comentario descriptivo → Copilot genera código
- Tests: Escribir `[Fact]` → Copilot completa el test

## Revisión con Claude

```
Revisa el siguiente código y propón mejoras siguiendo
los Documentos_Base de la OTD:

[Pegar código]

Analiza:
- Aplicación de SOLID
- Code smells
- Seguridad (OWASP)
- Rendimiento
- Manejo de errores
```

---

## Reglas Importantes

Ver `Documentos_Base/01_Estructura_Tecnica/` para:
- Sin estado local (infraestructura balanceada)
- Azure Key Vault para secretos
- Azure Blob Storage para archivos
- Redis para caché distribuida
- Queries parametrizadas (SQL Injection)

---

## Enlaces

- [README principal](../README.md)
- [Anterior: Entorno](../02_Entorno/)
- [Siguiente: Pruebas](../04_Pruebas/)
