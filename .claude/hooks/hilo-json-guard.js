// hilo-json-guard.js - Bloquea commitear un _hilo/*.json vacio o invalido (FB-007, EWP)
// Evento: PreToolUse[Bash]. Exit 0 = permitir, Exit 2 = bloquear (razon en stderr).
// Version: 1.0.0-node (port de hilo-json-guard.ps1 v1.0.0, ADR-F006)
// Historial del original (condensado):
//   v1.0.0 (Ovillo, FB-007): un hook dejo _hilo/ESTADO_PROYECTO.json a 0 bytes Y se committeo ->
//     rompio el @import del CLAUDE.md y /mcp-sync. Intercepta 'git commit' y rechaza si algun
//     _hilo/*.json STAGED esta vacio o no parsea. Complementa writeHiloJson (defensa en profundidad).
//
// Politica (ADR-F000/F001): BLOCK INTRINSECO — data-loss del state file, dano concreto e inmediato;
// resolvePolicy con intrinsicBlock:true devuelve 'block' incondicionalmente.

'use strict';

const h = require('./lib/helpers');
const config = require('./lib/config');

try {
  const hookData = h.readHookInput();
  if (!hookData) process.exit(0);
  const toolInput = h.getToolInput(hookData);
  if (!toolInput) process.exit(0);

  // Extraer comando bash
  let command = null;
  if (hookData.tool_input && typeof hookData.tool_input === 'object' && hookData.tool_input.command) {
    command = hookData.tool_input.command;
  } else {
    const m = toolInput.match(/"command"\s*:\s*"((?:[^"\\]|\\.)*)"/);
    if (m) command = m[1];
  }
  if (!command) process.exit(0);

  // Solo activa en 'git commit' (no diff, log, etc.)
  if (!/\bgit\s+commit\b/i.test(command)) process.exit(0);

  const mode = config.resolvePolicy(config.load(), 'hilo-json-guard', { intrinsicBlock: true }); // siempre 'block'

  const repoRoot = process.env.CLAUDE_PROJECT_DIR || process.cwd();

  // Leer staged files (added/modified). Sin lock (GIT_OPTIONAL_LOCKS=0 via gitReadOnly)
  // para no colisionar con VS/GitLens.
  const diff = h.gitReadOnly(['-c', 'core.quotepath=off', 'diff', '--cached', '--name-only', '--diff-filter=AM'], repoRoot);
  if (diff.exitCode !== 0) process.exit(0); // si git falla (repo nuevo, primer commit), no bloquear
  const staged = diff.stdOut.split(/\r?\n/).filter(Boolean);
  if (staged.length === 0) process.exit(0);

  const duranJsons = staged.filter((f) => /(^|\/)_hilo\/.*\.json$/i.test(f));
  if (duranJsons.length === 0) process.exit(0);

  const bad = [];
  for (const f of duranJsons) {
    const show = h.gitReadOnly(['show', `:${f}`], repoRoot); // contenido STAGED (indice), no el working tree
    if (show.exitCode !== 0) continue; // no se pudo leer el staged: no bloquear por esto
    const raw = show.stdOut;
    if (!raw || !raw.trim()) {
      bad.push(`${f} (vacio / 0 bytes)`);
      continue;
    }
    try {
      JSON.parse(raw);
    } catch {
      bad.push(`${f} (JSON invalido)`);
    }
  }

  if (bad.length > 0) {
    console.error('');
    console.error('BLOQUEADO hilo-json-guard: vas a commitear un _hilo/*.json vacio o invalido (data loss).');
    for (const b of bad) console.error(`  - ${b}`);
    console.error('');
    console.error('Un _hilo/*.json vacio rompe el @import del CLAUDE.md y /mcp-sync.');
    console.error('Fix: restaura el contenido (git checkout HEAD -- <archivo> o regeneralo)');
    console.error('     y re-stagea antes de commitear.');
    process.exit(mode === 'block' ? 2 : 1); // intrinseco: siempre 2
  }

  process.exit(0);
} catch (e) {
  // Error inesperado: permitir operacion en lugar de romper el flujo.
  console.error(`hilo-json-guard.js: error inesperado, permitiendo operacion. Detalle: ${e && e.message ? e.message : e}`);
  process.exit(0);
}
