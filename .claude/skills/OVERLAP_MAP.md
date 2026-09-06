# Skill Overlap Map - Ovillo

> Mapa de solapamientos entre skills para evitar false triggers.
> Cada par documenta la frontera y la regla de resolucion.
> Referencia: Skills 2.0 FASE 2 - Trigger Evals

---

## Pares con Overlap Identificado

### 1. security-audit <-> cloud-config

| Aspecto | security-audit | cloud-config |
|---------|---------------|-------------|
| **Funcion** | DETECTA secretos expuestos | CONFIGURA Key Vault |
| **Verbo clave** | auditar, revisar, buscar, escanear | configurar, integrar, setup |
| **Keyword** | OWASP, vulnerabilidad, secret, hardcoded | Key Vault, Blob Storage, Redis |

**Regla**: "configurar Key Vault" -> cloud-config | "buscar secretos hardcodeados" -> security-audit

---

### 2. security-audit <-> api-integration-patterns

| Aspecto | security-audit | api-integration-patterns |
|---------|---------------|------------------------|
| **Funcion** | AUDITA flujos de autenticacion | IMPLEMENTA OAuth2/HttpClient |
| **Verbo clave** | auditar, revisar, verificar | implementar, conectar, integrar |
| **Keyword** | vulnerabilidad, CORS, headers | un sistema externo del catalogo, Oracle, HttpClientFactory |

**Regla**: "auditar autenticacion OAuth" -> security-audit | "implementar OAuth2 para un sistema externo del catalogo" -> api-integration-patterns

---

### 3. security-audit <-> testing-patterns

| Aspecto | security-audit | testing-patterns |
|---------|---------------|-----------------|
| **Funcion** | ANALIZA codigo existente por vulnerabilidades | GENERA tests nuevos |
| **Verbo clave** | revisar, auditar, escanear | generar, crear, escribir tests |
| **Keyword** | OWASP, CVSS, CWE, SAST | xUnit, Moq, FluentAssertions |

**Regla**: "revisar seguridad del codigo" -> security-audit | "crear tests de seguridad" -> testing-patterns

---

### 4. analisis-arquitectura <-> generador-crud

| Aspecto | analisis-arquitectura | generador-crud |
|---------|----------------------|---------------|
| **Funcion** | EVALUA compliance Clean Architecture | CREA codigo siguiendo el patron |
| **Verbo clave** | analizar, revisar, evaluar, auditar | crear, generar, scaffolding |
| **Keyword** | dependencias, capas, violaciones, diagrama | CRUD, Controller, Service, DTO |

**Regla**: "revisar si cumple Clean Architecture" -> analisis-arquitectura | "crear entidad con todas las capas" -> generador-crud

---

### 5. analisis-arquitectura <-> nugets-management

| Aspecto | analisis-arquitectura | nugets-management |
|---------|----------------------|-------------------|
| **Funcion** | Analiza dependencias entre CAPAS de codigo | Analiza dependencias de PAQUETES NuGet |
| **Verbo clave** | dependencias entre proyectos, capas | paquetes, NuGet, actualizar, CPM |
| **Keyword** | layer, module, reference, graph | package, version, vulnerable, outdated |

**Regla**: "dependencias entre proyectos .csproj" -> analisis-arquitectura | "NuGet desactualizados" -> nugets-management

---

### 6. observability-patterns <-> resilience-patterns

| Aspecto | observability-patterns | resilience-patterns |
|---------|----------------------|-------------------|
| **Funcion** | TELEMETRIA: logging, tracing, metricas | FIABILIDAD: retry, circuit breaker, health |
| **Verbo clave** | monitorizar, trazar, loguear | reintentar, recuperar, tolerancia |
| **Keyword** | OpenTelemetry, Serilog, App Insights | Polly, circuit breaker, health check |

**Regla**: "configurar logging y metricas" -> observability-patterns | "configurar retry y circuit breaker" -> resilience-patterns

**Nota**: Health checks es area gris. Si el contexto es "monitorizar" -> observability. Si el contexto es "recuperacion ante fallos" -> resilience.

---

### 7. generador-crud <-> api-integration-patterns

| Aspecto | generador-crud | api-integration-patterns |
|---------|---------------|------------------------|
| **Funcion** | Genera endpoints API INTERNOS (CRUD) | Conecta con APIs EXTERNAS |
| **Verbo clave** | crear endpoint, nueva entidad, CRUD | conectar, integrar, consumir API |
| **Keyword** | Controller, Service, Repository | sistema externo del catalogo, HttpClient |

**Regla**: "crear endpoint para Scholarships" -> generador-crud | "conectar con API un sistema externo del catalogo academico" -> api-integration-patterns

