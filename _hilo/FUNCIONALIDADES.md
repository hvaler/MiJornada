# Funcionalidades del Proyecto

> **Proposito**: modulos y features del proyecto.
> **Leer (Read) antes de modificar una funcionalidad documentada**; actualizar tras implementar
> una nueva.

> **Estado a 2026-09-06**: verificado funcionalmente contra Microsoft Graph. Lo unico sin
> comprobar son dos detalles visuales que necesitan una persona mirando la pantalla: el parpadeo
> del anillo (DT-007) y el globo de notificacion al terminar.

---

## Proposito

Que al empezar la jornada, un boton anclado en la barra de tareas ponga la presencia de Teams en
**Disponible** y arranque una cuenta atras de 7 horas; y que al terminar la ponga en **Fuera del
trabajo**. Con pausa, reanudacion y cancelacion. Sin Power Platform, sin flujos y sin licencias.

El problema real que resuelve: **no aparecer disponible fuera del horario de trabajo** sin tener
que acordarse de cambiar el estado a mano.

---

## Modulos

### M1 — Jornada (maquina de estados)

**Fichero**: `Estado.cs` · **Estado**: verificado 2026-09-06

Tres situaciones: `SinFichar`, `Activa`, `Pausada`.

| Accion | Efecto |
|---|---|
| **Iniciar jornada** | Presencia a `Available`/`Available`, se calcula y persiste la hora de fin (ahora + 7 h) |
| **Pausar** | Congela el restante y pone la presencia elegida en Ajustes (`Ausente` por defecto). La hora de fin **no** se toca |
| **Reanudar** | Desplaza la hora de fin por los minutos parados y vuelve a `Available` |
| **Cancelar jornada** | Con confirmacion. Cierra y pone `Offline`/`OffWork` |
| **Fin de la cuenta atras** | Presencia a `Offline`/`OffWork` y globo de notificacion |

**Regla central**: el restante es **siempre una resta contra el reloj real**, nunca un contador
que se decrementa. Durante la pausa la referencia es `PausaDesde` en lugar de `DateTime.Now`; eso
congela la cifra sin mover la hora de fin. Ver ADR-005.

### M2 — Persistencia

**Fichero**: `Estado.cs` · **Estado**: verificado 2026-09-06

- `%APPDATA%/MiJornada/estado.json`, reescrito **en cada transicion**.
- Se puede cerrar y reabrir la aplicacion sin perder la cuenta atras, porque no se guarda un
  contador sino la hora de fin.
- Un `estado.json` corrupto no impide arrancar: `Cargar()` traga la excepcion y empieza de cero.
- Si al arrancar la hora de fin ya paso, se descarta en silencio: no tiene sentido notificar el
  final de una jornada que termino ayer.

### M3 — Presencia (Microsoft Graph)

**Fichero**: `PresenciaService.cs` · **Estado**: verificado 2026-09-06

POST a `users/{objectId}/presence/setUserPreferredPresence`. Detalle en `_hilo/DEPENDENCIAS.md`.

### M4 — Autenticacion

**Fichero**: `PresenciaService.cs` · **Estado**: verificado 2026-09-06

Codigo de dispositivo con MSAL, token cacheado en disco cifrado con DPAPI. El codigo solo se pide
la primera vez y cuando caduca el refresh token.

### M5 — Interfaz

**Fichero**: `MainForm.cs` · **Estado**: verificado 2026-09-06

- Ventana de 340×430, no redimensionable.
- **Anillo de progreso** dibujado con GDI+: nace morado (`#5B5FC7`) y completo, y va cediendo
  terreno al gris segun avanza la jornada. Ambar (`#C19C00`) durante las pausas. Anillo y cifra
  central cuentan lo mismo: **lo que queda**.
- Un solo boton principal que cambia segun el estado, mas un enlace de cancelar y un engranaje
  discreto arriba a la derecha que abre los Ajustes (M7).
- Icono en la bandeja del sistema. **Cerrar la ventana con la jornada en marcha la manda a la
  bandeja, no la termina** (ADR-006).

### M6 — Modo de prueba

**Fichero**: `Program.cs` · **Estado**: verificado

