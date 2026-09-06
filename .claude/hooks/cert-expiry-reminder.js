#!/usr/bin/env node
// cert-expiry-reminder.js - Aviso sobre certificados x.509 caducados o proximos a caducar
// Evento: PreToolUse[Write|Edit]
// Exit 0 = permitir (con aviso si caduca <90d) · Exit 1 = AVISO (politica warn) ·
// Exit 2 = BLOCK (politica block)
// Version: 1.0.0-node (port de cert-expiry-reminder.ps1 v1.1.0, ADR-F006)
//   WARN-first: al detectar un cert CADUCADO, resolvePolicy(cfg, 'cert-expiry-reminder')
//   decide exit 1 (warn, default) o exit 2 (block) segun ecosystem.config ->
//   hooks.policy / hooks.blockList. certBlockOnExpired (ESTADO_PROYECTO.json) sigue
//   siendo el opt-in strict del proyecto (mismo mensaje que el .ps1).
//
// Detecta edicion de archivos: *.pfx, *.cer, *.crt, *.p12
// Para cada uno, lee la fecha de caducidad del cert:
//   - crypto.X509Certificate de Node (equivalente al X509Certificate2 de .NET que usa
//     el .ps1) para PEM/DER (.cer/.crt).
//   - Para .pfx/.p12 (PKCS#12), fallback a `openssl pkcs12` sin password via spawnSync;
//     si openssl no esta disponible o el cert tiene password, degrada con gracia al
//     mismo aviso "no se pudo leer" del .ps1 (exit 0).
// Comportamiento:
//   - Cert caducado (NotAfter < hoy): AVISO por defecto (exit segun politica).
//   - Caduca en <30 dias: warning critico (no bloquea, exit 0)
//   - Caduca en <90 dias: warning (no bloquea, exit 0)
//   - Caduca en >=90 dias: silencioso (exit 0 sin output)

'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');
const h = require('./lib/helpers');
const cfgLib = require('./lib/config');

// Emitir aviso por stderr
function aviso(msg) {
  console.error(msg);
}

function fmtDate(d) {
  const y = d.getFullYear();
  const mo = String(d.getMonth() + 1).padStart(2, '0');
  const da = String(d.getDate()).padStart(2, '0');
  return `${y}-${mo}-${da}`;
}

// Node separa los RDN del subject/issuer con '\n'; .NET los une con ', '
function flattenDn(dn) {
  return String(dn).split('\n').join(', ');
}

function loadCertificate(filePath, ext) {
  const buf = fs.readFileSync(filePath);
  try {
    return new crypto.X509Certificate(buf); // PEM o DER (.cer/.crt)
  } catch (ePrimary) {
    // PKCS#12: X509Certificate no lo parsea; intentar openssl sin password
    if (ext === '.pfx' || ext === '.p12') {
      try {
        const r = spawnSync('openssl',
          ['pkcs12', '-in', filePath, '-nokeys', '-clcerts', '-passin', 'pass:'],
          { encoding: 'utf8' });
        if (r.status === 0 && r.stdout && r.stdout.includes('-----BEGIN CERTIFICATE-----')) {
          return new crypto.X509Certificate(r.stdout.slice(r.stdout.indexOf('-----BEGIN CERTIFICATE-----')));
        }
      } catch { /* openssl no disponible - degradar con gracia */ }
    }
    throw ePrimary;
  }
}

