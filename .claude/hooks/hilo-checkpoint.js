#!/usr/bin/env node
// hilo-checkpoint.js - Actualizar Hilo y verificar cambios sin commit
// Evento: Stop
// Exit 0 = siempre (no bloquea cierre)
// Version: 1.0.0-node (port de hilo-checkpoint.ps1 v1.1.0, ADR-F006)
//
// - Escribe ESTADO_PROYECTO.json SIEMPRE via writeHiloJson (FB-004: atomico,
//   UTF-8 sin BOM, serializador unico).
// - Git read-only con GIT_OPTIONAL_LOCKS=0 (v1.0.1: evitar colisiones index.lock con IDE).

'use strict';

const fs = require('fs');
const path = require('path');
const h = require(path.join(__dirname, 'lib', 'helpers'));

function pad2(n) {
  return String(n).padStart(2, '0');
}

function main() {
  const projectDir = h.projectDir();
  const duranDir = path.join(projectDir, '_hilo');
  if (!fs.existsSync(duranDir)) return 0;

  // === 1. Verificar cambios sin commit (read-only, sin lock) ===
  let uncommitted = [];
  const st = h.gitReadOnly(['status', '--porcelain'], projectDir);
  if (st.exitCode === 0 && st.stdOut && st.stdOut.trim()) {
    uncommitted = st.stdOut
      .split(/\r?\n/)
      .filter((l) => l.trim())
      .map((l) => l.substring(3).trim());
  }

  if (uncommitted.length > 0) {
    console.log('');
    console.log(`AVISO: ${uncommitted.length} archivo(s) sin commit:`);
    for (const f of uncommitted.slice(0, 10)) console.log(`  - ${f}`);
    if (uncommitted.length > 10) {
      console.log(`  ... y ${uncommitted.length - 10} mas`);
    }
    console.log('Considera ejecutar /commit antes de cerrar.');
    console.log('');
  }

  // === 2. Actualizar timestamp en ESTADO_PROYECTO.json ===
  const estadoFile = path.join(duranDir, 'ESTADO_PROYECTO.json');
  if (fs.existsSync(estadoFile)) {
    try {
      const estado = JSON.parse(fs.readFileSync(estadoFile, 'utf8'));
      const now = new Date();
      const ahora = `${now.getFullYear()}-${pad2(now.getMonth() + 1)}-${pad2(now.getDate())}`;

      let usuario = null;
      const gu = h.gitReadOnly(['config', 'user.name'], projectDir);
      if (gu.exitCode === 0 && gu.stdOut && gu.stdOut.trim()) usuario = gu.stdOut.trim();
      if (!usuario) usuario = process.env.USERNAME || process.env.USER || null;

      // Actualizar ultimaSesion
      if (estado.ultimaSesion) {
        estado.ultimaSesion.fecha = ahora;
        estado.ultimaSesion.usuario = usuario;
        if (uncommitted.length > 0) {
          estado.ultimaSesion.archivosModificados = uncommitted.slice(0, 20);
        }
      }

      // Actualizar estado.ultima_actualizacion
      if (estado.estado) {
        estado.estado.ultima_actualizacion = ahora;
        estado.estado.actualizado_por = usuario;
      }

      h.writeHiloJson(estado, estadoFile); // FB-004: atomico, UTF-8 sin BOM
    } catch {
      // Silencioso - no bloquear cierre por error de escritura
    }
  }

  // === 3. Verificar si hay alertas pendientes ===
  if (fs.existsSync(estadoFile)) {
    const estado = h.readJsonSafe(estadoFile);
    if (
      estado &&
      estado.alertas &&
      Array.isArray(estado.alertas.activas) &&
      estado.alertas.activas.length > 0
    ) {
      console.log(`RECORDATORIO: ${estado.alertas.activas.length} alerta(s) activa(s) en el proyecto.`);
    }
  }

  return 0;
}

try {
  process.exit(main());
} catch (e) {
  console.error(`[hilo-checkpoint] error no fatal: ${e.message}`);
  process.exit(0);
}
