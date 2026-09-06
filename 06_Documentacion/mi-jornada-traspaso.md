# Mi jornada — documento de traspaso

Aplicación personal de fichaje integrada en Microsoft Teams. Este documento
recoge el estado final de la solución, las decisiones tomadas y los caminos
que se descartaron, para poder retomar el trabajo sin repetir el proceso.

> **Estado a 6 de septiembre de 2026: funcionando y aparcado.** El ciclo
> completo se validó de punta a punta ese día. Se aparcó por coste de
> licencia, no por problemas técnicos (sección 12). El flujo
> `CierreJornadas` quedó **desactivado** a propósito; para retomarlo hay
> que volver a activarlo y revisar la duración de jornada, que se dejó
> parametrizada.

---

## 1. Objetivo

Al empezar la jornada, pulsar un botón que:

1. Cambie el estado de Teams a **Disponible**
2. Arranque una cuenta atrás de **7 horas** (jornada reducida continuada)
3. Al terminar, cambie el estado a **Fuera del trabajo** y envíe un aviso

Con posibilidad de **pausar**, **reanudar** y **cancelar** la jornada.

---

## 2. Arquitectura final

```
[App de lienzo en Teams]
        │
        ├──> Lista de SharePoint "Jornadas"  (estado persistente)
        │
        └──> Flujo "InicioJornada"  (instantáneo, Power Apps V2)
                    └──> Conector personalizado → Graph: presencia = Available

[Flujo "CierreJornadas" cada 5 min]
        └──> Lee "Jornadas" buscando activas con FinPrevisto vencido
                    ├──> Conector personalizado → Graph: presencia = Offline/OffWork
                    ├──> Actualiza el elemento a Estado = Finalizada
                    └──> Mensaje de Teams (Flow bot)
```

La clave del diseño: **el estado vive en SharePoint, no en el flujo**. Un
flujo con `Delay` no se puede pausar ni cancelar una vez lanzado; un flujo
de recurrencia que consulta una tabla sí respeta cualquier cambio que haga
la app.

---

## 3. Datos concretos del entorno

| Dato | Valor |
|---|---|
| Entorno Power Platform | `Comillas (Upgrade)` |
| Object ID del usuario en Entra | `264d916a-ed08-4bb4-9bac-df107a78a65e` |
| Sitio de SharePoint | `https://upcomillas-my.sharepoint.com/personal/hvaler_comillas_edu` |
| Lista | `Jornadas` |
| Conector personalizado | `Teams Presence Flow` |
| Flujo instantáneo | `InicioJornada` |
| Nombre en Power Fx | `'InicioJornada'` |
| Solución | `Inicio Jornada` |

---

## 4. La API de presencia

Endpoint que funciona:

```http
POST https://graph.microsoft.com/v1.0/users/{objectId}/presence/setUserPreferredPresence
Content-Type: application/json

{ "availability": "Available", "activity": "Available" }
```

**Importante:** la ruta documentada `/me/presence/setUserPreferredPresence`
devuelve **404 con mensaje vacío**. Hay que usar la ruta con el object ID
explícito. Sigue siendo una llamada delegada, así que el permiso necesario
es `Presence.ReadWrite` (no hace falta `.All`, que sí requeriría consentimiento
de administrador).

Combinaciones válidas de availability/activity:

- `Available` / `Available`
- `Busy` / `Busy`
- `DoNotDisturb` / `DoNotDisturb`
- `BeRightBack` / `BeRightBack`
- `Away` / `Away`
- `Offline` / `OffWork` ← el que Teams muestra como "Fuera del trabajo"

Para volver al cálculo automático: `POST .../presence/clearUserPreferredPresence`

`setUserPreferredPresence` solo tiene efecto si existe al menos una sesión de
presencia activa, es decir, con Teams abierto.

---

## 5. Caminos descartados

Anotados para no repetirlos.

### 5.1 Duración nativa de Teams
El selector de estado permite fijar una duración, pero al expirar vuelve a
"automático", no a un estado concreto. No sirve.

### 5.2 Conector "HTTP con Microsoft Entra ID"
**Bloqueante definitivo.** Al crear la conexión contra Graph devuelve:

```
AADSTS65002: Consent between first party application 'd2ebd3a9-1ada-4480-8b2d-eac162716601'
and first party resource '00000003-0000-0000-c000-000000000000' must be configured
via preauthorization
```

Las dos son aplicaciones de Microsoft y la preautorización solo la puede
configurar Microsoft. No hay nada que el tenant pueda hacer. Ese conector
sirve para APIs propias, no para Graph.

