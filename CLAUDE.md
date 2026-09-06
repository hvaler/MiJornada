# CLAUDE.md

Este archivo guía a Claude Code (claude.ai/code) cuando trabaja con código en este repositorio.

> **Nota:** Ejecuta `/init` para que Claude analice el proyecto y mejore este archivo con información específica.

---

## @imports (Contexto Automático)

@_hilo/ESTADO_PROYECTO.json
@_hilo/SESION_ACTUAL.md
@.claude/CLAUDE_BASE.md

> `_hilo/DEPENDENCIAS.md` y `_hilo/FUNCIONALIDADES.md` ya NO se importan (dieta de contexto,
> AUD-008): Claude los lee bajo demanda antes de modificar código con dependencias o
> funcionalidades documentadas — ver "Sistema Hilo" más abajo.

---

## Ecosistema Ovillo

| Componente | Carpeta | Proposito |
|------------|---------|-----------|
| **Ovillo** | `/` | Ecosistema completo: plantilla + comandos + skills + reglas |
| **Hilo** | `_hilo/` | Memoria del proyecto: estado, sesiones, lecciones, historial |
| **Patrón** | `_patron/` | Base de conocimiento: indice de Documentos_Base, rules, patterns |

> La identidad de la organizacion (nombre, namespace, IdP, cloud, CI/CD, tema) vive en
> `ecosystem.config.json` (copiar de `ecosystem.config.example.json`; validar con
> `node .claude/scripts/validate-config.js`). Sin ese archivo, defaults neutrales.

> Claude consulta **Hilo** para entender el estado actual del proyecto y **Patrón** para acceder a documentacion de referencia.

---

## Información del Proyecto

| Campo | Valor |
|-------|-------|
| **Nombre** | Mi jornada |
| **Versión** | 0.0.0 — sin publicar (el `.csproj` declara `1.0.0`) |
| **Tipo** | Aplicación de escritorio (WinForms, `WinExe`) |
| **Framework** | .NET 8 (`net8.0-windows`) |
| **Código** | `03_Desarrollo/` — 5 ficheros, namespace plano `MiJornada`, sin `.sln` |
| **Build** | ✅ Verde desde 2026-09-06 (0 errores, 0 advertencias) |

> ⚠️ **Compila, pero nunca se ha ejecutado.** Falta el `ClientId` de Entra ID en `Estado.cs`
> (DT-003), y sin ejecutar la app los riesgos de runtime DT-004 a DT-007 siguen sin verificar.
> Un build verde no dice nada sobre ellos. Leer `_hilo/DEUDA_TECNICA.md` antes de tocar código.

> Este proyecto es una **excepción deliberada** a varias reglas de `CLAUDE_BASE.md`: sin capas ni
> DI (ADR-007), namespace plano, y el estado en disco local (ADR-004) — que aquí es correcto,
> porque es una app de escritorio de un solo usuario, no un servicio balanceado. No hay base de
> datos, así que las reglas SQL no aplican. Ver `_hilo/DECISIONES.md` antes de "corregir" nada
> de esto.

---

## Glosario del Dominio

> **Propósito**: Definir términos de negocio específicos para que Claude entienda el contexto del proyecto.
> Completar durante `/onboarding` o manualmente. Evita redefinir términos en cada conversación.

