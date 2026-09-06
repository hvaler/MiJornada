#!/usr/bin/env node
// auth-config-guard.js - Validar configuracion de autenticacion (Azure AD + providers extensibles)
// Evento: PreToolUse[Write|Edit]
// Exit 0 = sin hallazgos · Exit 1 = AVISO (politica warn) · Exit 2 = BLOCK (politica block)
// Version: 1.0.0-node (port de auth-config-guard.ps1 v2.1.0, ADR-F006)
//   WARN-first: resolvePolicy(cfg, 'auth-config-guard') decide exit 1 (warn, default) o
//   exit 2 (block) segun ecosystem.config -> hooks.policy / hooks.blockList.
//   Mensajes via stderr (console.error) para que Claude Code los surface correctamente.
//   Reglas Azure AD hardcoded + reglas extensibles via _hilo/oauth-providers.json
//   (template: Documentos_Base/01_Estructura_Tecnica/OAUTH_PROVIDERS_TEMPLATE.json).
//   Si no existe el archivo de providers, el hook funciona solo con las reglas Azure AD.

'use strict';

const fs = require('fs');
const path = require('path');
const h = require('./lib/helpers');
const cfgLib = require('./lib/config');

// Emitir aviso por stderr (visible para Claude Code)
function aviso(msg) {
  console.error(msg);
}

function main() {
  const hookData = h.readHookInput();
  if (!hookData) return 0;

  // Solo archivos de configuracion y Program.cs/Startup.cs
  const filePath = h.getFilePath(hookData);
  if (!filePath) return 0;
  if (!/appsettings.*\.json$|Program\.cs$|Startup\.cs$|\.cs$/i.test(filePath)) return 0;

  // Extraer contenido (decodificado si viene como objeto, escapado si viene como string)
  const content = h.getNewContent(hookData);
  if (!content) return 0;

  let errors = 0;
  let warnings = 0;

  // ==========================================================================
  // REGLAS AZURE AD HARDCODED (backwards compatible con v1.0.0 del .ps1)
  // ==========================================================================

  // TenantId debe ser GUID (no "common" ni "organizations" en produccion)
  let m = content.match(/"TenantId"\s*:\s*"(common|organizations|consumers)"/i);
  if (m) {
    aviso(`AVISO [AzureAd]: TenantId='${m[1]}' es inseguro. Usar GUID del tenant de la organización.`);
    errors++;
  }

  // Redirect URIs no deben tener wildcards
  if (/RedirectUri.*\*|CallbackPath.*\*|redirect_uri.*\*/i.test(content)) {
    aviso('AVISO [AzureAd]: Wildcard en redirect URI detectado. Usar URIs exactas.');
    errors++;
  }

  // Audience debe estar configurado
  if (/AzureAd|JwtBearer|AddMicrosoftIdentity/i.test(content)) {
    if (!/Audience|ValidAudience|ValidAudiences/i.test(content)) {
      aviso('AVISO [AzureAd]: Configuracion Azure AD sin Audience. Verificar que ValidateAudience=true.');
      warnings++;
    }
  }

  // ValidateIssuer/Audience/Lifetime deben ser true
  if (/ValidateIssuer\s*=\s*false/i.test(content)) {
    aviso('AVISO [AzureAd]: ValidateIssuer=false es inseguro. Debe ser true.');
    errors++;
  }
  if (/ValidateAudience\s*=\s*false/i.test(content)) {
    aviso('AVISO [AzureAd]: ValidateAudience=false es inseguro. Debe ser true.');
    errors++;
  }
  if (/ValidateLifetime\s*=\s*false/i.test(content)) {
    aviso('AVISO [AzureAd]: ValidateLifetime=false es inseguro. Tokens expirados serian aceptados.');
    errors++;
  }

  // ClockSkew excesivo (>5 min)
  m = content.match(/ClockSkew\s*=\s*TimeSpan\.From(Minutes|Hours)\s*\(\s*(\d+)/i);
  if (m) {
    const unit = m[1];
    const value = parseInt(m[2], 10);
    if (unit.toLowerCase() === 'hours' || (unit.toLowerCase() === 'minutes' && value > 5)) {
      aviso(`AVISO [AzureAd]: ClockSkew de ${value} ${unit} es excesivo. Maximo recomendado: 5 minutos.`);
      warnings++;
    }
  }

  // ==========================================================================
  // REGLAS EXTENSIBLES via _hilo/oauth-providers.json
  // ==========================================================================
  // Schema esperado:
  // {
  //   "providers": [
  //     {
  //       "name": "OracleCloud",
  //       "description": "Oracle HCM Cloud OAuth2",
  //       "rules": [
  //         { "pattern": "regex (escapado JSON)", "severity": "block"|"warn", "message": "..." }
  //       ]
  //     }
  //   ]
  // }
  // Si no existe el archivo, el hook funciona como v1.0.0 (solo Azure AD).
  // El consumidor lo crea opt-in para sus dominios (Oracle, Banner, Sigma, etc.).

  const repoRoot = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const providersFile = path.join(repoRoot, '_hilo', 'oauth-providers.json');

  if (fs.existsSync(providersFile)) {
    try {
      const providersConfig = JSON.parse(fs.readFileSync(providersFile, 'utf8'));
      if (providersConfig.providers) {
        for (const provider of providersConfig.providers) {
          if (!provider.name || !provider.rules) continue;

          for (const rule of provider.rules) {
            if (!rule.pattern || !rule.severity) continue;

            try {
              // PS -match es case-insensitive -> /i
              const mm = content.match(new RegExp(rule.pattern, 'i'));
              if (mm) {
                const msg = rule.message ? rule.message : 'Regla violada';
                const matchedText = mm[0];
                const matchedShort = matchedText.length > 60 ? matchedText.substring(0, 57) + '...' : matchedText;

                switch (String(rule.severity).toLowerCase()) {
                  case 'block':
                    aviso(`AVISO [${provider.name}]: ${msg}`);
                    aviso(`  Match: ${matchedShort}`);
                    errors++;
                    break;
                  case 'warn':
                    aviso(`AVISO [${provider.name}]: ${msg}`);
                    aviso(`  Match: ${matchedShort}`);
                    warnings++;
                    break;
                }
              }
            } catch {
              aviso(`AVISO [auth-config-guard]: regex invalida en provider '${provider.name}': ${rule.pattern}`);
            }
          }
        }
      }
    } catch (e) {
      aviso(`AVISO [auth-config-guard]: no se pudo parsear _hilo/oauth-providers.json: ${e.message}`);
    }
  }

  // ==========================================================================
  // RESULTADO
  // ==========================================================================

  if (errors > 0 || warnings > 0) {
    const policy = cfgLib.resolvePolicy(cfgLib.load(), 'auth-config-guard');
    const total = errors + warnings;
    console.error('');
    console.error(`Se detectaron ${total} posible(s) hallazgo(s) de configuracion auth. Politica de la organización:`);
    console.error(`  - politica: ${policy} (ecosystem.config hooks.policy): configs OAuth pueden tener providers legitimos no-AzureAD`);
    console.error('  - Estandar (identity.idp=entra): tenant especifico para apps internas');
    console.error('  - Providers extensibles: _hilo/oauth-providers.json (Banner, Sigma, EWP, etc.)');
    console.error('  - Si la auth es legitima no-AzureAD: documentar en _hilo/DECISIONES.md como ADR');
    return policy === 'block' ? 2 : 1;
  }

  return 0;
}

try {
  process.exit(main());
} catch (e) {
  console.error(`auth-config-guard: error inesperado (${e.message}) - no se bloquea el flujo`);
  process.exit(0);
}
