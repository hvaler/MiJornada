# Mi jornada (escritorio) — traspaso de contexto

Aplicación de escritorio en .NET 8 WinForms que cambia la presencia de Teams
desde un botón anclado en la barra de tareas. Este documento recoge todo lo que
hace falta para retomarla sin repetir el camino.

> **Estado: escrita, nunca compilada.** El código se generó del tirón y no ha
> pasado por `dotnet build` ni una vez. Lo primero es compilar y arreglar lo que
> salga. Ver la sección 8, que lista lo que más probabilidad tiene de fallar.

---

## 1. De dónde viene

Esto es la tercera implementación de la misma idea. El historial completo está
en `mi-jornada-traspaso.md`, y conviene leerlo antes de tomar decisiones de
diseño, porque documenta bastantes callejones sin salida.

Resumen del recorrido:

1. **Script de PowerShell** con `Start-Sleep`. Funcionaba, pero moría al cerrar
   la consola y no avanzaba con el equipo suspendido.
2. **Power Apps + Power Automate + SharePoint**, integrado en Teams. Llegó a
   funcionar de punta a punta el 6/9/2026. Se aparcó porque el conector
   personalizado es premium: ~20 $ usuario/mes, injustificable para una sola
   persona que quiere no aparecer disponible fuera de su horario.
3. **Esta aplicación.** Sin conector, sin flujos, sin licencia. Habla con Graph
   directamente y todo el estado vive en un JSON local.

Lo que sobrevive del recorrido anterior: el diseño visual del anillo, la máquina
de estados con pausa, y el conocimiento sobre la API de presencia.

---

## 2. Qué hace

- Un botón anclable en la barra de tareas abre una ventana de 340×430.
- **Iniciar jornada** pone la presencia en `Available` y arranca una cuenta atrás
  de 7 horas.
- **Pausar** congela la cuenta y pone `Away`. **Reanudar** desplaza la hora de fin
  por los minutos parados y vuelve a `Available`.
- **Cancelar jornada**, con confirmación, cierra y pone `Offline`/`OffWork`.
- Al llegar a cero, presencia a `Offline`/`OffWork` y globo de notificación.
- Cerrar la ventana con la jornada en marcha la manda a la bandeja; no la termina.

El anillo nace morado y completo y va cediendo terreno al gris según avanza la
jornada, en ámbar durante las pausas. Anillo y cifra central cuentan lo mismo:
lo que queda.

---

## 3. Ficheros

| Fichero | Contenido |
|---|---|
| `MiJornada.csproj` | .NET 8, WinForms, dos paquetes de MSAL |
| `Program.cs` | Punto de entrada. Acepta `--minutos N` para probar |
| `Estado.cs` | `Config` (client id, scopes, duración) y `Estado` (situación, fin, pausa, persistencia) |
| `PresenciaService.cs` | MSAL, caché de token en disco y el POST a Graph |
| `MainForm.cs` | Toda la interfaz: anillo, cuenta atrás, botones, bandeja |
| `LEEME.md` | Instrucciones de registro en Entra, compilación y anclado |

Sin capa de abstracción ni inyección de dependencias a propósito: son 500 líneas
y meterle arquitectura sería peor.

---

## 4. Reglas de negocio

**El cálculo del tiempo es siempre una resta contra el reloj real**, nunca un
contador que se decrementa. Se guarda la hora de fin, no los segundos restantes.
Un contador se desincroniza si el equipo se suspende o el proceso se congela; la
resta contra `DateTime.Now` siempre da el valor correcto al volver.

**Durante la pausa, la referencia es `PausaDesde` en lugar de `Now`.** Eso
congela el restante sin tocar la hora de fin, que solo se desplaza al reanudar.
Es la misma solución que en Power Apps, donde los minutos parados se sumaban a
`FinPrevisto`.

**El estado se persiste en cada transición**, en
`%APPDATA%\MiJornada\estado.json`. Si la aplicación se cierra y se reabre, la
jornada sigue. Si al arrancar la hora de fin ya pasó, se descarta en silencio:
no tiene sentido notificar el final de una jornada que terminó ayer.

---

## 5. Autenticación

**Flujo de código de dispositivo, y no es un capricho.** El flujo interactivo
normal falla en este tenant con `Error response came from MDM terms of use page`
por las políticas de acceso condicional en equipos no gestionados. El de
dispositivo es el que se comprobó que funciona.

El token se cachea con `MsalCacheHelper` en `%APPDATA%\MiJornada\msal.cache`,
cifrado con DPAPI. El código solo se pide la primera vez y cuando caduca el
refresh token.

**Requisitos del registro en Entra ID** (se puede reutilizar `Teams Presence
Flow`, que ya existe):

- Plataforma **Aplicaciones móviles y de escritorio** con la URI
  `https://login.microsoftonline.com/common/oauth2/nativeclient`
- **Permitir flujos de cliente público: Sí**. Sin esto, `AADSTS7000218`
- Permiso delegado `Presence.ReadWrite`. No hace falta `.All`, que sí exigiría
  consentimiento de administrador
- **Sin secreto de cliente.** Una aplicación de escritorio es un cliente público
  y no puede guardar secretos. El secreto que tiene el registro es para el
  conector de Power Platform y aquí no se usa

El object ID sale de `HomeAccountId.ObjectId` de la cuenta autenticada, no está
escrito en el código. Eso hace que la aplicación funcione para cualquiera que la
ejecute, sin tocar nada.