| Término | Definición | Ejemplo de uso |
|---------|------------|----------------|
| **Jornada** | Periodo de trabajo de 7 h. Se persiste su **hora de fin**, nunca un contador de segundos | "Al iniciar la jornada se calcula `Fin = ahora + Config.Jornada`" |
| **Presencia preferida** | Estado que el usuario fija a mano en Teams, por encima del que Teams calcula solo. Se cambia con `setUserPreferredPresence` | "Poner la presencia preferida en `Available` al fichar" |
| **Sesión de presencia activa** | Que Teams esté abierto en algún dispositivo. **Sin ella, cambiar la presencia no hace nada** y la llamada no falla | "Sin sesión de presencia activa el cambio se pierde en silencio" |
| **Fuera del trabajo** | La pareja `Offline`/`OffWork` de Graph, que es como Teams muestra el fin de jornada | "Al llegar a cero, presencia a Fuera del trabajo" |
| **Código de dispositivo** | Flujo de autenticación en el que se copia un código y se pega en el navegador. Aquí es **obligatorio**: el interactivo falla por acceso condicional | "El código de dispositivo solo se pide la primera vez" |
| **Pausa** | Congela el restante usando `PausaDesde` como referencia en vez de `Now`. La hora de fin solo se desplaza al **reanudar** | "Reanudar suma los minutos parados a la hora de fin" |
| **Anillo** | El indicador circular de la ventana. Representa **lo que queda**: nace completo y va cediendo terreno | "El anillo se pone ámbar durante las pausas" |

<!--
EJEMPLOS (eliminar al completar):

Para una aplicación de becas:
| Scholarship | Ayuda económica otorgada a estudiantes según criterios académicos o socioeconómicos | "El estudiante solicita una Scholarship de Excelencia" |
| Convocatoria | Period en que se pueden solicitar becas, con fechas de inicio y fin | "La Convocatoria 2026 abre el 1 de marzo" |
| Adjudicación | Proceso de asignar becas a solicitantes que cumplen requisitos | "La Adjudicación se realiza tras el cierre de la convocatoria" |

Para una aplicación de RRHH:
| Empleado | Persona con contrato laboral activo en la organización | "El Empleado solicita vacaciones" |
| Nómina | Documento mensual con el desglose salarial | "La Nómina se genera el día 25 de cada mes" |
| Fichaje | Registro de entrada/salida del empleado | "El Fichaje se realiza mediante tarjeta RFID" |

CATEGORÍAS COMUNES:
- Entidades principales (Usuario, Cliente, Producto, Pedido...)
- Estados y flujos (Pendiente, Aprobado, Rechazado...)
- Procesos de negocio (Facturación, Matriculación, Validación...)
- Roles (Administrador, Gestor, Solicitante...)
- Métricas (KPI, SLA, Cobertura...)
-->

---

## Comandos Comunes

### Backend (.NET)

```bash
# Ejecutar desde la carpeta del proyecto o solución
dotnet build                              # Compilar
dotnet run                                # Ejecutar
dotnet test                               # Ejecutar todos los tests
dotnet test --filter "ClassName"          # Test específico
dotnet watch run                          # Hot reload

# Entity Framework (si aplica)
dotnet ef migrations add <Nombre> --project <Infra> --startup-project <API>
dotnet ef database update --project <Infra> --startup-project <API>
```

### Frontend (si aplica)

```bash
npm install                # Instalar dependencias
npm run dev                # Servidor desarrollo
npm run build              # Build producción
npm run test               # Tests
npm run lint               # Linting
```

### Docker (si aplica)

```bash
docker-compose up -d              # Levantar servicios
docker-compose up --build -d      # Rebuild y levantar
docker-compose down               # Parar servicios
```

---

## Workflows

### Crear/Modificar Endpoint API

Cuando crees o modifiques endpoints:

1. **Planificar** - Proponer cambios (método, ruta, payload) antes de implementar
2. **Confirmar** - Esperar aprobación del usuario
3. **Implementar** - Crear/modificar Controller, Service, Repository
4. **Documentar** - Actualizar archivo .http o Swagger
5. **Probar** - Ejecutar tests relacionados

### Nueva Funcionalidad

1. Ejecutar `/nuevo-evolutivo --spec "descripción"`
2. Crear spec en `_hilo/specs/`
3. Implementar siguiendo la arquitectura existente
4. Añadir tests unitarios
5. Actualizar `_hilo/FUNCIONALIDADES.md`
6. Ejecutar `/finalizar-evolutivo`

### Bug Fix