`MiJornada.exe --minutos 2` acorta la jornada para no esperar siete horas. Manda sobre los
ajustes guardados y **deshabilita** la duración en el diálogo mientras dure esa ejecución.

### M7 — Ajustes

**Ficheros**: `DialogoAjustes.cs`, `Ajustes` en `Estado.cs` · **Estado**: verificado 2026-09-06

Un engranaje discreto arriba a la derecha abre un diálogo aparte. La pantalla principal se queda
solo con el anillo y el botón; la configuración crece aquí sin ensuciarla.

| Ajuste | Valores | Por defecto |
|---|---|---|
| Duración general de la jornada | 0-23 h + 0-59 min | 7 h |
| Duración por día de la semana | excepción opcional para cada uno de los 7 días | sin excepciones |
| Al pausar, aparecer como | Ausente · Vuelvo enseguida · Ocupado · No molestar | Ausente |
| Fichar al desbloquear el equipo | sí / no | **no** |
| Avisar N minutos antes del final | 0-120 (0 = sin aviso) | 15 |
| Arrancar con Windows | sí / no | **no** |
| ...y hacerlo en la bandeja | sí / no | no |
| Compartir la jornada entre equipos | sí / no | **sí** |
| Franja del fichaje automático | dos horas (HH:mm) | 07:00 – 11:00 |
| No fichar solo sábados ni domingos | sí / no | **sí** |
| Festivos en los que no fichar solo | lista de fechas | vacía |

- Se persisten en `%APPDATA%/MiJornada/ajustes.json`, **fichero aparte de `estado.json`**:
  cancelar una jornada no debe olvidar que tu jornada dura 6 horas.
- **La duración no se puede cambiar con una jornada en marcha**: el anillo se calcula contra
  `Config.Jornada` y mostraría una fracción distinta a la que se usó al fichar. El diálogo lo
  deshabilita y lo explica, en vez de dejar hacerlo y descuadrar la pantalla.
- Una jornada de cero minutos terminaría nada más empezar: el botón Guardar se deshabilita y se
  dice por qué. **No se corrige el valor mientras el usuario escribe** — bajando las horas se pasa
  por "0 h 0 min", y ajustarlo justo ahí le secuestraría la entrada.
- El estado de pausa se guarda por su **clave de Graph** (`BeRightBack`), no por la etiqueta
  traducida, para que cambiar textos no invalide los ajustes ya guardados.

### M8 — Icono propio

**Ficheros**: `mijornada.ico`, `Iconos` en `Estado.cs`, `01_Diseno/generar-icono.ps1`

El anillo de la aplicación como icono, en 7 resoluciones (16 a 256 px) dentro de un único `.ico`
con marcos PNG. Se pide el marco concreto en cada uso (16 px bandeja, 32 ventana): con uno solo,
Windows escala y se ve borroso.

Se dibuja como arco de 270° y no como círculo cerrado porque a 16 px un círculo completo se lee
como una rosquilla indistinguible; el hueco es lo que hace reconocible que es un progreso. La
pista gris solo aparece de 32 px para arriba: por debajo es ruido.

Para regenerarlo: `01_Diseno/generar-icono.ps1`. El `.ico` se commitea.

### M9 — Icono de bandeja dinamico

**Ficheros**: `IconoAnillo.cs`, `MainForm.ActualizarIconoBandeja` · **Estado**: verificado 2026-09-06

El icono de la bandeja **deja de ser fijo mientras hay jornada**: dibuja el anillo con el avance
real, para ver cuanto queda sin abrir la ventana. Morado corriendo, ambar en pausa, y vuelve al
icono estatico al terminar.

Dos cosas que hacen que esto no se rompa a las horas:

- **Se redibuja solo cuando cambia el porcentaje entero.** A un icono por segundo durante siete
  horas serian 25.000 iconos para 100 imagenes distintas.
- **Se destruye el HICON con `DestroyIcon`.** El handle que devuelve `Bitmap.GetHicon()` no lo
  gestiona el recolector: sin liberarlo, cada actualizacion filtra un objeto GDI y el proceso
  acaba agotandolos. Verificado: **los objetos GDI se quedan en 40 tras ~100 redibujados**.
