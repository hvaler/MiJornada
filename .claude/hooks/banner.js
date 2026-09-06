#!/usr/bin/env node
// banner.js - Contexto de inicio de sesion Ovillo para Claude Code
// Evento: SessionStart
// Version: 1.0.0-node (port de banner.ps1, ADR-F006)
//
// Hook SessionStart que inyecta contexto del proyecto en Claude.
// Lee ESTADO_PROYECTO.json y emite informacion relevante a stdout,
// que Claude Code captura como contexto inicial de la sesion.
// Tambien detecta complementos faltantes y actualiza el announcement.
//
// stdout -> contexto para Claude (no visible al usuario)
// stderr -> visible al usuario en terminal
//
// Parametrizacion FASE 2 (ADR-F001):
//   - El announcement se escribe en .claude/settings.json companyAnnouncements (como el .ps1),
//     ahora de forma ATOMICA via writeHiloJson (FB-004/FB-007).
//   - El check de update usa ecosystem.config -> distribution.baseUrl (+ /VERSION.json).
//     baseUrl vacio (y sin serverUrl en _hilo/VERSION.json) -> check saltado silenciosamente;
//     el cache de 24h (_hilo/.update-check.json) se conserva para el statusline.
//   - distribution.updateCheck=false tambien desactiva la consulta remota.

'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const h = require(path.join(__dirname, 'lib', 'helpers'));
const configLib = require(path.join(__dirname, 'lib', 'config'));

function runCli(commandLine) {
  // Equivalente a `& cmd ... 2>&1 | Out-String` con degradacion silenciosa.
  // shell:true (comando como string unico, args estaticos) para resolver
  // shims .cmd/.ps1 en Windows (claude, dotnet).
  try {
    const r = spawnSync(commandLine, { encoding: 'utf8', shell: true, timeout: 10000, windowsHide: true });
    return `${r.stdout || ''}${r.stderr || ''}`;
  } catch {
    return '';
  }
}

