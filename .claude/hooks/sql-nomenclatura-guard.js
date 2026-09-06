// sql-nomenclatura-guard.js - Detectar violaciones de nomenclatura SQL configurada (database.naming)
// Evento: PostToolUse[Write|Edit]
// Version: 1.0.0-node (port de sql-nomenclatura-guard.ps1 v1.1.0, ADR-F006)
//   Las listas (prefijos/sufijos prohibidos, prefijos legacy, verbos permitidos, prefijos de
//   funcion/vista/trigger, ruta del baseline) se leen de ecosystem.config.json ->
//   database.naming.* (ADR-F001). El gating de features por version SQL solo aplica si
//   database.version esta fijada. Politica: WARN-first (exit 1) elevable a BLOCK (exit 2)
//   via hooks.policy/blockList.

'use strict';

const fs = require('fs');
const path = require('path');
const h = require(path.join(__dirname, 'lib', 'helpers'));
const cfgLib = require(path.join(__dirname, 'lib', 'config'));

try {
  const hookData = h.readHookInput();
  const toolInput = h.getToolInput(hookData);
  if (!toolInput) process.exit(0);

  let filePath = '';
  let m = toolInput.match(/"file_path"\s*:\s*"([^"]+)"/);
  if (m) filePath = m[1];

  let content = null;
  m = toolInput.match(/"new_string"\s*:\s*"((?:[^"\\]|\\.)*)"/);
  if (m) content = m[1];
  else {
    m = toolInput.match(/"content"\s*:\s*"((?:[^"\\]|\\.)*)"/);
    if (m) content = m[1];
  }
  if (!content) process.exit(0);

  // Solo escanear si el contenido o el path sugieren SQL
  const isSqlFile = /\.(sql|sqlproj|tsql|ddl|dml)$/i.test(filePath);
  const isRepoFile = /Repository\.cs$|Repositorio\.cs$|Repositorios[/\\]|Repositories[/\\]|StoredProcedures[/\\]|DbContext\.cs$|ProcedimientoAlmacenado\.cs$/i.test(filePath);
  const isDeployScript = /03_Desarrollo[/\\]SQL[/\\]|[/\\]Scripts[/\\][^/\\]+\.sql$|[/\\]Database[/\\][^/\\]+\.sql$|[/\\]Deploy[/\\][^/\\]+\.sql$|[/\\]Migrations[/\\][^/\\]+\.sql$/i.test(filePath);
  const mentionsSqlObject = /CREATE\s+(OR\s+ALTER\s+)?(PROCEDURE|PROC|FUNCTION|VIEW|TRIGGER)/i.test(content);
  if (!(isSqlFile || isRepoFile || isDeployScript || mentionsSqlObject)) process.exit(0);

  const cfg = cfgLib.load();
  const naming = cfgLib.get(cfg, 'database.naming', {});

  // Respetar marcadores de legacy (3 vias)
  if (/Legacy[/\\]|Obsoleto[/\\]|MigracionPendiente[/\\]/i.test(filePath)) process.exit(0);
  if (/^\s*--\s*LEGACY:\s*no\s+renombrar/im.test(content)) process.exit(0);

  const projectDir = h.projectDir();
  const baselineRel = naming.legacyBaselineFile || '.claude/sql-legacy-baseline.txt';
  const baselineFile = path.isAbsolute(baselineRel) ? baselineRel : path.join(projectDir, baselineRel);
  if (fs.existsSync(baselineFile)) {
    const relativePath = filePath
      .replace(new RegExp('^' + projectDir.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '[/\\\\]'), '')
      .replace(/\\/g, '/');
    const baseline = fs.readFileSync(baselineFile, 'utf8').split(/\r?\n/).filter(Boolean);
    if (baseline.includes(relativePath)) {
      console.error(`[SQL] Nota: '${relativePath}' esta en baseline legacy. Si lo renombras, actualiza ${baselineRel}`);
      process.exit(0);
    }
  }

  // Destravar el contenido (el JSON escapa comillas y saltos)
  const decoded = content.replace(/\\n/g, '\n').replace(/\\"/g, '"').replace(/\\\\/g, '\\');

  const warnings = [];
  const spPattern = naming.storedProcedurePattern || '{schema}.{Verb}{Entity}';
  const fnPref = (naming.functionPrefix || 'fn_').replace(/_$/, '');
  const fntPref = (naming.tableFunctionPrefix || 'fnt_').replace(/_$/, '');
  const vwPref = (naming.viewPrefix || 'vw_').replace(/_$/, '');
  const trPref = (naming.triggerPrefix || 'tr_').replace(/_$/, '');
  const alt = (list) => (list || []).map((p) => p.replace(/_$/, '')).filter(Boolean).join('|');

  // 1. CREATE PROCEDURE con prefijo prohibido (database.naming.forbiddenPrefixes)
  const prefAlt = alt(naming.forbiddenPrefixes);
  if (prefAlt) {
    const rx = new RegExp(String.raw`CREATE\s+(?:OR\s+ALTER\s+)?PROC(?:EDURE)?\s+\[?(?:\w+\]?\.\[?)?\[?(${prefAlt})_\w+\]?`, 'gim');
    for (const mm of decoded.matchAll(rx)) {
      warnings.push(`[SQL] CREATE PROCEDURE con prefijo prohibido '${mm[1]}_': ${mm[0].trim()}`);
    }
  }

  // 2. CREATE PROCEDURE con sufijo prohibido (database.naming.forbiddenSuffixes; vacio = check off)
  const sufAlt = (naming.forbiddenSuffixes || []).map((s) => s.replace(/^_/, '')).filter(Boolean).join('|');
  if (sufAlt) {
    const rx = new RegExp(String.raw`CREATE\s+(?:OR\s+ALTER\s+)?PROC(?:EDURE)?\s+\[?\w+\]?\.\[?\w+_(${sufAlt})\]?\b`, 'gim');
    for (const mm of decoded.matchAll(rx)) {
      warnings.push(`[SQL] CREATE PROCEDURE con sufijo prohibido '_${mm[1]}': ${mm[0].trim()}`);
    }
  }

  // 2b. Verbos permitidos (database.naming.allowedVerbs; vacio = cualquier verbo)
  const verbs = naming.allowedVerbs || [];
  if (verbs.length > 0) {
    const rx = /CREATE\s+(?:OR\s+ALTER\s+)?PROC(?:EDURE)?\s+\[?\w+\]?\.\[?([A-Za-z]\w*)\]?/gim;
    for (const mm of decoded.matchAll(rx)) {
      const name = mm[1];
      if (!verbs.some((v) => name.toLowerCase().startsWith(String(v).toLowerCase()))) {
        warnings.push(`[SQL] SP '${name}' no empieza por un verbo permitido (database.naming.allowedVerbs): ${verbs.slice(0, 8).join(', ')}${verbs.length > 8 ? ', ...' : ''}`);
      }
    }
  }

  // 3. CREATE PROCEDURE sin schema (solo nombre)
  //    Fix vs .ps1 v1.1.0: el original hacia falso positivo con schemas terminados en "as"
  //    (ej. 'ventas.ObtenerPedido' -> el AS\b case-insensitive mordia el final de 'ventas').
  //    El lookahead (?![.\[\]\w]) exige fin de identificador: si sigue '.', '[', ']' o letra,
  //    hay schema (incluir ']' evita el falso positivo por backtracking con [schema].[Nombre]).
  {
    const rx = /CREATE\s+(?:OR\s+ALTER\s+)?PROC(?:EDURE)?\s+\[?\w+\]?(?![.\[\]\w])/gim;
    for (const mm of decoded.matchAll(rx)) {
      if (!/\.\w/.test(mm[0])) {
        warnings.push(`[SQL] CREATE PROCEDURE sin schema (usar 'schema.Name'): ${mm[0].substring(0, 80).trim()}`);
      }
    }
  }

  // 4. CREATE FUNCTION sin prefijo de funcion configurado
  {
    const rx = /CREATE\s+(?:OR\s+ALTER\s+)?FUNCTION\s+\[?\w+\]?\.\[?(\w+)\]?\s*\(/gim;
    for (const mm of decoded.matchAll(rx)) {
      const name = mm[1];
      if (!new RegExp(`^(${fnPref}_|${fntPref}_)`, 'i').test(name)) {
        warnings.push(`[SQL] CREATE FUNCTION sin prefijo '${fnPref}_' (escalar) o '${fntPref}_' (tabla): ${mm[0].trim()}`);
      }
    }
  }

  // 5. Prefijos de funcion cruzados (escalar con fnt_ / tabla con fn_)
  {
    const rx = new RegExp(String.raw`CREATE\s+(?:OR\s+ALTER\s+)?FUNCTION\s+\[?\w+\]?\.\[?(${fnPref}_|${fntPref}_)(\w+)\]?\s*\([^)]*\)\s*RETURNS\s+(TABLE|\w+)`, 'gis');
    for (const mm of decoded.matchAll(rx)) {
      const prefix = mm[1].toLowerCase();
      const returns = mm[3].toUpperCase();
      if (prefix === `${fnPref}_` && returns === 'TABLE') {
        warnings.push(`[SQL] Funcion tabla (RETURNS TABLE) debe usar prefijo '${fntPref}_', no '${fnPref}_': ${mm[0].substring(0, 80).trim()}`);
      }
      if (prefix === `${fntPref}_` && returns !== 'TABLE') {
        warnings.push(`[SQL] Funcion escalar debe usar prefijo '${fnPref}_', no '${fntPref}_': ${mm[0].substring(0, 80).trim()}`);
      }
    }
  }

  // 6. CREATE VIEW sin prefijo configurado
  {
    const rx = /CREATE\s+(?:OR\s+ALTER\s+)?VIEW\s+\[?\w+\]?\.\[?(\w+)\]?\b/gim;
    for (const mm of decoded.matchAll(rx)) {
      if (!new RegExp(`^${vwPref}_`, 'i').test(mm[1])) {
        warnings.push(`[SQL] CREATE VIEW sin prefijo '${vwPref}_': ${mm[0].trim()}`);
      }
    }
  }

  // 7. CREATE TRIGGER sin prefijo configurado
  {
    const rx = /CREATE\s+(?:OR\s+ALTER\s+)?TRIGGER\s+\[?\w+\]?\.\[?(\w+)\]?\b/gim;
    for (const mm of decoded.matchAll(rx)) {
      if (!new RegExp(`^${trPref}_`, 'i').test(mm[1])) {
        warnings.push(`[SQL] CREATE TRIGGER sin prefijo '${trPref}_': ${mm[0].trim()}`);
      }
    }
  }

  // 8. Prefijos legacy custom en SPs NUEVOS (database.naming.legacyPrefixes; vacio = check off)
  //    Trampa: BD cross-schema con SPs legacy mayoritarios. NO imitar el patron vecino.
  const legAlt = alt(naming.legacyPrefixes);
  if (legAlt) {
    const rx = new RegExp(String.raw`CREATE\s+(?:OR\s+ALTER\s+)?PROC(?:EDURE)?\s+\[?\w+\]?\.\[?(${legAlt})_\w+\]?`, 'gim');
    for (const mm of decoded.matchAll(rx)) {
      const prefix = mm[1].toLowerCase();
      warnings.push(`[SQL] CREATE PROCEDURE con prefijo legacy custom '${prefix}_' en archivo NUEVO: ${mm[0].trim()}`);
      warnings.push(`       -> Trampa: NO imitar patron legacy de SPs vecinos. Aplicar la convencion: ${spPattern}`);
      warnings.push(`       -> Si es legacy intencional, mover a Legacy/ o anadir a ${baselineRel}`);
    }
  }

  // --- Features por version (solo si database.version esta fijada — ADR-F001) ---
  const engine = String(cfgLib.get(cfg, 'database.engine', 'sqlserver')).toLowerCase();
  const version = cfgLib.get(cfg, 'database.version', null);
  const verNum = version ? parseInt(String(version), 10) : NaN;
  if (engine === 'sqlserver' && !Number.isNaN(verNum)) {
    const tag = `[SQL-${verNum}]`;
    if (verNum < 2022) {
      if (/GENERATE_SERIES\s*\(/i.test(decoded)) warnings.push(`${tag} GENERATE_SERIES es SQL Server 2022+. Usar CTE recursivo o tabla de numeros.`);
      if (/IS\s+(NOT\s+)?DISTINCT\s+FROM/i.test(decoded)) warnings.push(`${tag} IS [NOT] DISTINCT FROM es 2022+. Usar '((a = b) OR (a IS NULL AND b IS NULL))'.`);
      if (/\bDATE_BUCKET\s*\(/i.test(decoded)) warnings.push(`${tag} DATE_BUCKET es 2022+. Usar aritmetica con DATEADD/DATEDIFF.`);
      if (/\b(GREATEST|LEAST)\s*\(/i.test(decoded)) warnings.push(`${tag} GREATEST/LEAST son 2022+. Usar CASE WHEN o subquery con VALUES.`);
      if (/STRING_SPLIT\s*\([^)]+,\s*[^,)]+,\s*1\s*\)/i.test(decoded)) warnings.push(`${tag} STRING_SPLIT con 3er parametro (enable_ordinal) es 2022+.`);
    }
    if (verNum < 2019 && /_UTF8\b/i.test(decoded)) {
      warnings.push(`${tag} Collations _UTF8 son 2019+. Usar collations clasicas SQL_Latin1_General_*.`);
    }
  }

  // --- Emitir warnings ---
  if (warnings.length === 0) process.exit(0);

  const mode = cfgLib.resolvePolicy(cfg, 'sql-nomenclatura-guard');
  const e = console.error;
  e('');
  e('+----------------------------------------------------------------+');
  e(`| sql-nomenclatura-guard: ${warnings.length} violacion(es) detectada(s)`);
  e('+----------------------------------------------------------------+');
  for (const w of warnings) e(`  - ${w}`);
  e('');
  e('Referencia: CLAUDE_BASE.md seccion 8.1 / rules/database.md');
  e(`Patron OK:  CREATE PROCEDURE ${spPattern}`);
  e(`            CREATE FUNCTION {schema}.${fnPref}_{Descr}  |  ${fntPref}_ para TVF`);
  e(`            CREATE VIEW      {schema}.${vwPref}_{Descr}`);
  e('Excepcion:  Legacy/, Obsoleto/, MigracionPendiente/, -- LEGACY: no renombrar');
  e(`            o ruta listada en ${baselineRel}`);
  e('Scope:      .sql/.sqlproj/.tsql + 03_Desarrollo/SQL/, Scripts/, Database/, Deploy/');
  e(`Politica:   ${mode} (ecosystem.config hooks.policy)`);
  e('');

  process.exit(mode === 'block' ? 2 : 1);
} catch (err) {
  console.error(`sql-nomenclatura-guard.js: error inesperado, permitiendo operacion. Detalle: ${err.message}`);
  process.exit(0);
}
