// antipattern-guard.js - Detectar anti-patrones .NET en archivos staged
// Evento: PreToolUse[Bash] (cuando el comando es git commit)
// Exit 1 = AVISO informativo (no bloquea commit), Exit 0 = sin hallazgos.
// Version: 1.0.0-node (port de antipattern-guard.ps1 v2.0.0, ADR-F006)
// Historial del original (condensado):
//   v2.0.0 (Ovillo v3.9.0): politica WARN-first — todos los ERROR pasan a AVISO/exit 1; mensajes via
//     stderr (Write-Host no surfaceaba en Claude Code); escanea contenido COMPLETO de staged, no solo diff.
//   v1.0.1 (v3.8.7): GIT_OPTIONAL_LOCKS=0 (colisiones index.lock con IDE). v1.0.0: 7 antipatrones .NET.
// Detecta: DateTime.Now, new HttpClient(), async void, .Result, sync-over-async,
//          catch generico, string interpolation en logs, connection strings hardcoded.
//
// Politica (ADR-F000/F001): WARN-first configurable — resolvePolicy(cfg, 'antipattern-guard');
// exit 2 (prefijo BLOQUEADO) solo si hooks.policy='block' o hooks.blockList lo incluye.

'use strict';

const fs = require('fs');
const h = require('./lib/helpers');
const config = require('./lib/config');

try {
  const hookData = h.readHookInput();
  const command = h.getToolInput(hookData);
  if (!command) process.exit(0);

  // Solo actuar cuando el comando es git commit
  if (!/git\s+commit/i.test(command)) process.exit(0);

  // Obtener archivos .cs en staging (GIT_OPTIONAL_LOCKS=0 via gitReadOnly: sin lock,
  // no colisiona con VS Code/IDE)
  const diff = h.gitReadOnly(['diff', '--cached', '--name-only', '--diff-filter=ACM']);
  if (diff.exitCode !== 0) process.exit(0);
  const stagedFiles = diff.stdOut.split(/\r?\n/).filter(Boolean).filter((f) => /\.cs$/i.test(f));

  if (stagedFiles.length === 0) process.exit(0);

  const mode = config.resolvePolicy(config.load(), 'antipattern-guard'); // WARN-first (default 'warn')
  const prefijo = mode === 'block' ? 'BLOQUEADO' : 'AVISO';

  // Helper: emitir aviso por stderr (visible para Claude Code)
  const aviso = (msg) => console.error(msg);

  aviso(`Verificando ${stagedFiles.length} archivo(s) C# en staging...`);

  let warnings = 0;

  for (const file of stagedFiles) {
    if (!fs.existsSync(file)) continue;
    let content = null;
    try {
      content = fs.readFileSync(file, 'utf8');
    } catch {
      continue;
    }
    if (!content) continue;
    const lines = content.split(/\r?\n/);

    let lineNum = 0;
    for (const line of lines) {
      lineNum++;

      // AP001: async void (excepto event handlers)
      if (/async\s+void/i.test(line) && !/EventArgs/i.test(line)) {
        aviso(`${prefijo} ${file}:${lineNum} - async void detectado. Recomendado: async Task.`);
        warnings++;
      }

      // AP002: .Result o .GetAwaiter().GetResult() (sync-over-async)
      if (/\.Result\b/i.test(line) || /\.GetAwaiter\(\)\.GetResult\(\)/i.test(line)) {
        aviso(`${prefijo} ${file}:${lineNum} - sync-over-async (.Result / .GetAwaiter().GetResult())`);
        warnings++;
      }

      // AP003: new HttpClient() (socket exhaustion)
      if (/new\s+HttpClient\s*\(/i.test(line)) {
        aviso(`${prefijo} ${file}:${lineNum} - new HttpClient(). Recomendado: IHttpClientFactory.`);
        warnings++;
      }

      // AP004: DateTime.Now / DateTime.UtcNow (untestable)
      if (/DateTime\.(Now|UtcNow)/i.test(line)) {
        aviso(`${prefijo} ${file}:${lineNum} - DateTime.Now/UtcNow. Recomendado: TimeProvider.`);
        warnings++;
      }

      // AP005: catch(Exception) broad catch
      if (/catch\s*\(\s*Exception\s*\)/i.test(line) || /catch\s*\(\s*Exception\s+\w+\s*\)/i.test(line)) {
        aviso(`${prefijo} ${file}:${lineNum} - catch(Exception) generico. Recomendado: capturar excepciones especificas.`);
        warnings++;
      }

      // AP006: String interpolation en logging
      if (/Log(Information|Warning|Error|Debug|Critical)\s*\(\s*\$"/i.test(line)) {
        aviso(`${prefijo} ${file}:${lineNum} - Interpolacion en log. Recomendado: template "Msg {Param}", value`);
        warnings++;
      }

      // COMILLAS: Connection string hardcoded
      if (/(Server|Data Source|Initial Catalog|Password)\s*=/i.test(line) &&
          !/(appsettings|configuration|IOptions|GetConnectionString)/i.test(line)) {
        if (/"[^"]*Server\s*=/i.test(line)) {
          aviso(`${prefijo} ${file}:${lineNum} - Connection string hardcoded. Recomendado: appsettings + Key Vault.`);
          warnings++;
        }
      }
    }
  }

  if (warnings > 0) {
    aviso('');
    aviso(`Se encontraron ${warnings} posible(s) antipatron(es) en archivos staged. Politica de la organización:`);
    aviso('  - Entorno seguro y deuda tecnica progresiva - NO bloqueante actualmente');
    aviso('  - El hook escanea contenido completo del archivo, no solo el diff.');
    aviso('    Un refactor sobre archivo con .Result/DateTime.Now/etc legacy lo dispara.');
    aviso('  - Si el antipatron es NUEVO (introducido por este commit): corregirlo.');
    aviso('  - Si es legacy preexistente: documentar en _hilo/DEUDA_TECNICA.md como DT-XXX.');
    aviso('  - Si Sistemas decide enforcement: hook bumpea a v3.0.0 con exit 2');
    process.exit(mode === 'block' ? 2 : 1); // exit 1 = AVISO informativo, patron WARN-first
  }

  aviso('OK: Verificacion de anti-patrones completada (0 hallazgos).');
  process.exit(0);
} catch (e) {
  // Error inesperado: permitir operacion en lugar de romper el flujo.
  console.error(`antipattern-guard.js: error inesperado, permitiendo operacion. Detalle: ${e && e.message ? e.message : e}`);
  process.exit(0);
}
