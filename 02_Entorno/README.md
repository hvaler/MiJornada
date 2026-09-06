# 02_Entorno — Instalación y registro en Entra

Scripts que hacen todo lo que antes se hacía a mano.

> **Nota**: `docker-compose.yml` es residuo de la plantilla del ecosistema. Este proyecto **no
> tiene base de datos ni servicios**: el estado vive en un JSON en `%APPDATA%`. Se puede borrar.

---

## Instalar

```powershell
.\instalar.ps1
```

Publica la aplicación desde el código, la deja en `%LOCALAPPDATA%\Programs\MiJornada`, crea el
acceso directo del menú Inicio y la registra en «Aplicaciones instaladas».

**No hace falta ser administrador.** Instala solo para el usuario actual, y es deliberado: es la
diferencia entre «te lo instalas y ya» y «abre un ticket». Además la aplicación es de un usuario
por definición —cambia *tu* presencia de Teams—, así que una instalación para toda la máquina no
tendría sentido.

| Opción | Para qué |
|---|---|
| `-ConInicio` | Arrancar con Windows |
| `-ConInicio -Minimizado` | Arrancar con Windows, directo a la bandeja |
| `-Ligero` | Publicar dependiendo del runtime: 1,4 MB en vez de 155, pero exige el **.NET Desktop Runtime 8** instalado |
| `-Origen <carpeta>` | Instalar desde una carpeta ya publicada, sin necesitar el SDK de .NET |

### Autocontenido por defecto, y por qué

| | Tamaño | Requisitos |
|---|---|---|
| **Autocontenido** (por defecto) | 155 MB, un solo `.exe` | ninguno |
| Ligero (`-Ligero`) | 1,4 MB | .NET Desktop Runtime 8 |

Son 110 veces más grande, y aun así el autocontenido es el que se queda por defecto: el objetivo
del instalador es que la aplicación funcione en un equipo donde no hay nada, sin tener que
explicarle a nadie que se instale un runtime primero. Para actualizar tu propio equipo, `-Ligero`
va de sobra.

### Dárselo a otra persona

```powershell
dotnet publish ..\03_Desarrollo\MiJornada.csproj -c Release -r win-x64 `
  --self-contained true -p:PublishSingleFile=true -o MiJornada-0.11.0
```

Se le pasa esa carpeta junto a `instalar.ps1` y `desinstalar.ps1`, y ejecuta:

```powershell
.\instalar.ps1 -Origen .\MiJornada-0.11.0
```

**No necesita su propio registro en Entra** — ver más abajo.

---

## Desinstalar

```powershell
.\desinstalar.ps1              # conserva tus ajustes y tu histórico
.\desinstalar.ps1 -ConDatos    # borra también %APPDATA%\MiJornada
```

También desde **Configuración → Aplicaciones instaladas**. El desinstalador se copia junto a la
aplicación al instalar, para que se pueda quitar aunque ya no exista este repositorio.

Por defecto **conserva los datos**: una desinstalación no debería llevarse por delante meses de
histórico sin preguntar, y lo normal al desinstalar es volver a instalar.

---

## Registro en Entra ID

```powershell
.\crear-registro-entra.ps1
```

**Esto se ejecuta UNA vez para todo el tenant, no una por persona.** Ya está hecho: ClientId
`dbcd6425-561b-4d91-a4d5-f0bb25b31241`.

El registro se creó con `signInAudience = AzureADMyOrg`, así que cualquier cuenta de la
organización puede usar el mismo `.exe`; y como los permisos son **delegados**
(`Presence.ReadWrite`, `Files.ReadWrite.AppFolder`), cada persona solo puede tocar su propia
presencia. Crear un registro por persona multiplicaría registros sin ganar nada.

El script sabe **actualizar** uno existente, añadiendo solo los permisos que falten. Se ejecuta
si algún día hace falta un permiso nuevo.

---

## Lo que el instalador NO hace

- **Anclar a la barra de tareas.** Windows 11 quitó esa posibilidad a los scripts a propósito,
  para que ningún programa te llene la barra sin permiso. Hay que hacerlo a mano: buscarlo en el
  menú Inicio, botón derecho, «Anclar a la barra de tareas».
- **Crear el registro de Entra.** Ver arriba: ya existe y es compartido.
- **Firmar el ejecutable.** Sin firma, SmartScreen puede avisar la primera vez en un equipo
  ajeno. Requeriría un certificado de firma de código.

---

## Aviso para quien edite estos scripts

Se guardan en **UTF-8 con BOM**. Sin el BOM, Windows PowerShell 5.1 —que es el que ejecuta un
`.ps1` al hacer doble clic— los lee como ANSI y los acentos salen como `â€¦`. Verificado: la
primera versión se guardó sin BOM y la salida salía con mojibake. Ver TEC-017 en
`_hilo/LECCIONES.md`.
