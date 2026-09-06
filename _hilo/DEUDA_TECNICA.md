# Deuda Tecnica

> **Proposito**: issues conocidos, riesgos y trabajo pendiente de saneamiento.
> Se sincroniza al Hub con `/mcp-sync` (categoria `deuda`) cuando el Hub este activo.

**Ultima revision**: 2026-09-06 (onboarding)

---

## Resumen

| Severidad | Abiertas |
|---|---|
| 🔴 Critica | 3 |
| 🟡 Media | 4 |
| 🔵 Baja | 3 |

**El elefante en la habitacion**: el codigo se escribio del tiron y **nunca ha pasado por
`dotnet build`**. Nada de lo que sigue esta verificado; los DT-002 a DT-007 son *sospechas
ordenadas por probabilidad*, no fallos observados.

---

## 🔴 Criticas

### DT-001 — El proyecto nunca se ha compilado

**Ficheros**: todos · **Evolutivo**: EV-001

Ni un `dotnet build`. Es el bloqueante de todo lo demas: no tiene sentido pulir nada mientras no
haya un build verde del que partir.

**Como se resuelve**: `cd 03_Desarrollo && dotnet build`, y corregir en el orden que salga.
DT-002 a DT-007 son la lista de lo que probablemente aparezca.

---

### DT-002 — Versiones de MSAL sin verificar

**Fichero**: `03_Desarrollo/MiJornada.csproj`

`Microsoft.Identity.Client` y `Microsoft.Identity.Client.Extensions.Msal` estan fijados a
**4.66.2**, un numero que puede no existir en NuGet o no ser el conveniente.

**Como se resuelve**: si NuGet protesta, subir ambos a la ultima estable de la rama 4.x —
**los dos a la misma version**, porque la extension esta acoplada al cliente.

---

### DT-003 — `ClientId` sin rellenar

**Fichero**: `03_Desarrollo/Estado.cs`

```csharp
public const string ClientId = "PON-AQUI-TU-CLIENT-ID";
```

La aplicacion compila con el placeholder pero no autentica. No es un secreto (un Id de cliente
publico es informacion publica), asi que puede ir en el codigo sin problema.

**Como se resuelve**: pegar el Id de aplicacion del registro de Entra ID. Se puede reutilizar
`Teams Presence Flow` anadiendole la plataforma de escritorio y activando "flujos de cliente
publico".

---

## 🟡 Medias

### DT-004 — Transparencia de las etiquetas sobre el anillo

**Fichero**: `03_Desarrollo/MainForm.cs`

WinForms no tiene transparencia real: un `Label` con `BackColor = Transparent` pinta el fondo de
su **padre**. La cuenta atras esta como hija del panel del anillo (`_lblTiempo.Parent = _anillo`)
precisamente por eso.

**Sintoma si falla**: un rectangulo gris sobre el anillo.
**Como se resuelve**: dibujar el texto en el `Paint` del panel con `DrawString`, en vez de usar
un `Label`.

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

**Fichero**: `03_Desarrollo/PresenciaService.cs`

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

### DT-007 — Parpadeo del anillo

**Fichero**: `03_Desarrollo/MainForm.cs`

`Refrescar()` invalida el panel cada segundo sin doble bufer.

**Como se resuelve**: si parpadea, un `Panel` derivado con `DoubleBuffered = true`. El globo de
notificacion tiene un riesgo parecido: no aparece si `_tray.Visible` es `false` en ese momento
(se pone a `true` justo antes, pero merece comprobacion).

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
`PresenciaService` exigirian abstracciones que hoy no existen y que ADR-007 descarta a proposito.

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
