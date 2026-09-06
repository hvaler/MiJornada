// helpers.js - Funciones comunes para hooks Ovillo (Node >= 18, sin dependencias)
// Port de hook-helpers.ps1 (ADR-F006). Todos los hooks importan:
//   const h = require('./lib/helpers');
//
// Protocolo Claude Code hooks:
//   - PreToolUse/PostToolUse: JSON via stdin con tool_name, tool_input, tool_output
//   - SessionStart/Stop/UserPromptSubmit: stdin puede venir vacio
//   - stdout -> contexto Claude (PreToolUse/SessionStart) o transcript
//   - Exit 0 = permitir · Exit 1 = WARN (avisa, no bloquea) · Exit 2 = BLOCK (solo PreToolUse)

'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

// ---------------------------------------------------------------------------
// INPUT
// ---------------------------------------------------------------------------

/** Lee y parsea el JSON de stdin. Fallback a env vars (compatibilidad). */
function readHookInput() {
  let data = null;
  try {
    if (!process.stdin.isTTY) {
      const raw = fs.readFileSync(0, 'utf8');
      if (raw && raw.trim().length > 0) data = JSON.parse(raw);
    }
  } catch { /* stdin no disponible o no-JSON */ }

  if (!data) {
    data = {
      tool_name: process.env.CLAUDE_TOOL_NAME,
      tool_input: process.env.CLAUDE_TOOL_INPUT,
      tool_output: process.env.CLAUDE_TOOL_OUTPUT,
    };
  }
  return data;
}

/** Input del tool como string (command de Bash; Write/Edit serializado para regex). */
function getToolInput(hookData) {
  if (!hookData) return null;
  const ti = hookData.tool_input;
  if (typeof ti === 'string') return ti;
  if (ti) return JSON.stringify(ti);
  return null;
}

/** Output del tool (solo PostToolUse) como string. */
function getToolOutput(hookData) {
  if (!hookData) return null;
  const to = hookData.tool_output ?? hookData.tool_response;
  if (typeof to === 'string') return to;
  if (to) return JSON.stringify(to);
  return null;
}

/** file_path del input (Write/Edit). */
function getFilePath(hookData) {
  if (!hookData) return null;
  if (hookData.tool_input && typeof hookData.tool_input === 'object' && hookData.tool_input.file_path) {
    return hookData.tool_input.file_path;
  }
  const s = getToolInput(hookData);
  if (s) {
    const m = s.match(/"file_path"\s*:\s*"([^"]+)"/);
    if (m) return m[1];
  }
  return process.env.CLAUDE_EDITED_FILE || null;
}

/** new_string (Edit) o content (Write) del input. */
function getNewContent(hookData) {
  if (!hookData) return null;
  const ti = hookData.tool_input;
  if (ti && typeof ti === 'object') {
    if (ti.new_string) return ti.new_string;
    if (ti.content) return ti.content;
  }
  const s = getToolInput(hookData);
  if (s) {
    let m = s.match(/"new_string"\s*:\s*"((?:[^"\\]|\\.)*)"/);
    if (m) return JSON.parse('"' + m[1] + '"');
    m = s.match(/"content"\s*:\s*"((?:[^"\\]|\\.)*)"/);
    if (m) return JSON.parse('"' + m[1] + '"');
  }
  return null;
}

/** Raiz del proyecto (CLAUDE_PROJECT_DIR si Claude Code la define; si no, cwd). */
function projectDir() {
  return process.env.CLAUDE_PROJECT_DIR || process.cwd();
}

// ---------------------------------------------------------------------------
// GIT (manejo robusto de index.lock concurrente — v1.1.0 del helper PS)
// ---------------------------------------------------------------------------

/** `git` read-only sin crear locks (GIT_OPTIONAL_LOCKS=0). status/diff/log/rev-parse... */
function gitReadOnly(gitArgs, workingDir) {
  const r = spawnSync('git', gitArgs, {
    cwd: workingDir || process.cwd(),
    encoding: 'utf8',
    env: { ...process.env, GIT_OPTIONAL_LOCKS: '0' },
  });
  return { exitCode: r.status ?? 1, stdOut: r.stdout || '', stdErr: r.stderr || '' };
}

