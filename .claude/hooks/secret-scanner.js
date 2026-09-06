#!/usr/bin/env node
// secret-scanner.js - Detectar secrets/credenciales antes de escribir
// Evento: PreToolUse[Write|Edit]
// Exit 0 = sin hallazgos · Exit 1 = AVISO (politica warn) · Exit 2 = BLOCK (politica block)
// Version: 1.0.0-node (port de secret-scanner.ps1 v2.0.0, ADR-F006)
//   WARN-first: resolvePolicy(cfg, 'secret-scanner') decide exit 1 (warn, default) o
//   exit 2 (block) segun ecosystem.config -> hooks.policy / hooks.blockList.
//   Mismos patrones y mensajes que el .ps1:
//     - deteccion generica: connection strings, API keys, bearer tokens, Azure Storage
//       keys, passwords en string literal.
//     - tokens hardcoded en bloques mcpServers de .mcp.json, ~/.claude.json y
//       .claude/settings*.json (GitHub PAT, Atlassian, Anthropic, claves
//       _TOKEN/_KEY/_SECRET sin placeholder ${env:...}).

'use strict';

const h = require('./lib/helpers');
const cfgLib = require('./lib/config');

function main() {
  const hookData = h.readHookInput();
  const toolInput = h.getToolInput(hookData);
  if (!toolInput) return 0;

  // Extraer contenido nuevo (new_string para Edit, content para Write)
  let content = null;
  let m = toolInput.match(/"new_string"\s*:\s*"((?:[^"\\]|\\.)*)"/);
  if (m) {
    content = m[1];
  } else {
    m = toolInput.match(/"content"\s*:\s*"((?:[^"\\]|\\.)*)"/);
    if (m) content = m[1];
  }
  if (!content) return 0;

  // des-escapar secuencias JSON (\" -> ", \\ -> \, \n -> newline) — mismo orden que el .ps1
  // Necesario para que los patrones que buscan comillas literales (ej. "ghp_...") funcionen.
  content = content.replace(/\\n/g, '\n').replace(/\\"/g, '"').replace(/\\\\/g, '\\');

  // No escanear archivos de config de ejemplo o templates
  let filePath = '';
  m = toolInput.match(/"file_path"\s*:\s*"([^"]+)"/);
  if (m) filePath = m[1];
  if (/\.template$|\.example$|\.sample$|SKILL\.md$|README\.md$/i.test(filePath)) return 0;

  let warnings = 0;

  // === PATRONES DE SECRETS ===

  // Connection strings con password
  if (/Password\s*=\s*[^;]{3,}|pwd\s*=\s*[^;]{3,}/i.test(content) &&
      !/GetConnectionString|IOptions|configuration\[|builder\.Configuration/i.test(content)) {
    console.log('AVISO: Connection string con password detectada. Recomendado: Azure Key Vault o User Secrets.');
    warnings++;
  }

  // API Keys hardcoded
  if (/"(sk-[a-zA-Z0-9]{20,}|api[_-]?key[_-]?[=:]\s*['"][a-zA-Z0-9]{10,})"/i.test(content)) {
    console.log('AVISO: API key hardcoded detectada. Recomendado: configuracion o Key Vault.');
    warnings++;
  }

  // Bearer tokens
  if (/"Bearer\s+[a-zA-Z0-9\-._~+/]+=*"/i.test(content) && !/example|placeholder|test/i.test(content)) {
    console.log('AVISO: Bearer token hardcoded detectado.');
    warnings++;
  }

  // Azure Storage keys
  if (/AccountKey\s*=\s*[a-zA-Z0-9+/]{40,}/i.test(content)) {
    console.log('AVISO: Azure Storage key hardcoded. Recomendado: DefaultAzureCredential.');
    warnings++;
  }

  // Passwords en strings literales (alta confianza)
  if (/"password"\s*:\s*"[^"]{4,}"/i.test(content) && !/schema|example|placeholder|validation|error/i.test(content)) {
    console.log('AVISO: Password en string literal. Recomendado: configuracion segura.');
    warnings++;
  }

  // === MCP servers con secrets hardcoded en bloque env ===
  // Cubre .mcp.json (project), ~/.claude.json (user), .claude/settings*.json
  const isMcpConfig = /\.mcp\.json$|[/\\]\.claude\.json$|[/\\]claude\.json$|\.claude[/\\]settings(\.local)?\.json$/i.test(filePath);
  const mentionsMcpServers = /"mcpServers"\s*:/i.test(content);

  if (isMcpConfig || mentionsMcpServers) {
    // GitHub PAT clasico (ghp_) o fine-grained (github_pat_)
    if (/"(ghp_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{30,})"/i.test(content)) {
      console.log('AVISO: GitHub PAT hardcoded en config MCP. Recomendado: placeholder ${env:GITHUB_TOKEN} y setx en sesion.');
      warnings++;
    }
    // Atlassian API token en JIRA_API_TOKEN/ATLASSIAN_API_TOKEN/CONFLUENCE_API_TOKEN con valor literal
    // ([regex] en PS = case-sensitive; se respeta)
    const rxAtlassian = /"(JIRA|ATLASSIAN|CONFLUENCE)_API_TOKEN"\s*:\s*"((?!\$\{)[A-Za-z0-9]{20,})"/;
    if (rxAtlassian.test(content)) {
      console.log('AVISO: Atlassian/Jira/Confluence API token hardcoded en config MCP. Recomendado: ${env:JIRA_API_TOKEN}.');
      warnings++;
    }
    // Anthropic API key
    if (/"(sk-ant-[A-Za-z0-9_-]{40,})"/i.test(content)) {
      console.log('AVISO: Anthropic API key hardcoded en config MCP. Recomendado: ${env:ANTHROPIC_API_KEY}.');
      warnings++;
    }
    // Generic env block: cualquier clave _TOKEN/_KEY/_SECRET/_PASSWORD con valor literal (no placeholder)
    // Excluye: ${env:..}, {{var}}, <placeholder>, TODO, YOUR_*, PLACEHOLDER, EXAMPLE, SAMPLE, REPLACE_*
    // ([regex] en PS = case-sensitive; se respeta)
    const rxEnvLiteral = /"(\w*(?:TOKEN|KEY|SECRET|PASSWORD|PWD)\w*)"\s*:\s*"(?!\$\{|\{\{|<|TODO|YOUR_|PLACEHOLDER|EXAMPLE|SAMPLE|REPLACE_|XXX|---)([^"]{12,})"/g;
    let mm;
    while ((mm = rxEnvLiteral.exec(content)) !== null) {
      const envKey = mm[1];
      const valuePreview = mm[2].substring(0, Math.min(8, mm[2].length));
      console.log(`AVISO: Posible secret hardcoded en bloque MCP env (clave '${envKey}', valor empieza con '${valuePreview}...'). Recomendado: \${env:${envKey}}.`);
      warnings++;
    }
  }

  if (warnings > 0) {
    const policy = cfgLib.resolvePolicy(cfgLib.load(), 'secret-scanner');
    console.log('');
    console.log(`Se detectaron ${warnings} posible(s) secret(s) hardcoded. Politica de la organización:`);
    console.log(`  - politica: ${policy} (ecosystem.config hooks.policy)`);
    console.log('  - Recomendado migrar progresivamente a Azure Key Vault');
    console.log('  - Documentar en _hilo/DEUDA_TECNICA.md como SEC-XXX si no se migra ya');
    return policy === 'block' ? 2 : 1;
  }

  return 0;
}

try {
  process.exit(main());
} catch (e) {
  console.error(`secret-scanner: error inesperado (${e.message}) - no se bloquea el flujo`);
  process.exit(0);
}
