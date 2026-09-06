# Deuda Tecnica

> **Proposito**: issues conocidos, riesgos y trabajo pendiente de saneamiento.
> Se sincroniza al Hub con `/mcp-sync` (categoria `deuda`) cuando el Hub este activo.

**Ultima revision**: 2026-09-06 (tras el primer `dotnet build`)

---

## Resumen

| Severidad | Abiertas |
|---|---|
| 🔴 Critica | 0 |
| 🟡 Media | 4 |
| 🔵 Baja | 4 |
| ✅ Resueltas | 3 |

**Estado**: el proyecto **compila** (0 errores, 0 advertencias) y **ya esta configurado**: tiene
ClientId y tenant reales. Nada impide ejecutarlo.

### Primer arranque real — 2026-09-06

Se ejecuto `MiJornada.exe --minutos 2` y se capturo la ventana con `PrintWindow`.

| Comprobado | Resultado |
|---|---|
| Arranque | ✅ Sin excepciones. Ventana 356×469, titulo "Mi jornada" |
| Dibujado del anillo (GDI+) | ✅ Se pinta el circulo de pista completo, centrado |
| **DT-004** (rectangulo gris sobre el anillo) | ✅ **No se manifiesta.** Fondo limpio bajo `--:--:--` |
| Boton principal y rotulo | ✅ "Sin fichar" + "Iniciar jornada" en morado |
| Cierre con jornada en `SinFichar` | ✅ `WM_CLOSE` termina el proceso, como debe |

### Ciclo completo verificado — 2026-09-06

Se ejecuto el ciclo entero con `--minutos 2`, autenticando de verdad y cambiando la presencia real.

| Comprobado | Resultado |
|---|---|
| Codigo de dispositivo | ✅ Dialogo con el codigo, navegador abierto, login completado |
| Cache de token (DPAPI) | ✅ `%APPDATA%/MiJornada/msal.cache` creado (8342 bytes) |
| POST a Graph — inicio | ✅ Presencia a `Available`. Si hubiera fallado, `CambiarPresenciaAsync` habria devuelto `false` y la jornada no habria arrancado |
| Persistencia | ✅ `estado.json` con `Situacion:1` y la hora de fin absoluta |
| Cuenta atras | ✅ Decrementa correctamente contra el reloj real |
| Anillo en marcha | ✅ Morado, mostrando **lo que queda** (PAT-003), extremo redondeado |
| Maquina de estados | ✅ El boton pasa a "Pausar" y aparece "Cancelar jornada" |
| POST a Graph — fin | ✅ **Verificado leyendo `GET /me/presence`: `Offline` / `OffWork`** |
| Reset al terminar | ✅ `estado.json` vuelve a `Situacion:0`, UI a "Sin fichar" |
| Estabilidad | ✅ El proceso sobrevive al ciclo completo sin excepciones |
| **DT-006** (`Clipboard` vacio) | ✅ No se manifiesta: el codigo llego con contenido |
| **DT-005** (`async void`) | ⚠️ El camino feliz funciona. El riesgo real —una excepcion en `Estado.Guardar()`— **no se ha ejercitado** |

### Pausa, cancelacion y bandeja — verificado 2026-09-06

| Comprobado | Resultado |
|---|---|
| Token cacheado entre arranques | ✅ El segundo arranque **no pide login**: `AcquireTokenSilent` resuelve |
| **Pausa** | ✅ Cuenta atras congelada en `00:04:35` durante 20 s. `Situacion:2`, `PausaDesde` puesto y **`Fin` SIN tocar** (ADR-005) |
| Anillo en pausa | ✅ Ambar, con la cifra congelada |
| **Reanudar** | ✅ Pausa de **51 s** → `Fin` desplazado **exactamente 51 s** (13:00:49 → 13:01:40). Con precision de segundos, no redondeando a minutos como la version de Power Apps |
| Confirmacion de cancelar | ✅ Dialogo "¿Seguro que quieres cancelar la jornada?" con Si/No |
| Cancelar → **No** | ✅ No destruye nada: la jornada sigue activa |
| Cancelar → **Si** | ✅ `Situacion:0`, UI reseteada, presencia a `Offline`/`OffWork` |
| **Cerrar con jornada activa** | ✅ La ventana se oculta y **el proceso sigue vivo** (ADR-006) |
| **Fin de jornada DESDE LA BANDEJA** | ✅ **La prueba clave**: con la ventana oculta, la jornada termino sola a su hora y puso la presencia en `Offline`/`OffWork`, confirmado leyendo `GET /me/presence` |
| Cierre con `SinFichar` | ✅ Termina el proceso, sin dejar zombis |