---

### 8. documentacion-tecnica <-> user-documentation

| Aspecto | documentacion-tecnica | user-documentation |
|---------|----------------------|-------------------|
| **Funcion** | Docs para DESARROLLADORES (ADR, API ref) | Docs para USUARIOS (guias, FAQ) |
| **Verbo clave** | documentar arquitectura, ADR, deployment | guia de uso, FAQ, manual usuario |
| **Keyword** | README, ADR, Mermaid, CONTRIBUTING | usuario, guia, FAQ, screenshot |

**Regla**: "crear ADR" -> documentacion-tecnica | "crear guia de uso para el usuario final" -> user-documentation

---

### 9. docs-agente-sync <-> analisis-arquitectura

| Aspecto | docs-agente-sync | analisis-arquitectura (--agente) |
|---------|------------------|----------------------------------|
| **Funcion** | REGISTRA el doc de agente + drift al hub | DERIVA/escribe el doc de agente |
| **Verbo clave** | sincronizar, publicar, registrar, drift | analizar, generar, derivar contexto |
| **Keyword** | DOC, docs-batch, srcStamp, stale, token budget | contexto de agente, entrypoint, derivar, sellar |

**Regla**: "genera el contexto de agente del proyecto" -> analisis-arquitectura --agente | "publica/registra el estado de los docs de agente" -> docs-agente-sync

---

### 10. docs-agente-sync <-> calidad-codigo-sync

| Aspecto | docs-agente-sync | calidad-codigo-sync |
|---------|------------------|---------------------|
| **Funcion** | Publica DOC (estado del contexto de agente) | Publica QR (metricas de calidad) |
| **Verbo clave** | sincronizar docs de agente, drift | sincronizar calidad, cobertura, CRAP |
| **Keyword** | DOC, contexto de agente, srcStamp, docs-batch | QR, cobertura, CRAP, NPath, quality-batch |

**Regla**: "sube el estado de docs de agente al hub" -> docs-agente-sync | "sube cobertura/CRAP al hub" -> calidad-codigo-sync
**Nota**: hermanos estructurales (mismo canal Hub, mismo patron best-effort), tipos de registro distintos (DOC vs QR).

---

### 11. docs-agente-sync <-> documentacion-tecnica

| Aspecto | docs-agente-sync | documentacion-tecnica |
|---------|------------------|-----------------------|
| **Funcion** | Estado de docs para AGENTES (machine-facing) | Docs para DESARROLLADORES (ADR/README/API-ref) |
| **Verbo clave** | registrar contexto de agente, drift | documentar arquitectura, ADR, API |
| **Keyword** | DOC, contexto de agente, docs-batch | README, ADR, Mermaid, CONTRIBUTING |

**Regla**: "estado de la doc que consume el agente de codigo" -> docs-agente-sync | "crear ADR/README de desarrollador" -> documentacion-tecnica

---

## Pares SIN Overlap Significativo

Estas combinaciones tienen fronteras claras y no requieren atencion especial:

| Skill A | Skill B | Razon |
|---------|---------|-------|
| webapp-layout | security-audit | Diseño visual vs seguridad |
| postman-collection | testing-patterns | Colecciones API vs tests unitarios |
| git-best-practices | generador-crud | Workflows Git vs generacion codigo |
| webapp-layout | analisis-arquitectura | Frontend design vs backend structure |

---

## Resumen de Densidad de Overlaps

| Skill | Overlaps | Pares |
|-------|----------|-------|
| security-audit | 3 | cloud-config, api-integration, testing-patterns |
| docs-agente-sync | 3 | analisis-arquitectura, calidad-codigo-sync, documentacion-tecnica |
| analisis-arquitectura | 3 | generador-crud, nugets-management, docs-agente-sync |
| generador-crud | 2 | analisis-arquitectura, api-integration-patterns |
| api-integration-patterns | 2 | security-audit, generador-crud |
| observability-patterns | 1 | resilience-patterns |
| resilience-patterns | 1 | observability-patterns |
| documentacion-tecnica | 2 | user-documentation, docs-agente-sync |
| user-documentation | 1 | documentacion-tecnica |
| calidad-codigo-sync | 1 | docs-agente-sync |
| cloud-config | 1 | security-audit |
| testing-patterns | 1 | security-audit |
| nugets-management | 1 | analisis-arquitectura |
| webapp-layout | 0 | - |
| git-best-practices | 0 | - |
| postman-collection | 0 | - |

---

*Skills 2.0 FASE 2 - Ovillo v3.7.0 | 2026-03-12*