async function main() {
  const projectDir = h.projectDir();
  const cfg = configLib.load(projectDir);
  const baseUrl = String(configLib.get(cfg, 'distribution.baseUrl', '') || '').trim().replace(/\/+$/, '');
  const updateCheckEnabled = configLib.get(cfg, 'distribution.updateCheck', true) !== false;
  const installUrlBase = baseUrl || '<distribution.baseUrl>';

  const duranDir = path.join(projectDir, '_hilo');
  const estadoFile = path.join(duranDir, 'ESTADO_PROYECTO.json');
  const versionFile = path.join(duranDir, 'VERSION.json');

  // Valores por defecto
  let Version = '?.?.?';
  let Idioma = 'es-ES';
  let Modo = '';
  let Proyecto = '';
  let Evolutivo = '';
  let Fase = '';
  let Alertas = [];

  const estado = h.readJsonSafe(estadoFile);
  if (estado) {
    if (estado.ecosistema && estado.ecosistema.version) Version = estado.ecosistema.version;
    if (estado.configuracion && estado.configuracion.idioma) Idioma = estado.configuracion.idioma;
    if (estado.estado && estado.estado.modo) Modo = estado.estado.modo;
    if (estado.estado && estado.estado.fase_actual) Fase = estado.estado.fase_actual;
    if (estado.proyecto && estado.proyecto.nombre && estado.proyecto.nombre !== '[NOMBRE_PROYECTO]') {
      Proyecto = estado.proyecto.nombre;
    }
    if (estado.evolutivoActivo) Evolutivo = estado.evolutivoActivo;
    if (estado.alertas && Array.isArray(estado.alertas.activas) && estado.alertas.activas.length > 0) {
      Alertas = estado.alertas.activas;
    }
  }

  // Fallback: leer version de VERSION.json si no se obtuvo de ESTADO_PROYECTO.json
  if (Version === '?.?.?') {
    const vData = h.readJsonSafe(versionFile);
    if (vData && vData.installedVersion) Version = vData.installedVersion;
  }

  // === DETECTAR ESTADO DE COMPLEMENTOS ===
  let roslynTool = false;
  let roslynMcp = false;
  let context7Mcp = false;
  let dotnetSkills = false;

  const tools = runCli('dotnet tool list -g');
  if (/cwm\.roslynnavigator|cwm-roslyn-navigator/i.test(tools)) roslynTool = true;

  const mcpList = runCli('claude mcp list');
  if (/cwm-roslyn-navigator/i.test(mcpList)) roslynMcp = true;
  if (/context7/i.test(mcpList)) context7Mcp = true;

  const pluginList = runCli('claude plugin list');
  if (/dotnet/i.test(pluginList) && !/No plugins installed/i.test(pluginList)) dotnetSkills = true;

  // === ACTUALIZAR companyAnnouncements DINAMICAMENTE ===
  try {
    const settingsFile = path.join(projectDir, '.claude', 'settings.json');
    if (fs.existsSync(settingsFile)) {
      // Construir banner dinamico
      const bannerParts = [`Ovillo v${Version}`];
      if (Proyecto) bannerParts.push(Proyecto);

      // Rama Git (sin crear lock para no colisionar con IDE: GIT_OPTIONAL_LOCKS=0)
      const branchRes = h.gitReadOnly(['rev-parse', '--abbrev-ref', 'HEAD'], projectDir);
      const branch = (branchRes.stdOut || '').trim();
      if (branchRes.exitCode === 0 && branch) bannerParts.push(`rama: ${branch}`);

      if (Evolutivo) bannerParts.push(`evolutivo: ${Evolutivo}`);
      if (Modo) bannerParts.push(`modo: ${Modo}`);

      const line1 = bannerParts.join(' | ');

      // Linea 2: complementos
      const compParts = [];
      if (roslynTool && roslynMcp) compParts.push('Roslyn');
      if (context7Mcp) compParts.push('Context7');
      if (dotnetSkills) compParts.push('dotnet/skills');
      const missingParts = [];
      if (!roslynTool || !roslynMcp) missingParts.push('Roslyn');
      if (!context7Mcp) missingParts.push('Context7');
      if (!dotnetSkills) missingParts.push('dotnet/skills');

      let line2 = '';
      if (compParts.length > 0) line2 += `MCPs: ${compParts.join(', ')}`;
      if (missingParts.length > 0) {
        if (line2) line2 += ' | ';
        line2 += `Falta: ${missingParts.join(', ')}`;
      }

      let bannerText = line1;
      if (line2) bannerText += `\n${line2}`;
      bannerText += '\n/sos para ayuda rapida';

      // Leer settings, actualizar solo companyAnnouncements, escribir (atomico, UTF-8 sin BOM)
      const settings = JSON.parse(fs.readFileSync(settingsFile, 'utf8'));
      settings.companyAnnouncements = [bannerText];
      h.writeHiloJson(settings, settingsFile);
    }
  } catch {
    // Silenciar - no bloquear sesion por error en banner
  }

  // === CHECK UPDATE DISPONIBLE (silencioso si falla) ===
  // Consulta VERSION.json del servidor de distribucion y cachea en
  // _hilo/.update-check.json (TTL 24h). El statusline lee el cache sin red.
  let updateInfo = null;
  const cacheFile = path.join(duranDir, '.update-check.json');
  let cacheValid = false;

  const cache = h.readJsonSafe(cacheFile);
  if (cache && cache.checkedAt) {
    try {
      const checkedAt = new Date(cache.checkedAt);
      const ageHours = (Date.now() - checkedAt.getTime()) / 3600000;

      // Invalidar cache si el localVersion cacheado no coincide con la version actual
      // (previene que tras /actualizar el cache siga marcando updateAvailable=true).
      const cacheLocalVer = Object.prototype.hasOwnProperty.call(cache, 'localVersion') ? cache.localVersion : null;
      const cacheLocalStale = Boolean(cacheLocalVer && Version !== '?.?.?' && cacheLocalVer !== Version);

      if (!Number.isNaN(ageHours) && ageHours < 24 && !cacheLocalStale) {
        updateInfo = cache;
        cacheValid = true;
      }
    } catch { /* cache ilegible -> re-consultar */ }
  }

  if (!cacheValid && updateCheckEnabled) {
    try {
      let localVer = null;
      let localHash = null;
      let serverUrl = baseUrl; // FASE 2: antes '<distribution.baseUrl>' hardcoded

      const lv = h.readJsonSafe(versionFile);
      if (lv) {
        if (lv.installedVersion) localVer = lv.installedVersion;
        if (Object.prototype.hasOwnProperty.call(lv, 'installedZipSha256')) localHash = lv.installedZipSha256;
        if (Object.prototype.hasOwnProperty.call(lv, 'serverUrl') && lv.serverUrl) serverUrl = String(lv.serverUrl).replace(/\/+$/, '');
      }

      if (serverUrl) {
        // Consulta al servidor con timeout corto (no bloquear sesion)
        const ctrl = new AbortController();
        const timer = setTimeout(() => ctrl.abort(), 3000);
        let remote;
        try {
          const resp = await fetch(`${serverUrl}/VERSION.json`, { signal: ctrl.signal });
          if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
          remote = await resp.json();
        } finally {
          clearTimeout(timer);
        }

        let updateAvailable = false;
        let updateType = 'none';
        if (localVer && remote && remote.version) {
          if (localVer !== remote.version) {
            updateAvailable = true;
            updateType = 'minor';
          } else if (localHash && remote.zipSha256 && localHash !== remote.zipSha256) {
            updateAvailable = true;
            updateType = 'hotfix';
          }
        }

        updateInfo = {
          checkedAt: new Date().toISOString().replace(/\.\d{3}Z$/, 'Z'),
          localVersion: localVer,
          localZipSha256: localHash,
          serverVersion: remote ? (remote.version ?? null) : null,
          serverZipSha256: remote ? (remote.zipSha256 ?? null) : null,
          updateAvailable,
          updateType,
          serverUrl,
        };

        // Escribir cache (atomico, UTF-8 sin BOM, RFC 8259 - FB-004/FB-007)
        h.writeHiloJson(updateInfo, cacheFile);
      }
      // serverUrl vacio (distribution.baseUrl sin configurar) -> saltar check silenciosamente.
      // El cache anterior, si existe, se conserva para el statusline.
    } catch {
      // Sin conectividad / servidor no responde / timeout. Silencioso.
      // El cache anterior (si existe pero > 24h) sigue siendo legible por el statusline.
    }
  }

  // === EMITIR CONTEXTO A STDOUT (para Claude) ===
  const output = [];
  output.push('[Ovillo SessionStart Context]');
  output.push(`Ecosistema: Ovillo v${Version} (Hilo + Patrón)`);
  if (Proyecto) output.push(`Proyecto: ${Proyecto}`);
  if (Modo) output.push(`Modo: ${Modo}`);
  if (Fase) output.push(`Fase: ${Fase}`);
  output.push(`Idioma: ${Idioma}`);
  if (Evolutivo) output.push(`Evolutivo activo: ${Evolutivo}`);
  if (Alertas.length > 0) {
    output.push('ALERTAS:');
    for (const alerta of Alertas) output.push(`  - ${alerta}`);
  }

  // Estado de complementos (siempre mostrar)
  const roslynStatus = roslynTool && roslynMcp ? 'instalado' : 'NO instalado';
  const context7Status = context7Mcp ? 'instalado' : 'NO instalado';
  const dotnetStatus = dotnetSkills ? 'instalado' : 'NO instalado';
  output.push('Complementos:');
  output.push(`  - MCP Roslyn (analisis semantico C#): ${roslynStatus}`);
  output.push(`  - MCP Context7 (documentacion librerias): ${context7Status}`);
  output.push(`  - dotnet/skills (68 skills Microsoft): ${dotnetStatus}`);

  const missingCritical = [];
  const missingOptional = [];
  if (!roslynTool || !roslynMcp) missingCritical.push('MCP Roslyn');
  if (!context7Mcp) missingCritical.push('MCP Context7');
  if (!dotnetSkills) missingOptional.push('dotnet/skills');

  if (missingCritical.length > 0) {
    output.push(`ACCION REQUERIDA: Faltan complementos (${missingCritical.join(', ')}). Indicar al usuario que ejecute: irm ${installUrlBase}/install.ps1 | iex`);
  }
  if (missingOptional.length > 0) {
    output.push(`OPCIONAL: Complementos disponibles no instalados (${missingOptional.join(', ')}). Instalar con: irm ${installUrlBase}/install.ps1 | iex`);
  }

  // Update Ovillo disponible
  if (updateInfo && updateInfo.updateAvailable) {
    if (updateInfo.updateType === 'minor') {
      output.push(`UPDATE Ovillo DISPONIBLE: v${updateInfo.serverVersion} (local v${updateInfo.localVersion}). Sugerir al usuario ejecutar /actualizar.`);
    } else if (updateInfo.updateType === 'hotfix') {
      output.push(`HOTFIX Ovillo DISPONIBLE: v${updateInfo.localVersion} (zipSha256 distinto en servidor). Sugerir al usuario ejecutar /actualizar para aplicar retro-fix.`);
    }
  }

  console.log(output.join('\n'));
  return 0;
}

main()
  .then((code) => process.exit(code ?? 0))
  .catch((e) => {
    console.error(`[banner] error no fatal: ${e.message}`);
    process.exit(0);
  });
