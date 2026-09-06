# Lecciones Aprendidas del Proyecto

> **INSTRUCCIONES PARA CLAUDE**: Este archivo documenta patrones, errores y particularidades
> descubiertos durante el desarrollo. Consulta este archivo al inicio de cada sesion para
> evitar repetir errores y aprovechar lo que ya funciona. Actualiza con `/sesion` al final
> de cada sesion si hay nuevas lecciones.
>
> **Categoria (dashboard Ovillo)**: el PREFIJO del codigo categoriza la leccion en el hub:
> `PAT-` patron, `ERR-` error, `TEC-` tecnica, `PREF-` preferencia (lo infiere `/mcp-sync`).

---

## Resumen Rapido (Top 5)

| # | Leccion | Categoria |
|---|---------|-----------|
| 1 | La ruta `/me/presence/setUserPreferredPresence` devuelve **404 con cuerpo vacio**: hay que usar la ruta con el object ID explicito | Error |
| 2 | `setUserPreferredPresence` **no falla y no hace nada** si Teams no esta abierto en algun dispositivo | Tecnica |
| 3 | El equipo **no esta unido a Entra ID**: por eso falla el interactivo, y por eso ni ROPC ni WAM son alternativas. Comprobar con `dsregcmd /status` | Error |
| 4 | El tiempo restante se calcula **restando contra el reloj real**, nunca decrementando un contador | Patron |
| 5 | En WinForms, un `Label` con `BackColor = Transparent` pinta el fondo de su **padre**, no lo que hay debajo | Tecnica |

---

## 1. Patrones del Proyecto

### PAT-001: El tiempo se calcula restando, nunca decrementando

**Contexto**: cualquier cambio en la cuenta atras, la pausa o el anillo.

**Patron**: se persiste la **hora de fin**, y el restante es siempre `Fin - referencia`. La
referencia es `DateTime.Now`, salvo durante la pausa, donde es `PausaDesde` (lo que congela la
cifra sin mover la hora de fin). Al reanudar, la hora de fin se desplaza por los minutos parados.

**Por que**: un contador que se decrementa se desincroniza si el equipo se suspende o el proceso
se congela. La resta contra el reloj real siempre da el valor correcto al volver.

**Ejemplo**: `03_Desarrollo/Estado.cs`, propiedad `Restante`. Ver ADR-005.

**Fecha**: 2026-09-06

---

### PAT-002: El estado se persiste en cada transicion

**Contexto**: al anadir cualquier accion que cambie la situacion de la jornada.

**Patron**: toda transicion escribe `%APPDATA%/MiJornada/estado.json` inmediatamente. Si al
arrancar la hora de fin ya paso, se descarta en silencio.

**Por que**: la aplicacion se puede cerrar y reabrir sin perder la jornada. Y no tiene sentido
notificar el final de una jornada que termino ayer.

**Ejemplo**: `03_Desarrollo/Estado.cs`, metodos `Guardar()` y `Limpiar()`.

**Fecha**: 2026-09-06

---

### PAT-003: El anillo cuenta lo que queda, no lo consumido

**Contexto**: al tocar el dibujado del anillo o la cifra central.

**Patron**: el anillo nace completo en morado (`#5B5FC7`) y va cediendo terreno al gris segun
avanza la jornada; ambar (`#C19C00`) durante las pausas. Anillo y cifra central cuentan **lo
mismo**: lo que queda.

**Por que**: coherencia visual. Si el anillo creciera y la cifra bajase, contarian cosas distintas.

**Ejemplo**: `03_Desarrollo/MainForm.cs`, `DibujarAnillo`; `Estado.Fraccion`.

**Fecha**: 2026-09-06

---

## 2. Errores y sus causas

### ERR-001: La ruta con `/me/` devuelve 404 con cuerpo vacio

**Sintoma**: `POST /v1.0/me/presence/setUserPreferredPresence` responde **404 sin mensaje**, lo que
hace pensar en un problema de permisos o de token.

**Causa**: esa ruta, aunque aparece documentada, no funciona para esta operacion.

**Solucion**: usar la ruta con el object ID explicito:
`POST /v1.0/users/{objectId}/presence/setUserPreferredPresence`. Sigue siendo una llamada
delegada, asi que el permiso necesario es el mismo (`Presence.ReadWrite`, sin `.All`).

El object ID sale de `cuenta.HomeAccountId.ObjectId` de la cuenta autenticada, **no esta escrito
en el codigo**: asi la aplicacion funciona para cualquiera que la ejecute.

**Fecha**: 2026-09-06

---

### ERR-002: `AADSTS7000218` al pedir el token

**Sintoma**: el flujo de codigo de dispositivo falla nada mas empezar.

**Causa**: el registro de Entra ID no tiene activado "Permitir flujos de cliente publico".

