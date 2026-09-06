// sql-baseline-generate.js - Genera el baseline de archivos SQL legacy que incumplen
// la nomenclatura configurada (database.naming). Utilidad CLI, no cableada a eventos.
// Version: 1.0.0-node (port de sql-baseline-generate.ps1 v1.0, ADR-F006)
//
// Uso:
//   node .claude/hooks/sql-baseline-generate.js [--dry-run] [--project-dir <ruta>] [--output <ruta>]
//
// El hook sql-nomenclatura-guard.js omitira los archivos listados al editarlos, pero
// SEGUIRA avisando en archivos nuevos o renombrados que no esten en el baseline.

'use strict';

const fs = require('fs');
const path = require('path');
const cfgLib = require(path.join(__dirname, 'lib', 'config'));

const args = process.argv.slice(2);
const dryRun = args.includes('--dry-run') || args.includes('-DryRun');
const argVal = (name) => {
  const i = args.indexOf(name);
  return i >= 0 && args[i + 1] ? args[i + 1] : null;
};
const projectDir = path.resolve(argVal('--project-dir') || process.env.CLAUDE_PROJECT_DIR || process.cwd());

const cfg = cfgLib.load(projectDir);
const naming = cfgLib.get(cfg, 'database.naming', {});
const outputFile = path.resolve(argVal('--output') || path.join(projectDir, naming.legacyBaselineFile || '.claude/sql-legacy-baseline.txt'));

const fnPref = (naming.functionPrefix || 'fn_').replace(/_$/, '');
const fntPref = (naming.tableFunctionPrefix || 'fnt_').replace(/_$/, '');
const vwPref = (naming.viewPrefix || 'vw_').replace(/_$/, '');
const trPref = (naming.triggerPrefix || 'tr_').replace(/_$/, '');
const prefAlt = (naming.forbiddenPrefixes || []).map((p) => p.replace(/_$/, '')).filter(Boolean).join('|');
const sufAlt = (naming.forbiddenSuffixes || []).map((s) => s.replace(/^_/, '')).filter(Boolean).join('|');
const legAlt = (naming.legacyPrefixes || []).map((p) => p.replace(/_$/, '')).filter(Boolean).join('|');

console.log(`[SQL Baseline] Escaneando ${projectDir}...`);

function walk(dir, acc) {
  let entries;
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return acc; }
  for (const e of entries) {
    if (/^(bin|obj|node_modules|\.git|packages)$/i.test(e.name)) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, acc);
    else if (/\.sql$/i.test(e.name)) acc.push(p);
  }
  return acc;
}
const sqlFiles = walk(projectDir, []);
console.log(`[SQL Baseline] ${sqlFiles.length} archivos .sql encontrados`);

const violations = [];
for (const file of sqlFiles) {
  let content;
  try { content = fs.readFileSync(file, 'utf8'); } catch { continue; }
  if (!content) continue;

  if (/^\s*--\s*LEGACY:\s*no\s+renombrar/im.test(content)) continue;
  if (/Legacy[/\\]|Obsoleto[/\\]|MigracionPendiente[/\\]/i.test(file)) continue;

  let hasViolation = false;

  // 1. SP con prefijo prohibido (o legacy custom)
  const allPref = [prefAlt, legAlt].filter(Boolean).join('|');
  if (allPref && new RegExp(String.raw`CREATE\s+(?:OR\s+ALTER\s+)?PROC(?:EDURE)?\s+\[?(?:\w+\]?\.\[?)?\[?(${allPref})_\w+\]?`, 'im').test(content)) hasViolation = true;

  // 2. SP con sufijo prohibido
  if (!hasViolation && sufAlt && new RegExp(String.raw`CREATE\s+(?:OR\s+ALTER\s+)?PROC(?:EDURE)?\s+[^\r\n]*_(${sufAlt})\b`, 'im').test(content)) hasViolation = true;

  // 3. Funcion escalar sin prefijo configurado
  if (!hasViolation && new RegExp(String.raw`CREATE\s+(?:OR\s+ALTER\s+)?FUNCTION\s+\[?\w+\]?\.\[?(?!${fnPref}_|${fntPref}_)\w+\]?\s*\([^)]*\)\s*RETURNS\s+(?!TABLE)`, 'im').test(content)) hasViolation = true;

  // 4. TVF con prefijo escalar
  if (!hasViolation && new RegExp(String.raw`CREATE\s+(?:OR\s+ALTER\s+)?FUNCTION\s+\[?\w+\]?\.\[?${fnPref}_\w+\]?\s*\([^)]*\)\s*RETURNS\s+TABLE`, 'im').test(content)) hasViolation = true;

  // 5. Vista sin prefijo configurado
  if (!hasViolation && new RegExp(String.raw`CREATE\s+(?:OR\s+ALTER\s+)?VIEW\s+\[?\w+\]?\.\[?(?!${vwPref}_)\w+\]?`, 'im').test(content)) hasViolation = true;

  // 6. Trigger sin prefijo configurado
  if (!hasViolation && new RegExp(String.raw`CREATE\s+(?:OR\s+ALTER\s+)?TRIGGER\s+\[?(?:\w+\]?\.\[?)?\[?(?!${trPref}_)\w+\]?`, 'im').test(content)) hasViolation = true;

  // 7. SP sin schema (mismo fix del guard: lookahead que exige fin de identificador,
  //    evita falso positivo con schemas terminados en "as")
  if (!hasViolation && /CREATE\s+(?:OR\s+ALTER\s+)?PROC(?:EDURE)?\s+\[?[A-Za-z]\w*\]?(?![.\[\]\w])/im.test(content)) {
    hasViolation = true;
  }

  if (hasViolation) {
    const rel = path.relative(projectDir, file).replace(/\\/g, '/');
    violations.push(rel);
  }
}

console.log('');
console.log(`[SQL Baseline] ${violations.length} archivos legacy detectados`);

if (violations.length === 0) {
  console.log('[SQL Baseline] No se detectaron violaciones. No se creara baseline.');
  process.exit(0);
}

const sorted = violations.sort();

if (dryRun) {
  console.log('');
  console.log('[SQL Baseline] DRY RUN - archivos que se anadirian:');
  for (const v of sorted) console.log(`  ${v}`);
  console.log('');
  console.log(`[SQL Baseline] Ejecuta sin --dry-run para escribir ${outputFile}`);
  process.exit(0);
}

const parent = path.dirname(outputFile);
if (!fs.existsSync(parent)) fs.mkdirSync(parent, { recursive: true });
fs.writeFileSync(outputFile, sorted.join('\n') + '\n', 'utf8'); // UTF-8 sin BOM (default Node)

console.log('');
console.log(`[SQL Baseline] Baseline creado: ${outputFile}`);
console.log(`[SQL Baseline] ${sorted.length} archivos listados`);
console.log('');
console.log('Proximos pasos:');
console.log(`  1. Revisar ${outputFile} y quitar archivos que SI deberian respetar la nomenclatura`);
console.log('  2. Commit del baseline al repo');
console.log('  3. El hook sql-nomenclatura-guard.js ya omitira esos archivos al editarlos');