### 5.3 Power Apps dentro de Teams (pestaña "Crear")
La pestaña Compilación de la app Power Apps en Teams falla con
`Cannot read properties of undefined (reading 'name')`. El stack apunta al
chunk `teamsAcquireFlow~team`, que resuelve el entorno de Dataverse for Teams.
Como la app vive en un entorno normal, revienta. Trabajar siempre desde
make.powerapps.com.

### 5.4 Tabla de Dataverse
Sin permisos para crear tablas en `Comillas (Upgrade)`: aparece el aviso
"Uno o más comandos no están disponibles debido a sus privilegios actuales".
Haría falta el rol *System Customizer* o *Environment Maker*. Se optó por
SharePoint, que además usa conector estándar.

### 5.5 PnP.PowerShell para crear la lista
Dos obstáculos encadenados: el módulo exige PowerShell 7.4, y desde la
versión 2.x `Connect-PnPOnline -Interactive` requiere un `-ClientId` de una
app registrada propia, porque Microsoft retiró la aplicación multiinquilino.
La lista se creó a mano desde la interfaz en cinco minutos.

### 5.6 SaveData / LoadData
Se usó al principio para persistir el fichaje. Limitaciones: no funciona en
navegador (solo en apps nativas) y es por dispositivo. Sustituido por
SharePoint, que resuelve ambas cosas.

---

## 6. Configuración del conector personalizado

Registro en Entra ID:

- Nombre: `Teams Presence Flow`
- Cuentas: solo este directorio organizativo
- Permiso de API: Microsoft Graph → **delegado** → `Presence.ReadWrite`
- Secreto de cliente generado
- **Autenticación → plataforma Web → URI de redirección**: la que genera el
  conector, tipo `https://global.consent.azure-apim.net/redirect`

> Sin la URI de redirección registrada, la conexión falla con
> `AADSTS500113: No reply address is registered for the application`.
> Es un ida y vuelta obligatorio: el conector no muestra esa URL hasta que
> se guarda por primera vez.

Conector personalizado en Power Apps:

- **General**: host `graph.microsoft.com`, URL base `/v1.0`
- **Seguridad**: OAuth 2.0, proveedor Azure Active Directory
  - URL de recurso: `https://graph.microsoft.com`
  - Ámbito: `Presence.ReadWrite offline_access`
  - El `offline_access` es imprescindible: sin refresh token la conexión
    caduca en una hora
- **Definición**: operación `SetPresence`, POST a la URL con object ID,
  cuerpo de ejemplo `{ "availability": "Available", "activity": "Available" }`

---

## 7. La lista de SharePoint

Lista `Jornadas` con estas columnas (además del `Title` por defecto):

| Columna | Tipo | Notas |
|---|---|---|
| `Inicio` | Fecha y hora | **Incluir hora** activado |
| `FinPrevisto` | Fecha y hora | **Incluir hora** activado |
| `PausaDesde` | Fecha y hora | **Incluir hora** activado |
| `Estado` | Opción | Activa, Pausada, Finalizada, Cancelada |
| `MinutosPausa` | Número | Predeterminado 0 |
| `Usuario` | Texto | Correo del usuario |

Nombres sin espacios ni acentos: SharePoint convertiría "Fin previsto" en
`Fin_x0020_previsto`, incómodo de escribir en Power Fx.

Si alguna columna de fecha se crea sin hora, se pierde la hora del fichaje
y toda la cuenta atrás deja de funcionar.

SharePoint almacena las fechas en UTC. La comparación del flujo de
recurrencia contra `utcNow()` es coherente; Power Apps convierte a hora
local al leer.

---

## 8. Los flujos

### 8.1 `InicioJornada` (instantáneo)

1. Disparador **Power Apps (V2)**, sin parámetros
2. `Teams Presence Flow` → `SetPresence` con `Available` / `Available`
3. **Respond to a Power App or flow** → salida de texto `mensaje` = `OK`

> El paso 3 es obligatorio y va **antes** de cualquier espera. `.Run()`
> bloquea la app hasta que el flujo responde o termina. El comprobador de
> flujos avisa de que "quite la acción de respuesta"; esa advertencia no
> aplica aquí y se ignora.

> **Historia importante.** Hasta el 6/9/2026 este flujo llevaba además tres
> pasos después de la respuesta: `Delay` de 7 horas, un segundo
> `SetPresence` con `Offline`/`OffWork` y un **Publicar mensaje**. Es decir,
> el cierre de jornada estaba implementado con la espera bloqueante que la
> sección 2 da por descartada, y el flujo de recurrencia **nunca llegó a
> existir**. Los tres pasos se eliminaron; si algún día reaparecen en el
> historial ejecuciones de `InicioJornada` con duración `07:00:0x`, es que
> han vuelto.

### 8.2 `CierreJornadas` (recurrencia)

