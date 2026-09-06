#!/usr/bin/env node
/**
 * validate-config.js — Valida ecosystem.config.json contra su JSON Schema.
 *
 * Sin dependencias externas (Node >= 18). Implementa el subconjunto de JSON Schema
 * draft-07 que usa ecosystem.config.schema.json: type, enum, const, pattern,
 * required, properties, patternProperties, additionalProperties, items,
 * minimum/maximum, minLength/maxLength.
 *
 * Uso:
 *   node .claude/scripts/validate-config.js [ruta/al/config.json]
 *
 * Sin argumento busca ecosystem.config.json en el directorio actual.
 * Si el archivo NO existe: exit 0 con aviso (el ecosistema funciona con
 * defaults neutrales — la config es opcional por diseno).
 * Exit 0 = valido · Exit 1 = invalido o JSON malformado.
 */

'use strict';

const fs = require('fs');
const path = require('path');

const SCHEMA_PATH = path.join(__dirname, '..', 'schemas', 'ecosystem.config.schema.json');
const DEFAULT_CONFIG = 'ecosystem.config.json';

function typeOf(value) {
  if (value === null) return 'null';
  if (Array.isArray(value)) return 'array';
  if (Number.isInteger(value)) return 'integer'; // integer valida tambien como number
  return typeof value;
}

function matchesType(value, expected) {
  const actual = typeOf(value);
  if (expected === 'number') return actual === 'number' || actual === 'integer';
  return actual === expected;
}

function validate(schema, value, jsonPath, errors) {
  if (!schema || typeof schema !== 'object') return; // {} = cualquier valor (comentarios ^_)

  if ('const' in schema && value !== schema.const) {
    errors.push(`${jsonPath}: debe ser ${JSON.stringify(schema.const)} (encontrado ${JSON.stringify(value)})`);
    return;
  }

  if (schema.enum && !schema.enum.includes(value)) {
    errors.push(`${jsonPath}: valor ${JSON.stringify(value)} no permitido. Opciones: ${schema.enum.join(' | ')}`);
    return;
  }

  if (schema.type) {
    const types = Array.isArray(schema.type) ? schema.type : [schema.type];
    if (!types.some((t) => matchesType(value, t))) {
      errors.push(`${jsonPath}: tipo esperado ${types.join('|')}, encontrado ${typeOf(value)}`);
      return;
    }
  }

  if (typeof value === 'string') {
    if (schema.pattern && !new RegExp(schema.pattern).test(value)) {
      errors.push(`${jsonPath}: "${value}" no cumple el patron ${schema.pattern}`);
    }
    if (schema.minLength !== undefined && value.length < schema.minLength) {
      errors.push(`${jsonPath}: longitud minima ${schema.minLength}`);
    }
    if (schema.maxLength !== undefined && value.length > schema.maxLength) {
      errors.push(`${jsonPath}: longitud maxima ${schema.maxLength}`);
    }
  }

  if (typeof value === 'number') {
    if (schema.minimum !== undefined && value < schema.minimum) {
      errors.push(`${jsonPath}: minimo ${schema.minimum}`);
    }
    if (schema.maximum !== undefined && value > schema.maximum) {
      errors.push(`${jsonPath}: maximo ${schema.maximum}`);
    }
  }

  if (Array.isArray(value) && schema.items) {
    value.forEach((item, i) => validate(schema.items, item, `${jsonPath}[${i}]`, errors));
  }

  if (typeOf(value) === 'object') {
    for (const key of schema.required || []) {
      if (!(key in value)) errors.push(`${jsonPath}: falta la propiedad requerida "${key}"`);
    }

    const props = schema.properties || {};
    const patternProps = schema.patternProperties || {};

    for (const [key, child] of Object.entries(value)) {
      const childPath = jsonPath === '$' ? `$.${key}` : `${jsonPath}.${key}`;

      if (key in props) {
        validate(props[key], child, childPath, errors);
        continue;
      }

      const patternKey = Object.keys(patternProps).find((p) => new RegExp(p).test(key));
      if (patternKey !== undefined) {
        validate(patternProps[patternKey], child, childPath, errors);
        continue;
      }

      if (schema.additionalProperties === false) {
        const known = Object.keys(props).filter((k) => k !== '$schema');
        errors.push(`${childPath}: propiedad desconocida "${key}". Conocidas: ${known.join(', ')}`);
      }
    }
  }
}

function main() {
  const configPath = path.resolve(process.argv[2] || DEFAULT_CONFIG);

  if (!fs.existsSync(configPath)) {
    console.log(`[validate-config] No existe ${configPath}.`);
    console.log('[validate-config] OK — el ecosistema funciona con defaults neutrales (la config es opcional).');
    console.log('[validate-config] Para crearla: copiar ecosystem.config.example.json a ecosystem.config.json');
    process.exit(0);
  }

  let schema;
  try {
    schema = JSON.parse(fs.readFileSync(SCHEMA_PATH, 'utf8'));
  } catch (err) {
    console.error(`[validate-config] ERROR leyendo el schema ${SCHEMA_PATH}: ${err.message}`);
    process.exit(1);
  }

  let config;
  try {
    config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  } catch (err) {
    console.error(`[validate-config] ERROR: ${configPath} no es JSON valido: ${err.message}`);
    process.exit(1);
  }

  const errors = [];
  validate(schema, config, '$', errors);

  if (errors.length > 0) {
    console.error(`[validate-config] ${configPath} INVALIDO (${errors.length} error(es)):`);
    for (const e of errors) console.error(`  - ${e}`);
    process.exit(1);
  }

  console.log(`[validate-config] OK — ${configPath} valido contra ecosystem.config.schema.json`);
  process.exit(0);
}

main();
