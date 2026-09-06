# Registro de Decisiones Arquitectonicas (ADRs)

> **INSTRUCCIONES PARA CLAUDE**: Este archivo documenta las decisiones tecnicas importantes.
> SIEMPRE respeta las decisiones ya tomadas a menos que el desarrollador indique lo contrario.
> Antes de proponer una solucion, verifica que no contradiga decisiones existentes.

---

## Indice de Decisiones

| ID | Titulo | Fecha | Estado | Categoria |
|----|--------|-------|--------|-----------|
| ADR-001 | Abandonar Power Platform por coste de licencia | 2026-09-06 | Aceptada | Arquitectura |
| ADR-002 | Flujo de codigo de dispositivo, no interactivo | 2026-09-06 | Aceptada | Seguridad |
| ADR-003 | Sin secreto de cliente | 2026-09-06 | Aceptada | Seguridad |
| ADR-004 | JSON local en vez de SharePoint | 2026-09-06 | Aceptada | Arquitectura |
| ADR-005 | Persistir la hora de fin, no un contador | 2026-09-06 | Aceptada | Arquitectura |
| ADR-006 | Cerrar la ventana manda a la bandeja | 2026-09-06 | Aceptada | Frontend |
| ADR-007 | Sin capas, sin DI, namespace plano | 2026-09-06 | Aceptada | Arquitectura |
| ADR-008 | WinForms y no WPF | 2026-09-06 | Aceptada | Frontend |
| ADR-009 | Estado compartido entre equipos via la carpeta de aplicacion de OneDrive | 2026-09-06 | Aceptada | Arquitectura |

---

## Decisiones Vigentes

### ADR-001: Abandonar Power Platform por coste de licencia

**Estado**: Aceptada · **Fecha**: 2026-09-06 · **Categoria**: Arquitectura

#### Contexto

La segunda implementacion (Power Apps + Power Automate + SharePoint, integrada en Teams) llego a
funcionar **de punta a punta**. No se abandono por problemas tecnicos.

El conector personalizado hacia Graph es **premium**, y eso arrastra a la app y a los dos flujos
que lo usan: no entra en Microsoft 365. Precios de lista consultados el 6/9/2026: Power Apps
Premium ~20 $/usuario/mes, Power Automate Premium 15 $/usuario/mes, Power Automate Process
~150 $ por flujo/mes. Para una sola persona que quiere no aparecer disponible fuera de su
horario, no se justifica frente a hacerlo a mano.

#### Decision

Reescribir como aplicacion de escritorio que habla con Graph directamente. Sin conector, sin
flujos, sin licencia.

#### Consecuencias

- Coste cero. Sin dependencia de red ni de licencia.
- Se pierde el historico compartido que daba la lista de SharePoint.
- Con el equipo apagado no hay quien cierre la jornada (aceptable: apagado ya apareces
  desconectado).

#### Alternativas descartadas

- **Conector "HTTP con Microsoft Entra ID"** (estandar, no premium): bloqueante definitivo.
  Devuelve `AADSTS65002`, y la preautorizacion entre dos aplicaciones de Microsoft solo la puede
  configurar Microsoft. Ese conector sirve para APIs propias, no para Graph.
- **Duracion nativa de Teams**: al expirar vuelve a "automatico", no a un estado concreto.
- **Script de PowerShell con `Start-Sleep`** (la primera implementacion): moria al cerrar la
  consola y no avanzaba con el equipo suspendido.
- **Retomarlo para varias personas**: ademas del coste, tiene un bloqueante propio. El flujo de
  recurrencia se ejecuta con las conexiones de quien lo creo, asi que cambiaria *su* presencia;
  `Presence.ReadWrite` delegado solo permite tocar la de uno mismo.

> Historia completa en `06_Documentacion/mi-jornada-traspaso.md`.

---

### ADR-002: Flujo de codigo de dispositivo, no interactivo

**Estado**: Aceptada · **Fecha**: 2026-09-06 · **Categoria**: Seguridad
**Revisada**: 2026-09-06 — se anade la causa raiz y se descartan las alternativas

