// post-build-check.js - Verificar resultado de build/test tras ejecucion
// Evento: PostToolUse[Bash] · Exit 0 = siempre (informativo, no bloquea)
// Version: 1.0.0-node (port de post-build-check.ps1 v1.0.0, ADR-F006)

'use strict';

const path = require('path');
const h = require(path.join(__dirname, 'lib', 'helpers'));

try {
  const hookData = h.readHookInput();
  const command = h.getToolInput(hookData);
  if (!command) process.exit(0);

  const output = h.getToolOutput(hookData) || '';

  if (!/dotnet\s+(build|test|publish)/i.test(command)) process.exit(0);

  if (/dotnet\s+build/i.test(command)) {
    if (/Build succeeded/i.test(output)) {
      // Silencioso en exito
    } else if (/Build FAILED|error CS\d{4}/i.test(output)) {
      const errorCount = (output.match(/error CS\d{4}/gi) || []).length;
      console.log(`BUILD FALLIDO: ${errorCount} error(es) detectado(s). Revisar antes de continuar.`);
    }

    const warningCount = (output.match(/warning CS\d{4}/gi) || []).length;
    if (warningCount > 10) {
      console.log(`AVISO: ${warningCount} warnings en build. Considerar ejecutar /clean para limpiar.`);
    }
  }

  if (/dotnet\s+test/i.test(command)) {
    const failed = output.match(/Failed!\s+.*Failed:\s*(\d+)/i);
    if (failed) {
      console.log(`TESTS FALLIDOS: ${failed[1]} test(s) fallido(s). Revisar antes de commit.`);
    } else if (/No test is available/i.test(output)) {
      console.log('AVISO: No se encontraron tests en el proyecto.');
    }
  }

  if (/dotnet\s+publish/i.test(command)) {
    if (/error/i.test(output)) {
      console.log('PUBLISH FALLIDO: Errores detectados en la publicacion.');
    }
  }

  process.exit(0);
} catch (err) {
  console.error(`post-build-check.js: error inesperado, continuando. Detalle: ${err.message}`);
  process.exit(0);
}
