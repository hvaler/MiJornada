// auto-format.js - Auto-formato C# tras escritura
// Evento: PostToolUse[Write|Edit] · Exit 0 = siempre (no bloquea, solo formatea)
// Version: 1.0.0-node (port de auto-format.ps1 v1.0.0, ADR-F006)

'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const h = require(path.join(__dirname, 'lib', 'helpers'));

try {
  const editedFile = h.getFilePath(h.readHookInput());
  if (!editedFile) process.exit(0);
  if (!/\.cs$/i.test(editedFile)) process.exit(0);
  if (!fs.existsSync(editedFile)) process.exit(0);

  // Buscar .csproj / .sln / .slnx subiendo directorios (max 10 niveles)
  let searchDir = path.dirname(editedFile);
  let projectFile = null;
  for (let i = 0; i < 10; i++) {
    if (!searchDir || searchDir === path.dirname(searchDir)) break;
    let entries = [];
    try { entries = fs.readdirSync(searchDir); } catch { break; }
    projectFile =
      entries.find((f) => f.toLowerCase().endsWith('.csproj')) ||
      entries.find((f) => f.toLowerCase().endsWith('.sln')) ||
      entries.find((f) => f.toLowerCase().endsWith('.slnx')) || null;
    if (projectFile) { projectFile = path.join(searchDir, projectFile); break; }
    searchDir = path.dirname(searchDir);
  }
  if (!projectFile) process.exit(0);

  // dotnet format scoped al archivo (silencioso; degradacion graciosa si falta dotnet)
  const relativePath = path.relative(path.dirname(projectFile), editedFile);
  spawnSync('dotnet', ['format', projectFile, '--include', relativePath, '--verbosity', 'quiet'], {
    stdio: 'ignore',
    timeout: 60000,
    shell: process.platform === 'win32',
  });

  process.exit(0);
} catch (err) {
  console.error(`auto-format.js: error inesperado, continuando. Detalle: ${err.message}`);
  process.exit(0);
}