#### Contexto

El flujo interactivo normal de MSAL falla en este tenant con
`Error response came from MDM terms of use page`.

**Causa raiz (verificada el 2026-09-06 con `dsregcmd /status`)**: el equipo de desarrollo **no
esta unido a Entra ID de ninguna forma**.

```
AzureAdJoined : NO      DomainJoined     : NO
EnterpriseJoined : NO   WorkplaceJoined  : NO
```

Es una maquina personal sin gestionar, y la politica de acceso condicional de la organizacion
exige dispositivo gestionado. **El error no es un fallo de la aplicacion ni un problema de
configuracion del registro**: es una politica del tenant que ninguna linea de codigo puede
sortear.

#### Decision

Usar `AcquireTokenWithDeviceCode`. **No es un capricho ni una preferencia estetica**: es el flujo
que Microsoft recomienda explicitamente para equipos sin acceso a navegador o sin gestionar, y el
unico que se ha comprobado que funciona aqui.

#### Consecuencias

- Funciona en equipos no gestionados.
- La primera vez hay que copiar un codigo y pegarlo en el navegador. Despues el token se cachea
  con DPAPI y no vuelve a pedirse hasta que caduque el refresh (del orden de 90 dias).

#### Alternativas descartadas

Las tres se evaluaron el 2026-09-06 a raiz de la pregunta "¿no puede pedirme usuario y
contrasena, como cuando me conecto a las aplicaciones?".

| Alternativa | Por que no |
|---|---|
| **Caja de usuario/contrasena en la propia app** (ROPC, `AcquireTokenByUsernamePassword`) | Microsoft la documenta como **incompatible con Acceso Condicional y con MFA** por diseno: no hay interaccion donde meter el segundo factor. El mismo muro que obligo al codigo de dispositivo la invalida. Ademas esta **deprecada** por riesgo de seguridad |
| **Flujo interactivo** (`AcquireTokenInteractive`, la pantalla de login de Microsoft) | Es lo que falla. Causa raiz arriba: dispositivo no gestionado |
| **WAM / broker de Windows** (`Microsoft.Identity.Client.Broker`, el selector de cuentas del sistema) | Es lo que hace que Teams u Outlook no pidan contrasena en un portatil corporativo, pero **se apoya en que el dispositivo tenga identidad propia en Entra**, que es justo lo que a esta maquina le falta. Caeria al navegador y chocaria con la misma politica |

> **No volver a plantear ninguna de las tres sin comprobar antes `dsregcmd /status`.** Lo que
> cambiaria el panorama no es codigo: seria unir el equipo a Entra ID (Configuracion de Windows →
> Cuentas → Acceder al trabajo o escuela). Eso da a la organizacion capacidad de gestion sobre un
> equipo personal, asi que es una **decision del usuario, no tecnica**.

---

### ADR-003: Sin secreto de cliente

**Estado**: Aceptada · **Fecha**: 2026-09-06 · **Categoria**: Seguridad

#### Contexto

El registro de Entra ID `Teams Presence Flow` tiene un secreto, pero es para el conector de Power
Platform y aqui no se usa.

#### Decision

La aplicacion de escritorio es un **cliente publico** y no usa secreto. Requiere activar
"Permitir flujos de cliente publico" en el registro; sin eso, `AADSTS7000218`.

#### Consecuencias

- Nada que rotar ni que proteger.
- El `ClientId` en `Estado.cs` **no es un secreto**: un Id de cliente publico es informacion
  publica. Que aparezca en el codigo no incumple la regla de "nunca hardcodear secretos".

> Un secreto dentro de un `.exe` no es un secreto.

---

### ADR-004: JSON local en vez de SharePoint

**Estado**: Aceptada · **Fecha**: 2026-09-06 · **Categoria**: Arquitectura

#### Contexto

La version de Power Apps guardaba el estado en una lista de SharePoint, lo que daba historico
pero ataba a la red y a la licencia.

#### Decision

Todo el estado en `%APPDATA%/MiJornada/estado.json`.

