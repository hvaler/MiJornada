#!/usr/bin/env node
// pre-cicd-init.js - Validacion pre-flight antes de ejecutar /cicd-init
// Evento: UserPromptSubmit
// Trigger: prompt del usuario que invoque "/cicd-init"
// Exit 0 = continuar (stdout se inyecta como contexto adicional)
// Exit 2 = bloquear con mensaje accionable EN STDERR (R14: idempotencia + pre-flight)
// Version: 1.0.0-node (port de pre-cicd-init.ps1 v1.0.2, ADR-F006)
//
// Parametrizacion FASE 2 (ADR-F001/F002):
//   - La URL de instalacion sale de ecosystem.config -> distribution.baseUrl
//     (placeholder '<distribution.baseUrl>' si esta vacio, como el texto original).
//   - La conectividad al servidor CI/CD (antes hardcodeada a un host TFS) se deriva de
//     cicd.platform / ESTADO_PROYECTO.infraestructura.cicd:
//       * plataforma != 'azure-pipelines' -> sin pre-flight de conectividad (skip informativo)
//       * URL del servidor: ESTADO_PROYECTO.infraestructura.cicd.serverUrl >
//         ecosystem.config cicd.serverUrl; sin URL -> skip informativo (nunca bloquear
//         contra un host placeholder).
//
// Logica (identica al .ps1):
//   1. Solo se activa si el prompt contiene "/cicd-init"
//   2. Verifica que la version instalada de la plantilla sea >= 3.11.0 (si se detecta)
//   3. Detecta TFS Classic (aborta delegando al migrador)
//   4. Si la fase no es 0: verifica conectividad al servidor CI/CD configurado

'use strict';

const fs = require('fs');
const path = require('path');
const h = require(path.join(__dirname, 'lib', 'helpers'));
const configLib = require(path.join(__dirname, 'lib', 'config'));

function writeBlock(lines) {
  for (const l of lines) console.error(l);
}

/** Compara 'a.b.c' vs 'x.y.z'. Devuelve <0, 0, >0 o null si no parsea. */
function compareVersions(a, b) {
  const pa = String(a).split('.').map((n) => parseInt(n, 10));
  const pb = String(b).split('.').map((n) => parseInt(n, 10));
  if (pa.some(Number.isNaN) || pb.some(Number.isNaN) || pa.length === 0) return null;
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const x = pa[i] ?? 0;
    const y = pb[i] ?? 0;
    if (x !== y) return x - y;
  }
  return 0;
}

function relPath(full, root) {
  // path.relative es robusto ante mezcla de separadores / y \ en root (ej. env vars)
  const rel = path.relative(root, full);
  if (rel && !rel.startsWith('..') && !path.isAbsolute(rel)) return rel;
  return full.replace(root, '').replace(/^[\\/]+/, '');
}