1. Disparador **Periodicidad**, cada 5 minutos
2. **Obtener elementos** (SharePoint), sitio y lista `Jornadas`, y en
   parámetros avanzados la consulta de filtro:
   ```
   Estado eq 'Activa' and FinPrevisto le '@{utcNow()}'
   ```
   `utcNow()` hay que insertarlo desde el panel de **Expresión**; escrito a
   mano se queda como texto y la consulta no devuelve nada nunca.
3. **Aplicar a cada uno** sobre `body/value`, con tres acciones dentro:
   - **Actualizar elemento** → `Id` y `Título` del elemento actual,
     `Estado Value` = `Finalizada`
   - `Teams Presence Flow` → `SetPresence` con `Offline` / `OffWork`,
     `Content-Type` = `application/json`
   - **Publicar mensaje en un chat o canal** → Flow bot → Chat con Flow bot

**Actualizar elemento va primero a propósito**: si algo falla después,
prefieres el registro cerrado sin aviso que el aviso repitiéndose cada
cinco minutos.

Al crear el flujo desde cero, la acción de Teams nació con una conexión sin
autorizar y fallaba con `Unauthorized`. Se arregla desde **Cambiar
conexión** al pie del panel de la acción.

Conviene además poner **Control de simultaneidad** a 1 en el disparador,
para que dos ejecuciones no procesen el mismo elemento.

Si la consulta de filtro da problemas, alternativa: filtrar solo por
`Estado eq 'Activa'` y comparar fechas con una condición dentro del bucle.

Para probar sin esperar siete horas, se baja la periodicidad a 1 minuto y
la jornada a 2 minutos (ver `varSegundosJornada` en 9.3). Ambas cosas hay
que revertirlas después: a 1 minuto son 1.440 ejecuciones diarias contra
los límites de licencia.

---

## 9. La aplicación

### 9.1 Advertencia sobre la sintaxis

**El editor usa punto y coma como separador de argumentos y doble punto y
coma entre instrucciones.** Es consecuencia de la configuración regional
española, donde la coma es el separador decimal. Toda la documentación y los
ejemplos que se encuentren por ahí usan comas y hay que traducirlos.

```
Set(varInicio; Now());;          // correcto
Set(varInicio, Now());           // error: "se recibieron 1, se esperaban 2"
```

Los decimales sí llevan punto: `RGBA(0; 0; 0; 0.5)`.

### 9.2 Controles

| Nombre | Tipo | Función |
|---|---|---|
| `imgAnillo` | Imagen | Anillo de progreso (SVG) |
| `icoReloj` | Icono | Reloj del estado sin fichar |
| `btnInicioJornada` | Botón | Inicio Jornada |
| `btnPausar` | Botón | Pausar |
| `btnReanudar` | Botón | Reanudar |
| `btnResetear` | Botón | Cancelar jornada |
| `Label4` | Etiqueta | Rótulo de estado |
| `lblTiempoRestante` | Etiqueta | Cuenta atrás |
| `Timer1` | Temporizador | Refresco de la cuenta atrás |
| `rectPrincipal` | Rectángulo | Fondo oscuro del diálogo |
| `rectTarjeta` | Rectángulo | Tarjeta blanca del diálogo |
| `Label1` | Etiqueta | Texto de confirmación |
| `btnNo` / `btnCancelar` | Botones | Opciones del diálogo |

### 9.3 App.OnStart y Screen1.OnVisible

**Las dos llevan exactamente el mismo bloque:**

```
Set(varSegundosJornada; 7*3600);;
Set(varConfirmar; false);;
Set(varRegistro;
    LookUp(Jornadas;
        Usuario = User().Email &&
        (Estado.Value = "Activa" || Estado.Value = "Pausada")
    )
);;
Set(varEstado; If(IsBlank(varRegistro); ""; varRegistro.Estado.Value));;
Set(varInicio; varRegistro.Inicio);;
Set(varFin; varRegistro.FinPrevisto)
```

`App.OnStart` no se ejecuta si Teams mantiene la app cargada en segundo
plano, así que sin la copia en `OnVisible` la app puede pasarse horas
mostrando una jornada que ya terminó.

> **La versión anterior estaba rota y costó media mañana.** Era así:
>
> ```
> If(!IsBlank(varRegistro);
>     Set(varInicio; varRegistro.Inicio);;
>     Set(varFin; varRegistro.FinPrevisto);;
>     Set(varEstado; varRegistro.Estado.Value);
>     Set(varEstado; "")
> )
> ```
>
> Los `;;` dentro de la rama "entonces" hacen que el editor lea las
> instrucciones como argumentos sueltos del `If`, de modo que
> `Set(varEstado; "")` queda como un cuarto argumento que no se evalúa
> nunca. Resultado: al no haber registro activo, `varEstado` conservaba su
> valor anterior y la app se quedaba clavada en la jornada de ayer.
>
> La regla: **un `If` que ejecuta bloques no admite `;;` dentro de sus
> ramas.** Si hace falta encadenar, que el `If` devuelva un valor
> (`Set(x; If(cond; a; b))`) en lugar de ejecutar instrucciones.