- El tamano lo marca `SystemInformation.SmallIconSize`, que respeta el DPI. Dibujar a 32 fijo y
  dejar que Windows reduzca da un anillo emborronado.

### M10 — Fichaje automatico al desbloquear

**Fichero**: `MainForm.Sesion_Cambiada` · **Estado**: implementado, **sin probar de punta a punta**

Escucha `SystemEvents.SessionSwitch` y ficha solo al desbloquear el equipo. Es lo que convierte
la aplicacion en algo que no hay que acordarse de usar.

**Desactivado por defecto**: cambia la presencia del usuario sin que el haga nada, y eso se pide,
no se impone.

Guardas, en orden:

1. Solo el evento `SessionUnlock`.
2. Solo si el ajuste esta activado.
3. Solo si no hay ya una jornada en marcha o pausada.
4. **Solo una vez al dia** (`UltimoAutoFichaje`): volver del cafe no vuelve a fichar, y si hoy se
   cancelo la jornada a proposito, tampoco — cancelar significa "hoy no quiero estar fichado".
5. El dia solo se marca como consumido **si Graph respondio bien**: un fallo de red no gasta el
   intento.

Detalles tecnicos que no son opcionales:

- `SystemEvents` notifica en un **hilo del pool**: hay que volver al de la interfaz con
  `BeginInvoke` antes de tocar nada.
- `SystemEvents` guarda una **referencia estatica** al manejador: hay que darse de baja en
  `OnFormClosing` o seguiria vivo sobre un formulario destruido.
- El manejador es `async void` y lleva su propio try/catch: una excepcion ahi tumbaria el proceso
  y con el la jornada (DT-005).
- Solo avisa con globo **si la ventana no esta a la vista**; si lo esta, la cuenta atras ya se ve.

**Como probarlo**: activar la casilla en Ajustes, bloquear con Win+L y desbloquear.

**Que hace y que NO hace Win+L**:

| Evento | Comportamiento |
|---|---|
| **Bloquear** (Win+L) | **Nada.** La jornada sigue contando. Bloquear el equipo no significa dejar de trabajar |
| **Desbloquear**, primera vez del dia | Ficha, si el ajuste esta activo y no hay jornada en marcha |
| **Desbloquear**, resto del dia | Nada. Volver del cafe no vuelve a fichar |
| **Suspender / hibernar** | Nada especial: al volver, la resta contra el reloj real da el valor correcto (PAT-001) |

### M15 — Cuando puede fichar solo

**Ficheros**: `Ajustes.PuedeFicharSolo`, pestaña Calendario de `DialogoAjustes` · **Estado**: verificado 2026-09-06

Tres guardas sobre el fichaje automatico, en este orden: fin de semana, festivo, franja horaria.
Cada una devuelve su motivo, que va al registro de depuracion.

**Solo condicionan al AUTOMATISMO.** Fichar a mano funciona cualquier dia y a cualquier hora: si
un sabado decides trabajar, la aplicacion no tiene por que llevarte la contraria.

| Guarda | Por defecto |
|---|---|
| Franja horaria | 07:00 – 11:00. Sin ella, desbloquear a las 3 de la madrugada ficharia la jornada |
| Fin de semana | No ficha sabados ni domingos |
| Festivos | Lista de fechas, vacia de serie |

Los festivos se escriben a mano, una fecha por linea. `Ajustes.ParsearFecha` acepta lo que la
gente escribe de verdad —`25/12/2026`, `1/5/2026`, `2026-01-06`, `06-01-2026`— y **siempre con
cultura invariante**, nunca la del equipo: el fichero viaja por OneDrive entre maquinas que
pueden tener otra configuracion regional, y con la cultura local un `03/04/2026` seria marzo aqui
y abril alli. Se guardan normalizados a `yyyy-MM-dd`, sin duplicados y ordenados.

Una linea que no se entienda **avisa pero no bloquea** el guardado: se descarta. Bloquear el
dialogo entero por una linea suelta seria desproporcionado. Solo la duracion de cero minutos
impide guardar.

**Verificado** llamando a la logica directamente: lunes 08:30 ficha; lunes 03:00 y 15:00 quedan
fuera de franja; sabado y domingo son fin de semana; 25 de diciembre es festivo. Y el parseo
acepta los cuatro formatos y rechaza `32/13/2026`, texto libre y cadena vacia.