async function main() {
  const hookData = h.readHookInput();
  if (!hookData) return 0;

  // Solo dispara si el prompt menciona /cicd-init
  let prompt = null;
  if (typeof hookData.prompt === 'string') prompt = hookData.prompt;
  else if (hookData.prompt) prompt = String(hookData.prompt).trim();
  if (!prompt || !/\/cicd-init\b/.test(prompt)) return 0;

  // Localizar repo root + config de organizacion
  const repoRoot = h.projectDir();
  const cfg = configLib.load(repoRoot);
  const baseUrl = String(configLib.get(cfg, 'distribution.baseUrl', '') || '').trim().replace(/\/+$/, '');
  const installCmd = `irm ${baseUrl || '<distribution.baseUrl>'}/install.ps1 | iex`;

  // ------------------------------------------------------------------------
  // Check 1: version instalada de la plantilla >= 3.11.0
  // Fuente: _hilo/VERSION.json (.installedVersion / .version) -> fallback
  //         _hilo/ESTADO_PROYECTO.json (.ecosistema.version).
  // Si no se detecta: WARN (NO bloquear; el wizard maneja el resto).
  // ------------------------------------------------------------------------
  let installedVersion = null;
  try {
    const vj = h.readJsonSafe(path.join(repoRoot, '_hilo', 'VERSION.json'));
    if (vj) {
      if (vj.installedVersion) installedVersion = vj.installedVersion;
      else if (vj.version) installedVersion = vj.version;
    }
    if (!installedVersion) {
      const ej = h.readJsonSafe(path.join(repoRoot, '_hilo', 'ESTADO_PROYECTO.json'));
      if (ej && ej.ecosistema && ej.ecosistema.version) installedVersion = ej.ecosistema.version;
    }
  } catch (e) {
    console.log(`[!] pre-cicd-init: no se pudo leer la version instalada (${e.message}). Continuando.`);
  }

  if (installedVersion) {
    // Strip pre-release suffix (-beta, -rc1...) antes de comparar
    const clean = String(installedVersion).replace(/-.*$/, '');
    const cmp = compareVersions(clean, '3.11.0');
    if (cmp === null) {
      console.log(`[!] pre-cicd-init: version '${installedVersion}' no parseable. Continuando.`);
    } else if (cmp < 0) {
      writeBlock([
        `[X] pre-cicd-init: version de plantilla insuficiente (actual ${installedVersion}, requerida >= 3.11.0).`,
        '    /cicd-init con 3 fases de adopcion necesita Ovillo >= 3.11.0.',
        `    Actualizar:  ${installCmd}`,
      ]);
      return 2;
    }
  } else {
    console.log('[!] pre-cicd-init: no se detecto version instalada en _hilo/. Continuando bajo riesgo.');
  }

  // ------------------------------------------------------------------------
  // Check 2: fase explicita (--fase 0 no necesita servidor CI/CD)
  // ------------------------------------------------------------------------
  const mFase = prompt.match(/--fase\s+(\d)/);
  if (mFase && parseInt(mFase[1], 10) === 0) {
    console.log('[i] pre-cicd-init: Fase 0 detectada (solo Ovillo local, cero infra TFS). Saltando validacion TFS.');
    return 0;
  }

  // ------------------------------------------------------------------------
  // Check 3: TFS Classic -> abortar (mensaje en stderr)
  // ------------------------------------------------------------------------
  const classicXaml = [];
  const classicXoml = [];
  const classicDirs = [];
  const skipDirs = new Set(['.git', 'node_modules']);

  function walk(dir) {
    if (classicXaml.length >= 3 && classicXoml.length >= 3 && classicDirs.length >= 1) return;
    let entries;
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      const full = path.join(dir, e.name);
      if (e.isDirectory()) {
        if (skipDirs.has(e.name)) continue;
        if (e.name === 'BuildProcessTemplates' && classicDirs.length < 1) classicDirs.push(full);
        walk(full);
      } else if (e.isFile()) {
        const lower = e.name.toLowerCase();
        if (lower.endsWith('.xaml') && classicXaml.length < 3 && /TfsBuild|BuildProcessTemplates/i.test(full)) {
          classicXaml.push(full);
        } else if (lower.endsWith('.xoml') && classicXoml.length < 3) {
          classicXoml.push(full);
        }
      }
    }
  }
  try {
    walk(repoRoot);
  } catch { /* scan best-effort */ }

  const classicFiles = classicXaml.concat(classicXoml);
  if (classicFiles.length > 0 || classicDirs.length > 0) {
    const msg = ['[X] pre-cicd-init: detectado pipeline TFS Classic (.xaml/.xoml/BuildProcessTemplates).', ''];
    if (classicFiles.length > 0) {
      msg.push('    Archivos Classic:');
      for (const f of classicFiles.slice(0, 3)) msg.push(`      - ${relPath(f, repoRoot)}`);
    }
    if (classicDirs.length > 0) msg.push(`    Directorio: ${relPath(classicDirs[0], repoRoot)}`);
    msg.push(
      '',
      '    /cicd-init es para GREENFIELD. Migracion Classic -> YAML: guia manual en',
      '    .claude/skills/cicd-architect/references/classic-migration.md (ADR-053).'
    );
    writeBlock(msg);
    return 2;
  }

  // ------------------------------------------------------------------------
  // Check 4: conectividad al servidor CI/CD (solo fase >= 1, implicita o explicita).
  // FASE 2: derivado de cicd.platform + ESTADO_PROYECTO (antes host TFS hardcodeado).
  // Node negocia TLS 1.2+ por defecto (equivalente al fix R2/h9 de PS 5.1).
  // ------------------------------------------------------------------------
  const estado = h.readJsonSafe(path.join(repoRoot, '_hilo', 'ESTADO_PROYECTO.json'));
  const platform =
    (estado && estado.infraestructura && estado.infraestructura.cicd && estado.infraestructura.cicd.plataforma) ||
    configLib.get(cfg, 'cicd.platform', 'none');

  if (String(platform).toLowerCase() !== 'azure-pipelines') {
    console.log(`[i] pre-cicd-init: plataforma CI/CD '${platform}' sin pre-flight de conectividad especifico. Continuando.`);
    return 0;
  }

  let serverBase =
    (estado && estado.infraestructura && estado.infraestructura.cicd && estado.infraestructura.cicd.serverUrl) ||
    configLib.get(cfg, 'cicd.serverUrl', '') ||
    '';
  serverBase = String(serverBase).trim().replace(/\/+$/, '');
  if (!serverBase) {
    console.log('[i] pre-cicd-init: sin URL de servidor CI/CD configurada (infraestructura.cicd.serverUrl o ecosystem.config cicd.serverUrl). Saltando validacion de conectividad.');
    return 0;
  }

  let host;
  try {
    host = new URL(serverBase).host;
  } catch (e) {
    console.log(`[!] pre-cicd-init: error inesperado validando TFS (${e.message}). Continuando bajo riesgo.`);
    return 0;
  }

  const tfsUrl = `${serverBase}/_apis/connectionData?api-version=6.0`;
  try {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 5000);
    let resp;
    try {
      resp = await fetch(tfsUrl, { method: 'HEAD', signal: ctrl.signal, redirect: 'manual' });
    } finally {
      clearTimeout(timer);
    }
    const status = resp.status;
    if (status === 200) {
      console.log('[OK] pre-cicd-init: TFS accesible (HTTP 200). Pre-flight OK.');
      return 0;
    }
    if (status === 401 || status === 403) {
      console.log(`[!] pre-cicd-init: TFS accesible pero auth fallida (HTTP ${status}). Continuando bajo riesgo.`);
      return 0;
    }
    // HTTP 405 Method Not Allowed: el servidor rechaza HEAD pero el endpoint EXISTE (accesible)
    if (status === 405) {
      console.log('[OK] pre-cicd-init: TFS accesible (HTTP 405 a HEAD; el endpoint existe). Pre-flight OK.');
      return 0;
    }
    console.log(`[!] pre-cicd-init: TFS respondio HTTP ${status}. Continuando bajo riesgo.`);
    return 0;
  } catch (e) {
    writeBlock([
      `[X] pre-cicd-init: sin conectividad a ${host}.`,
      `    Error: ${e.message}`,
      `    Verificar: estas en red corporativa o VPN? ${host} responde en tu navegador?`,
      '    Si solo quieres Fase 0 (sin TFS), ejecuta: /cicd-init --fase 0',
    ]);
    return 2;
  }
}

main()
  .then((code) => process.exit(code ?? 0))
  .catch((e) => {
    console.error(`[pre-cicd-init] error no fatal: ${e.message}`);
    process.exit(0);
  });