1. Identificar el archivo y línea del problema
2. Verificar si hay tests existentes
3. Crear test que reproduzca el bug
4. Implementar la corrección
5. Verificar que el test pasa
6. Actualizar `_hilo/HISTORIAL_CAMBIOS.md`

### Pre-Commit

1. Ejecutar `/revision` para análisis de impacto
2. Verificar que todos los tests pasen
3. Ejecutar `/commit` para mensaje estructurado

---

## Orquestacion del Trabajo

> Principios que Claude debe seguir para organizar su trabajo de forma efectiva.

### Planificacion

- **Proponer antes de implementar** - En cambios no triviales, presentar un plan breve (archivos afectados, enfoque) y esperar confirmacion antes de escribir codigo.
- **Descomponer tareas grandes** - Dividir en pasos claros y ejecutar uno a uno, verificando cada paso antes de continuar.
- **Identificar dependencias** - Antes de empezar, revisar `_hilo/DEPENDENCIAS.md` y la matriz de impacto para anticipar efectos colaterales.
- **Replanificar si falla** - Si un enfoque falla tras 2 intentos, detenerse y replantear la estrategia antes de seguir forzando.

### Verificacion

- **Compilar tras cada cambio significativo** - No acumular cambios sin verificar que el proyecto compila. Ejecutar `dotnet build` como checkpoint.
- **Revisar antes de entregar** - Releer el codigo generado con ojo critico antes de presentarlo. Buscar errores de sintaxis, imports faltantes, nombres inconsistentes.
- **Tests como validacion** - Ejecutar tests existentes despues de modificar codigo. Si no hay tests, proponer crearlos.
- **Comparar con main** - En refactors o cambios complejos, comparar el diff contra la rama principal para verificar que no se pierde comportamiento.

### Autonomia y Correccion

- **Corregir errores sin preguntar** - Si un build falla por un error evidente (typo, import faltante, parentesis), corregirlo directamente. Solo preguntar cuando la correccion implique una decision de diseno.
- **Documentar lo inesperado** - Si algo no funciona como se esperaba, documentarlo en `_hilo/LECCIONES.md` para futuras sesiones.
- **Arreglar CI sin que te lo pidan** - Si los tests de CI fallan tras un cambio, identificar la causa y corregirla directamente.

### Elegancia y Simplicidad

- **Solucion minima viable** - Implementar lo que se pide, no mas. Evitar over-engineering, abstracciones prematuras o features no solicitados.
- **Codigo legible sobre codigo ingenioso** - Preferir claridad. Un bloque de 5 lineas claras es mejor que una linea críptica de LINQ encadenado.
- **Respetar patrones existentes** - Antes de crear algo nuevo, buscar como se ha resuelto algo similar en el proyecto. Mantener consistencia.

### Lecciones Aprendidas

- **Consultar `_hilo/LECCIONES.md`** al inicio de cada sesion para evitar repetir errores conocidos.
- **Actualizar con `/sesion`** al final de cada sesion si se descubrio un patron util, se corrigio un error no trivial o se identifico una particularidad del proyecto.

---

## Estándares de Código

### C# / .NET

- **Indentación:** 4 espacios
- **Clases/Métodos:** `PascalCase`
- **Campos privados:** `_camelCase`
- **Variables locales:** `camelCase`
- **Interfaces:** `IPrefijo` (ej: `IUserService`)
- **Async:** Sufijo `Async` en métodos async
- **Comentarios:** XML docs en clases y métodos públicos

### Tests

- **Clase:** `<ClaseTesteada>Tests`
- **Método:** `<Method>_<Scenario>_<ExpectedResult>`
- **Patrón:** Arrange, Act, Assert (comentar cada sección)

### Commits

- **Formato:** Conventional Commits
- **Tipos:** `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`
- **Scope:** Nombre del módulo afectado

---

## Arquitectura

### Estructura de Carpetas

