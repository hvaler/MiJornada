# Contexto Tecnico del Proyecto

> **INSTRUCCIONES PARA CLAUDE**: Este archivo contiene el stack tecnologico detectado del proyecto.
> Se genera automaticamente con `/onboarding` o `/analizar`. Consultalo para entender las
> tecnologias y versiones en uso antes de generar codigo.

> ⚠️ **El proyecto nunca se ha compilado.** Todo lo que sigue esta leido del codigo fuente y del
> `.csproj`, no verificado contra un build. Ver `_hilo/DEUDA_TECNICA.md` (DT-001).

---

## Stack Tecnologico

| Aspecto | Valor |
|---------|-------|
| **Framework** | `net8.0-windows` |
| **Tipo de proyecto** | Aplicacion de escritorio (WinForms), `OutputType=WinExe` |
| **Version .NET** | 8 (LTS, soporte hasta noviembre de 2026) |
| **Lenguaje** | C# 12, con `Nullable` e `ImplicitUsings` habilitados |
| **IDE** | Visual Studio 2022 / VS Code |
| **UI** | WinForms con dibujado GDI+ a mano (`System.Drawing.Drawing2D`) |

> **Nota sobre la version de .NET**: `CLAUDE_BASE.md` seccion 1 marca .NET 8 como "planificar
> migracion a .NET 10". Aqui **no aplica todavia**: el proyecto ni siquiera compila. Primero
> EV-001, y la migracion cuando haya un build verde del que partir.

---

## Base de Datos

**No hay base de datos.** El estado persiste en un JSON local.

| Aspecto | Valor |
|---------|-------|
| **Motor** | Ninguno |
| **ORM** | Ninguno |
| **Persistencia** | `System.Text.Json` sobre `%APPDATA%/MiJornada/estado.json` |
| **Migraciones** | No aplica |

`acceso_bd.habilitado` esta a `false` en `ESTADO_PROYECTO.json`. Las reglas de nomenclatura SQL
de `CLAUDE_BASE.md` seccion 8 y `.claude/rules/database.md` no tienen nada sobre lo que dispararse
en este repositorio.

---

## Autenticacion y Seguridad

| Aspecto | Valor |
|---------|-------|
| **Proveedor** | Microsoft Entra ID |
| **Libreria** | MSAL (`Microsoft.Identity.Client`) como **cliente publico** |
| **Flujo** | Codigo de dispositivo (`AcquireTokenWithDeviceCode`) |
| **Tenant** | `organizations` (`Config.TenantId`) |
| **Permiso** | Microsoft Graph delegado `Presence.ReadWrite` |
| **Secreto de cliente** | **Ninguno, a proposito.** Un `.exe` no puede guardar secretos |
| **Cache de token** | `%APPDATA%/MiJornada/msal.cache`, cifrado con DPAPI via `MsalCacheHelper` |

Por que codigo de dispositivo y no el flujo interactivo: el interactivo falla en este tenant con
`Error response came from MDM terms of use page`, por las politicas de acceso condicional en
equipos no gestionados. Ver `_hilo/DECISIONES.md` (ADR-002) y `_hilo/LECCIONES.md`.

**Requisitos del registro en Entra ID** (se puede reutilizar `Teams Presence Flow`):

- Plataforma "Aplicaciones moviles y de escritorio" con la URI
  `https://login.microsoftonline.com/common/oauth2/nativeclient`
- "Permitir flujos de cliente publico": **Si**. Sin esto, `AADSTS7000218`
- Permiso delegado `Presence.ReadWrite` (no hace falta `.All`, que exigiria consentimiento
  de administrador)

---

## Integraciones Detectadas

| Integracion | Tipo | NuGet/Libreria |
|-------------|------|----------------|
| Microsoft Graph v1.0 — `setUserPreferredPresence` | API REST (`HttpClient` a pelo) | Ninguna: se construye el POST a mano |
| Microsoft Entra ID | OAuth2 codigo de dispositivo | `Microsoft.Identity.Client` |

No se usa el SDK `Microsoft.Graph`: es **una sola llamada** POST y el SDK completo no compensa.

---

## NuGets Principales

| Categoria | Paquetes |
|-----------|----------|
| **Identidad** | `Microsoft.Identity.Client` 4.66.2, `Microsoft.Identity.Client.Extensions.Msal` 4.66.2 |
| **ORM** | Ninguno |
| **Logging** | **Ninguno** — ver DT-010 en `DEUDA_TECNICA.md` |
| **Validacion** | Ninguna |
| **Mediador** | Ninguno |
| **Testing** | **Ninguno** — no hay proyecto de tests |
| **Cloud** | Ninguno |

> ⚠️ Las dos versiones `4.66.2` estan **sin verificar**: puede que ese numero no exista en NuGet.
> Es el primer sospechoso si falla el build (DT-002).

---

## Estructura del Proyecto

```
03_Desarrollo/
├── MiJornada.csproj      # net8.0-windows, WinExe, 2 paquetes MSAL
├── Program.cs            # Punto de entrada. Acepta --minutos N para probar
├── Estado.cs             # Config (ClientId, scopes, duracion) + Estado (maquina de estados + persistencia)
├── PresenciaService.cs   # MSAL, cache de token en disco y el POST a Graph
├── MainForm.cs           # Toda la interfaz: anillo, cuenta atras, botones, bandeja
└── LEEME.md              # Registro en Entra, compilacion y anclado a la barra de tareas
```

**Namespace unico y plano: `MiJornada`.** No hay capas, ni interfaces, ni inyeccion de
dependencias, y es deliberado: son ~500 lineas y la convencion
`{prefix}.[Area].[Proyecto].[Capa]` de `CLAUDE_BASE.md` seccion 2 no aporta nada aqui. Ver
`_hilo/DECISIONES.md` (ADR-007).

No existe ningun `.sln`: el `.csproj` va suelto.

---

## Observaciones

- **La aplicacion no tiene servidor.** Todo corre en el equipo del usuario, con el estado en
  `%APPDATA%`. Las reglas del ecosistema sobre infraestructura balanceada (no guardar en disco
  local, cache distribuida, storage remoto) **no aplican**: aqui el disco local es exactamente
  el sitio correcto.
- **El calculo del tiempo es siempre una resta contra el reloj real**, nunca un contador que se
  decrementa. Se persiste la hora de fin, no los segundos restantes. Un contador se
  desincroniza si el equipo se suspende. Ver ADR-005.
- `setUserPreferredPresence` **solo surte efecto si hay una sesion de presencia activa**, es
  decir, con Teams abierto en algun dispositivo. La llamada no falla: simplemente no cambia nada.
- La ruta `/me/presence/setUserPreferredPresence` devuelve **404 con cuerpo vacio**. Hay que usar
  la ruta con el object ID explicito. Ver `_hilo/LECCIONES.md`.

---

*Completado por `/onboarding` el 2026-09-06*
