#!/usr/bin/env node
// sql-injection-guard.js - Detectar SQL inseguro en codigo C#
// Evento: PostToolUse[Write|Edit]
// Exit 0 = sin hallazgos · Exit 1 = AVISO (politica warn) · Exit 2 = BLOCK (politica block)
// Version: 1.0.0-node (port de sql-injection-guard.ps1 v1.0.0, ADR-F006)
//   WARN-first: el .ps1 v1.0.0 salia siempre 0 (avisos, el dev decide); en el port,
//   con hallazgos resolvePolicy(cfg, 'sql-injection-guard') decide exit 1 (warn,
//   default) o exit 2 (block) segun ecosystem.config -> hooks.policy / hooks.blockList.
//   Mismos patrones y mensajes que el .ps1 (los patrones se aplican sobre el contenido
//   JSON-escapado del tool_input, igual que el original).

'use strict';

const h = require('./lib/helpers');
const cfgLib = require('./lib/config');

function main() {
  const hookData = h.readHookInput();
  const toolInput = h.getToolInput(hookData);
  if (!toolInput) return 0;

  // Solo archivos .cs
  let filePath = '';
  let m = toolInput.match(/"file_path"\s*:\s*"([^"]+)"/);
  if (m) filePath = m[1];
  if (!/\.cs$/i.test(filePath)) return 0;

  // Extraer contenido (sin des-escapar, igual que el .ps1)
  let content = null;
  m = toolInput.match(/"new_string"\s*:\s*"((?:[^"\\]|\\.)*)"/);
  if (m) {
    content = m[1];
  } else {
    m = toolInput.match(/"content"\s*:\s*"((?:[^"\\]|\\.)*)"/);
    if (m) content = m[1];
  }
  if (!content) return 0;

  let warnings = 0;

  // === PATRONES SQL INSEGURO ===

  // FromSqlRaw con interpolacion de string
  if (/FromSqlRaw\s*\(\s*\$"/i.test(content) || /FromSqlRaw\s*\(\s*"[^"]*"\s*\+/i.test(content)) {
    console.log('SQL INJECTION: FromSqlRaw con interpolacion/concatenacion. Usar FromSqlInterpolated o parametros.');
    warnings++;
  }

  // ExecuteSqlRaw con interpolacion
  if (/ExecuteSqlRaw\s*\(\s*\$"/i.test(content) || /ExecuteSqlRaw\s*\(\s*"[^"]*"\s*\+/i.test(content)) {
    console.log('SQL INJECTION: ExecuteSqlRaw con interpolacion. Usar ExecuteSqlInterpolated.');
    warnings++;
  }

  // SqlCommand con concatenacion
  if (/SqlCommand\s*\(\s*"[^"]*"\s*\+/i.test(content) || /CommandText\s*=\s*"[^"]*"\s*\+/i.test(content)) {
    console.log('SQL INJECTION: SqlCommand con concatenacion de string. Usar SqlParameter.');
    warnings++;
  }

  // EXEC con concatenacion en string SQL
  if (/EXEC\s*\(\s*'[^']*'\s*\+|EXEC\s*\(\s*"[^"]*"\s*\+/i.test(content)) {
    console.log('SQL INJECTION: EXEC con concatenacion. Usar sp_executesql con parametros.');
    warnings++;
  }

  // string.Format en queries SQL
  if (/string\.Format\s*\(.*SELECT|string\.Format\s*\(.*INSERT|string\.Format\s*\(.*UPDATE|string\.Format\s*\(.*DELETE/i.test(content)) {
    console.log('SQL INJECTION: string.Format en query SQL. Usar parametros.');
    warnings++;
  }

  if (warnings > 0) {
    const policy = cfgLib.resolvePolicy(cfgLib.load(), 'sql-injection-guard');
    console.log('');
    console.log(`Se detectaron ${warnings} patron(es) de SQL injection potencial.`);
    console.log('Referencia: OWASP A03:2021 - Injection');
    console.log('Solucion: Usar siempre parametros (@param) o FromSqlInterpolated.');
    console.log(`Politica: ${policy} (ecosystem.config hooks.policy)`);
    return policy === 'block' ? 2 : 1;
  }

  return 0;
}

try {
  process.exit(main());
} catch (e) {
  console.error(`sql-injection-guard: error inesperado (${e.message}) - no se bloquea el flujo`);
  process.exit(0);
}