```
Proyecto/
├── CLAUDE.md                 ← Este archivo
├── _hilo/                   ← Hilo: Memoria del proyecto
├── _patron/                   ← Patrón: Indice de conocimiento
├── .claude/                  ← Comandos, reglas y skills
│   ├── commands/             # Comandos personalizados
│   ├── rules/                # Reglas condicionales
│   └── skills/               # Skills con auto-invocación
├── Documentos_Base/          ← Estándares de la organización
├── 00_Gestion/               ← Gestión del proyecto
├── 01_Diseño/                ← Arquitectura y diagramas
├── 03_Desarrollo/            ← Código fuente
├── 04_Pruebas/               ← Tests
└── 06_Documentacion/         ← Documentación
```

### Capas (Clean Architecture)

```
[API/Controllers] → [Application/Services] → [Domain/Entities]
                           ↓
                  [Infrastructure/Repositories] → [Database]
```

---

## Integraciones MCP (Model Context Protocol)

### Servidores Configurados

| Servidor | Scope | Uso |
|----------|-------|-----|
| **context7** | user | Documentación actualizada de 1000+ librerías y frameworks |

### Context7 - Documentación Actualizada (Uso Automatico)

Context7 proporciona documentación en tiempo real desde repositorios oficiales, eliminando alucinaciones y código desactualizado.

**INSTRUCCION PARA CLAUDE**: Cuando trabajes con librerias externas (.NET, NuGet, Azure SDK, JavaScript, etc.) y necesites consultar documentacion actualizada, usa **automaticamente** las herramientas de Context7 (`resolve-library-id` + `get-library-docs`) sin esperar a que el usuario lo pida. Esto incluye:
- Implementar codigo que use librerias de terceros
- Resolver dudas sobre APIs o patrones de una libreria
- Verificar sintaxis o versiones actualizadas de paquetes NuGet
- Configurar servicios de Azure, middleware, o frameworks

```
Ejemplos de uso automatico por Claude:
- Al implementar Entity Framework Core → consultar docs EF Core 10
- Al configurar Azure Key Vault → consultar docs Azure.Identity
- Al escribir tests → consultar docs xUnit/FluentAssertions
```

**Servidor**: el servicio público de Context7, o el mirror interno de la organización si
`ecosystem.config.json → mcp.context7Url` lo define (útil en intranets sin salida a internet).

**Configuración** (el instalador la aplica automáticamente):
```
claude mcp add --transport http --scope user context7 <context7Url>
```

### Instrucciones MCP

- Usar **Context7** siempre que necesites consultar documentación de librerías externas
- Preferir comandos nativos de Git sobre MCP para commits
- Documentar cualquier servidor MCP adicional configurado en el proyecto

### Hub Ovillo — Convenciones de configuración (ADR-037 + ADR-038)

> El Hub es **opcional y opt-in**: `ecosystem.config.json → hub.enabled` (default `false`).
> Sin Hub, los comandos `/mcp-*`, `/calidad-sync` y `/docs-sync` degradan con un mensaje claro.

> **CRÍTICO**: estas convenciones evitan bugs de privacidad y duplicación de identidad. Aplican a cualquier edición que toque `_hilo/ESTADO_PROYECTO.json.mcpSync` o `_hilo/.mcp-credentials.json`.

**Dos fuentes de verdad separadas, NO mezclar**:

| Archivo | Scope | Commiteable | Contiene |
|---|---|---|---|
| `_hilo/.mcp-project.json` | **per-PROYECTO** | ✅ sí | `projectId`, `serverUrl` — para que otros devs se unan via `/v2/join` al clonar |
| `_hilo/ESTADO_PROYECTO.json.mcpSync` | **per-PROYECTO** | ✅ sí | `habilitado`, `categorias`, `projectId` (duplicado), `ultimaSync` |
| `_hilo/.mcp-credentials.json` | **per-DEV** | ❌ no (gitignored) | `apiKey`, `devAlias`, `devEmail`, `telemetryOptIn` |