`varSegundosJornada` centraliza la duración: la usan el botón de inicio y
el anillo. Para probar se pone a `2*60` en los dos sitios, y al terminar se
devuelve a `7*3600`. Vive solo en memoria, así que si se cambia con una
jornada abierta el anillo se calcula con una duración distinta a la que se
usó al fichar.

### 9.5 Botón `btnInicioJornada`

`OnSelect`:
```
Set(varInicio; Now());;
Set(varFin; DateAdd(varInicio; varSegundosJornada; TimeUnit.Seconds));;
'InicioJornada'.Run();;
Set(varRegistro;
    Patch(Jornadas; Defaults(Jornadas);
        {
            Title: Text(varInicio; "dd/mm/yyyy");
            Inicio: varInicio;
            FinPrevisto: varFin;
            Estado: {Value: "Activa"};
            MinutosPausa: 0;
            Usuario: User().Email
        }
    )
);;
Set(varEstado; "Activa");;
Set(varRestante; DateDiff(Now(); varFin; TimeUnit.Seconds))
```

`Visible`:
```
varEstado = ""
```

> Antes este botón se quedaba deshabilitado durante la jornada. Ocultarlo
> deja un único botón en pantalla en cada estado, los tres en la misma
> posición.

> `Estado` es columna de tipo Opción: se escribe `{Value: "Activa"}`, no
> texto plano. Es el error más común con SharePoint.

### 9.6 Botón `btnPausar`

`OnSelect`:
```
Set(varRegistro;
    Patch(Jornadas; varRegistro;
        {Estado: {Value: "Pausada"}; PausaDesde: Now()}
    )
);;
Set(varEstado; "Pausada");;
Set(varRestante; DateDiff(varRegistro.PausaDesde; varFin; TimeUnit.Seconds))
```

`Visible`: `varEstado = "Activa"`

### 9.7 Botón `btnReanudar`

`OnSelect`:
```
Set(varMinutos; DateDiff(varRegistro.PausaDesde; Now(); TimeUnit.Minutes));;
Set(varFin; DateAdd(varRegistro.FinPrevisto; varMinutos; TimeUnit.Minutes));;
Set(varRegistro;
    Patch(Jornadas; varRegistro;
        {
            Estado: {Value: "Activa"};
            FinPrevisto: varFin;
            MinutosPausa: varRegistro.MinutosPausa + varMinutos
        }
    )
);;
Set(varEstado; "Activa");;
Set(varRestante; DateDiff(Now(); varFin; TimeUnit.Seconds))
```

`Visible`: `varEstado = "Pausada"`

Aquí está el mecanismo central: los minutos parados se suman a
`FinPrevisto`. El flujo de recurrencia solo mira esa fecha, así que respeta
la pausa sin saber nada de ella.

Pausar y Reanudar comparten posición exacta: nunca se ven a la vez y
parecen un único botón que cambia de nombre.

### 9.8 Botón Resetear y diálogo

`btnResetear.OnSelect`: `Set(varConfirmar; true)`

`btnResetear.Visible`: `varEstado = "Activa" || varEstado = "Pausada"`

`btnCancelar.OnSelect` (el "Sí, cancelar"):
```
Patch(Jornadas; varRegistro; {Estado: {Value: "Cancelada"}});;
Set(varEstado; "");;
Set(varRegistro; Blank());;
Set(varConfirmar; false)
```

`btnNo.OnSelect`: `Set(varConfirmar; false)`

Los cinco controles del diálogo llevan `Visible: varConfirmar`.

`rectPrincipal` (fondo): `X` y `Y` a 0, `Width` = `Parent.Width`,
`Height` = `Parent.Height`, `Fill` = `RGBA(0; 0; 0; 0.5)`.

Los dos botones invierten el peso visual a propósito: `btnNo` es el sólido
morado y `btnCancelar` va en contorno rojo, `Color` y `BorderColor` a
`RGBA(164; 38; 44; 1)` sobre fondo transparente. Así el gesto por inercia
es el que no destruye nada.

`rectTarjeta`: 320×180, centrado con
`Parent.Width/2 - Self.Width/2` y `Parent.Height/2 - Self.Height/2`.
Los controles interiores se posicionan relativos a `rectTarjeta`.

Se queda con las esquinas en pico: los rectángulos clásicos no tienen
propiedad de radio. La única forma de redondearlas es sustituir el control
por un botón deshabilitado o por una imagen SVG, y eso obliga a recolocar
todo el apilamiento del diálogo. No compensa por un elemento que se ve tres
segundos.

