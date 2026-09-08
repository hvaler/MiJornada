# Mi jornada (aplicación de escritorio)

Controla la presencia de Teams desde un botón anclado en la barra de tareas.
Sin Power Apps, sin flujos y sin licencia premium: habla directamente con
Microsoft Graph.

## 1. Registro en Entra ID

Puedes reutilizar el registro **Teams Presence Flow** que ya existe, o crear
uno nuevo. En cualquier caso necesita dos cosas que el conector no tenía:

1. **Autenticación → Agregar plataforma → Aplicaciones móviles y de escritorio**,
   marcando la URI `https://login.microsoftonline.com/common/oauth2/nativeclient`
2. **Autenticación → Configuración avanzada → Permitir flujos de cliente
   público: Sí**

Sin ese segundo interruptor, el flujo de código de dispositivo falla con
`AADSTS7000218`.

El permiso sigue siendo el mismo de siempre: Microsoft Graph → **delegado** →
`Presence.ReadWrite`. No hace falta secreto de cliente: una aplicación de
escritorio es un cliente público y no puede guardar secretos.

Copia el **Id. de aplicación (cliente)** y pégalo en `Estado.cs`:

```csharp
public const string ClientId = "...";
```

## 2. Compilar

```powershell
dotnet build -c Release
```

Para un ejecutable que funcione en un equipo sin .NET instalado:

```powershell
dotnet publish -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true
```

El `.exe` queda en `bin\Release\net8.0-windows\win-x64\publish\`.

## 3. Anclar a la barra de tareas

Ejecuta el `.exe`, clic derecho en su botón de la barra de tareas → **Anclar a
la barra de tareas**. A partir de ahí se abre desde ahí.

Para que arranque con Windows, un acceso directo al `.exe` en `shell:startup`.

## 4. Probar sin esperar siete horas

```powershell
.\MiJornada.exe --minutos 2
```

## Cómo funciona

- **Estado** en `%APPDATA%\MiJornada\estado.json`. Se puede cerrar y reabrir sin
  perder la cuenta atrás, porque no se guarda un contador sino la hora de fin y
  se resta contra el reloj real.
- **Token** cacheado en `%APPDATA%\MiJornada\msal.cache`, cifrado con DPAPI. El
  código de dispositivo solo se pide la primera vez y cuando caduca el refresh.
- **Pausa**: congela el restante y desplaza la hora de fin al reanudar, igual
  que hacía la versión de Power Apps con `MinutosPausa`.
- **Cerrar la ventana** con una jornada en marcha la manda a la bandeja, no la
  termina. Si matas el proceso, nadie pondrá el "Fuera del trabajo" al final.

## Limitaciones conocidas

- `setUserPreferredPresence` solo surte efecto si hay una sesión de presencia
  activa, es decir, con Teams abierto en algún dispositivo.
- Con el equipo apagado no hay quien cierre la jornada. Para este uso da igual:
  con el equipo apagado ya apareces desconectado.
- El estado preferido persiste entre sesiones de Teams. Si un día cierras sin
  finalizar, al día siguiente puedes aparecer como Disponible antes de fichar.
