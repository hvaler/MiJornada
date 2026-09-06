# Dependencias del Proyecto

> **Proposito**: stack, paquetes e integraciones, con la matriz de impacto de cada uno.
> **Leer (Read) antes de modificar codigo que toque dependencias o integraciones.**

> ⚠️ **Nada de esto esta verificado contra un build.** El proyecto nunca se ha compilado.

---

## Stack

| Capa | Tecnologia | Version |
|---|---|---|
| Runtime | .NET | 8 (`net8.0-windows`) |
| Lenguaje | C# | 12 (`Nullable` + `ImplicitUsings` activados) |
| UI | WinForms + GDI+ | Incluido en el SDK |
| Identidad | MSAL (cliente publico) | 4.66.2 |
| Persistencia | `System.Text.Json` | Incluido en el SDK |
| Cifrado del token | DPAPI (via `MsalCacheHelper`) | Incluido |

---

## Paquetes NuGet

| Paquete | Version | Para que |
|---|---|---|
| `Microsoft.Identity.Client` | 4.66.2 | Obtener el token delegado de Graph con codigo de dispositivo |
| `Microsoft.Identity.Client.Extensions.Msal` | 4.66.2 | Cachear ese token en disco cifrado con DPAPI |

**Ambas versiones estan sin verificar** y son el primer sospechoso si falla el build (DT-002).
Si NuGet protesta, subir a la ultima estable de la rama 4.x. Las dos deben ir **a la misma
version**: la extension esta acoplada a la version del cliente.

No se usa Central Package Management (`Directory.Packages.props`): con dos paquetes y un solo
`.csproj` no compensa.

---

## Integraciones externas

### Microsoft Graph v1.0 — presencia

```http
POST https://graph.microsoft.com/v1.0/users/{objectId}/presence/setUserPreferredPresence
Authorization: Bearer {token}
Content-Type: application/json

{ "availability": "Available", "activity": "Available" }
```

- **Sin SDK**: se construye el `HttpRequestMessage` a mano en
  `GraphService.EstablecerPresenciaAsync`. Meter `Microsoft.Graph` entero por esto no compensa.
- **La ruta con `/me/` NO vale**: devuelve 404 con cuerpo vacio. Hay que usar el object ID
  explicito, que sale de `cuenta.HomeAccountId.ObjectId` (no esta escrito en el codigo, asi que
  la app funciona para cualquiera que la ejecute).
- **Combinaciones validas** de `availability`/`activity`: `Available`/`Available`,
  `Busy`/`Busy`, `DoNotDisturb`/`DoNotDisturb`, `BeRightBack`/`BeRightBack`, `Away`/`Away`,
  `Offline`/`OffWork` (lo que Teams muestra como "Fuera del trabajo").
- **Para devolver el control al calculo automatico**:
  `POST .../presence/clearUserPreferredPresence`, en `GraphService.LimpiarPresenciaAsync`. Lo usa
  **cancelar la jornada**. Dos trampas verificadas: **exige cuerpo JSON** aunque no lleve datos
  (sin `{}` responde 400 `Request_BadRequest`), y la ruta `/me/...` da 404 igual que la de
  establecer. Sin esta llamada, una presencia fijada **se queda fijada**: Teams no vuelve a
  calcularla por su cuenta.
- **Requiere una sesion de presencia activa** (Teams abierto en algun dispositivo). Sin ella la
  llamada devuelve 200 y no cambia nada visible.

### Microsoft Entra ID — autenticacion

- Cliente publico, **sin secreto**. Flujo de codigo de dispositivo.
- Permiso delegado `Presence.ReadWrite`.
- Requisitos del registro: ver `_hilo/CONTEXTO_TECNICO.md` (seccion Autenticacion).

---

## Matriz de impacto

Que se rompe si tocas cada fichero:

| Si modificas... | Revisa tambien | Por que |
|---|---|---|
| `GraphService.cs` | Autenticacion **y** Graph a la vez | El mismo fichero resuelve el token, el object ID y las llamadas. Un cambio en la cache de MSAL puede dejar sin object ID a `EstablecerPresenciaAsync` y `LimpiarPresenciaAsync`, que lo sacan de la cuenta autenticada |
| `Estado.cs` → `Config.Jornada` | `MainForm.DibujarAnillo`, `Estado.Fraccion` | La fraccion del anillo se calcula contra `Config.Jornada`. Cambiarla con una jornada abierta dibuja el anillo con una duracion distinta a la que se uso al fichar |
| `Estado.cs` → persistencia | Compatibilidad con `estado.json` ya escritos | `Cargar()` traga cualquier fallo y empieza de cero, asi que un cambio de forma **pierde la jornada en curso en silencio** |
| `Estado.Restante` / `PausaDesde` | Pausa, reanudacion y anillo | Es la unica fuente de verdad del tiempo. Durante la pausa la referencia es `PausaDesde`, no `DateTime.Now` |
| `MainForm` (cierre / bandeja) | Cierre de jornada | Si el proceso muere, **nadie** pone el "Fuera del trabajo" al final. Por eso cerrar la ventana manda a la bandeja |
| Versiones MSAL en el `.csproj` | Las dos a la vez | `Extensions.Msal` esta acoplada a la version de `Identity.Client` |

---

## Dependencias del entorno (no son paquetes)

| Dependencia | Impacto si falta |
|---|---|
| **Teams abierto** en algun dispositivo | `setUserPreferredPresence` no hace nada. Falla silencioso: la app cree que lo cambio |
| **Registro en Entra ID** con "flujos de cliente publico" activado | `AADSTS7000218` al pedir el token |
| **`ClientId` real en `Estado.cs`** | La app no autentica. Hoy tiene el placeholder `PON-AQUI-TU-CLIENT-ID` (DT-003) |
| **Windows** (DPAPI, WinForms, bandeja) | El proyecto es `net8.0-windows`: no es multiplataforma ni pretende serlo |
| **Conexion a internet** en el momento de fichar | El POST a Graph falla y **no hay reintento** (DT-008) |

---

## Actualizaciones pendientes

| Que | Prioridad | Nota |
|---|---|---|
| Verificar/ajustar las versiones MSAL 4.66.2 | Alta | Parte de EV-001 |
| Migrar de .NET 8 a .NET 10 | Baja | Solo cuando haya un build verde del que partir |

---

*Completado por `/onboarding` el 2026-09-06*
