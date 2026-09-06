# /mcp-forget

Desregistra este proyecto del MCP Server Ovillo y borra TODOS sus datos del servidor.

> **RGPD Art. 17 (right to be forgotten)** - Accion inmediata e irreversible.

---

## Cuando ejecutar

- El usuario quiere ejercer derecho de supresion RGPD
- Se va a cerrar el proyecto definitivamente
- Se quiere re-registrar con configuracion distinta (forget + register)
- Sospecha de compromiso de la apiKey (rotacion)

---

## Flujo

### Paso 1: Confirmacion EXPLICITA

Mostrar al usuario:

```
================================================================
  ATENCION: Right to be forgotten (RGPD Art. 17)
================================================================

Vas a BORRAR del MCP Server Ovillo:
  - Registro del proyecto (mcp.Proyectos)
  - TODOS los heartbeats historicos (mcp.Heartbeats)
  - TODAS las invocaciones de agents (mcp.AgentInvocations)
  - Snapshots Hilo sincronizados (mcp.HiloSnapshots)

Esta accion es INMEDIATA e IRREVERSIBLE en el servidor.
NO afecta a tus datos LOCALES (_hilo/agent-telemetry.jsonl se mantiene).

Tras forget:
  - El proyecto desaparece del dashboard
  - Se libera el nombre+owner (puedes re-registrar con /mcp-register)
  - _hilo/.mcp-credentials.json local se borra
  - ESTADO_PROYECTO.json.mcpSync se desactiva

¿Confirmas el borrado? Escribe exactamente: FORGET
================================================================
```

Si el usuario NO escribe `FORGET` literalmente: abortar sin tocar nada.

### Paso 2: Leer credenciales locales

```powershell
$credsPath = '_hilo/.mcp-credentials.json'
if (-not (Test-Path $credsPath)) {
    Write-Output "Este proyecto no esta registrado (sin credenciales locales)."
    Write-Output "Si crees que SI esta en el servidor pero perdiste la apiKey,"
    Write-Output "contacta soporte@example.com indicando nombre+owner."
    return
}
$creds = Get-Content $credsPath -Raw | ConvertFrom-Json
```

### Paso 3: POST /v2/forget

```powershell
$serverUrl = $creds.serverUrl  # o leer de ESTADO_PROYECTO.json.mcpSync.serverUrl
$body = @{ projectId = $creds.projectId } | ConvertTo-Json
Invoke-RestMethod -Uri "$serverUrl/v2/forget" -Method Post `
    -Headers @{ 'X-Hub-Api-Key' = $creds.apiKey } `
    -Body $body -ContentType 'application/json'
```

### Paso 4: Limpiar artefactos locales

```powershell
Remove-Item $credsPath -Force                              # credenciales
Remove-Item '_hilo/.mcp-telemetry-state.json' -Force      # estado upload telemetria
# NO borrar _hilo/agent-telemetry.jsonl (es del usuario, no del servidor)
```

### Paso 5: Actualizar ESTADO_PROYECTO.json

```json
"mcpSync": {
  "habilitado": false,
  "serverUrl": "https://hub.example.org",
  "projectId": null,
  "telemetryOptIn": false,
  "ultimaSync": null
}
```

### Paso 6: Resumen

```
================================================================
  Forget completado (RGPD Art. 17)
================================================================

Proyecto borrado del servidor Ovillo:  {projectId}
Credenciales locales eliminadas:        SI
ESTADO_PROYECTO.json.mcpSync:            desactivado

Datos LOCALES preservados:
  - _hilo/agent-telemetry.jsonl  (telemetria local)
  - Todo lo demas

Para re-registrar este proyecto en el futuro: /mcp-register
Soporte: soporte@example.com
```

---

## Si falla la llamada al servidor

```
⚠️ El servidor no respondio (red caida, etc).
   El registro PUEDE seguir en el servidor.

Opciones:
  [1] Reintentar
  [2] Borrar credenciales locales de todos modos (el proyecto seguira
      registrado en el servidor pero ya no podras gestionarlo desde aqui)
  [3] Cancelar
```

---

## Anti-patrones

- NUNCA borrar sin confirmacion FORGET literal
- NUNCA borrar `_hilo/agent-telemetry.jsonl` (es del usuario, no del servidor)
- NUNCA exportar/loggear la apiKey antes de borrarla
