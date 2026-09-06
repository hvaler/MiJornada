// quality-alert.js - Alertar si muchos warnings o deuda tecnica
// Evento: PostToolUse[Bash] · Exit 0 = siempre (informativo)
// Version: 1.0.0-node (port de quality-alert.ps1 v1.0.0, ADR-F006)

'use strict';

const path = require('path');
const h = require(path.join(__dirname, 'lib', 'helpers'));

try {
  const hookData = h.readHookInput();
  const command = h.getToolInput(hookData);
  if (!command) process.exit(0);

  const output = h.getToolOutput(hookData) || '';

  if (!/dotnet\s+build/i.test(command)) process.exit(0);

  const count = (rx) => (output.match(rx) || []).length;
  const nullableWarnings = count(/warning CS86\d{2}/gi);
  const obsoleteWarnings = count(/warning CS0618|warning CS0619/gi);
  const analyzerWarnings = count(/warning IDE\d{4}|warning CA\d{4}/gi);
  const totalWarnings = count(/warning (CS|IDE|CA)\d{4}/gi);

  if (nullableWarnings > 20) {
    console.log(`CALIDAD: ${nullableWarnings} warnings de nullable reference types. Considerar activar <Nullable>enable</Nullable> y corregir.`);
  }
  if (obsoleteWarnings > 5) {
    console.log(`CALIDAD: ${obsoleteWarnings} APIs obsoletas detectadas. Planificar actualizacion.`);
  }
  if (analyzerWarnings > 15) {
    console.log(`CALIDAD: ${analyzerWarnings} warnings de analyzers. Ejecutar /clean para limpieza sistematica.`);
  }
  if (totalWarnings > 50) {
    console.log(`CALIDAD CRITICA: ${totalWarnings} warnings totales. El proyecto necesita una sesion de limpieza con /clean.`);
  }

  const todoCount = count(/TODO|HACK|FIXME/g);
  if (todoCount > 0) {
    console.log(`DEUDA TECNICA: ${todoCount} TODO/HACK/FIXME encontrados en output del build.`);
  }

  process.exit(0);
} catch (err) {
  console.error(`quality-alert.js: error inesperado, continuando. Detalle: ${err.message}`);
  process.exit(0);
}
