# Funcionalidades del Proyecto

> **Proposito**: modulos y features del proyecto.
> **Leer (Read) antes de modificar una funcionalidad documentada**; actualizar tras implementar
> una nueva.

> ⚠️ Todo lo que sigue esta **escrito pero no probado**: el proyecto nunca se ha compilado.
> "Implementado" aqui significa "el codigo existe", no "funciona".

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

**Fichero**: `Estado.cs` · **Estado**: escrito, sin compilar

Tres situaciones: `SinFichar`, `Activa`, `Pausada`.

| Accion | Efecto |
|---|---|
| **Iniciar jornada** | Presencia a `Available`/`Available`, se calcula y persiste la hora de fin (ahora + 7 h) |
| **Pausar** | Congela el restante y pone `Away`/`Away`. La hora de fin **no** se toca |
| **Reanudar** | Desplaza la hora de fin por los minutos parados y vuelve a `Available` |
| **Cancelar jornada** | Con confirmacion. Cierra y pone `Offline`/`OffWork` |
| **Fin de la cuenta atras** | Presencia a `Offline`/`OffWork` y globo de notificacion |

**Regla central**: el restante es **siempre una resta contra el reloj real**, nunca un contador
que se decrementa. Durante la pausa la referencia es `PausaDesde` en lugar de `DateTime.Now`; eso
congela la cifra sin mover la hora de fin. Ver ADR-005.

### M2 — Persistencia

**Fichero**: `Estado.cs` · **Estado**: escrito, sin compilar

- `%APPDATA%/MiJornada/estado.json`, reescrito **en cada transicion**.
- Se puede cerrar y reabrir la aplicacion sin perder la cuenta atras, porque no se guarda un
  contador sino la hora de fin.
- Un `estado.json` corrupto no impide arrancar: `Cargar()` traga la excepcion y empieza de cero.
- Si al arrancar la hora de fin ya paso, se descarta en silencio: no tiene sentido notificar el
  final de una jornada que termino ayer.

### M3 — Presencia (Microsoft Graph)

**Fichero**: `PresenciaService.cs` · **Estado**: escrito, sin compilar

POST a `users/{objectId}/presence/setUserPreferredPresence`. Detalle en `_hilo/DEPENDENCIAS.md`.

### M4 — Autenticacion

**Fichero**: `PresenciaService.cs` · **Estado**: escrito, sin compilar

Codigo de dispositivo con MSAL, token cacheado en disco cifrado con DPAPI. El codigo solo se pide
la primera vez y cuando caduca el refresh token.

### M5 — Interfaz

**Fichero**: `MainForm.cs` · **Estado**: escrito, sin compilar

- Ventana de 340×430, no redimensionable.
- **Anillo de progreso** dibujado con GDI+: nace morado (`#5B5FC7`) y completo, y va cediendo
  terreno al gris segun avanza la jornada. Ambar (`#C19C00`) durante las pausas. Anillo y cifra
  central cuentan lo mismo: **lo que queda**.
- Un solo boton principal que cambia segun el estado, mas un enlace de cancelar.
- Icono en la bandeja del sistema. **Cerrar la ventana con la jornada en marcha la manda a la
  bandeja, no la termina** (ADR-006).

### M6 — Modo de prueba

**Fichero**: `Program.cs` · **Estado**: escrito, sin compilar

`MiJornada.exe --minutos 2` acorta la jornada para no esperar siete horas.

---

## Funcionalidades criticas (no pueden fallar)

1. **Poner `Offline`/`OffWork` al final de la jornada.** Es el proposito entero de la aplicacion.
   Hoy no hay reintento si el POST falla (DT-008) ni registro de que ocurrio (DT-010).
2. **Persistir la hora de fin en cada transicion.** Si se pierde, la jornada en curso desaparece.
3. **Que cerrar la ventana no mate el proceso.** Si muere, nadie cierra la jornada.

---

## Planificadas (ninguna empezada)

De `06_Documentacion/CONTEXTO.md` seccion 9. Ordenadas por lo que aportan frente a lo que cuestan:

**Cerca del codigo, utiles ya**

- **Icono propio** (`.ico` con el anillo) en ventana y bandeja. Hoy usa `SystemIcons.Application`,
  lo que deja el boton anclado sin identidad — y el boton anclado es justo el punto de la app.
- **Icono de bandeja dinamico** con el anillo dibujado en 32×32. Hay una implementacion funcional
  en la funcion `Nuevo-Icono` del script `mi-jornada.ps1`, portable casi tal cual.
- **Duracion configurable** desde la interfaz, no solo por parametro. Jornada de verano contra
  jornada de invierno es el caso real.
- **Ajustes persistidos**: duracion, arranque minimizado, fichar al iniciar sesion de Windows.

**Funcionalidad**

- **Fichaje automatico** al desbloquear el equipo por la manana, escuchando
  `SystemEvents.SessionSwitch`. Es lo que convierte la aplicacion en algo que no hay que
  acordarse de usar.
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
