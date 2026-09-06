#!/usr/bin/env node
// session-checkpoint.js - Registrar metricas de sesion al cerrar
// Evento: Stop
// Exit 0 = siempre (no bloquea cierre)
// Version: 1.0.0-node (port de session-checkpoint.ps1 v1.1.0, ADR-F006)
//
// Registra en _hilo/METRICAS.json (SIEMPRE via writeHiloJson - FB-004: atomico,
// UTF-8 sin BOM, serializador unico):
// - Fecha y duracion de sesion
// - Skills invocados (detectados por archivos modificados en .claude/skills/)
// - Archivos modificados
// - Commits realizados
// Git read-only con GIT_OPTIONAL_LOCKS=0 (v1.0.1: evitar colisiones index.lock con IDE).

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
  const metricasFile = path.join(duranDir, 'METRICAS.json');

  // Crear archivo si no existe
  if (!fs.existsSync(metricasFile)) {
    h.writeHiloJson({ version: '1.0.0', sesiones: [] }, metricasFile); // FB-004: UTF-8 sin BOM
  }

  // Leer metricas existentes
  let metricas = h.readJsonSafe(metricasFile);
  if (!metricas || typeof metricas !== 'object') {
    metricas = { version: '1.0.0', sesiones: [] };
  }

  // Recopilar datos de la sesion
  const now = new Date();
  const fecha = `${now.getFullYear()}-${pad2(now.getMonth() + 1)}-${pad2(now.getDate())}`;
  const ahora = `${fecha} ${pad2(now.getHours())}:${pad2(now.getMinutes())}:${pad2(now.getSeconds())}`;

  // Archivos modificados (git, read-only sin lock)
  let archivosModificados = [];
  const st = h.gitReadOnly(['status', '--porcelain'], projectDir);
  if (st.exitCode === 0 && st.stdOut && st.stdOut.trim()) {
    archivosModificados = st.stdOut
      .split(/\r?\n/)
      .filter((l) => l.trim())
      .map((l) => l.substring(3).trim());
  }

  // Commits de hoy (proxy de actividad)
  let commitsHoy = 0;
  const lg = h.gitReadOnly(['log', '--oneline', `--since=${fecha}`], projectDir);
  if (lg.exitCode === 0 && lg.stdOut && lg.stdOut.trim()) {
    commitsHoy = lg.stdOut.split(/\r?\n/).filter((l) => l.trim()).length;
  }

  // Detectar skills que pudieron usarse (directorios tocados en las ultimas 4h)
  let skillsUsados = [];
  try {
    const skillsDir = path.join(projectDir, '.claude', 'skills');
    if (fs.existsSync(skillsDir)) {
      const cutoff = Date.now() - 4 * 3600000;
      skillsUsados = fs
        .readdirSync(skillsDir, { withFileTypes: true })
        .filter((d) => d.isDirectory())
        .filter((d) => {
          try {
            return fs.statSync(path.join(skillsDir, d.name)).mtimeMs > cutoff;
          } catch {
            return false;
          }
        })
        .map((d) => d.name);
    }
  } catch { /* silencioso */ }

  // Detectar agents disponibles
  let agentsCount = 0;
  try {
    const agentsDir = path.join(projectDir, '.claude', 'agents');
    if (fs.existsSync(agentsDir)) {
      agentsCount = fs.readdirSync(agentsDir).filter((f) => f.toLowerCase().endsWith('.md')).length;
    }
  } catch { /* silencioso */ }

  // Detectar estado proyecto
  let modo = 'desconocido';
  let version = '0.0.0';
  const estado = h.readJsonSafe(path.join(duranDir, 'ESTADO_PROYECTO.json'));
  if (estado && estado.estado) {
    modo = estado.estado.modo ?? null;
    version = estado.estado.version_actual ?? null;
  }

  // Construir registro de sesion
  const sesion = {
    fecha: ahora,
    archivosModificados: archivosModificados.length,
    archivos: archivosModificados.length <= 20 ? archivosModificados : archivosModificados.slice(0, 20),
    commitsHoy,
    skillsTocados: skillsUsados,
    agentsDisponibles: agentsCount,
    modoProyecto: modo,
    versionProyecto: version,
  };

  // Anadir sesion (mantener ultimas 50)
  if (!Array.isArray(metricas.sesiones)) metricas.sesiones = [];
  let sesiones = metricas.sesiones.concat([sesion]);
  if (sesiones.length > 50) {
    sesiones = sesiones.slice(sesiones.length - 50);
  }
  metricas.sesiones = sesiones;

  // Guardar (FB-004: atomico, UTF-8 sin BOM)
  try {
    h.writeHiloJson(metricas, metricasFile);
  } catch { /* silencioso */ }

  return 0;
}

try {
  process.exit(main());
} catch (e) {
  console.error(`[session-checkpoint] error no fatal: ${e.message}`);
  process.exit(0);
}