En la vista de árbol, lo que aparece **arriba** se dibuja **encima**. Los
botones del diálogo deben quedar por encima del rectángulo de fondo, o este
absorbe los clics.

### 9.9 Cuenta atrás

`Timer1`: `Duration` = `1000`, `Repeat` = `true`, `AutoStart` = `true`,
**"Pausar automáticamente" desactivado**, `OnTimerEnd`:

```
Set(varAhora; Now());;
Set(varRestante;
    If(varEstado = "Pausada";
        DateDiff(varRegistro.PausaDesde; varFin; TimeUnit.Seconds);
        DateDiff(varAhora; varFin; TimeUnit.Seconds)
    )
);;
If(varEstado = "Activa" && varRestante <= 0;
    Set(varRegistro;
        LookUp(Jornadas;
            Usuario = User().Email &&
            (Estado.Value = "Activa" || Estado.Value = "Pausada")
        )
    );;
    If(IsBlank(varRegistro); Set(varEstado; ""))
)
```

El segundo bloque es la autocomprobación: cuando la cuenta atrás llega a
cero, la app relee la lista. Si `CierreJornadas` ya cerró el registro, el
`LookUp` devuelve vacío y la pantalla vuelve sola al estado inicial. Sin
esto, la app se queda mostrando 00:00:00 indefinidamente. Solo consulta
SharePoint al llegar a cero, así que no añade tráfico durante la jornada.

`varRestante` es la única fuente de verdad: de ella cuelgan la cuenta atrás
y el anillo. Congelarla durante la pausa evita que el anillo siga
avanzando con la jornada parada, porque `varFin` no se desplaza hasta que
se reanuda. Los tres botones de acción terminan poniéndola al día para que
no haya un segundo de desfase al pulsar.

> Un temporizador con `Visible = false` **no se ejecuta**. Para ocultarlo,
> sacarlo del área visible con `X` e `Y` negativos.
>
> `AutoStart` solo dispara al cargarse la pantalla. Si se añade el control
> con la app ya abierta, no arranca hasta recargar.
>
> En modo Edición los temporizadores no corren, solo en vista previa o
> publicado. Y como `Duration` es 1000, el propio control siempre muestra
> 00:00:00: no es indicador de nada, hay que mirar la variable `varAhora`.

`lblTiempoRestante.Text` (cuenta atrás):
```
If(varEstado = ""; "";
    Text(
        Time(
            RoundDown(Max(varRestante; 0)/3600; 0);
            Mod(RoundDown(Max(varRestante; 0)/60; 0); 60);
            Mod(Max(varRestante; 0); 60)
        );
        "hh:mm:ss"
    )
)
```

`Label4.Text` (rótulo):
```
If(
    varEstado = ""; "Sin fichar";
    varEstado = "Pausada"; "En pausa desde las " & Text(varRegistro.PausaDesde; "HH:mm");
    "Termina a las " & Text(varFin; "HH:mm")
)
```

Durante la pausa la cifra ya no se sustituye por un texto: se queda
congelada en el tiempo que quedaba al pausar, y el rótulo de abajo dice
desde cuándo. El color ámbar del anillo es lo que marca el estado.

El cálculo se hace siempre restando contra `Now()`, nunca decrementando un
contador. Si Teams congela la app en segundo plano o el equipo se suspende,
un contador decrementado se desincroniza; la resta contra la hora real
siempre da el valor correcto al volver.

### 9.10 El anillo de progreso

El control `Circle` de lienzo **no tiene** `StartAngle`/`EndAngle`; esa idea
del pendiente original no existe. El anillo se dibuja con un SVG metido en
la propiedad `Image` de un control Imagen, mediante un data-uri construido
con una fórmula. Es la técnica que Microsoft documentó en su día para
gauges radiales, advirtiendo de que no está soportada oficialmente.

`imgAnillo.Image`:
```
With(
    {
        pct: If(varEstado = ""; 0; Min(1; Max(0; varRestante/Max(varSegundosJornada; 1))));
        col: If(varEstado = "Pausada"; "#C19C00"; "#5B5FC7");
        cap: If(varEstado = "" || varRestante >= varSegundosJornada; "butt"; "round")
    };
    "data:image/svg+xml;utf8, " & EncodeUrl("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 200 200'><circle cx='100' cy='100' r='88' fill='none' stroke='#EDEBE9' stroke-width='14'/><circle cx='100' cy='100' r='88' fill='none' stroke='" & col & "' stroke-width='14' stroke-linecap='" & cap & "' stroke-dasharray='553' stroke-dashoffset='" & Text(553*(1-pct); "0.0"; "en-US") & "' transform='rotate(-90 100 100)'/></svg>")
)
```