/** `git` con retry exponencial ante "index.lock: File exists" (exit 128). add/commit/checkout... */
function gitWithRetry(gitArgs, opts = {}) {
  const maxRetries = opts.maxRetries ?? 5;
  let backoff = opts.initialBackoffMs ?? 300;
  const cwd = opts.workingDir || process.cwd();
  let result = null;
  for (let attempt = 1; attempt <= maxRetries + 1; attempt++) {
    const r = spawnSync('git', gitArgs, { cwd, encoding: 'utf8' });
    result = { exitCode: r.status ?? 1, stdOut: r.stdout || '', stdErr: r.stderr || '', attempts: attempt };
    if (result.exitCode === 0) return result;
    const isLock = result.exitCode === 128 && /index\.lock.*File exists/.test(result.stdErr);
    if (!isLock) return result;
    if (attempt <= maxRetries) {
      sleepMs(backoff);
      backoff = Math.min(backoff * 2, 5000);
    }
  }
  return result;
}

/** ¿Existe .git/index.lock? ¿Que edad tiene? */
function testGitLockHealthy(repoPath) {
  const lockPath = path.join(repoPath || process.cwd(), '.git', 'index.lock');
  try {
    const st = fs.statSync(lockPath);
    const ageSeconds = (Date.now() - st.mtimeMs) / 1000;
    return { hasLock: true, ageSeconds, lockPath };
  } catch {
    return { hasLock: false, ageSeconds: -1, lockPath };
  }
}

/** Elimina .git/index.lock si es huerfano (> minAgeSeconds). Si esta activo, NO toca nada. */
function clearStaleGitLock(repoPath, minAgeSeconds = 30) {
  const info = testGitLockHealthy(repoPath);
  if (!info.hasLock) return { removed: false, reason: 'no-lock' };
  const age = Math.floor(info.ageSeconds);
  if (info.ageSeconds < minAgeSeconds) {
    return { removed: false, reason: `active-lock (${age}s < ${minAgeSeconds}s)` };
  }
  try {
    fs.unlinkSync(info.lockPath);
    return { removed: true, reason: `stale-lock-removed (age ${age}s)` };
  } catch (e) {
    return { removed: false, reason: `remove-failed: ${e.message}` };
  }
}

function sleepMs(ms) {
  // sleep sincrono (los hooks son procesos cortos de un solo hilo)
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

// ---------------------------------------------------------------------------
// JSON Hilo (FB-004 + FB-007): serializador UNICO, atomico, UTF-8 sin BOM
// ---------------------------------------------------------------------------

/**
 * Escribe un JSON de _hilo/ (o cualquier JSON del proyecto) de forma ATOMICA:
 * valida ANTES de tocar el destino, escribe a .tmp, valida el .tmp y hace swap.
 * Nunca deja el destino vacio/corrupto (FB-007: un hook dejo ESTADO_PROYECTO.json
 * a 0 bytes y se committeo). UTF-8 SIN BOM (default de Node).
 * @returns {{success: boolean, path: string, message: string}}
 */
function writeHiloJson(inputObject, filePath, opts = {}) {
  let tmpPath = null;
  try {
    const json = JSON.stringify(inputObject, null, opts.compress ? undefined : 2);
    if (!json || !json.trim()) {
      return { success: false, path: filePath, message: 'writeHiloJson abortado: serializacion vacia - destino intacto' };
    }
    JSON.parse(json); // valida ANTES de tocar el destino

    const fullPath = path.isAbsolute(filePath) ? filePath : path.join(process.cwd(), filePath);
    const dir = path.dirname(fullPath);
    if (dir && !fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

    tmpPath = fullPath + '.tmp';
    fs.writeFileSync(tmpPath, json, 'utf8');

    const tmpRaw = fs.readFileSync(tmpPath, 'utf8');
    if (!tmpRaw || !tmpRaw.trim()) {
      fs.unlinkSync(tmpPath);
      return { success: false, path: fullPath, message: 'writeHiloJson abortado: .tmp vacio tras escribir - destino intacto' };
    }
    JSON.parse(tmpRaw);

    fs.renameSync(tmpPath, fullPath); // atomico en el mismo volumen
    return { success: true, path: fullPath, message: 'ok' };
  } catch (e) {
    try { if (tmpPath && fs.existsSync(tmpPath)) fs.unlinkSync(tmpPath); } catch { /* noop */ }
    return { success: false, path: filePath, message: `writeHiloJson fallo: ${e.message}` };
  }
}

/** Lee un JSON best-effort (null si no existe o no parsea). */
function readJsonSafe(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return null;
  }
}

module.exports = {
  readHookInput,
  getToolInput,
  getToolOutput,
  getFilePath,
  getNewContent,
  projectDir,
  gitReadOnly,
  gitWithRetry,
  testGitLockHealthy,
  clearStaleGitLock,
  writeHiloJson,
  readJsonSafe,
  sleepMs,
};