**Solucion**: Autenticacion → Configuracion avanzada → **Permitir flujos de cliente publico: Si**.
Y anadir la plataforma "Aplicaciones moviles y de escritorio" con la URI
`https://login.microsoftonline.com/common/oauth2/nativeclient`.

**Fecha**: 2026-09-06

---

### ERR-003: `Error response came from MDM terms of use page`

**Sintoma**: el flujo interactivo de MSAL falla al abrir el navegador.

**Causa raiz** (verificada el 2026-09-06): el equipo **no esta unido a Entra ID de ninguna forma**
y la politica de acceso condicional del tenant exige dispositivo gestionado. Se comprueba en dos
segundos:

```powershell
dsregcmd /status | Select-String 'AzureAdJoined|DomainJoined|WorkplaceJoined'
```

Si los tres dicen `NO`, el flujo interactivo **no va a funcionar**, y no hay configuracion del
registro de Entra ni linea de codigo que lo cambie: es politica del tenant.

**Solucion**: flujo de **codigo de dispositivo**. Ver ADR-002.

**Fecha**: 2026-09-06

---

### ERR-005: Ni ROPC ni WAM son alternativas al codigo de dispositivo aqui

**Contexto**: la pregunta que sale sola al ver el codigo de dispositivo es "¿no puede pedirme
usuario y contrasena, como en las demas aplicaciones?". La respuesta es no, por dos motivos
distintos que conviene no confundir.

**Una caja de usuario/contrasena en la app** (ROPC, `AcquireTokenByUsernamePassword`) es
**incompatible con Acceso Condicional y con MFA por diseno**: al no haber interaccion, no hay
donde meter el segundo factor. Este tenant tiene acceso condicional — es exactamente lo que
rompio el flujo interactivo — asi que el mismo obstaculo invalida esta via. Microsoft ademas la
tiene **deprecada** por riesgo de seguridad.

**El selector de cuentas de Windows** (WAM, paquete `Microsoft.Identity.Client.Broker`) es lo que
hace que Teams u Outlook no pidan contrasena en un portatil corporativo, pero funciona porque el
**dispositivo** tiene identidad propia en Entra y la presenta por el usuario. En una maquina no
unida (ver ERR-003) MSAL cae al navegador y se topa con la misma politica. Nota tecnica por si
algun dia el equipo se une: WAM exigiria ademas cambiar el TFM a `net8.0-windows10.0.17763.0` y
registrar la URI `ms-appx-web://microsoft.aad.brokerplugin/{ClientId}`.

**Regla practica**: antes de proponer cualquier cambio de flujo de autenticacion en este
proyecto, ejecutar `dsregcmd /status`. Si el equipo sigue sin unir, la respuesta ya esta dada.

**Fecha**: 2026-09-06

---

### ERR-004: `AADSTS65002` con el conector "HTTP con Microsoft Entra ID"

**Sintoma**: al crear la conexion contra Graph desde Power Platform.

**Causa**: `Consent between first party application ... and first party resource ... must be
configured via preauthorization`. Las dos son aplicaciones de Microsoft y la preautorizacion solo
la puede configurar Microsoft.

**Solucion**: ninguna desde el tenant. Ese conector sirve para APIs propias, no para Graph. Es
uno de los motivos por los que la via Power Platform necesitaba el conector personalizado
(premium). Ver ADR-001.

**Fecha**: 2026-09-06 · **Aplica a**: la implementacion anterior, ya descartada. Anotado para no
volver a intentarlo.

---

## 3. Tecnicas y particularidades

### TEC-001: `setUserPreferredPresence` no hace nada sin Teams abierto

La llamada **solo surte efecto si existe al menos una sesion de presencia activa**, es decir, con
Teams abierto en algun dispositivo. Sin ella responde correctamente y no cambia nada visible.

**Es un fallo silencioso**: la aplicacion cree que lo cambio. La forma de detectarlo seria leer la
presencia real con `GET /users/{id}/presence`, que hoy no se hace (esta en el backlog).

Para devolver el control al calculo automatico: `POST .../presence/clearUserPreferredPresence`.

**Fecha**: 2026-09-06

---

### TEC-002: Combinaciones validas de availability/activity

`Available`/`Available` · `Busy`/`Busy` · `DoNotDisturb`/`DoNotDisturb` ·
`BeRightBack`/`BeRightBack` · `Away`/`Away` · `Offline`/`OffWork` (lo que Teams muestra como
"Fuera del trabajo").

No son libres: hay que usar las parejas.

**Fecha**: 2026-09-06

---

### TEC-003: WinForms no tiene transparencia real

Un `Label` con `BackColor = Transparent` pinta el fondo de su **padre**, no lo que haya debajo en
la ventana. Por eso la cuenta atras se asigna como hija del panel del anillo
(`_lblTiempo.Parent = _anillo`) en vez de anadirse al formulario.