El anillo representa **lo que queda**: nace completo en morado y va cediendo
terreno al gris según avanza la jornada, de modo que anillo y cifra central
cuentan lo mismo. En pausa se pone ámbar. `553` es la circunferencia de un
radio 88 (2π·88 = 552,9) y el `rotate(-90)` hace que arranque arriba.

**Los dos obstáculos serios, ambos silenciosos:**

1. **La cadena del SVG tiene que ir en una sola línea.** Partida en varias,
   el editor rompe el emparejado de comillas y el error aparece en
   cualquier función posterior. El síntoma engañoso es un mensaje del tipo
   "Número de argumentos no válido: se recibieron 1, se esperaban 2 o más"
   señalando un `If` que está perfectamente escrito. El `With` sí puede ir
   en varias líneas; la cadena entre comillas no.

2. **El separador decimal.** Con configuración regional española,
   `Text(553*(1-pct))` produce `331,8` con coma. El navegador no entiende
   ese `stroke-dashoffset`, lo ignora sin dar ningún error y pinta el
   círculo completo. La forma de forzar el punto es el **tercer argumento**
   de `Text`, el idioma:
   ```
   Text(553*(1-pct); "0.0"; "en-US")
   ```
   Poner `[$-en-US]` dentro de la cadena de formato **no funciona**: ese
   marcador indica cómo interpretar el formato, no en qué idioma escribir
   el resultado. Alternativa que no depende de nada:
   `Substitute(Text(RoundDown(553*(1-pct); 0)); ","; ".")`.

**El `Max(varSegundosJornada; 1)` del divisor no es paranoia.** Power Fx
evalúa **las dos ramas** de un `If` al analizar la fórmula, no solo la que
se ejecutaría, así que una guarda del tipo
`If(varSegundosJornada = 0; 0; algo/varSegundosJornada)` sigue dando
"Operación no válida: división entre cero". La única salida es que el
denominador no pueda valer cero nunca.

**Cómo probarlo sin esperar siete horas.** Un control Deslizador temporal,
`sldPrueba`, con `pct: sldPrueba.Value/100`, permite recorrer los cien
estados del anillo en diez segundos. En modo Edición los temporizadores no
corren, así que `varRestante` está en blanco y el anillo se ve completo:
eso no es un fallo, pero impide depurar en el lienzo. Conviene dejar el
deslizador puesto hasta el final y borrarlo al terminar.

### 9.11 Posiciones y estilos

`imgAnillo`:

- `X`: `Parent.Width/2 - Self.Width/2`, `Y`: `40`
- `Width`: `Min(Parent.Width - 96; 240)`, `Height`: `Self.Width`

`lblTiempoRestante`, superpuesta y con `Fill` transparente:

- `X`: `imgAnillo.X`, `Width`: `imgAnillo.Width`
- `Y`: `imgAnillo.Y + imgAnillo.Height/2 - 26`, `Height`: `52`
- `Size` `28`, `FontWeight.Semibold`, `Align.Center`, `VerticalAlign.Middle`
- `Color`: `RGBA(32; 31; 30; 1)`

`Label4`, bajo el anillo: `Y` = `imgAnillo.Y + imgAnillo.Height + 6`,
`Height` `24`, `Size` `11`, `Align.Center`, `Color` `RGBA(96; 94; 92; 1)`.

`icoReloj` (`Icon.Clock`), centrado en el hueco del anillo, `48`×`48`,
`Color` `RGBA(200; 198; 196; 1)`, `Visible` = `varEstado = ""`.

Los tres botones de acción comparten `X` (`Parent.Width/2 - Self.Width/2`),
`Y` (`imgAnillo.Y + imgAnillo.Height + 44`), `Width`
(`Min(Parent.Width - 96; 240)`) y `Height` (`40`). `btnResetear` va a
`+ 96`, con `Height` `28`, `Size` `11` y `Underline` a `true`.

| Propiedad | Primario (`btnInicioJornada`, `btnReanudar`) | Secundario (`btnPausar`) | Enlace (`btnResetear`) |
|---|---|---|---|
| `Fill` | `RGBA(91; 95; 199; 1)` | `RGBA(0; 0; 0; 0)` | `RGBA(0; 0; 0; 0)` |
| `HoverFill` | `RGBA(75; 79; 179; 1)` | `RGBA(243; 242; 241; 1)` | `RGBA(0; 0; 0; 0)` |
| `PressedFill` | `RGBA(68; 71; 161; 1)` | — | `RGBA(0; 0; 0; 0)` |
| `Color` | `White` | `RGBA(32; 31; 30; 1)` | `RGBA(96; 94; 92; 1)` |
| `HoverColor` | `White` | `RGBA(32; 31; 30; 1)` | `RGBA(164; 38; 44; 1)` |
| `BorderThickness` | `0` | `1` | `0` |