> ⚠️ **Modificada por ADR-009 (2026-09-06).** El JSON local sigue siendo el almacen de
> trabajo, pero ya no es la unica copia: se sincroniza con la carpeta de aplicacion de OneDrive.
> Lo que sigue describe la decision original.

#### Consecuencias

- Sin dependencia de red ni de licencia.
- Sin historico compartido ni multidispositivo.
- **Las reglas del ecosistema sobre infraestructura balanceada no aplican aqui.** "Nunca guardar
  en disco local" vale para servicios balanceados; esta es una aplicacion de escritorio de un
  solo usuario y el disco local es exactamente el sitio correcto.

---

### ADR-005: Persistir la hora de fin, no un contador

**Estado**: Aceptada · **Fecha**: 2026-09-06 · **Categoria**: Arquitectura

#### Contexto

Un contador que se decrementa se desincroniza si el equipo se suspende o el proceso se congela.

#### Decision

Guardar la **hora de fin** y calcular el restante siempre como resta contra el reloj real. Durante
la pausa la referencia es `PausaDesde` en lugar de `DateTime.Now`, lo que congela la cifra sin
tocar la hora de fin; esta solo se desplaza al reanudar.

#### Consecuencias

- Sobrevive a suspensiones, cierres y reinicios: al volver, la resta da el valor correcto.
- Es la misma solucion que en Power Apps, donde los minutos parados se sumaban a `FinPrevisto`.

> **Esta es la regla de negocio central del proyecto.** Cualquier refactor del calculo del tiempo
> debe preservarla.

---

### ADR-006: Cerrar la ventana manda a la bandeja

**Estado**: Aceptada · **Fecha**: 2026-09-06 · **Categoria**: Frontend

#### Contexto

Si el proceso muere con una jornada en marcha, **nadie** pone el "Fuera del trabajo" al final, que
es el proposito entero de la aplicacion.

#### Decision

Cerrar la ventana con una jornada activa la envia a la bandeja del sistema; no termina el proceso.

#### Consecuencias

- La jornada se cierra sola aunque el usuario cierre la ventana.
- Hay que salir explicitamente desde la bandeja, lo que sorprende a quien no lo sabe.

---

### ADR-007: Sin capas, sin DI, namespace plano

**Estado**: Aceptada · **Fecha**: 2026-09-06 · **Categoria**: Arquitectura

#### Contexto

`CLAUDE_BASE.md` propone Clean Architecture y namespaces `{prefix}.[Area].[Proyecto].[Capa]`.

#### Decision

Cinco ficheros en un namespace plano `MiJornada`, sin interfaces, sin inyeccion de dependencias y
sin separacion en capas. Son unas 500 lineas.

#### Consecuencias

- Se lee entero de una sentada.
- `MainForm` y `PresenciaService` no son testeables sin introducir abstracciones. Asumido: los
  tests razonables son los de `Estado` (logica pura). Ver DT-011.

> **Es una excepcion deliberada al estandar, no un descuido.** Meterle arquitectura a esto seria
> peor. Si el proyecto creciera mucho, reabrir esta decision.

---

### ADR-008: WinForms y no WPF

**Estado**: Aceptada · **Fecha**: 2026-09-06 · **Categoria**: Frontend

#### Contexto

Una sola ventana y un anillo de progreso dibujado a mano con GDI+.

#### Decision

WinForms, dibujando el anillo en el `Paint` de un panel.

#### Consecuencias

- Menos ceremonia para el mismo resultado.
- WinForms no tiene transparencia real: un `Label` transparente pinta el fondo de su **padre**
  (por eso la cuenta atras es hija del panel del anillo). Ver DT-004.

---

### ADR-009: Estado compartido entre equipos via la carpeta de aplicacion de OneDrive

**Estado**: Aceptada · **Fecha**: 2026-09-06 · **Categoria**: Arquitectura
**Modifica**: ADR-004

#### Contexto

El uso real es en **dos equipos** (casa y remoto), con Teams abierto en ambos y en el movil. Con
el estado solo en `%APPDATA%`, el segundo equipo mostraba "Iniciar jornada" y permitia arrancar
una **segunda jornada** con su propia hora de fin.