**Metodo**: se condujo la interfaz con UIAutomation y se leyo la presencia real contra Graph
despues de cada transicion. No es inferencia: es el estado que ve Teams.

Al terminar se restauro la presencia del usuario con `clearUserPreferredPresence`.

**Sigue SIN comprobar**, y son cosas que necesitan un humano mirando la pantalla:

- **DT-007** (parpadeo del anillo): no es evaluable con capturas estaticas.
- **El globo de notificacion** al terminar la jornada.
- **DT-005**: solo se ha ejercitado el camino feliz. El riesgo real —una excepcion dentro de
  `Estado.Guardar()` en un manejador `async void`— no se ha provocado.

---

## ✅ Resueltas

### DT-003 — `ClientId` sin rellenar — RESUELTA 2026-09-06

**Fichero**: `03_Desarrollo/Estado.cs`

Se creo un registro **propio** en Entra ID con `02_Entorno/crear-registro-entra.ps1`:

| | |
|---|---|
| displayName | `Mi jornada` |
| ClientId (appId) | `dbcd6425-561b-4d91-a4d5-f0bb25b31241` |
| objectId | `5000bd20-ba36-4d78-8150-6a5aed0b08bd` |
| Permiso | delegado `Presence.ReadWrite` (`8d3c54a7-cf58-4773-bf81-c0cd6ad522bb`) |
| Cliente publico | si (`isFallbackPublicClient`), sin secreto |

Se descarto reutilizar el ClientId de Microsoft Graph PowerShell: ver TEC-007 en
`_hilo/LECCIONES.md`. Este registro solo podra hacer una cosa, cambiar la presencia.

El ClientId **no es un secreto** y va en el codigo a proposito (ADR-003).

---

### DT-001 — El proyecto nunca se ha compilado — RESUELTA 2026-09-06

**Evolutivo**: EV-001

Primer `dotnet build` de la historia del proyecto: **compilacion correcta, 0 advertencias,
0 errores**, en 5,2 segundos. Ni un error que corregir.
`bin/Debug/net8.0-windows/MiJornada.exe` generado (151 KB).

Que compile con `Nullable` activado y sin una sola advertencia es mas de lo que cabia esperar de
codigo escrito del tiron y nunca verificado.

---

### DT-002 — Versiones de MSAL sin verificar — RESUELTA 2026-09-06 (falsa alarma)

**Fichero**: `03_Desarrollo/MiJornada.csproj`

Era el sospechoso numero uno y no lo era. `dotnet list package` confirma que
`Microsoft.Identity.Client` y `Microsoft.Identity.Client.Extensions.Msal` **4.66.2** existen y
resuelven exacto (solicitado 4.66.2 → resuelto 4.66.2). `dotnet list package --vulnerable` no
reporta ninguna vulnerabilidad conocida en esas versiones.

**No tocar las versiones sin un motivo concreto.** Funcionan.

---

## 🟡 Medias

### DT-004 — Transparencia de las etiquetas sobre el anillo — **NO SE MANIFIESTA** (2026-09-06)

**Fichero**: `03_Desarrollo/MainForm.cs`

WinForms no tiene transparencia real: un `Label` con `BackColor = Transparent` pinta el fondo de
su **padre**. La cuenta atras esta como hija del panel del anillo (`_lblTiempo.Parent = _anillo`)
precisamente por eso.

**Verificado en el primer arranque real (2026-09-06)**: capturada la ventana con `PrintWindow`,
la cuenta atras (`--:--:--`) aparece sobre el anillo con fondo limpio. **No hay rectangulo gris.**
La solucion de hacer el `Label` hijo del panel funciona.

Se deja anotado y no se borra porque el riesgo vuelve en cuanto alguien anada otra etiqueta sobre
el anillo sin asignarle `Parent = _anillo`. Si eso pasa, la salida es dibujar el texto en el
`Paint` del panel con `DrawString`.

---

### DT-005 — `async void` en los manejadores

**Fichero**: `03_Desarrollo/MainForm.cs`

