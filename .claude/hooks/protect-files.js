// protect-files.js - Bloquear escritura en archivos protegidos
// Evento: PreToolUse[Write|Edit]
// Exit 2 = bloquear (certs/keys, dano irreversible), Exit 1 = AVISO (configs PROD), Exit 0 = permitir.
// Version: 1.0.0-node (port de protect-files.ps1 v1.1.0, ADR-F006)
// Historial del original (condensado):
//   v1.1.0 (Ovillo v3.9.0 hotfix #28): politica WARN-first selectiva — certs (.pfx/.key/.pem/.p12/
//     .cer/.crt) siguen BLOCK (editar private key destruye el cert, dano irreversible); configs de
//     PROD pasan a WARN (los devs si las editan legitimamente). Mensajes via stderr para visibilidad
//     en Claude Code. v1.0.0 (v3.8.0): todos los archivos sensibles bloqueados.
//
// Politica (ADR-F000/F001): la parte de certificados/keys es BLOCK INTRINSECO (resolvePolicy con
// intrinsicBlock:true — siempre exit 2); la parte de configs PROD es WARN-first configurable
// (hooks.policy / hooks.blockList en ecosystem.config.json).

'use strict';

const path = require('path');
const h = require('./lib/helpers');
const config = require('./lib/config');

try {
  const hookData = h.readHookInput();
  const toolInput = h.getToolInput(hookData);
  if (!toolInput) process.exit(0);

  // Helper: emitir mensaje por stderr (visible para Claude Code)
  const aviso = (msg) => console.error(msg);

  // Extraer file_path del input
  const filePath = h.getFilePath(hookData);
  if (!filePath) process.exit(0);

  // path.win32.basename maneja / y \ (equivalente a Split-Path -Leaf en Windows)
  const fileName = path.win32.basename(filePath);
  const extension = path.extname(fileName).toLowerCase();
  const fileNameLower = fileName.toLowerCase();

  const cfg = config.load();

  // === BLOCK ESTRICTO (dano irreversible) ===

  // Certificados y claves privadas: editar = destruir. Renovar via CA, NO modificar.
  const blockedExtensions = ['.pfx', '.key', '.pem', '.p12', '.cer', '.crt'];
  if (blockedExtensions.includes(extension)) {
    const modeCerts = config.resolvePolicy(cfg, 'protect-files', { intrinsicBlock: true }); // siempre 'block'
    aviso(`BLOQUEADO: No se permite escribir archivos de certificado/clave (${fileName})`);
    aviso('  Razon: editar private key destruye el cert. Renovar con CA, NO modificar.');
    aviso('  Si necesitas crear un cert NUEVO: hacerlo fuera de Claude (openssl, certmgr, etc.)');
    process.exit(modeCerts === 'block' ? 2 : 1); // intrinseco: siempre 2
  }

  // === WARN (configs PROD - se editan legitimamente pero con cuidado) ===

  // Archivos de produccion sensibles (comparacion case-insensitive, como -contains en PS)
  const warnProdFiles = [
    'Production.json',
    'appsettings.Production.json',
    'appsettings.Staging.json',
    'web.Production.config',
  ];
  if (warnProdFiles.some((f) => f.toLowerCase() === fileNameLower)) {
    const mode = config.resolvePolicy(cfg, 'protect-files'); // WARN-first configurable
    const prefijo = mode === 'block' ? 'BLOQUEADO' : 'AVISO';
    aviso(`${prefijo}: Editando configuracion de PRODUCCION (${fileName}).`);
    aviso('  Verifica:');
    aviso('    1. El cambio es realmente necesario en PROD ya, o puede esperar a develop primero?');
    aviso('    2. Tienes backup del archivo original (commit anterior en git)?');
    aviso('    3. Has revisado con el JP/responsable tecnico antes de desplegar?');
    aviso('  Politica de la organización WARN-first: edit permitido, decision del dev.');
    process.exit(mode === 'block' ? 2 : 1);
  }

  // === AVISOS INFORMATIVOS (no bloquean ni hacen exit 1, solo informan) ===

  // Connection strings en appsettings
  if (/^appsettings.*\.json$/i.test(fileName) && /(Password|pwd|Server=|Data Source)/i.test(toolInput)) {
    aviso(`AVISO: Posible connection string en ${fileName}. Usa Azure Key Vault para produccion.`);
  }

  // .env files
  if (/^\.env/i.test(fileName)) {
    aviso(`AVISO: Archivo .env detectado (${fileName}). Verifica que esta en .gitignore.`);
  }

  // Archivos de configuracion critica
  const warnFiles = ['global.json', 'Directory.Build.props', 'Directory.Packages.props', 'NuGet.Config'];
  if (warnFiles.some((f) => f.toLowerCase() === fileNameLower)) {
    aviso(`AVISO: Modificando archivo de configuracion critica (${fileName}).`);
  }

  process.exit(0);
} catch (e) {
  // Error inesperado: permitir operacion en lugar de romper el flujo.
  console.error(`protect-files.js: error inesperado, permitiendo operacion. Detalle: ${e && e.message ? e.message : e}`);
  process.exit(0);
}
