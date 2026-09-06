# ESTADO_PROYECTO.schema.md — Documentacion de campos

> **Proposito**: documentacion extendida, ejemplos y opciones de `_hilo/ESTADO_PROYECTO.json`.
> Este archivo **NO se importa en CLAUDE.md** (no consume contexto en cada sesion). Claude lo
> consulta bajo demanda cuando necesita rellenar o interpretar una seccion del JSON
> (tipicamente durante `/onboarding`, `/cicd-init`, `/devops-sync` o `/analizar`).
>
> Regla de mantenimiento: si anades un campo nuevo al JSON, documentalo AQUI (no inline en el
> JSON) y deja como mucho una linea `_doc` de puntero. Origen: dieta de contexto AUD-008.

---

## equipo

Miembros del equipo. Configurar manualmente o via `/onboarding` (paso `equipo`).

| Campo | Regla |
|---|---|
| `usuario` | DEBE coincidir con el usuario Git (`git config user.name` o alias corto). Es la clave de matching para `/tomar`, `/equipo`, `asignadoA`. |
| `nombre` | DEBE coincidir **EXACTAMENTE** con el displayName de Active Directory (no email, no alias). Se usa como `System.AssignedTo` en Azure DevOps on-premises — TFS **no resuelve** email/UPN (HTTP 400 `unknown identity`). Verificar con: `curl --negotiate -u : '{URL}/_apis/identities?searchFilter=General&filterValue={alias}&api-version=6.0'` |
| `email` | Email corporativo de la organizacion. |
| `roles` | **Array** de roles (un miembro puede ser JP y developer a la vez). Si un JSON legacy tiene `rol` (string), se trata como array de un elemento. `/devops-sync` considera developer a quien tenga `desarrollador` en `roles`. Valores: `jefe_proyecto`, `desarrollador`, `analista`, `tester`, `arquitecto`, `lider_tecnico`. |
| `git_author_name` | Opcional. Solo si el nombre que figura en los commits (`git log --format=%an`) difiere de `nombre`. Ej.: `git config user.name='Raquel A.'` pero AD dice `Raquel Agudelo Villarrubia`. Si no se especifica, se usa `nombre` para el matching en git log. |

```json
"miembros": [
  {
    "usuario": "jgarcia",
    "nombre": "Juan García López",
    "email": "jgarcia@example.com",
    "roles": ["desarrollador"],
    "git_author_name": null
  },
  {
    "usuario": "mmartinez",
    "nombre": "Maria Martinez Ruiz",
    "email": "mmartinez@example.com",
    "roles": ["jefe_proyecto", "desarrollador"],
    "git_author_name": "Maria Martinez"
  }
]
```

---

## configuracion

### nivelIntegracionGit

| Valor | Comportamiento de Claude |
|---|---|
| `basico` | Solo sugiere comandos Git, no ejecuta nada |
| `medio` | Pregunta confirmacion antes de ejecutar comandos Git |
| `alto` | Ejecuta comandos Git automaticamente (excepto destructivos) |

### branching

Estrategia de ramificacion (v3.7.0). Se configura en `/onboarding` y la leen `/commit`,
`/git-sync`, `/liberar`, la regla `devops-awareness` y `/cicd-init` (R21 trigger + R24
branch-gated). Los arrays `_estrategias_disponibles`, `_mergeStrategies` y
`_convencionRamas_opciones` **permanecen en el JSON** porque los validan programaticamente
`/branching`, `/analizar` y `/actualizar` — no moverlos aqui.

- `tiposTarea`: solo aplica con nomenclatura temporal o combinada (que contenga `{tipo}`);
  `null` = no aplica. Ejemplo:

```json
"tiposTarea": {
  "DT": "Deuda técnica",
  "HV": "Evolutivo",
  "BUG": "Corrección",
  "REF": "Refactoring"
}
```

---

## soluciones

Soporte multi-solucion (v2.8.7). Se auto-detecta al ejecutar `/onboarding` o
`integracion-vs.ps1`. Estructura de cada entrada de `soluciones[]`:

```json
{
  "nombre": "MyCompany.MiApp.sln",
  "ruta": "03_Desarrollo/MyCompany.MiApp.sln",
  "framework": ".NET 10",
  "descripcion": "API principal",
  "esActiva": true
}
```

Notas:
- Si `multiSolucion=true`, `/test` y `/analizar` preguntaran que solucion usar.
- Para `/onboarding` se procesan TODAS las soluciones automaticamente.
- `solucionActiva` guarda la ultima solucion seleccionada para comandos.
- Usar `integracion-vs.ps1 -All` para aplicar a todas sin preguntar.

---