Las excepciones se capturan dentro de `CambiarPresenciaAsync`, pero **un fallo en
`Estado.Guardar()` se iria sin controlar y tumbaria el proceso**. Y si el proceso muere, nadie
pone el "Fuera del trabajo" al final, que es justo lo que la aplicacion existe para hacer.

**Como se resuelve**: envolver el cuerpo de cada manejador en try/catch, o extraer a metodos
`async Task` invocados desde un unico punto con manejo de errores.

---

### DT-008 — Sin reintento en el POST a Graph

**Fichero**: `03_Desarrollo/GraphService.cs`

Un fallo de red al final de la jornada deja la presencia sin cambiar **y el aviso ya se mostro**:
el usuario cree que ha fichado la salida cuando no.

**Como se resuelve**: reintento con backoff (3 intentos). Con dos paquetes en el proyecto, meter
Polly por esto es desproporcionado; un bucle basta.

---

### DT-009 — Sin instancia unica

**Fichero**: `03_Desarrollo/Program.cs`

Dos ventanas abiertas escriben el mismo `estado.json` y la ultima gana.

**Como se resuelve**: un `Mutex` con nombre en `Main`, y traer al frente la instancia existente.

---

## 🔵 Bajas

### DT-006 — `Clipboard.SetText` con cadena vacia

**Fichero**: `03_Desarrollo/MainForm.cs`

Lanza excepcion. El codigo de dispositivo no deberia venir vacio, pero conviene el `if`.

---

### DT-007 — Parpadeo del anillo — RESUELTA 2026-09-06

**Fichero**: `03_Desarrollo/MainForm.cs`

`Refrescar()` invalidaba el panel cada segundo y el `Panel` no tenia doble bufer: borraba el fondo
y **luego** pintaba, y ese hueco se veia.

**Confirmada midiendola**, no mirandola. Se localizo un pixel sobre el trazo del anillo y se
muestreo a 60 Hz durante 6 s. Aparecieron 5 muestras del color de fondo (blanco `255,255,255` y
gris de la pista `237,235,233`) en:

```
t =  218 ms · 1216 ms · 2216 ms · 3218 ms · 4219 ms
     separadas 998, 1000, 1002 y 1001 ms
```

Esa periodicidad de un segundo clavado **es** la cadencia del reloj: no habia duda de que fuera el
repintado. Un destello de ~16 ms por segundo, todas las horas de jornada.

**Resuelta** con un `Panel` derivado (`MainForm.Lienzo`) con `DoubleBuffered = true`: se pinta
fuera de pantalla y se vuelca de una vez, asi que no hay instante intermedio que ver. Repetida la
misma medicion sobre el binario corregido: **0 muestras de fondo en 361**, frente a 5 de 360.

> La nota original avisaba de un riesgo parecido en el globo de notificacion. Resulto ser un
> problema distinto y peor (Windows los descarta con No molestar): ver TEC-016 y M16.

---

### DT-010 — Sin registro de actividad

**Ficheros**: todos

Hoy, si algo no funciona, no queda rastro de nada. Combinado con DT-008, un fallo al cerrar la
jornada es completamente invisible.

**Como se resuelve**: un fichero de texto en `%APPDATA%/MiJornada/`, con las transiciones y el
resultado de cada llamada a Graph. Sin librerias.

---

### DT-011 — Sin tests

No hay proyecto de tests ni un solo test. `CLAUDE.md` marca "tests obligatorios para codigo
nuevo"; este codigo es preexistente y llego sin ellos.

**Nota de alcance**: los candidatos razonables son `Estado` (la maquina de estados y el calculo
del restante, que es logica pura y facil de testear) y la serializacion. `MainForm` y
`GraphService` exigirian abstracciones que hoy no existen y que ADR-007 descarta a proposito.

---

## Limitaciones asumidas (no son deuda)

Documentadas para que nadie las "arregle" por error:

- **`setUserPreferredPresence` solo surte efecto con Teams abierto** en algun dispositivo. Es
  como funciona la API, no un fallo.
- **Con el equipo apagado no hay quien cierre la jornada.** Da igual: apagado ya apareces
  desconectado.
- **El estado preferido persiste entre sesiones de Teams.** Si un dia cierras sin finalizar,
  al dia siguiente puedes aparecer como Disponible antes de fichar.

---

*Creado por `/onboarding` el 2026-09-06 a partir de `06_Documentacion/CONTEXTO.md` seccion 8*
