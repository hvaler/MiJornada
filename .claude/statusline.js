// statusline.js - StatusLine personalizado Claude Code
// Formato (con ANSI colors):  [proyecto]  git:rama[*]  Ovillo vX.Y.Z  @ modelo
// Version: 1.0.0-node (port de statusline.ps1, ADR-F006)

'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

// --- ANSI color codes ------------------------------------------------------
const ESC = '';
const RESET = `${ESC}[0m`;
const DIM = `${ESC}[2m`;
const CYAN = `${ESC}[96m`;
const GREEN = `${ESC}[32m`;
const YELLOW = `${ESC}[33m`;
const MAGENTA = `${ESC}[95m`;
const BLUE = `${ESC}[94m`;
const BOLD = `${ESC}[1m`;

function readJson(p) {
  try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return null; }
}

// --- Leer input --------------------------------------------------------------
let cwd = null;
let modelDisplay = null;
try {
  if (!process.stdin.isTTY) {
    const raw = fs.readFileSync(0, 'utf8').trim();
    if (raw) {
      const data = JSON.parse(raw);
      cwd = data.cwd;
      if (data.model) modelDisplay = data.model.display_name || data.model.id;
    }
  }
} catch { /* input no-JSON: seguir con defaults */ }
if (!cwd) cwd = process.cwd();

// --- Proyecto ----------------------------------------------------------------
const folder = path.basename(cwd);
const projInfo = `${DIM}[${RESET}${CYAN}${folder}${RESET}${DIM}]${RESET}`;

// --- Git branch + dirty flag ---------------------------------------------------
let gitInfo = '';
try {
  const headFile = path.join(cwd, '.git', 'HEAD');
  if (fs.existsSync(headFile)) {
    const head = fs.readFileSync(headFile, 'utf8').trim();
    let branch = null;
    const m = head.match(/^ref:\s+refs\/heads\/(.+)$/);
    if (m) branch = m[1];
    else if (head.length >= 7) branch = head.substring(0, 7);

    if (branch) {
      let dirtyFlag = '';
      const r = spawnSync('git', ['-C', cwd, 'status', '--porcelain=v1'], {
        encoding: 'utf8',
        timeout: 3000,
        env: { ...process.env, GIT_OPTIONAL_LOCKS: '0' },
      });
      if (r.status === 0 && r.stdout && r.stdout.trim()) dirtyFlag = `${YELLOW}*${RESET}`;
      gitInfo = `  ${DIM}git:${RESET}${GREEN}${branch}${RESET}${dirtyFlag}`;
    }
  }
} catch { /* sin git info */ }

// --- Version del ecosistema -----------------------------------------------------
let ecoVersion = null;
let ecoHash = null;
const duranVersion = readJson(path.join(cwd, '_hilo', 'VERSION.json'));
if (duranVersion && duranVersion.installedVersion) {
  ecoVersion = duranVersion.installedVersion;
  ecoHash = duranVersion.installedZipSha256 || null;
}
if (!ecoVersion) {
  const estadoVersion = readJson(path.join(cwd, '_estado', 'VERSION.json'));
  if (estadoVersion && estadoVersion.version && estadoVersion.version.actual) {
    ecoVersion = estadoVersion.version.actual;
  }
}

let ecoInfo = '';
if (ecoVersion) {
  ecoInfo = `  ${BOLD}${MAGENTA}Ovillo${RESET} ${MAGENTA}v${ecoVersion}${RESET}`;

  // Indicador de update disponible (lee el cache que escribe banner.js al inicio de sesion).
  // Defensa: comparar el server cacheado contra la version/hash actual para no mostrar un
  // falso positivo si tras /actualizar el cache aun no se refresco.
  const uc = readJson(path.join(cwd, '_hilo', '.update-check.json'));
  if (uc && uc.updateAvailable) {
    const UPD = `${ESC}[93m`;
    if (uc.updateType === 'minor') {
      if (uc.serverVersion && uc.serverVersion !== ecoVersion) {
        ecoInfo += ` ${BOLD}${UPD}^v${uc.serverVersion}${RESET}`;
      }
    } else if (uc.updateType === 'hotfix') {
      if (uc.serverZipSha256 && ecoHash && uc.serverZipSha256 !== ecoHash) {
        ecoInfo += ` ${BOLD}${UPD}^hotfix${RESET}`;
      }
    }
  }
}

// --- Modelo ------------------------------------------------------------------
let modelInfo = '';
if (modelDisplay) modelInfo = `  ${DIM}@${RESET} ${BLUE}${modelDisplay}${RESET}`;

// --- Output ------------------------------------------------------------------
process.stdout.write(`${projInfo}${gitInfo}${ecoInfo}${modelInfo}`);