Lo que lo hace grave: **la presencia de Teams es por usuario, no por dispositivo**.
`setUserPreferredPresence` fija un unico valor para toda la cuenta, lo mande quien lo mande. Los
dos equipos se pelearian por el mismo valor.

#### Decision

Compartir estado y ajustes en `me/drive/special/approot` (permiso delegado
`Files.ReadWrite.AppFolder`), **manteniendo el fichero local como almacen de trabajo**. Graph es
una capa de sincronizacion, no la fuente de verdad en caliente.

Esa separacion no es un detalle de implementacion, es lo que hace que sea seguro:

- La cuenta atras corre en un temporizador de **un segundo**; ninguna E/S de red puede colgar de
  esa ruta.
- `Cancelar_Click` y `Reloj_Tick` son `async void`. Meter red dentro de `Guardar()` habria
  convertido **DT-005 de riesgo teorico en caida probable**, y una caida se lleva por delante la
  jornada — justo lo que la aplicacion existe para evitar.
- Sin red, la jornada sigue corriendo desde el fichero local y se sube al recuperar conexion.

**Conflictos**: se escribe con `If-Match` y el eTag de la ultima lectura; un `412` significa que
el otro equipo se adelanto, se relee y **gana el `Actualizado` mas reciente**. Con un solo usuario
es correcto: no haces cosas contradictorias en dos equipos en el mismo segundo.

**Excepcion deliberada en el cierre**: al llegar a cero se cambia la presencia **primero** y se
publica despues, sin reclamar el cierre con `If-Match`. Reclamarlo seria mas elegante, pero
dejaria al equipo sin cerrar la jornada cuando no hay red. El precio es que, con los dos equipos
encendidos, ambos manden el mismo `Offline`/`OffWork`: inocuo, es idempotente.

#### Consecuencias

- Cualquier equipo puede pausar y cancelar la jornada: es del usuario, no del equipo. Un texto
  discreto indica donde se inicio cuando no fue este.
- **Se gana algo que antes no habia**: si se apaga el equipo que inicio la jornada, otro con la
  aplicacion abierta la cierra. Antes nadie ponia el "Fuera del trabajo".
- Ampliar `Config.Scopes` invalida el token en cache: un consentimiento nuevo por equipo.
- `Fin` y `PausaDesde` pasan de `DateTime` a `DateTimeOffset`: una hora sin desfase es ambigua
  cuando el estado viaja.
- **No resuelve dos instancias en el MISMO equipo**: eso sigue siendo DT-009.

#### Alternativas descartadas

| Alternativa | Por que no |
|---|---|
| **Solo documentar la limitacion** ("ficha en un solo equipo") | Depende de la disciplina del usuario para evitar un fallo que la aplicacion puede evitar sola |
| **Carpeta sincronizada de OneDrive** (fichero en disco) | Sin permisos nuevos, pero la latencia de sincronizacion es opaca y genera ficheros de conflicto (`estado-EQUIPO.json`) que nadie resuelve |
| **`Files.ReadWrite`** | Funciona, pero da acceso a **todo** el OneDrive del usuario para guardar un JSON de seis campos. Desproporcionado |
| **Propiedades de extension en el objeto de usuario** (`User.ReadWrite`) | Permite modificar el perfil del usuario: mas permiso del necesario |

> La documentacion de Microsoft se contradice sobre si `Files.ReadWrite.AppFolder` vale para
> cuentas de trabajo: el articulo actual de Graph dice que si, el antiguo de OneDrive dice que es
> solo para cuentas personales. **Verificado empiricamente el 2026-09-06 con esta cuenta**: el
> scope se concede, `GET /me/drive/special/approot` responde 200 y el `PUT` devuelve eTag. El
> documento antiguo esta desfasado.

---

*Completado por `/onboarding` el 2026-09-06 a partir de `06_Documentacion/CONTEXTO.md` seccion 10
y `06_Documentacion/mi-jornada-traspaso.md`*
