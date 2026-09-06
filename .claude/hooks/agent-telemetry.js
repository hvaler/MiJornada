#!/usr/bin/env node
// agent-telemetry.js - telemetria local + batch upload al Hub Ovillo v2
// Evento: PostToolUse[Task]
// Version: 1.0.0-node (port de agent-telemetry.ps1 - ADR-035 F2 -, ADR-F006)
//
// Comportamiento:
//   1. Append-only local: _hilo/agent-telemetry.jsonl (siempre, sin requerir red)
//   2. Batch upload diario al Hub SI:
//      - ecosystem.config -> hub.enabled == true Y hub.url no vacia (FASE 2; antes host hardcodeado)
//      - mcpSync.habilitado == true (ESTADO_PROYECTO.json)
//      - _hilo/.mcp-credentials.json existe con projectId+apiKey
//      - telemetryOptIn == true en .mcp-credentials.json (per-DEV, ADR-038; el server
//        tambien lo re-valida)
//      - Ultimo upload > 24h (cooldown, estado en _hilo/.mcp-telemetry-state.json)
//   3. Best-effort SIEMPRE: si la red falla, NO bloquea (exit 0); reintenta manana
//   4. Header de auth configurable: hub.apiKeyHeader (default X-Hub-Api-Key)
//
// Output: stdout va a contexto Claude (silent si todo OK). Exit 0 siempre.
// Nota TLS: Node negocia TLS 1.2+ por defecto (equivalente al fix h9/R2 de PS 5.1).

'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const h = require(path.join(__dirname, 'lib', 'helpers'));
const configLib = require(path.join(__dirname, 'lib', 'config'));

async function tryBatchUpload(projectRoot, duranDir, jsonlPath, credsPath, statePath) {
  // Gate de organizacion (FASE 2): sin Hub habilitado/URL -> silencio total
  const cfg = configLib.load(projectRoot);
  const hubEnabled = configLib.get(cfg, 'hub.enabled', false) === true;
  const hubUrl = String(configLib.get(cfg, 'hub.url', '') || '').trim().replace(/\/+$/, '');
  if (!hubEnabled || !hubUrl) return;
  const apiKeyHeader =
    String(configLib.get(cfg, 'hub.apiKeyHeader', 'X-Hub-Api-Key') || '').trim() || 'X-Hub-Api-Key';

  // Pre-checks rapidos: credentials + estado proyecto
  if (!fs.existsSync(credsPath)) return;
  const estadoPath = path.join(duranDir, 'ESTADO_PROYECTO.json');
  if (!fs.existsSync(estadoPath)) return;

  const estado = h.readJsonSafe(estadoPath);
  if (!estado || !estado.mcpSync || !estado.mcpSync.habilitado) return;

  const creds = h.readJsonSafe(credsPath);
  if (!creds || !creds.projectId || !creds.apiKey) return;

  // Opt-in per-dev (ADR-038): solo subir si el dev dio consentimiento explicito
  if (creds.telemetryOptIn !== true) return;

  // Cooldown: 24h desde ultimo upload (estado en .mcp-telemetry-state.json)
  const state = h.readJsonSafe(statePath);
  let lastUpload = null;
  if (state && state.lastUpload) {
    const d = new Date(state.lastUpload);
    if (!Number.isNaN(d.getTime())) lastUpload = d;
  }
  if (lastUpload && (Date.now() - lastUpload.getTime()) / 3600000 < 24) return;

  // Recolectar eventos NO subidos: leer offset desde state
  let startOffset = 0;
  if (lastUpload && state && state.bytesRead) {
    startOffset = Number(state.bytesRead) || 0;
  }

  let fileLen = 0;
  try {
    fileLen = fs.statSync(jsonlPath).size;
  } catch {
    return;
  }
  if (!fileLen || fileLen <= startOffset) return;

  // Leer eventos nuevos
  const pending = [];
  try {
    const fd = fs.openSync(jsonlPath, 'r');
    try {
      const buf = Buffer.alloc(fileLen - startOffset);
      const bytesRead = fs.readSync(fd, buf, 0, buf.length, startOffset);
      const text = buf.subarray(0, bytesRead).toString('utf8');
      for (const l of text.split(/\r?\n/)) {
        if (!l.trim()) continue;
        try {
          const e = JSON.parse(l);
          pending.push({
            ts: e.ts,
            agent: e.subagent_type,
            success: Boolean(e.success),
            description: e.description,
          });
        } catch { /* linea corrupta - skip */ }
      }
    } finally {
      fs.closeSync(fd);
    }
  } catch {
    return;
  }

  if (pending.length === 0) return;

  // Upload en lotes de 100. URL: mcpSync.serverUrl del proyecto gana sobre hub.url (precedencia).
  const serverUrl = String(estado.mcpSync.serverUrl || hubUrl).trim().replace(/\/+$/, '');
  const headers = { [apiKeyHeader]: creds.apiKey, 'Content-Type': 'application/json' };
  let uploadOk = true;

  for (let i = 0; i < pending.length; i += 100) {
    const slice = pending.slice(i, i + 100);
    const body = JSON.stringify({ projectId: creds.projectId, events: slice });
    try {
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(), 10000);
      try {
        const resp = await fetch(`${serverUrl}/v2/telemetry`, {
          method: 'POST',
          headers,
          body,
          signal: ctrl.signal,
        });
        if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      } finally {
        clearTimeout(timer);
      }
    } catch {
      uploadOk = false;
      break;
    }
  }

  if (uploadOk) {
    // Actualizar estado: ultimo upload + bytes leidos (atomico, UTF-8 sin BOM - FB-004/FB-007)
    const newState = {
      lastUpload: new Date().toISOString(),
      bytesRead: fileLen,
      uploaded: pending.length,
    };
    h.writeHiloJson(newState, statePath, { compress: true });
  }
}