**Reglas absolutas**:

1. **NUNCA añadir `telemetryOptIn` en `ESTADO_PROYECTO.json.mcpSync`**. Es per-dev (cada dev decide individualmente con `/mcp-register`). Vive solo en `.mcp-credentials.json` (local) y `mcp.ProyectoDevs.TelemetryOptIn` (hub). Ponerlo en el JSON commiteable significa que un dev cambiaría el opt-in de todo el equipo sin consentimiento.

2. **NUNCA añadir `apiKey` o `devAlias` en `ESTADO_PROYECTO.json`**. Es per-dev. Si aparece, eliminarlo.

3. **`habilitado` lo activa el registro en el Hub** (`/mcp-register`, o el instalador SOLO si `hub.registerOnInstall=true` — el registro es siempre opt-in explícito, ADR-F000).

4. **Para cambiar opt-in de telemetría**: usar `/mcp-register` (privacy notice + 3 opciones). Esto actualiza `.mcp-credentials.json` local + POST `/v2/opt-in` al hub. Nunca editar `ESTADO_PROYECTO.json` para esto.

5. **Para "right to be forgotten"**: usar `/mcp-forget` (proyecto entero) o `/v2/leave` API (solo el dev). Nunca borrar `.mcp-credentials.json` manualmente sin desregistrar primero.

> Si encuentras `telemetryOptIn` en `ESTADO_PROYECTO.json.mcpSync`, **elimínalo** (es residual de versiones <v3.9.0).

### `/mcp-register` — ¿cuándo es necesario?

**Es el punto de entrada al Hub** (registro opt-in explícito, ADR-F000; el instalador solo
registra si la organización configuró `hub.registerOnInstall=true`). `/mcp-register`:

- ✅ Registra el proyecto en el Hub (`hub.url` del `ecosystem.config`) y crea
  `.mcp-project.json` (commiteable) + `.mcp-credentials.json` (gitignored)
- ✅ Habilita `/mcp-sync` (decisiones, lecciones, nugets, evolutivos, equipo, feedback),
  el dashboard de cartera y el heartbeat
- 🔔 Pregunta el opt-in de **telemetría de agents** con privacy notice (per-dev, revocable)

### Flujo típico para el primer dev del repo

```
1. cd MiProyecto/  (con el ecosistema instalado)
2. claude
3. /mcp-register   ← registra proyecto + dev en el Hub (requiere hub.enabled=true)
4. /mcp-sync       ← sincroniza decisiones/lecciones/F3 al hub
```

### Flujo para 2º dev (clona un repo ya registrado)

```
1. git clone <repo>     ← .mcp-project.json viene commiteado
2. cd repo/
3. /mcp-register        ← detecta .mcp-project.json → POST /v2/join con git config
                          user.email → genera su propia apiKey local
4. /mcp-sync            ← sincroniza con devAlias propio (no el del primer dev)
```

---

## Reglas del Proyecto

### Seguridad (CRÍTICO)

- ❌ NUNCA hardcodear passwords, API keys o secrets
- ❌ NUNCA exponer connection strings con credenciales
- ✅ SIEMPRE usar el servicio de secretos configurado (`cloud.secrets`) en producción
- ✅ SIEMPRE usar `customErrors mode="On"` en producción

### Infraestructura

- ❌ NUNCA guardar archivos en disco local si la infraestructura es balanceada
- ✅ SIEMPRE usar el storage configurado (`cloud.storage`) para archivos
- ✅ SIEMPRE usar caché distribuida (Redis) en infraestructura balanceada — nunca MemoryCache/Session en memoria

### Código

- ❌ NUNCA dejar catch vacíos o genéricos sin logging
- ❌ NUNCA usar `Console.WriteLine` en producción
- ✅ SIEMPRE manejar excepciones específicas
- ✅ SIEMPRE incluir tests para código nuevo

---

## Comandos Personalizados