## jira

Integracion con Jira. Se auto-configura al detectar un ticket Jira por primera vez.

- `url` ejemplo: `https://miorg.atlassian.net` · `proyectoKey` ejemplo: `PROJ`.
- Cuando `habilitado=true`, evolutivos `PROYECTOKEY-XXX` muestran recordatorios de Jira.
  Evolutivos `EV-XX` o texto libre NO se vinculan a Jira.
- Fase 0: solo recordatorios manuales. Fase 2: automatizacion con MCP/API.

---

## acceso_bd

Claude puede conectarse a BD de desarrollo con enmascaramiento dinamico de datos personales.

- `connection_string_key`: nombre de la variable/secreto con la cadena de conexion (nunca la cadena en si).
- `usuario_claude`: usuario SQL especifico para Claude con enmascaramiento dinamico aplicado.
- `permisos`: por defecto solo `select`. Ampliar requiere decision explicita del equipo.

---

## infraestructura

Topologia de despliegue del proyecto. Se configura en `/onboarding` Fase 5b.
Desde v3.15.0 (ADR-048): cada entorno tiene servidor de **Aplicaciones** y de **Servicios**;
el routing se decide por `tipo`+`publico` del entrypoint (R25).

### entornos[] — ejemplo completo

```json
"entornos": [
  {
    "nombre": "Dev", "tipo": "desarrollo",
    "servidor_app": "dev01", "servidor_servicios": "svc01",
    "url_app": "dev.example.org", "url_servicios": "dev-svc.example.org",
    "deploy_automatico": true, "balanceo": false
  },
  {
    "nombre": "Pre", "tipo": "staging",
    "servidor_app": "pre.example.org", "servidor_servicios": "pre-svc.example.org",
    "url_app": "pre.example.org", "url_servicios": "pre-svc.example.org",
    "deploy_automatico": false, "balanceo": false
  },
  {
    "nombre": "Pro", "tipo": "produccion",
    "servidores_app": ["APP01.example.org", "APP02.example.org"],
    "servidores_servicios": ["SVCNODE01.example.org", "SVCNODE02.example.org"],
    "url_app": "www.example.org", "url_servicios": "svc.example.org",
    "deploy_automatico": false, "balanceo": true, "estrategia_deploy": "rolling"
  }
]
```

Nota Pro/servicios: SVCNODE02 apagado por ahora — el deploy va solo al nodo online; se declara
para cuando se encienda.

### cicd

- `plataforma`: `azure-pipelines` | `github-actions` | `manual` | `null`.
- **R25 (v3.15.0)**: un pipeline por **ENTRYPOINT** de la solucion (Web/API con CD; Console
  con CD por tarea programada desde v3.16.0/FB-B). `/cicd-init` rellena `pipelines[]`;
  `/cicd-deploy` y `/cicd-status` lo leen.

#### pipelines[] — campos por entrada

| Campo | Significado |
|---|---|
| `entrypoint` | Proyecto entrypoint (ej. `MyCompany.X.Api`) |
| `slug` | Sufijo corto del YAML/definicion (`api`, `web`, `worker`) |
| `tipo` | `web` \| `api` \| `console` |
| `publico` | Solo APIs: `true` → servidores de Aplicaciones (default `false` → Servicios) |
| `serverType` | `app` = Aplicaciones (web / API publica) · `svc` = Servicios (API privada) · `batch` = Console/Worker (sin tipo fijo; DeployTarget derivado del pool real, FB-002). Derivado de `tipo`+`publico` (R25); determina `DeployTarget=<env>-<serverType>` |
| `yaml` | Nombre del fichero pipeline (`azure-pipelines.<slug>.yml`) |
| `pipelineId` | ID de la definicion TFS |
| `fase` | Fase de adopcion CI/CD (0/1/2) |
| `stack` | `dotnet` \| `netfx` \| `spa` \| `console` |
| `deployConfirm` | Por entorno: `true` = `/cicd-deploy` pide confirmacion (default solo `pro`) |
| `ultimoBuildStatus` | Cache del ultimo estado de build |

Campos adicionales **solo Console/Worker** (CD via Tarea Programada, v3.16.0/FB-B):
`mecanismo` (`tarea-programada` | `windows-service`), `taskName`, `taskScheduleArgs`
(ej. `/SC HOURLY`), `taskRunAccount` (`NT AUTHORITY\SYSTEM`), `deployFolder`, `consoleExe`.

#### Ejemplos

```json
{ "entrypoint": "MyCompany.X.Api", "slug": "api", "tipo": "api", "publico": false,
  "serverType": "svc", "yaml": "azure-pipelines.api.yml", "pipelineId": 0, "fase": 2,
  "stack": "dotnet", "deployConfirm": { "dev": false, "pre": false, "pro": true },
  "ultimoBuildStatus": null }
```

