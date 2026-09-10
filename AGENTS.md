# AGENTS.md

Este archivo guía a Codex cuando trabaja en este repositorio.

## @imports (contexto automático)

@_hilo/ESTADO_PROYECTO.json
@_hilo/SESION_ACTUAL.md

> **Ovillo se usa como plugin y su andamio no se versiona aquí** (ADR-010, ampliado el
> 2026-09-08). El plugin `hv@ovillo` existe desde el 2026-09-09 y está instalado en el ámbito de
> usuario: de ahí salen los comandos `/hv:*`, los agents, los hooks y las reglas por ruta.
> Actualizarlo: `claude plugin update hv@ovillo` y reiniciar la sesión. Con el código en la raíz
> (ADR-011), las reglas del plugin condicionadas a `src/` no se activan aquí.
>
> **Lo que el plugin no puede traer lo dejó `/hv:init`** (ejecutado el 2026-09-09) en la copia de
> trabajo, **sin versionar** — está en `.gitignore`, así que un `git status` limpio con esas
> carpetas presentes es lo esperado: `.claude/` (`rules/` con las tres reglas incondicionales,
> `settings.json`, `CLAUDE_BASE*.md`, `CONFIGURACION.md`, `estructura-*.json`, `statusline.js`,
> `schemas/`, `scripts/`, `smoke-tests/`), `_patron/`, `INICIO_RAPIDO.md`, `VERSION.json` y
> `ecosystem.config.example.json`.
>
> **Lo deliberado fue borrar los 16 ficheros versionables que `/hv:init` sí crea**
> (`src/README.md`, `docs/{README,architecture,management,support,testing}`, `ops/**`,
> `docker-compose.yml`): son plantillas de proyecto de equipo (gestión, requisitos, actas, CI/CD)
> que no encajan en una app de escritorio personal sin base de datos ni pipeline, y con el código
> en la raíz `src/` se quedaría vacío. Re-ejecutar `/hv:init` es seguro (nunca sobrescribe), pero
> **volverá a crearlos**: hay que borrarlos otra vez.
>
> Todo lo retirado es recuperable: el andamio versionado, del historial (commit anterior a
> `fd5fb7e`); el clon `ovillo/`, re-clonando su repo.

---

## Información del Proyecto

| Campo | Valor |
|-------|-------|
| **Nombre** | Mi jornada |
| **Qué es** | App de escritorio que controla la presencia de Teams vía Microsoft Graph: Disponible al fichar, Fuera del trabajo al terminar |
| **Versión** | 0.11.0 — **instalada** en HUGOVALER vía `scripts/instalar.ps1` |
| **Framework** | .NET 8 (`net8.0-windows`), WinForms, C# 12 |
| **Código** | **la raíz del repositorio** — 13 ficheros `.cs` (~3.600 líneas), namespace plano `MiJornada`, sin `.sln` (ADR-011) |
| **Registro Entra** | `Mi jornada` — ClientId `dbcd6425-561b-4d91-a4d5-f0bb25b31241`, uno para todo el tenant |
| **Estado** | Backlog original cerrado (M1–M18). Sin verificar SOLO: cierre de jornada desde un segundo equipo real |

> **Excepciones deliberadas, no descuidos** (leer `_hilo/DECISIONES.md` antes de "corregir"):
> sin capas ni DI y namespace plano (ADR-007, con revisión pendiente de decisión del usuario),
> estado en JSON local (ADR-004 y ADR-009), sin base de datos, autenticación solo por código de
> dispositivo (ADR-002: el flujo interactivo no funciona en este tenant con equipos no
> gestionados). No hay tests (DT-011, asumido).

---

## Glosario del Dominio

