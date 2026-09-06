// config.js - Lector de ecosystem.config.json para hooks Ovillo (ADR-F001/F006)
// Precedencia: ESTADO_PROYECTO.json (proyecto) > ecosystem.config.json (org) > DEFAULTS.
// Los hooks NUNCA fallan por ausencia de config: sin archivo -> defaults neutrales.

'use strict';

const fs = require('fs');
const path = require('path');

// Defaults neutrales — espejo de .claude/schemas/ecosystem.config.schema.json
const DEFAULTS = {
  organization: { name: '', shortName: '', namespacePrefix: 'MyCompany', supportEmail: '', language: 'es' },
  theme: { primaryColor: '#33475B', secondaryColor: '#5A6B7B', logoUrl: '' },
  cloud: { provider: 'none', secrets: 'dotenv', storage: 'filesystem', telemetry: 'otlp' },
  identity: { idp: 'none', authority: '', defaultRoles: ['Admin', 'Manager', 'User'] },
  database: {
    engine: 'sqlserver',
    version: null,
    naming: {
      storedProcedurePattern: '{schema}.{Verb}{Entity}',
      functionPrefix: 'fn_',
      tableFunctionPrefix: 'fnt_',
      viewPrefix: 'vw_',
      triggerPrefix: 'tr_',
      schemaCase: 'lowercase',
      legacySchemas: [],
      allowedVerbs: [],
      forbiddenPrefixes: ['usp_', 'sp_', 'pr_', 'proc_', 'pa_'],
      forbiddenSuffixes: [],
      legacyPrefixes: [],
      legacyBaselineFile: '.claude/sql-legacy-baseline.txt',
    },
  },
  vcs: { type: 'git', platform: 'github', defaultBranch: 'main', branchingStrategy: 'github-flow' },
  cicd: { platform: 'none', variant: '', deployModel: 'on-demand', environments: [] },
  integrations: [],
  hub: { enabled: false, url: '', auth: 'apikey', apiKeyHeader: 'X-Hub-Api-Key', registerOnInstall: false },
  distribution: { baseUrl: '', updateCheck: true },
  hooks: { policy: 'warn', blockList: [] },
  workflow: { taskTypes: [{ code: 'EV', label: 'Evolutivo / Feature' }, { code: 'DT', label: 'Deuda tecnica / Tech debt' }] },
  mcp: { context7Url: '' },
};

function deepMerge(base, override) {
  if (override === null || override === undefined) return base;
  if (Array.isArray(base) || Array.isArray(override) || typeof base !== 'object' || typeof override !== 'object') {
    return override;
  }
  const out = { ...base };
  for (const k of Object.keys(override)) {
    if (k.startsWith('_')) continue; // claves _comentario
    out[k] = k in base ? deepMerge(base[k], override[k]) : override[k];
  }
  return out;
}

let _cache = null;

/**
 * Carga ecosystem.config.json de la raiz del proyecto (CLAUDE_PROJECT_DIR o cwd),
 * fusionado sobre los defaults neutrales. Cachea por proceso (los hooks son procesos cortos).
 */
function load(startDir) {
  if (_cache) return _cache;
  const root = startDir || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  let user = {};
  try {
    const p = path.join(root, 'ecosystem.config.json');
    if (fs.existsSync(p)) user = JSON.parse(fs.readFileSync(p, 'utf8'));
  } catch { /* config ilegible -> defaults (nunca romper un hook por esto) */ }
  _cache = deepMerge(DEFAULTS, user);
  return _cache;
}

/** Acceso por ruta: get(cfg, 'database.naming.forbiddenPrefixes', []) */
function get(cfg, dotted, fallback) {
  let cur = cfg;
  for (const part of dotted.split('.')) {
    if (cur === null || cur === undefined || typeof cur !== 'object') return fallback;
    cur = cur[part];
  }
  return cur === undefined ? fallback : cur;
}

/**
 * Politica efectiva de un hook defensivo (ADR-F000/F001):
 *   - intrinsicBlock=true  -> 'block' SIEMPRE (bash-guard, protect-files:certs, hilo-json-guard)
 *   - hooks.policy='block' -> 'block' global
 *   - hooks.blockList incluye el hook -> 'block'
 *   - default -> 'warn' (WARN-first)
 * Uso tipico:  exit(resolvePolicy(cfg, 'secret-scanner') === 'block' ? 2 : 1)
 */
function resolvePolicy(cfg, hookName, { intrinsicBlock = false } = {}) {
  if (intrinsicBlock) return 'block';
  const policy = get(cfg, 'hooks.policy', 'warn');
  if (String(policy).toLowerCase() === 'block') return 'block';
  const list = get(cfg, 'hooks.blockList', []) || [];
  if (list.some((n) => String(n).toLowerCase() === hookName.toLowerCase())) return 'block';
  return 'warn';
}

module.exports = { load, get, resolvePolicy, DEFAULTS };