```json
{ "entrypoint": "MyCompany.X.Worker", "slug": "worker", "tipo": "console", "publico": false,
  "serverType": "batch", "yaml": "azure-pipelines.worker.yml", "pipelineId": 0, "fase": 2,
  "stack": "console", "mecanismo": "tarea-programada", "taskName": "MyCompany.X.Sync",
  "taskScheduleArgs": "/SC HOURLY", "taskRunAccount": "NT AUTHORITY\\SYSTEM",
  "deployFolder": "D:\\Apps\\MyCompany.X", "consoleExe": "MyCompany.X.Worker.exe",
  "deployConfirm": { "dev": false, "pre": false, "pro": true }, "ultimoBuildStatus": null }
```

### aprobadores

Quien aprueba deploy a cada entorno (arrays de usuarios). Configurable por proyecto.

### azureDevOps (opcional, creado por /devops-sync)

Ver la regla `.claude/rules/devops-awareness.md` — estructura completa con `url`, `teamName`,
`epicId`, `features{}`, `proceso` (`Scrum`|`Basic`|`Agile`|`CMMI`), `autoSync`, `pendingOps`.

---

## criticidad · calendario

- `criticidad.sla` ejemplo: `99.9%` · `horario_mantenimiento` ejemplo: `Sabados 02:00-06:00`.
- `dependencias_inter_proyecto` ejemplo: `["Proyecto X depende de nuestra API", "Consumimos datos de Proyecto Y"]`.
- `calendario.freeze_periods` ejemplo: `"2026-03-01 a 2026-03-15 (cierre fiscal)"`.

---

## mcpSync

Sincronizacion con el Hub Ovillo (ADR-037 multi-dev + ADR-038 identidad por email).

**Modelo de identidad — tres archivos, NO mezclar** (detalle en `.claude/rules/mcp-config.md`):

| Archivo | Scope | Commiteable | Contenido |
|---|---|---|---|
| `_hilo/.mcp-project.json` | per-PROYECTO | ✅ | `projectId`, `serverUrl` (para que otros devs se unan via `/v2/join`) |
| `ESTADO_PROYECTO.json.mcpSync` | per-PROYECTO | ✅ | `habilitado`, `categorias`, `projectId`, `ultimaSync` |
| `_hilo/.mcp-credentials.json` | per-DEV | ❌ gitignored | `apiKey`, `devAlias`, `devEmail`, `telemetryOptIn` |

Reglas:
- `habilitado=true` lo activa `arranque.ps1` automaticamente (`irm | iex`). Si esta en `false`, `/mcp-sync` rechaza.
- `projectId` se asigna en el silent-register de `arranque.ps1` y se commitea.
- Cada categoria es un toggle independiente; si el Hub anade categorias nuevas, el script las activa por defecto (forward-compat). `feedbackEcosistema` (v3.13.0, ADR-044) sube `_hilo/FEEDBACK_ECOSISTEMA.md`.
- **`telemetryOptIn` NO existe aqui** — es per-dev; si aparece (residual <v3.9.0), eliminarlo y usar `/mcp-register`.

---

## evolutivos

Gestion de evolutivos con soporte para trabajo colaborativo. Estructura de cada evolutivo
(en `pendientes[]`, `enProgreso[]` o `completados[]`):

```json
{
  "codigo": "EV-XX",
  "titulo": "Descripción breve",
  "estado": "pendiente|en_progreso|pausado|completado|cancelado",
  "asignadoA": "usuario_git o null si no asignado",
  "rama": "feature/EV-XX o null",
  "prioridad": "alta|media|baja",
  "fechaCreacion": "YYYY-MM-DD",
  "fechaInicio": "YYYY-MM-DD o null",
  "fechaEstimada": "YYYY-MM-DD o null",
  "fechaCompletado": "YYYY-MM-DD o null",
  "creadoPor": "usuario_git",
  "notas": "Notas adicionales"
}
```

`evolutivoActivo` (raiz del JSON) = codigo del evolutivo actualmente en trabajo; se actualiza
con `/continuar`.

---

## dominiosExternos (opcional)

Mapeo de integraciones externas → Context7 (regla `domain-api-docs.md`). Ver esa regla para
la estructura (`nombre`, `carpetaPattern`, `context7Library`, `anchorTopics`, `skipPaths`).

---

*Schema de ESTADO_PROYECTO.json — Ovillo. Extraido del JSON en v3.18.0 (dieta de contexto, AUD-008).*