> Los radios hay que fijarlos a mano a `8` en las cuatro propiedades
> (`RadiusTopLeft` y compañía). El estilo por defecto de los botones nuevos
> los pone a la mitad de la altura, y con `Height` a `40` sale una píldora.
>
> En un botón con `Fill` transparente hay que acordarse del `Color`: si se
> queda en blanco, el texto solo aparece al pasar el ratón, cuando entra el
> `HoverColor`. Parece un botón sin etiqueta.

`Visible` de cada uno: `varEstado = ""` para `btnInicioJornada`,
`varEstado = "Activa"` para `btnPausar`, `varEstado = "Pausada"` para
`btnReanudar`.

### 9.12 Orden del árbol

De arriba abajo, es decir de delante hacia atrás:

```
btnNo
btnCancelar
Label1
rectTarjeta
rectPrincipal
btnResetear
btnPausar / btnReanudar / btnInicioJornada
Label4
lblTiempoRestante
icoReloj
imgAnillo
```

`imgAnillo` va al fondo o tapa la cuenta atrás. Y `rectPrincipal` tiene que
quedar por encima del anillo y las etiquetas: si se queda por debajo, el
velo oscuro del diálogo deja el anillo iluminado y el efecto se rompe.

---

## 10. Publicación

1. En el Studio: **Guardar** y luego **Publicar** (sin publicar, Teams sigue
   sirviendo la versión anterior)
2. En la lista de aplicaciones, `···` → **Agregar a Teams** → descarga un `.zip`
3. En Teams: *Aplicaciones* → *Administrar tus aplicaciones* → *Cargar una
   aplicación personalizada*
4. Clic derecho en el icono de la barra lateral → **Anclar**

El nombre y el icono viajan en el manifiesto. Cambiarlos en el Studio no
actualiza lo ya instalado: hay que desinstalar de Teams y volver a añadir.

**Configuración → Mostrar**: diseño **Adaptable**. Con formato de tableta
fijo aparecen bandas grises arriba y abajo en el panel de Teams.

---

## 11. Errores encontrados y sus causas

| Síntoma | Causa |
|---|---|
| `InvokerConnectionOverrideFailed` / `shared_teams` | Se añadió un conector al flujo después de engancharlo a la app. Solución: quitar y volver a agregar el flujo en el panel de Power Automate del Studio |
| `"Run" es una función desconocida` | El nombre del flujo en Power Fx cambió al reengancharlo. Usar el autocompletado escribiendo una comilla simple |
| App en solo lectura / "is locked by user" | Sesión de edición fantasma. Cerrar todas las pestañas y esperar unos 15 minutos |
| Cuenta atrás en 00:00:00 | `varFin` sin valor, o el temporizador parado |
| El diálogo aparece al arrancar | `varConfirmar` sin inicializar |
| `Encapsular` abre un asistente de Android/iOS | Es **Wrap**, genera APK e IPA. No tiene nada que ver con Teams |
| SVG en blanco o anillo siempre completo | `stroke-dashoffset` con coma decimal. El navegador ignora el valor sin avisar. Usar el tercer argumento de `Text` |
| "Número de argumentos no válido" en un `If` correcto | La cadena del SVG partida en varias líneas. Ponerla en una sola |
| Botón cuyo texto solo se ve al pasar el ratón | `Color` en blanco sobre `Fill` transparente |
| El velo del diálogo no cubre el anillo | `rectPrincipal` por debajo de `imgAnillo` en el árbol |
| Avisos de "Jornada finalizada" repetidos y sin razón aparente | Ejecuciones de `InicioJornada` con `Delay` de 7 h aún vivas. Se ven en el historial por su duración `07:00:0x`. No se pueden cancelar desde la app: `.Run()` no devuelve referencia a la ejecución |
| La app sigue mostrando la jornada de ayer | `App.OnStart` no corre en Teams, o el `If` con `;;` en las ramas (ver 9.3) |
| División entre cero pese a la guarda del `If` | Power Fx evalúa las dos ramas. Proteger el denominador con `Max(x; 1)` |
| `Unauthorized` en Publicar mensaje, con el flujo en verde | Conexión de Teams sin autorizar. Un fallo dentro de un `Aplicar a cada uno` no siempre tumba la ejecución |
| Acciones en gris con un guion en el historial | El bucle no iteró: `Obtener elementos` devolvió cero elementos |
| Los mensajes del chat parecen simultáneos | Teams agrupa los consecutivos del mismo remitente bajo la hora del primero. El historial del flujo es la única fuente fiable |
| Se prueba y no cambia nada | Falta **Publicar**, o el aviso amarillo de "versión anterior" en Teams sin pulsar Actualizar |