### M14 — Duracion por dia de la semana

**Ficheros**: `Ajustes.DuracionPorDia`, `Estado.DuracionMinutos`, `DialogoAjustes` · **Estado**: verificado 2026-09-06

Una duracion general y, opcionalmente, una **excepcion para cada uno de los siete dias**. Un dia
sin excepcion usa la general.

- Las excepciones se guardan con el **nombre invariante** de `DayOfWeek` (`"Friday"`), no el
  traducido: la aplicacion puede correr en equipos con idioma distinto y el fichero viaja entre
  ellos por OneDrive.
- Solo se guardan los dias marcados; los demas ni aparecen en el JSON.
- La duracion se resuelve **al fichar**, con el dia real: si la aplicacion lleva abierta desde
  ayer, la de ayer no vale.

**Cambio importante que trae esto**: `Estado` ahora guarda `DuracionMinutos`, la duracion **con
la que arranco esa jornada**. El anillo se calcula contra ella y no contra la configurada hoy.
Eso arregla de paso el riesgo que ya estaba documentado en `DEPENDENCIAS.md` — cambiar la
duracion con una jornada abierta descuadraba el anillo — y ademas hace correcto el caso nuevo:
una jornada iniciada en otro equipo con otra configuracion se dibuja bien aqui.

**Verificado**: con general 420 min y excepcion de domingo 90 min, fichar un domingo produjo una
jornada de 90 min (`estado.DuracionMinutos = 90`), no de 420.

### M13 — Arranque con Windows

**Fichero**: `ArranqueWindows.cs` · **Estado**: verificado 2026-09-06

Acceso directo en la carpeta de Inicio del usuario, creado por COM tardio (`WScript.Shell`) para
no anadir dependencias a un proyecto que solo tiene dos paquetes.

**Se usa la carpeta de Inicio y no la clave `Run` del registro a proposito**: es visible, el
usuario puede verla y borrarla, Windows la lista en el Administrador de tareas junto al resto de
aplicaciones de inicio, y no hace falta ningun permiso especial.

**No hay un ajuste booleano "ArrancarConWindows"**: la verdad es la existencia del `.lnk`. El
usuario puede borrarlo desde el Administrador de tareas, asi que un booleano guardado solo podria
desincronizarse y mentir. La casilla lee el fichero.

Con `--minimizado` (que solo lleva el acceso directo, no el arranque manual) la aplicacion va
directa a la bandeja. **Importa para el fichaje automatico**: si la aplicacion no esta corriendo,
nadie escucha el desbloqueo de sesion.

Verificado: la casilla crea el `.lnk` con destino, argumento `--minimizado` e icono correctos, y
al desmarcarla lo borra.

### M12 — Estado compartido entre equipos

**Ficheros**: `SincronizacionGraph.cs`, `GraphService.cs` · **Estado**: verificado 2026-09-06

Estado y ajustes viajan por `me/drive/special/approot` (carpeta privada de la aplicacion en
OneDrive). Ver **ADR-009** para el porque y las alternativas descartadas.

| Regla | |
|---|---|
| Almacen de trabajo | El **fichero local**. Graph es solo la capa de sincronizacion |
| Se lee | Al abrir la ventana, cada 60 s, al volver de la bandeja, y **antes de iniciar jornada** |
| Se escribe | Despues de cada transicion |
| Conflictos | `If-Match` con eTag; un 412 relee y **gana el `Actualizado` mas reciente** |
| Sin red | La cuenta atras sigue; indicador "Sin sincronizar" y reintento automatico |
| Sin sesion | La sincronizacion de fondo usa **solo token en cache**: abrir la ventana nunca pide un codigo de dispositivo |
| Control | Total desde cualquier equipo. El rotulo anade " · EQUIPO" cuando la inicio otro |

**Verificado de punta a punta** con dos instancias de datos separados (`--datos`):

- Instancia virgen, sin `estado.json`, **trae la jornada de OneDrive** y muestra Pausar/Cancelar
  en lugar de "Iniciar jornada". Ese era el problema a resolver.