Si aparece un rectangulo gris sobre el anillo, la salida es dibujar el texto en el `Paint` del
panel con `DrawString`. Ver DT-004.

**Fecha**: 2026-09-06

---

### TEC-004: El estado preferido persiste entre sesiones de Teams

No caduca al cerrar Teams. Si un dia se cierra la aplicacion sin finalizar la jornada, al dia
siguiente se puede aparecer como Disponible antes de fichar.

**Fecha**: 2026-09-06

---

### TEC-005: El precursor en PowerShell vive en 5.1, no en PowerShell 7

**Contexto**: el script `C:\temp\fichar.ps1` (la primera implementacion, ver seccion 5) se ejecuta
con `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`, es decir **Windows PowerShell
5.1**. El resto del entorno de desarrollo usa **PowerShell 7**.

Son dos almacenes de modulos **separados**:

| Consola | Modulos de usuario en |
|---|---|
| Windows PowerShell 5.1 | `Documents\WindowsPowerShell\Modules` ← aqui esta `Microsoft.Graph.Authentication` |
| PowerShell 7 (`pwsh`) | `Documents\PowerShell\Modules` |

**El sintoma**: `Connect-MgGraph` da "not recognized" en PowerShell 7 aunque el modulo este
perfectamente instalado. Se distingue que consola dio el error por el texto exacto: 5.1 dice
"as **the** name of a cmdlet", 7 dice "as **a** name of a cmdlet".

**La trampa anadida**: lanzar `powershell.exe` **desde** una sesion de PowerShell 7 (o desde una
herramienta que corra sobre ella) hace que el proceso hijo **herede el `PSModulePath` de la 7**,
que no incluye la carpeta de la 5.1. Resultado: `Get-Module -ListAvailable` dice que el modulo no
existe aunque este ahi. Comprobarlo asi da un falso negativo.

**Solucion fiable** desde cualquier consola: importar por ruta completa.

```powershell
Import-Module "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\Microsoft.Graph.Authentication\2.39.0\Microsoft.Graph.Authentication.psd1"
```

**Fecha**: 2026-09-06

---

### TEC-006: El cache de tokens de Graph PowerShell demuestra que la autenticacion funciona aqui

En `%LOCALAPPDATA%\.IdentityService\` estan `mg.msal.cache.cae` y `mg.msal.cache.nocae`, con fecha
2026-09-02. Son el cache MSAL de Microsoft Graph PowerShell.

**Por que importa**: es la prueba empirica de que, **en este equipo y con esta cuenta**, la
autenticacion delegada contra Graph con `Presence.ReadWrite` por codigo de dispositivo funciona.
No es documentacion ni teoria: ya ocurrio. Confirma ADR-002 desde un angulo independiente.

Tambien demuestra que se puede llamar a Graph **sin registrar ninguna aplicacion propia**, porque
`Connect-MgGraph` usa la aplicacion multiinquilino de Microsoft "Microsoft Graph Command Line
Tools" (`14d82eec-204b-4c2f-b7e8-296a70dab67e`, segun la documentacion de Microsoft). Es la salida
de emergencia para DT-003 si no hubiera acceso al portal — con la contrapartida de que en los
registros de inicio de sesion la app aparece como esa herramienta y no como "Mi jornada", y de que
el tenant puede bloquearla.

**No leer nunca el contenido de esos ficheros de cache**: contienen tokens de acceso y de
actualizacion.

**Fecha**: 2026-09-06

---

### TEC-007: NO usar el ClientId de Graph PowerShell en la app — sus scopes son enormes

**Contexto**: se planteo usar el ClientId de "Microsoft Graph Command Line Tools"
(`14d82eec-204b-4c2f-b7e8-296a70dab67e`) en MiJornada para saltarse el registro de aplicacion.
`Get-MgContext` el 2026-09-06 lo desaconseja:

```
Scopes: {Application.Read.All, Application.ReadWrite.All,
         AppRoleAssignment.ReadWrite.All, AuditLog.Read.All...}
```

Esa aplicacion tiene consentido en esta cuenta un conjunto de permisos **muy amplio**, acumulado
de cada `Connect-MgGraph -Scopes ...` del pasado. `Application.ReadWrite.All` permite crear y
modificar registros de aplicaciones; `AppRoleAssignment.ReadWrite.All`, conceder asignaciones de
rol.

**Conclusion**: aunque MiJornada solo pidiera `Presence.ReadWrite`, se estaria autenticando como
una identidad con ese consentimiento permanente detras. Un registro propio solo podra hacer jamas
una cosa: cambiar la presencia. **Registrar la aplicacion propia, siempre.**

**Efecto secundario util**: tener `Application.ReadWrite.All` consentido significa que el registro
se puede crear **desde PowerShell**, sin pisar el portal (POST a
`https://graph.microsoft.com/v1.0/applications` con `isFallbackPublicClient=true` y el
`requiredResourceAccess` de `Presence.ReadWrite`). El id del permiso delegado se busca en el
service principal de Graph (`appId='00000003-0000-0000-c000-000000000000'`), nunca se hardcodea.