---

## 12. Licencias: por qué se aparcó

El conector personalizado es **premium**, y eso arrastra a la app y a los
dos flujos que lo usan. No entra en Microsoft 365.

Precios de lista consultados el 6/9/2026, en USD y sin IVA, de fuentes
secundarias (las páginas de Microsoft en español devuelven "producto no
disponible en tu mercado"):

| Licencia | Precio de lista | Cubre |
|---|---|---|
| Power Apps Premium | ~20 $ usuario/mes | Apps ilimitadas y conectores premium. Incluye derechos de Power Automate |
| Power Automate Premium | 15 $ usuario/mes | Solo flujos |
| Power Automate Process | ~150 $ por flujo/mes | Un flujo, lo use quien lo use |

Para un solo usuario que quiere no aparecer disponible fuera de su horario,
20 $ al mes no se justifica frente a hacerlo a mano. **Esa fue la decisión.**

Si algún día se retoma para varias personas, el cálculo cambia de forma:
por usuario se multiplica, mientras que **Process** licencia el flujo y da
igual cuánta gente fiche. Pero para llegar ahí hay que resolver antes que
la app no invoque un flujo premium por usuario, y el multiusuario tiene su
propio bloqueante, descrito abajo.

Antes de estimar nada: mirar qué incluye el contrato de Microsoft 365
vigente (E3/E5 traen capacidades de Power Platform), si hay acuerdo de
campus, y cuándo caduca la prueba premium de 30 días en el centro de
administración. El día que expire, los flujos se paran sin aviso.

**El bloqueante del multiusuario.** El flujo de recurrencia se ejecuta con
las conexiones de quien lo creó, así que la llamada a Graph cambiaría *su*
presencia, no la del usuario cuya jornada terminó: `Presence.ReadWrite`
delegado solo permite tocar la presencia de uno mismo. Las salidas son
`Presence.ReadWrite.All` como permiso de aplicación, que exige
consentimiento de administrador, o un flujo por usuario, que multiplica
mantenimiento y licencias. Además habría que sacar el object ID de la URL
del conector a un parámetro `{userId}` y mover la lista fuera del OneDrive
personal.

---

## 13. Pendiente

La mejora visual está hecha (secciones 9.10 a 9.12). Lo que queda son
ideas, ninguna empezada:

**Retoques menores:**

- Esquinas redondeadas en `rectTarjeta`, que exige cambiar el control
- Animación del anillo al fichar, con `<animate>` dentro del SVG

**Funcionalidad:**

- Duración configurable (jornada de verano vs invierno) con un desplegable
- Leer la presencia real desde Graph con una operación GET en el conector,
  en lugar de asumir el estado
- Histórico de jornadas en una galería, aprovechando que ya está la lista
- Saltar fines de semana y festivos consultando un calendario

**Línea activa:** una aplicación local en la bandeja del sistema que llame
a Graph directamente, sin Power Platform ni licencias. Parte del script de
la sección 14.

---

## 14. Script de PowerShell (la vía elegida)

Con el proyecto de Power Platform aparcado por licencia, esta es la línea
de trabajo activa. Funciona sin Power Apps, sin conector y sin licencia
premium, porque `Connect-MgGraph` usa la aplicación multiinquilino de
Microsoft Graph PowerShell en lugar del conector personalizado:

```powershell
$uri = "https://graph.microsoft.com/v1.0/users/264d916a-ed08-4bb4-9bac-df107a78a65e/presence/setUserPreferredPresence"

Connect-MgGraph -Scopes "Presence.ReadWrite" -UseDeviceAuthentication -NoWelcome

Invoke-MgGraphRequest -Method POST -Uri $uri -Body @{ availability="Available"; activity="Available" }

$fin = (Get-Date).AddHours(7)
Write-Host "Jornada iniciada. Fuera del trabajo a las $($fin.ToString('HH:mm'))"

Start-Sleep -Seconds (7*3600)

Invoke-MgGraphRequest -Method POST -Uri $uri -Body @{ availability="Offline"; activity="OffWork" }
```

Requiere `Install-Module Microsoft.Graph.Authentication -Scope CurrentUser`.

El `setUserPreferredPresence` sigue necesitando una sesión de presencia
activa: con Teams cerrado la llamada se hace pero no cambia nada. Para un
script local eso importa poco, porque si el equipo está apagado ya
apareces desconectado.

`-UseDeviceAuthentication` es necesario: el flujo interactivo normal falla
con `Error response came from MDM terms of use page` por las políticas de
acceso condicional del tenant en equipos no gestionados.

Limitación: el `Start-Sleep` muere si se cierra la consola, y no avanza
mientras el equipo está suspendido.