---

## 6. La API de presencia

```http
POST https://graph.microsoft.com/v1.0/users/{objectId}/presence/setUserPreferredPresence
{ "availability": "Available", "activity": "Available" }
```

**La ruta `/me/presence/setUserPreferredPresence` devuelve 404 con cuerpo
vacío.** Hay que usar la ruta con el object ID explícito. Sigue siendo una
llamada delegada.

Combinaciones válidas: `Available`/`Available`, `Busy`/`Busy`,
`DoNotDisturb`/`DoNotDisturb`, `BeRightBack`/`BeRightBack`, `Away`/`Away`,
`Offline`/`OffWork` (que Teams muestra como "Fuera del trabajo").

Para devolver el control al cálculo automático:
`POST .../presence/clearUserPreferredPresence`.

**Solo surte efecto si existe una sesión de presencia activa**, es decir, con
Teams abierto en algún dispositivo. La llamada no falla, simplemente no cambia
nada visible.

---

## 7. Compilar y desplegar

```powershell
dotnet build -c Release

dotnet publish -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true
```

Ejecutar el `.exe`, clic derecho en su botón de la barra de tareas → Anclar.
Para arrancar con Windows, acceso directo en `shell:startup`.

Probar sin esperar: `MiJornada.exe --minutos 2`.

---

## 8. Lo que más probablemente falle

Ordenado por probabilidad. Nada de esto está verificado.

1. **Versiones de los paquetes.** `Microsoft.Identity.Client` y su extensión
   están fijados a `4.66.2`, que puede no existir o no ser la conveniente. Si
   NuGet protesta, subir a la última estable de la rama 4.x.
2. **Transparencia de las etiquetas.** WinForms no tiene transparencia real: un
   `Label` con `BackColor = Transparent` pinta el fondo de su *padre*. La cuenta
   atrás está como hija del panel del anillo para que funcione. Si sale un
   rectángulo gris sobre el anillo, hay que dibujar el texto en el `Paint` del
   panel con `DrawString` en vez de usar un `Label`.
3. **`Clipboard.SetText` con cadena vacía** lanza excepción. El código de
   dispositivo no debería venir vacío, pero conviene un `if`.
4. **El globo de notificación no aparece** si `_tray.Visible` es `false` en ese
   momento. Se pone a `true` justo antes, pero merece una comprobación.
5. **Parpadeo del anillo.** `Refrescar()` invalida el panel cada segundo sin
   doble búfer. Si parpadea, activar `DoubleBuffered` en un panel derivado.
6. **`async void` en los manejadores.** Las excepciones se capturan dentro de
   `CambiarPresenciaAsync`, pero un fallo en `Estado.Guardar()` se iría sin
   controlar y tumbaría el proceso.

---

## 9. Mejoras pendientes

**Cerca del código, útiles ya:**

- **Icono propio.** Ahora usa `SystemIcons.Application`, tanto en la ventana como
  en la bandeja. Un `.ico` con el anillo daría identidad al botón anclado, que es
  justo el punto de la aplicación.
- **Icono de bandeja dinámico**, con el anillo de progreso dibujado en 32×32.
  Hay una implementación funcional de esa idea en `mi-jornada.ps1`, en la función
  `Nuevo-Icono`, que se puede portar casi tal cual.
- **Duración configurable** desde la interfaz, no solo por parámetro. Jornada de
  verano contra jornada de invierno es el caso real.
- **Ajustes persistidos**: duración, si arranca minimizado, si ficha solo al
  iniciar sesión de Windows.

**Funcionalidad:**

- **Fichaje automático** al desbloquear el equipo por la mañana, escuchando
  `SystemEvents.SessionSwitch`. Es lo que convierte la aplicación en algo que no
  hay que recordar usar.
- **Aviso antes del final**, a los 15 minutos, para poder cerrar cosas.
- **Histórico de jornadas** en el propio JSON, con un resumen semanal. La versión
  de Power Apps lo tenía a mano por la lista de SharePoint y aquí se perdió.
- **Leer la presencia real** con un `GET /users/{id}/presence` en lugar de asumir
  que el cambio se aplicó. Detectaría el caso de Teams cerrado, que hoy pasa
  silenciosamente.
- **Saltar fines de semana y festivos**, que sigue pendiente desde la primera
  versión.

**Robustez:**

- **Reintento** en el POST a Graph. Un fallo de red al final de la jornada deja
  la presencia sin cambiar y el aviso ya se mostró.
- **Instancia única.** Dos ventanas abiertas escriben el mismo JSON y la última
  gana. Un `Mutex` con nombre lo resuelve.
- **Registro de actividad** en un fichero de texto. Hoy, si algo no funciona, no
  queda rastro de nada.

---

## 10. Decisiones tomadas, para no rehacerlas

| Decisión | Por qué |
|---|---|
| WinForms y no WPF | 500 líneas, una ventana y dibujado con GDI+. WPF no aporta aquí |
| Código de dispositivo y no interactivo | El interactivo falla por acceso condicional en equipos no gestionados |
| Sin secreto de cliente | Cliente público; un secreto en un `.exe` no es un secreto |
| JSON local y no SharePoint | Sin dependencia de red ni de licencia. El precio es que no hay histórico compartido |
| Hora de fin persistida, no un contador | Sobrevive a suspensiones y cierres |
| Cerrar manda a la bandeja | Si el proceso muere, nadie pone el "Fuera del trabajo" al final |