**Fecha**: 2026-09-06

---

### TEC-008: Datos reales del tenant

| Dato | Valor | Origen |
|---|---|---|
| Tenant (GUID) | `bcd2701c-aa9b-4d12-ba20-f3e3b83070c1` | `Get-MgContext`, 2026-09-06 |
| Dominio | `comillas.edu` | cuenta `hvaler@comillas.edu` |
| Graph (resource) | `00000003-0000-0000-c000-000000000000` | id fijo de Microsoft Graph |

`Config.TenantId` usa el **GUID** y no el dominio: es inmune a cambios de dominio verificado y no
depende de que `comillas.edu` siga siendo el dominio principal.

**Fecha**: 2026-09-06

---

### TEC-009: Un solo registro de Entra sirve para TODO el equipo

**La duda que surge sola**: "si se lo instalo a un companero, ¿tiene que crear el suyo con
`crear-registro-entra.ps1`?". **No.**

Hay que separar dos identidades que se confunden con facilidad:

| | Que identifica | De donde sale |
|---|---|---|
| **ClientId** | La **aplicacion** (`Mi jornada`) | Fijo en `Estado.cs`. Uno para todo el tenant |
| **Object ID** | La **persona** que la usa | `cuenta.HomeAccountId.ObjectId`, en tiempo de ejecucion |

El registro se creo con `signInAudience = AzureADMyOrg`, asi que **cualquier cuenta de Comillas**
puede autenticarse contra ese mismo ClientId. Y como `Presence.ReadWrite` es un permiso
**delegado**, cada persona solo puede cambiar **su propia** presencia: el token se emite a nombre
de quien inicia sesion.

Por eso `PresenciaService` saca el object ID de la cuenta autenticada en vez de tenerlo escrito.
Es lo que hace que el mismo `.exe` funcione para cualquiera sin tocar nada.

**Lo que necesita un companero**: el `.exe` y nada mas. Ni PowerShell, ni el modulo de Graph, ni
registro propio. La primera vez inicia sesion con codigo de dispositivo y acepta el consentimiento
de `Presence.ReadWrite` — un clic, permiso delegado, sin aprobacion de administrador.

**Lo que NO hay que hacer**: ejecutar `crear-registro-entra.ps1` por cada persona. Crearia
registros duplicados en el directorio de Comillas. El script es **una vez por tenant**, no una vez
por usuario (por eso es idempotente y comprueba si ya existe).

**Implicaciones a tener en cuenta**:

- El registro es un objeto del directorio de Comillas del que este proyecto depende. **Si se
  borra, deja de funcionar para todos.**
- Si el consentimiento individual molestase con varias personas, un administrador puede conceder
  consentimiento para toda la organizacion y nadie volveria a ver el aviso.
- Que la app se auto-registre en el primer arranque **no tiene sentido**: crear un registro exige
  `Application.ReadWrite.All`, que un usuario normal no tiene, y ademas habria que autenticarse
  para poder crear la aplicacion con la que autenticarse. Pescadilla que se muerde la cola.

**Fecha**: 2026-09-06

---

## 4. Preferencias del proyecto

### PREF-001: Sin arquitectura de mas

Son unas 500 lineas. Nada de capas, interfaces ni inyeccion de dependencias, y el namespace es
plano (`MiJornada`). Es una **excepcion deliberada** a `CLAUDE_BASE.md`, no un descuido. Ver
ADR-007.

Antes de proponer abstracciones aqui, comprobar que resuelven un problema real.

**Fecha**: 2026-09-06

---

### PREF-002: Sin librerias de mas

Una sola llamada a Graph construida a mano con `HttpClient`, sin el SDK `Microsoft.Graph`. Sin
Serilog, sin Polly, sin AutoMapper. Si hace falta reintento (DT-008), un bucle antes que un
paquete.

**Fecha**: 2026-09-06

---

## 5. Contexto historico

El proyecto es la **tercera implementacion** de la misma idea. Antes de proponer un cambio de
enfoque, leer `06_Documentacion/mi-jornada-traspaso.md`: documenta bastantes callejones sin
salida ya recorridos, incluida una solucion de Power Platform que llego a funcionar entera y se
descarto por coste de licencia, no por problemas tecnicos.

De aquella etapa sobreviven tres cosas: el diseno visual del anillo, la maquina de estados con
pausa, y el conocimiento sobre la API de presencia que recoge este fichero.

---

*Completado por `/onboarding` el 2026-09-06*
