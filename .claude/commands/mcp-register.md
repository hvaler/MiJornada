# /mcp-register

Registra el proyecto y al dev en el **Hub del ecosistema** (opt-in explicito, ADR-F000) y
gestiona el opt-in de **telemetria de agents**.

> ⚠️ Requiere `hub.enabled: true` + `hub.url` en `ecosystem.config.json` (sin Hub configurado:
> avisar y salir). El registro es SIEMPRE opt-in: este comando es el punto de entrada — crea el
> registro inicial, une a un dev nuevo via `/v2/join` si `.mcp-project.json` ya existe, y
> pregunta la telemetria. El instalador solo registra automaticamente si la organizacion fijo
> `hub.registerOnInstall: true`.

> **Privacidad**: la telemetria se envia SOLO si el usuario otorga opt-in explicito (privacy notice).
> Privacy notice completo: <distribution.baseUrl>/docs/privacy.html

---

## ¿Que habilita el registro (sin telemetria)?

- ✅ Proyecto registrado en el hub con identidad per-dev (`git config user.email`)
- ✅ `/mcp-sync` sincroniza decisiones, lecciones, nugets, evolutivos, equipo, branching
- ✅ Dashboard tab "Equipo" muestra el dev como miembro del proyecto
- ✅ Heartbeat semanal (proyecto vivo)

## ¿Que añade el opt-in de telemetria?

- 🔔 Hook `agent-telemetry.js` envia invocaciones (qué agent invocas cuándo) al hub
- 🔔 Dashboard tab "Operativo" muestra ranking de uso de agents per-dev
- 🔔 Deteccion de RETIRE candidates (agents sin uso en 30d ventana)

---

## Cuando ejecutar

- Primer registro del proyecto en el Hub (o unirse como 2º dev a un proyecto ya registrado)
- Quieres activar telemetria de agents (opt-in con privacy notice)
- Tras ejecutar `/mcp-forget` previamente y querer re-registrar
- Cambiar `telemetryOptIn` de `false` → `true` (o revocar de `true` → `false`)

NO usar para:
- Sincronizar contenido del proyecto (`/mcp-sync` se encarga, no requiere re-ejecutar esto)

---

## Flujo

### Paso 0: Detectar registro previo

Antes de mostrar el privacy notice, comprobar si el proyecto ya esta registrado (por una
ejecucion anterior de este comando, por el instalador con `hub.registerOnInstall=true`, o —
en proyectos migrados del ecosistema origen — por un silent register legacy).

```powershell
$credsPath = '_hilo/.mcp-credentials.json'
if (Test-Path $credsPath) {
    $creds = Get-Content $credsPath -Raw | ConvertFrom-Json
    if ($creds.silentRegister -and -not $creds.telemetryOptIn) {
        # Ya registrado en hub pero sin telemetria. Solo pedir opt-in y llamar a /v2/opt-in
        # → saltar a "Paso 1.bis: Upgrade silent → opt-in"
    } elseif ($creds.telemetryOptIn) {
        Write-Host "Proyecto ya registrado con telemetria activada. Nada que hacer."
        return
    }
}
```

### Paso 1.bis: Upgrade silent -> opt-in

Si el proyecto ya esta silently-registered, mostrar el privacy notice (Paso 1 abajo)
y luego SOLO llamar al endpoint de upgrade en lugar de crear un proyecto nuevo:

```powershell
$body = @{ projectId = $creds.projectId; telemetryOptIn = $true } | ConvertTo-Json
$resp = Invoke-RestMethod -Uri "$($creds.serverUrl)/v2/opt-in" -Method Post `
    -Headers @{ 'X-Hub-Api-Key' = $creds.apiKey } `
    -Body $body -ContentType 'application/json'
# Actualizar credentials locales: ya no es silent y telemetryOptIn=true
$creds.telemetryOptIn = $true
$creds.silentRegister = $false
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($credsPath, ($creds | ConvertTo-Json -Depth 4), $utf8)
# Activar sync en ESTADO_PROYECTO.json
# ... actualizar mcpSync.habilitado=true
```

Saltar el resto del flujo (no se hace POST /v2/register cuando ya hay silent register).

### Paso 1: Mostrar privacy notice y pedir opt-in

Mostrar al usuario:

```
================================================================
  REGISTRO EN MCP SERVER Ovillo - Privacidad
================================================================

Vas a registrar este proyecto en https://hub.example.org

Datos que se enviaran (privacy.html):
  - Nombre del proyecto
  - Alias git del owner (NO email)
  - Version Ovillo y stack (.NET version)
  - Heartbeat semanal con N agents disponibles
  - Telemetria de agents invocados (solo si opt-in):
      timestamp + nombre del agent + exito/fallo
      hash SHA-256 del prompt (el prompt en CLARO no se envia)

Lo que NUNCA se envia:
  - Contenido del codigo
  - Connection strings, secrets, tokens
  - Datos de negocio o de usuarios finales
  - Emails (solo alias git)

Retencion: 90 dias eventos, 12 meses heartbeats.
Right to be forgotten: ejecuta /mcp-forget para borrar TODO el rastro.

================================================================
```

