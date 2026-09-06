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

#### Contexto

El flujo interactivo normal de MSAL falla en este tenant con
`Error response came from MDM terms of use page`, por las politicas de acceso condicional en
equipos no gestionados.

#### Decision

Usar `AcquireTokenWithDeviceCode`. **No es un capricho ni una preferencia estetica**: es el unico
que se ha comprobado que funciona aqui.

#### Consecuencias

- Funciona en equipos no gestionados.
- La primera vez hay que copiar un codigo y pegarlo en el navegador. Despues el token se cachea
  con DPAPI y no vuelve a pedirse hasta que caduque el refresh.

> **No cambiar a interactivo "para mejorar la experiencia"**: ya se probo y no funciona.

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

*Completado por `/onboarding` el 2026-09-06 a partir de `06_Documentacion/CONTEXTO.md` seccion 10
y `06_Documentacion/mi-jornada-traspaso.md`*
