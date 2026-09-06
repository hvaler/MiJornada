#!/usr/bin/env node
// token-validation-guard.js - Verificar TokenValidationParameters
// Evento: PostToolUse[Write|Edit]
// Exit 0 = sin hallazgos · Exit 1 = AVISO (politica warn) · Exit 2 = BLOCK (politica block)
// Version: 1.0.0-node (port de token-validation-guard.ps1 v1.0.0, ADR-F006)
//   WARN-first: el .ps1 v1.0.0 salia siempre 0 (avisos informativos); en el port,
//   con hallazgos resolvePolicy(cfg, 'token-validation-guard') decide exit 1 (warn,
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

  // Solo actuar si hay TokenValidationParameters
  if (!/TokenValidationParameters/i.test(content)) return 0;

  let warnings = 0;

  // === CHECKLIST TOKEN VALIDATION ===

  // ValidateIssuer
  if (/ValidateIssuer\s*=\s*false/i.test(content)) {
    console.log('SEGURIDAD: ValidateIssuer=false. Cualquier emisor seria aceptado.');
    warnings++;
  }

  // ValidateAudience
  if (/ValidateAudience\s*=\s*false/i.test(content)) {
    console.log('SEGURIDAD: ValidateAudience=false. Tokens para otras apps serian aceptados.');
    warnings++;
  }

  // ValidateLifetime
  if (/ValidateLifetime\s*=\s*false/i.test(content)) {
    console.log('SEGURIDAD: ValidateLifetime=false. Tokens expirados serian aceptados.');
    warnings++;
  }

  // ValidateIssuerSigningKey
  if (/ValidateIssuerSigningKey\s*=\s*false/i.test(content)) {
    console.log('SEGURIDAD: ValidateIssuerSigningKey=false. Tokens sin firma valida serian aceptados.');
    warnings++;
  }

  // RequireExpirationTime
  if (/RequireExpirationTime\s*=\s*false/i.test(content)) {
    console.log('SEGURIDAD: RequireExpirationTime=false. Tokens sin expiracion serian aceptados.');
    warnings++;
  }

  // Algoritmos inseguros
  if (/SecurityAlgorithms\.(HmacSha256|None)|"none"|"HS256"/i.test(content)) {
    if (/"none"/i.test(content) || /SecurityAlgorithms\.None/i.test(content)) {
      console.log("SEGURIDAD CRITICA: Algoritmo 'none' detectado. Tokens sin firma serian aceptados.");
      warnings++;
    }
  }

  // ClockSkew excesivo
  if (/ClockSkew\s*=\s*TimeSpan\.MaxValue|ClockSkew\s*=\s*TimeSpan\.FromHours/i.test(content)) {
    console.log('SEGURIDAD: ClockSkew excesivo. Maximo recomendado: 5 minutos.');
    warnings++;
  }

  if (warnings > 0) {
    const policy = cfgLib.resolvePolicy(cfgLib.load(), 'token-validation-guard');
    console.log('');
    console.log(`Se detectaron ${warnings} problema(s) en TokenValidationParameters.`);
    console.log('Referencia: Estandar del ecosistema - IdP con validacion completa obligatoria.');
    console.log('Checklist: ValidateIssuer=true, ValidateAudience=true, ValidateLifetime=true,');
    console.log('           ValidateIssuerSigningKey=true, ClockSkew<=5min.');
    console.log(`Politica: ${policy} (ecosystem.config hooks.policy)`);
    return policy === 'block' ? 2 : 1;
  }

  return 0;
}

try {
  process.exit(main());
} catch (e) {
  console.error(`token-validation-guard: error inesperado (${e.message}) - no se bloquea el flujo`);
  process.exit(0);
}
