// bash-guard.js - Bloquear operaciones destructivas
// Evento: PreToolUse[Bash]. Exit 2 = bloquear, Exit 0 = permitir.
// Version: 1.0.0-node (port de bash-guard.ps1 v2.1.0, ADR-F006)
// Historial del original (condensado):
//   v2.1.0 (Ovillo v3.12.0-h2): safeTargets incluye .git/*.lock (FB-001: borrar un index.lock/HEAD.lock
//     huerfano que deja Visual Studio NO es destructivo).
//   v2.0.0 (v3.9.0): try/catch global, git restore ., branch -D, --no-verify, stash drop/clear, SQL DROP
//     ampliado, --force-with-lease NO bloqueado, word boundaries. v1.0.0 (v3.8.0): 7 patrones basicos.
//
// Politica (ADR-F000/F001): BLOCK INTRINSECO — resolvePolicy con intrinsicBlock:true devuelve
// 'block' incondicionalmente (operaciones destructivas irreversibles, no degradable a WARN).

'use strict';

const h = require('./lib/helpers');
const config = require('./lib/config');

// --- Wrapper de seguridad -----------------------------------------
// Cualquier excepcion no controlada -> exit 0 (permitir) + log a stderr.
// Mejor un falso negativo silencioso que un hook que rompe el flujo.
try {
  const hookData = h.readHookInput();
  const command = h.getToolInput(hookData);
  if (!command) process.exit(0);

  const mode = config.resolvePolicy(config.load(), 'bash-guard', { intrinsicBlock: true }); // siempre 'block'
  const EXIT_BLOCK = mode === 'block' ? 2 : 1; // intrinseco: siempre 2

  // -- Operaciones git destructivas ----------------------------------

  // --force-with-lease es SEGURO (chequea remoto antes de sobrescribir).
  // Solo bloquear --force / -f puros.
  if (/\bgit\s+push\b/i.test(command) &&
      /(\B--force\b|\B-f\b)/i.test(command) &&
      !/--force-with-lease/i.test(command)) {
    console.log('BLOQUEADO: git push --force/-f. Usa --force-with-lease (mas seguro) o un push normal.');
    process.exit(EXIT_BLOCK);
  }

  if (/\bgit\s+reset\s+--hard\b/i.test(command)) {
    console.log('BLOQUEADO: git reset --hard descartara todos los cambios no committeados.');
    process.exit(EXIT_BLOCK);
  }

  if (/\bgit\s+clean\s+-[a-zA-Z]*f/i.test(command)) {
    console.log('BLOQUEADO: git clean -f eliminara archivos no rastreados permanentemente.');
    process.exit(EXIT_BLOCK);
  }

  // v2.0.0: cubre legacy 'git checkout .' y moderno 'git restore .'
  if (/\bgit\s+(checkout|restore)\s+\.\B/i.test(command)) {
    console.log('BLOQUEADO: descartara todos los cambios sin stage (git checkout/restore .).');
    process.exit(EXIT_BLOCK);
  }

  // v2.0.0: git branch -D / --delete --force borra rama sin garantia de merge.
  // Case-sensitive (sin /i, como -cmatch) para distinguir -D (force) de -d (safe).
  if (/\bgit\s+branch\s+-D\b/.test(command) ||
      /\bgit\s+branch\s+--delete\s+--force\b/i.test(command)) {
    console.log('BLOQUEADO: git branch -D borra una rama sin garantia de merge. Usa -d en su lugar.');
    process.exit(EXIT_BLOCK);
  }

  // v2.0.0: --no-verify saltea pre-commit/pre-push hooks (red flag)
  if (/\bgit\s+(commit|push|merge|rebase)\b.*--no-verify\b/i.test(command)) {
    console.log('BLOQUEADO: --no-verify saltea hooks defensivos. Si fallan, arregla la causa raiz.');
    process.exit(EXIT_BLOCK);
  }

  // v2.0.0: git stash drop/clear elimina stashes sin recuperacion
  if (/\bgit\s+stash\s+(drop|clear)\b/i.test(command)) {
    console.log('BLOQUEADO: git stash drop/clear elimina stashes sin posibilidad de recuperar.');
    process.exit(EXIT_BLOCK);
  }

  // -- Eliminacion recursiva peligrosa -------------------------------
  // Cubre: rm -rf, rm -fr, rm --recursive --force, Remove-Item -Recurse -Force
  const rmDestructive = /\brm\s+-[a-zA-Z]*r[a-zA-Z]*f\b|\brm\s+-[a-zA-Z]*f[a-zA-Z]*r\b|\brm\s+--recursive\b.*--force\b|Remove-Item.*-Recurse.*-Force/i;
  if (rmDestructive.test(command)) {
    // Permitir en targets seguros (carpetas de build/cache/IDE + locks git huerfanos)
    // FB-001: .git/*.lock (index.lock, HEAD.lock) que deja Visual Studio NO es destructivo borrarlo.
    const safeTargets = /(node_modules|bin[\\/]|obj[\\/]|TestResults|\.vs|packages[\\/]|\.next|dist[\\/]|coverage[\\/]|out[\\/]|\.git[\\/][^ "']*\.lock)/i;
    if (!safeTargets.test(command)) {
      console.log('BLOQUEADO: Eliminacion recursiva forzada detectada. Verifica el path.');
      process.exit(EXIT_BLOCK);
    }
  }

  // -- Operaciones SQL destructivas ----------------------------------

  // v2.0.0: DROP ampliado a 8 tipos de objetos
  if (/\bDROP\s+(TABLE|DATABASE|SCHEMA|COLUMN|CONSTRAINT|INDEX|VIEW|PROCEDURE|FUNCTION|TRIGGER)\b/i.test(command)) {
    console.log('BLOQUEADO: Operacion SQL DROP destructiva detectada. Verifica scope y backup.');
    process.exit(EXIT_BLOCK);
  }

  if (/\bTRUNCATE\s+TABLE\b/i.test(command)) {
    console.log('BLOQUEADO: TRUNCATE TABLE no es transaccional y borra todos los datos.');
    process.exit(EXIT_BLOCK);
  }

  // DELETE FROM sin WHERE. Negative lookahead: bloquear si NO va seguido de WHERE.
  // Cubre tanto 'DELETE FROM T' final como 'DELETE FROM T;' o dentro de quotes.
  if (/\bDELETE\s+FROM\s+\w+\b(?!\s+WHERE\b)/i.test(command)) {
    console.log('BLOQUEADO: DELETE FROM sin WHERE detectado. Anade clausula WHERE.');
    process.exit(EXIT_BLOCK);
  }

  // v2.0.0: ALTER TABLE ... DROP COLUMN/CONSTRAINT
  if (/\bALTER\s+TABLE\s+\w+.*\bDROP\s+(COLUMN|CONSTRAINT)\b/i.test(command)) {
    console.log('BLOQUEADO: ALTER TABLE...DROP destructivo detectado. Verifica scope.');
    process.exit(EXIT_BLOCK);
  }

  // -- Proteccion de archivos sensibles ---------------------
  if (/\.(pfx|key|pem|p12)\b/i.test(command)) {
    if (/\b(rm|del|Remove-Item|move|mv)\b/i.test(command)) {
      console.log('BLOQUEADO: Operacion destructiva sobre certificado/clave privada detectada.');
      process.exit(EXIT_BLOCK);
    }
  }

  // -- Advertencia dotnet run (no bloquea) ---------------------------
  if (/\bdotnet\s+run\b/i.test(command)) {
    console.log('AVISO: dotnet run detectado. Verifica que launchSettings.json existe y el perfil es correcto.');
  }

  process.exit(0);
} catch (e) {
  // Error inesperado: permitir operacion en lugar de romper el flujo.
  // Log a stderr para diagnostico (no interfiere con exit 0).
  console.error(`bash-guard.js: error inesperado, permitiendo operacion. Detalle: ${e && e.message ? e.message : e}`);
  process.exit(0);
}