| Término | Definición |
|---------|------------|
| **Jornada** | Periodo de trabajo de 7 h. Se persiste su **hora de fin**, nunca un contador de segundos |
| **Presencia preferida** | Estado que el usuario fija en Teams por encima del calculado. `setUserPreferredPresence` la **fija**; solo `clearUserPreferredPresence` devuelve el mando a Teams |
| **Sesión de presencia activa** | Teams abierto en algún dispositivo. **Sin ella, cambiar la presencia no hace nada y la llamada no falla** — es un fallo silencioso |
| **Fuera del trabajo** | La pareja `Offline`/`OffWork` de Graph |
| **Código de dispositivo** | Flujo de autenticación (copiar código, pegarlo en el navegador). Aquí es **obligatorio** |
| **Pausa** | Congela el restante usando `PausaDesde` como referencia. La hora de fin solo se desplaza al **reanudar** |
| **Anillo** | El indicador circular. Representa **lo que queda**: nace completo y va cediendo terreno |
| **Aviso** | Tarjeta de notificación propia (`Aviso.cs`). No usa globos de bandeja: con No molestar, Windows los descarta sin dejar rastro (TEC-016) |

---

## Comandos

```powershell
dotnet build                                   # desde la raiz; 0 avisos es el estandar del proyecto
.\bin\Debug\net8.0-windows\MiJornada.exe --datos <carpeta> --minutos 2   # probar sin tocar datos reales

cd scripts
.\instalar.ps1                                 # publicar + instalar para el usuario actual
.\desinstalar.ps1                              # conserva los datos salvo -ConDatos
```

- La app instalada vive en `%LOCALAPPDATA%\Programs\MiJornada`; sus datos en `%APPDATA%\MiJornada`.
- `--datos <carpeta>` redirige los datos: es como se prueba sin ensuciar lo real ni pedir códigos
  (copiando el `msal.cache` real a la carpeta de prueba).

---

## Estándares

- **C#**: 4 espacios; `PascalCase` métodos/clases, `_camelCase` campos privados; sufijo `Async`;
  XML docs en público. Los comentarios cuentan **por qué**, no qué.
- **Commits**: Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`), cuerpo en español, sin
  scope obligatorio. Rama única `main`, push directo (github-flow-simplificado).
- **Idioma**: código y documentación en español; los nombres de la API de Graph, tal cual.

---

## Sistema Hilo (memoria del proyecto — SÍ versionado)

| Fichero | Qué es | Cuándo leerlo |
|---|---|---|
| `_hilo/ESTADO_PROYECTO.json` | Estado y configuración | siempre (importado) |
| `_hilo/SESION_ACTUAL.md` | Traspaso entre sesiones | siempre (importado) |
| `_hilo/DECISIONES.md` | ADR-001…011, con su porqué | **antes de proponer cambios de enfoque** |
| `_hilo/LECCIONES.md` | PAT/ERR/TEC/PREF: lo que costó horas | **al empezar a tocar código** |
| `_hilo/FUNCIONALIDADES.md` | Módulos M1–M18 con sus decisiones | antes de modificar una funcionalidad |
| `_hilo/DEUDA_TECNICA.md` | DT-001…011 y su estado | antes de "arreglar" algo conocido |
| `_hilo/DEPENDENCIAS.md` | Paquetes, Graph, matriz de impacto | antes de tocar integraciones |

---

## Notas para Codex

1. **Medir antes de dar por bueno**: en este proyecto se verifica con capturas, muestreo de
   píxeles, UIAutomation o cargando el ensamblado en PowerShell 7 (TEC-011/014/015). "Compila"
   no es "funciona".
2. **Al probar contra Graph**: hace falta Teams abierto; restaurar la presencia al terminar
   (`clearUserPreferredPresence`); usar `--datos` y borrar los datos de prueba después.
3. **Encodings**: los `.ps1` con acentos van en UTF-8 **con** BOM (TEC-017); los JSON de
   `_hilo`, UTF-8 **sin** BOM.
4. **Emoji para los avisos**: verlos pintados en blanco a 30 pt antes de añadirlos — GDI los
   renderiza en monocromo y en color engañan todos (M16).
5. **`git status` limpio con carpetas ignoradas es lo esperado** (ADR-010).
