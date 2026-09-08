# Contexto Tecnico del Proyecto

> **INSTRUCCIONES PARA CLAUDE**: Este archivo contiene el stack tecnologico detectado del proyecto.
> Se genera automaticamente con `/onboarding` o `/analizar`. Consultalo para entender las
> tecnologias y versiones en uso antes de generar codigo.

> ✅ **Compila y esta verificado contra la API real** desde 2026-09-06 (DT-001 resuelta).

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
> migracion a .NET 10". Sigue sin ser prioritario: .NET 8 tiene soporte hasta noviembre de 2026 y
> la aplicacion no usa nada que .NET 10 mejore. Reevaluar antes de esa fecha.

---

## Base de Datos

**No hay base de datos.** El estado persiste en un JSON local.

| Aspecto | Valor |
|---------|-------|
| **Motor** | Ninguno |
| **ORM** | Ninguno |
| **Persistencia** | `System.Text.Json` sobre `%APPDATA%/MiJornada/` (`estado.json`, `ajustes.json`) y, opcionalmente, la carpeta de aplicacion de OneDrive para compartir entre equipos |
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
| **Tenant** | `bcd2701c-aa9b-4d12-ba20-f3e3b83070c1` (comillas.edu), en `Config.TenantId`. GUID y no dominio: inmune a cambios de dominio verificado. Confirmado con `Get-MgContext` el 2026-09-06 |
| **Permisos** | Microsoft Graph delegados `Presence.ReadWrite` y `Files.ReadWrite.AppFolder` (este ultimo, para el estado compartido entre equipos; ADR-009) |
| **Secreto de cliente** | **Ninguno, a proposito.** Un `.exe` no puede guardar secretos |
| **Cache de token** | `%APPDATA%/MiJornada/msal.cache`, cifrado con DPAPI via `MsalCacheHelper` |

Por que codigo de dispositivo y no el flujo interactivo: el interactivo falla en este tenant con
`Error response came from MDM terms of use page`, por las politicas de acceso condicional en
equipos no gestionados. Ver `_hilo/DECISIONES.md` (ADR-002) y `_hilo/LECCIONES.md`.

**Registro en Entra ID**: se creo uno **propio**, `Mi jornada`, con
`scripts/crear-registro-entra.ps1` (el script tambien sabe actualizar uno existente, anadiendo
solo los permisos que falten). ClientId `dbcd6425-561b-4d91-a4d5-f0bb25b31241`. Requisitos:

- Plataforma "Aplicaciones moviles y de escritorio" con la URI
  `https://login.microsoftonline.com/common/oauth2/nativeclient`
- "Permitir flujos de cliente publico": **Si**. Sin esto, `AADSTS7000218`
- Permisos delegados `Presence.ReadWrite` y `Files.ReadWrite.AppFolder` (ninguno de los dos
  necesita consentimiento de administrador; `Presence.ReadWrite.All` si lo necesitaria)

`signInAudience = AzureADMyOrg`: cualquier cuenta del tenant puede usar el mismo `.exe` sin
registro propio, y al ser permisos delegados cada quien solo toca su propia presencia.

---

## Integraciones Detectadas

| Integracion | Tipo | NuGet/Libreria |
|-------------|------|----------------|
| Microsoft Graph — presencia (`set`/`clearUserPreferredPresence`, `GET /me/presence`) | API REST (`HttpClient` a pelo) | Ninguna: se construyen las peticiones a mano |
| Microsoft Graph — carpeta de aplicacion (`me/drive/special/approot`) | API REST con eTag e `If-Match` | Idem |
| Microsoft Entra ID | OAuth2 codigo de dispositivo | `Microsoft.Identity.Client` |

No se usa el SDK `Microsoft.Graph`: son un punado de llamadas REST y el SDK completo no compensa.

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

> ✅ Las dos versiones `4.66.2` estan verificadas: existen, resuelven exacto y sin vulnerabilidades
> conocidas (DT-002 era falsa alarma).

---

## Estructura del Proyecto

```

├── MiJornada.csproj        # net8.0-windows, WinExe, 2 paquetes MSAL
├── Program.cs              # Punto de entrada. Acepta --datos, --minutos N y --minimizado
├── Estado.cs               # Config, Ajustes, Rutas, Iconos y Estado (maquina de estados + persistencia)
├── GraphService.cs         # MSAL, cache de token en disco y las llamadas a Graph
├── SincronizacionGraph.cs  # Estado y ajustes compartidos entre equipos (carpeta de aplicacion)
├── MainForm.cs             # Toda la interfaz: anillo, cuenta atras, botones, bandeja
├── DialogoAjustes.cs       # Ajustes en pestanas (Jornada, Presencia, Automatismos, Calendario, Equipos)
├── DialogoAcercaDe.cs      # Version y datos de diagnostico
├── Aviso.cs                # Tarjeta de notificacion propia (los globos de bandeja no valen, TEC-016)
├── Mensajes.cs             # Mensajes de animo al empezar y terminar
├── IconoAnillo.cs          # Dibuja el anillo como icono de bandeja
├── ArranqueWindows.cs      # Acceso directo en la carpeta de Inicio
└── LEEME.md                # Registro en Entra, compilacion y anclado a la barra de tareas
```

**Namespace unico y plano: `MiJornada`.** No hay capas, ni interfaces, ni inyeccion de
dependencias, y es deliberado: son ~2.780 lineas repartidas en ficheros pequenos, y la convencion
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