async function main() {
  // Leer evento PostToolUse desde stdin
  let raw = '';
  try {
    if (!process.stdin.isTTY) raw = fs.readFileSync(0, 'utf8');
  } catch {
    return 0;
  }
  if (!raw || !raw.trim()) return 0;

  let evt;
  try {
    evt = JSON.parse(raw);
  } catch {
    return 0;
  }

  // Solo procesar Task tool
  if (!evt || evt.tool_name !== 'Task') return 0;

  // Resolver paths
  const projectRoot = process.env.CLAUDE_PROJECT_DIR || path.resolve(__dirname, '..', '..');
  const duranDir = path.join(projectRoot, '_hilo');
  if (!fs.existsSync(duranDir)) return 0;

  const jsonlPath = path.join(duranDir, 'agent-telemetry.jsonl');
  const credsPath = path.join(duranDir, '.mcp-credentials.json');
  const statePath = path.join(duranDir, '.mcp-telemetry-state.json');

  // Construir entry local
  const ti = evt.tool_input && typeof evt.tool_input === 'object' ? evt.tool_input : {};
  const tr = evt.tool_response && typeof evt.tool_response === 'object' ? evt.tool_response : {};
  const entry = {
    ts: new Date().toISOString(),
    tool: 'Task',
    subagent_type: ti.subagent_type ? String(ti.subagent_type) : 'general-purpose',
    description: ti.description ? String(ti.description) : null,
    model: ti.model ? String(ti.model) : null,
    success: tr.is_error !== null && tr.is_error !== undefined ? !tr.is_error : true,
    session_id: evt.session_id ? String(evt.session_id) : null,
  };

  // 1. APPEND-ONLY LOCAL (siempre; UTF-8 sin BOM - default de Node)
  try {
    fs.appendFileSync(jsonlPath, JSON.stringify(entry) + os.EOL, 'utf8');
  } catch { /* best-effort */ }

  // 2. BATCH UPLOAD AL HUB (best-effort, una vez al dia)
  try {
    await tryBatchUpload(projectRoot, duranDir, jsonlPath, credsPath, statePath);
  } catch { /* best-effort: nunca bloquear */ }

  return 0;
}

main()
  .then((code) => process.exit(code ?? 0))
  .catch((e) => {
    console.error(`[agent-telemetry] error no fatal: ${e.message}`);
    process.exit(0);
  });