- Pausar en un equipo se adopta en el otro con el fichero **identico byte a byte, incluido el
  `Actualizado`** — prueba de que no se re-sella al adoptar (si se sellara, el que adopta pasaria
  por autor y ganaria siempre el conflicto siguiente).
- Cancelar propaga: una instancia virgen posterior ve "Sin fichar".

**Sin verificar todavia**: el cierre por vencimiento desde el otro equipo. Usa la misma ruta de
publicacion que la pausa, ya verificada, pero no se ha ejercitado.

### M11 — Acerca de

**Fichero**: `DialogoAcercaDe.cs` · **Estado**: verificado 2026-09-06

Version y, sobre todo, los datos que hacen falta para diagnosticar: ClientId del registro de
Entra, tenant, permiso solicitado y un enlace que abre la carpeta de datos.

El ClientId y el tenant van en cuadros de texto **seleccionables**: son lo primero que se pide en
cualquier consulta de soporte, y copiarlos a mano de una captura es innecesariamente molesto.

Se llega desde dos sitios: el menu de la bandeja y un enlace discreto en Ajustes.

---

## Funcionalidades criticas (no pueden fallar)

1. **Poner `Offline`/`OffWork` al final de la jornada.** Es el proposito entero de la aplicacion.
   Hoy no hay reintento si el POST falla (DT-008) ni registro de que ocurrio (DT-010).
2. **Persistir la hora de fin en cada transicion.** Si se pierde, la jornada en curso desaparece.
3. **Que cerrar la ventana no mate el proceso.** Si muere, nadie cierra la jornada.

---

## Planificadas

De `06_Documentacion/CONTEXTO.md` seccion 9. Ordenadas por lo que aportan frente a lo que cuestan.
Lo tachado ya esta hecho.

**Cerca del codigo, utiles ya**

- ~~**Icono propio**~~ — HECHO 2026-09-06 (M8).
- ~~**Duracion configurable**~~ y ~~**ajustes persistidos**~~ — HECHO 2026-09-06 (M7).
- ~~**Icono de bandeja dinamico**~~ — HECHO 2026-09-06 (M9).
- ~~**Aviso antes del final**~~ y ~~**arranque con Windows / minimizado**~~ — HECHO 2026-09-06.
- ~~**Duracion por dia de la semana**~~ — HECHO 2026-09-06, con las siete y en pestañas.
- ~~**Franja horaria** del fichaje automatico~~ y ~~**saltar fines de semana y festivos**~~
  — HECHO 2026-09-06 (M15).
- **INSTALADOR**: todo lo que hoy se hace a mano deberia hacerlo el (crear/actualizar el registro
  de Entra con `02_Entorno/crear-registro-entra.ps1`, colocar el .exe, el acceso directo de
  inicio). Es el siguiente salto de usabilidad si esto lo va a usar alguien mas.

**Funcionalidad**

- ~~**Fichaje automatico** al desbloquear~~ — HECHO 2026-09-06 (M10), pendiente de probar
  bloqueando y desbloqueando el equipo.
- **Aviso 15 minutos antes del final**, para poder cerrar cosas.
- **Historico de jornadas** en el propio JSON, con resumen semanal. La version de Power Apps lo
  tenia a mano por la lista de SharePoint y aqui se perdio.
- **Leer la presencia real** con `GET /users/{id}/presence` en vez de asumir que el cambio se
  aplico. Detectaria el caso de Teams cerrado, que hoy pasa en silencio.
- **Saltar fines de semana y festivos.** Pendiente desde la primera version.

**Robustez** — ver `_hilo/DEUDA_TECNICA.md`: reintento en el POST (DT-008), instancia unica con
`Mutex` (DT-009), registro de actividad (DT-010).

---

## Fuera de alcance

- **Multiusuario.** `Presence.ReadWrite` delegado solo permite tocar la presencia de uno mismo.
  Hacerlo para otros exigiria `Presence.ReadWrite.All` como permiso de aplicacion, con
  consentimiento de administrador. Ver ADR-004.
- **Cerrar la jornada con el equipo apagado.** No hay quien haga la llamada. Da igual: con el
  equipo apagado ya apareces desconectado.

---

*Completado por `/onboarding` el 2026-09-06*