| Comando | Descripción |
|---------|-------------|
| `/init` | Analizar proyecto y mejorar este archivo |
| `/onboarding` | Configuración guiada en 8 fases |
| `/analizar` | Análisis profundo con diagramas |
| `/analisis-arquitectura` | Auditoría arquitectónica formal (MD + HTML) |
| `/nuevo-evolutivo` | Iniciar nueva funcionalidad |
| `/commit` | Commit con mensaje estructurado |
| `/test` | Generar tests unitarios |
| `/estado` | Dashboard del proyecto |
| `/actualizar` | Actualizar el paquete del ecosistema |
| `/sos` | Ayuda y comandos disponibles |
| `/health-check` | Configurar health checks (/health, /ready, /live) |
| `/add-telemetry` | Configurar OpenTelemetry + Serilog + App Insights |
| `/add-resilience` | Configurar Polly policies en HttpClients |
| `/mcp-sync` | Sincronizar documentacion con el Hub del ecosistema |
| `/optimizar` | Diagnostico de contexto + recomendacion de compactacion |
| `/devops-sync` | Sincronizar con Azure DevOps: work items, wiki, boards (DRY-RUN) |

---

## Contexto Adicional

### Sistema Hilo

- `_hilo/ESTADO_PROYECTO.json` - Configuración y estado actual (schema de campos: `_hilo/ESTADO_PROYECTO.schema.md`)
- `_hilo/DEPENDENCIAS.md` - Stack tecnológico y NuGets — **leer (Read) antes de modificar código con dependencias/integraciones** (matriz de impacto)
- `_hilo/FUNCIONALIDADES.md` - Módulos y features — **leer (Read) antes de modificar una funcionalidad documentada**; actualizar tras implementar una nueva
- `_hilo/DEUDA_TECNICA.md` - Issues conocidos
- `_hilo/DECISIONES.md` - ADRs (Architecture Decision Records)
- `_hilo/LECCIONES.md` - Patrones, errores y particularidades aprendidas
- `_hilo/FEEDBACK_ECOSISTEMA.md` - Gaps/bugs del ECOSISTEMA detectados en este proyecto (FB-XXX, se suben al hub via /mcp-sync)
- `_hilo/HISTORIAL_CAMBIOS.md` - Changelog

### Documentos Base

- `Documentos_Base/01_Estructura_Tecnica/` - Stack y arquitectura
- `Documentos_Base/02_Diseño_Usabilidad/` - Guía de estilos UI
- `Documentos_Base/03_Consideraciones_Comunes/` - RGPD, normativa
- `Documentos_Base/06_Observabilidad/` - OpenTelemetry, Serilog, métricas
- `Documentos_Base/07_Resiliencia/` - Polly v8+, Health Checks, graceful shutdown

---

## Notas para Claude

1. **Leer contexto primero** - Antes de modificar, leer `_hilo/` para entender el estado
2. **Preguntar si hay dudas** - Especialmente sobre integraciones y dependencias
3. **Actualizar documentación** - Mantener `_hilo/` sincronizado con cambios
4. **Seguir patrones existentes** - Analizar código existente antes de crear nuevo
5. **Tests obligatorios** - Todo código nuevo debe tener tests
6. **Consultar lecciones** - Revisar `_hilo/LECCIONES.md` para evitar errores conocidos y aplicar patrones del proyecto
7. **JSONs Hilo** - Los hooks son Node: cualquier hook/script Node que escriba `_hilo/*.json` usa `writeHiloJson` de `.claude/hooks/lib/helpers.js` (serializador unico FB-004/FB-007: atomico, UTF-8 sin BOM, re-validacion). Si un script PowerShell de skill escribe JSON, usar `[System.IO.File]::WriteAllText` con UTF-8 sin BOM — NUNCA `Out-File`/`Set-Content -Encoding UTF8` (PS 5.1 mete BOM)

---

*Archivo generado por Ovillo - Ejecuta /init para personalizar*