function main() {
  const hookData = h.readHookInput();
  const filePath = h.getFilePath(hookData);
  if (!filePath) return 0;

  // Solo procesar extensiones de cert
  const ext = path.extname(filePath).toLowerCase();
  const certExtensions = ['.pfx', '.cer', '.crt', '.p12'];
  if (!certExtensions.includes(ext)) return 0;

  // Si el archivo NO existe aun en disco (Write nuevo), no podemos leer cert -> avisar generico
  if (!fs.existsSync(filePath)) {
    aviso(`AVISO cert-expiry-reminder: vas a crear un cert nuevo (${filePath}). Verifica:`);
    aviso('  1. Su fecha de caducidad (NotAfter) cubre el periodo de uso planeado');
    aviso('  2. Esta protegido por .gitignore (no commitear .pfx con clave privada)');
    aviso('  3. Su clave privada esta en Azure Key Vault si es para produccion');
    return 0;
  }

  // Leer config (umbrales custom + bloqueo configurable)
  const repoRoot = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const estadoFile = path.join(repoRoot, '_hilo', 'ESTADO_PROYECTO.json');
  let umbralWarning = 90;
  let umbralCritico = 30;
  let bloqueaCaducado = false; // default: SOLO AVISO (WARN-first). Opt-in para strict.

  const estado = h.readJsonSafe(estadoFile); // JSON corrupto/ausente -> defaults
  if (estado && estado.configuracion) {
    if (estado.configuracion.certWarningDias !== null && estado.configuracion.certWarningDias !== undefined) {
      umbralWarning = parseInt(estado.configuracion.certWarningDias, 10);
    }
    if (estado.configuracion.certCriticalDias !== null && estado.configuracion.certCriticalDias !== undefined) {
      umbralCritico = parseInt(estado.configuracion.certCriticalDias, 10);
    }
    if (estado.configuracion.certBlockOnExpired !== null && estado.configuracion.certBlockOnExpired !== undefined) {
      bloqueaCaducado = Boolean(estado.configuracion.certBlockOnExpired);
    }
  }

  // Leer el cert
  let notAfter, subject, issuer;
  try {
    const cert = loadCertificate(filePath, ext);
    notAfter = new Date(cert.validTo);
    subject = flattenDn(cert.subject);
    issuer = flattenDn(cert.issuer);
  } catch (e) {
    // Si el cert tiene password (.pfx) o esta corrupto, no podemos leer NotAfter
    // No bloquear - solo avisar
    aviso(`AVISO cert-expiry-reminder: no se pudo leer fecha de caducidad de ${filePath}`);
    aviso(`  Razon: ${e.message}`);
    aviso('  (puede ser .pfx con password o cert corrupto). Verifica manualmente.');
    return 0;
  }

  const ahora = new Date();
  const diasRestantes = Math.round((notAfter.getTime() - ahora.getTime()) / 86400000);

  // Truncar nombres largos para legibilidad
  const subjectShort = subject.length > 80 ? subject.substring(0, 77) + '...' : subject;
  const fileName = path.basename(filePath);

  // Cert caducado
  if (diasRestantes < 0) {
    const policy = cfgLib.resolvePolicy(cfgLib.load(), 'cert-expiry-reminder');
    const exitCode = policy === 'block' ? 2 : 1;
    const diasCaducado = Math.abs(diasRestantes);
    aviso('');
    aviso(`AVISO cert-expiry-reminder: ${fileName} esta CADUCADO hace ${diasCaducado} dias.`);
    aviso(`  Subject: ${subjectShort}`);
    aviso(`  Issuer: ${issuer}`);
    aviso(`  NotAfter: ${fmtDate(notAfter)}`);
    aviso('');
    aviso('  Editar un cert caducado en lugar de renovar suele ser error.');
    aviso('  Fix recomendado: renovar el cert con CA, NO modificar el archivo caducado.');
    if (bloqueaCaducado) {
      aviso('  Modo strict (certBlockOnExpired=true): bloqueando edit.');
      return exitCode;
    }
    if (policy === 'block') {
      aviso('  Politica: block (ecosystem.config hooks.policy): bloqueando edit.');
    } else {
      aviso(`  Modo default (politica: ${policy}, ecosystem.config hooks.policy): edit permitido, decide tu si renovar o continuar.`);
      aviso('  Para bloquear: setear configuracion.certBlockOnExpired=true en _hilo/ESTADO_PROYECTO.json');
    }
    return exitCode;
  }

  // Cert critico (<30 dias)
  if (diasRestantes < umbralCritico) {
    aviso(`AVISO cert-expiry-reminder: ${fileName} caduca en ${diasRestantes} dias (umbral critico: ${umbralCritico}).`);
    aviso(`  Subject: ${subjectShort}`);
    aviso(`  NotAfter: ${fmtDate(notAfter)}`);
    aviso('  ACCION INMEDIATA: solicitar renovacion del cert AHORA.');
    return 0;
  }

  // Cert proximo (<90 dias)
  if (diasRestantes < umbralWarning) {
    aviso(`AVISO cert-expiry-reminder: ${fileName} caduca en ${diasRestantes} dias (umbral warning: ${umbralWarning}).`);
    aviso(`  Subject: ${subjectShort}`);
    aviso(`  NotAfter: ${fmtDate(notAfter)}`);
    aviso('  Planifica renovacion en las proximas semanas.');
    return 0;
  }

  // Cert OK (>=90 dias) - silencioso
  return 0;
}

try {
  process.exit(main());
} catch (e) {
  console.error(`cert-expiry-reminder: error inesperado (${e.message}) - no se bloquea el flujo`);
  process.exit(0);
}
