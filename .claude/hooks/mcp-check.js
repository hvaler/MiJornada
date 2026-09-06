#!/usr/bin/env node
// mcp-check.js - verifica MCPs user-scope esperados por Ovillo
// Evento: SessionStart
// Version: 1.0.0-node (port de mcp-check.ps1, ADR-F006)
//
// Origen: Gap 3 ANALISIS_INTERNO_PRIORIZACION v3.9.0 - MCPs user-scope se pierden al
// cambiar de maquina/formatear. Esta verificacion al inicio recuerda al dev re-instalar.
// Output: stdout va a contexto de Claude (NO terminal). Salida silenciosa si todo OK.
//
// Parametrizacion FASE 2 (ADR-F001): la URL esperada de context7 sale de
// ecosystem.config -> mcp.context7Url (vacio -> https://mcp.context7.com/mcp).

'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');
const h = require(path.join(__dirname, 'lib', 'helpers'));
const configLib = require(path.join(__dirname, 'lib', 'config'));

function main() {
  const projectDir = h.projectDir();

  // Solo correr la verificacion 1 vez por dia (cache local) - evita ruido
  const cacheDir = path.join(projectDir, '_hilo');
  const cacheFile = path.join(cacheDir, '.mcp-check.json');

  const cache = h.readJsonSafe(cacheFile);
  if (cache && cache.ultimaVerificacion) {
    const lastCheck = new Date(cache.ultimaVerificacion);
    if (!Number.isNaN(lastCheck.getTime()) && Date.now() < lastCheck.getTime() + 24 * 3600000) {
      // Cache fresca - no re-verificar
      return 0;
    }
  }

  const cfg = configLib.load(projectDir);
  const context7Url =
    String(configLib.get(cfg, 'mcp.context7Url', '') || '').trim() || 'https://mcp.context7.com/mcp';

  // MCPs esperados (mismo set que instala el instalador del ecosistema)
  const mcpsEsperados = [
    {
      nombre: 'context7',
      comando: `claude mcp add --transport http --scope user context7 ${context7Url}`,
      razon: 'Documentacion actualizada de librerias .NET/Azure/NuGet (uso diario)',
    },
  ];

  // Localizar config MCP user-scope (mismos candidatos que el .ps1)
  const home = process.env.USERPROFILE || os.homedir();
  const configCandidates = [
    path.join(home, '.claude', '.claude.json'),
    path.join(home, '.claude', 'settings.json'),
  ];
  if (process.env.APPDATA) {
    configCandidates.push(path.join(process.env.APPDATA, 'claude', '.claude.json'));
  }

  let configEncontrada = null;
  for (const candidato of configCandidates) {
    if (fs.existsSync(candidato)) {
      configEncontrada = candidato;
      break;
    }
  }

  let mcpsActuales = [];
  if (configEncontrada) {
    const userCfg = h.readJsonSafe(configEncontrada);
    if (userCfg && userCfg.mcpServers && typeof userCfg.mcpServers === 'object') {
      mcpsActuales = Object.keys(userCfg.mcpServers);
    }
  }

  // Detectar faltantes
  const faltantes = mcpsEsperados.filter((m) => !mcpsActuales.includes(m.nombre));

  if (faltantes.length > 0) {
    const out = [''];
    out.push(`MCP check Ovillo - faltan ${faltantes.length} MCP(s) user-scope esperado(s):`);
    out.push('');
    for (const f of faltantes) {
      out.push(`  - ${f.nombre} (${f.razon})`);
      out.push(`    Instalar: ${f.comando}`);
      out.push('');
    }
    out.push('Estos MCPs se perdieron probablemente al cambiar de maquina o formatear.');
    out.push('Re-instalar 1 vez (scope user, persistente).');
    console.log(out.join('\n'));
  }

  // Actualizar cache (independiente de si habia faltantes) - atomico, UTF-8 sin BOM (FB-004/FB-007)
  const cacheData = {
    ultimaVerificacion: new Date().toISOString(),
    mcpsActuales,
    faltantes: faltantes.map((f) => f.nombre),
  };
  h.writeHiloJson(cacheData, cacheFile, { compress: true });

  return 0;
}

try {
  process.exit(main());
} catch (e) {
  console.error(`[mcp-check] error no fatal: ${e.message}`);
  process.exit(0);
}