Preguntar:

```
[1] Registrar SIN telemetria de agents (solo heartbeat + inventario)
[2] Registrar CON telemetria de agents (opt-in completo)
[3] Cancelar

Eleccion (1-3):
```

### Paso 2: Lectura de datos del proyecto

De `_hilo/ESTADO_PROYECTO.json`:
- `nombreProyecto`: campo `proyecto.nombre` (si esta sin completar, pedir al usuario)
- `versionStic`: campo `ecosistema.version`
- `ownerAlias`: usuario git (`git config user.name` o usuario actual del SO)
- `stack`: detectar de `.csproj` o `package.json` (ej: ".NET 10 + EF Core 10")

Confirmar al usuario antes de enviar.

### Paso 3: POST /v2/register

```powershell
$serverUrl = '<hub.url del ecosystem.config.json>'   # ej. https://hub.example.org
$body = @{
    nombreProyecto = $nombreProyecto
    versionStic    = $versionStic
    ownerAlias     = $ownerAlias
    stack          = $stack
    telemetryOptIn = $optIn  # true/false segun eleccion paso 1
} | ConvertTo-Json

$resp = Invoke-RestMethod -Uri "$serverUrl/v2/register" -Method Post `
    -Body $body -ContentType 'application/json'
```

Posibles respuestas:
- **201 Created** -> capturar `projectId` y `apiKey`
- **409 Conflict** -> proyecto ya registrado. Pedir confirmacion antes de hacer `/mcp-forget` primero

### Paso 4: Guardar credenciales locales

Crear `_hilo/.mcp-credentials.json` (gitignored automaticamente — anadir si no esta):

```json
{
  "projectId": "uuid",
  "apiKey": "sk_proj_...",
  "registeredAt": "2026-05-19T...",
  "serverUrl": "https://hub.example.org"
}
```

**IMPORTANTE**: anadir `_hilo/.mcp-credentials.json` a `.gitignore` si no esta.

### Paso 5: Actualizar ESTADO_PROYECTO.json.mcpSync

```json
"mcpSync": {
  "habilitado": true,
  "serverUrl": "https://hub.example.org",
  "projectId": "uuid",
  "telemetryOptIn": true/false,
  "ultimaSync": null,
  "categorias": {
    "funcionalidades": true,
    "decisiones": true,
    "dependencias": true,
    "historial": true,
    "lecciones": true,
    "contexto_tecnico": true,
    "seguridad": false
  }
}
```

### Paso 6: Hacer primer heartbeat (validacion)

```powershell
$hb = @{
    projectId        = $resp.projectId
    versionStic      = $versionStic
    agentsDisponibles = 18
    comandosDisponibles = 45
} | ConvertTo-Json
Invoke-RestMethod -Uri "$serverUrl/v2/heartbeat" -Method Post `
    -Headers @{ 'X-Hub-Api-Key' = $resp.apiKey } `
    -Body $hb -ContentType 'application/json'
```

### Paso 7: Mostrar resumen

```
================================================================
  Registro completado
================================================================

Project ID:     {projectId}
Telemetria:     {SI/NO} (opt-in)
Servidor:       https://hub.example.org
Dashboard:      <distribution.baseUrl>/docs/dashboard/

Credenciales guardadas en _hilo/.mcp-credentials.json (gitignored)

Proximo paso opcional:
  /mcp-sync   - sincronizar documentacion Hilo al hub
  /mcp-forget - desregistrar y borrar todos los datos (RGPD)
```

---

## Mensajes de error comunes

| HTTP | Causa | Mensaje al usuario |
|---|---|---|
| 409 | Conflict - ya registrado | "Este proyecto ya esta registrado. Usar /mcp-forget primero si quieres re-registrar" |
| 400 | Validacion | "Faltan campos requeridos. Comprueba que ESTADO_PROYECTO.json tiene proyecto.nombre" |
| 5xx | Servidor caido | "El MCP Server no responde. Reintentar mas tarde - tus credenciales NO se han guardado" |
| timeout | Red del Hub no disponible | "Sin conexion al hub.url configurado. Comprueba red/VPN" |

---

## Anti-patrones

- NO commitear `_hilo/.mcp-credentials.json` (es secret per-proyecto)
- NO mostrar la apiKey en stdout despues del registro inicial (solo guardarla)
- NO permitir re-registrar sin /mcp-forget previo (conflict 409 es correcto)
- NO enviar telemetria si telemetryOptIn = false (el server lo rechaza con 403)
