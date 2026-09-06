#!/usr/bin/env node
// hilo-freshness.js - Aviso pasivo sobre frescura de Hilo
// Evento: UserPromptSubmit
// Exit 0 = continuar (stdout se inyecta como contexto adicional)
// NO bloquea jamas.
// Version: 1.0.0-node (port de hilo-freshness.ps1 v1.0.0 - item H1 bloque H, ADR-033 -, ADR-F006)
//
// Logica:
//   - Si _hilo/ESTADO_PROYECTO.json.ultimaSesion.fecha es > N dias atras, avisar
//   - Si hay evolutivos.enProgreso[] con fechaInicio > M dias y sin actualizar, avisar
//   - Umbrales configurables via configuracion.hiloFreshnessDiasSesion y .hiloFreshnessDiasEvolutivo
//     (defaults: 7 dias sesion, 5 dias evolutivo)
//
// Anti-ruido: prompts <10 chars no disparan.

'use strict';

const fs = require('fs');
const path = require('path');
const h = require(path.join(__dirname, 'lib', 'helpers'));

function main() {
  const hookData = h.readHookInput();
  if (!hookData) return 0;

  // Anti-ruido: prompt trivial
  let prompt = null;
  if (typeof hookData.prompt === 'string') prompt = hookData.prompt;
  else if (hookData.prompt) prompt = String(hookData.prompt).trim();
  if (!prompt || prompt.length < 10) return 0;

  // Localizar ESTADO_PROYECTO.json
  const repoRoot = h.projectDir();
  const estadoFile = path.join(repoRoot, '_hilo', 'ESTADO_PROYECTO.json');
  if (!fs.existsSync(estadoFile)) return 0; // No es proyecto Ovillo o aun no onboarded

  const estado = h.readJsonSafe(estadoFile);
  if (!estado) return 0; // JSON corrupto - no bloquear

  // Umbrales (con defaults)
  let umbralSesionDias = 7;
  let umbralEvolutivoDias = 5;
  if (estado.configuracion) {
    if (estado.configuracion.hiloFreshnessDiasSesion) {
      const v = parseInt(estado.configuracion.hiloFreshnessDiasSesion, 10);
      if (!Number.isNaN(v)) umbralSesionDias = v;
    }
    if (estado.configuracion.hiloFreshnessDiasEvolutivo) {
      const v = parseInt(estado.configuracion.hiloFreshnessDiasEvolutivo, 10);
      if (!Number.isNaN(v)) umbralEvolutivoDias = v;
    }
  }

  const ahora = Date.now();
  const avisos = [];

  // Check 1: ultimaSesion.fecha
  if (estado.ultimaSesion && estado.ultimaSesion.fecha) {
    const fechaSesion = new Date(estado.ultimaSesion.fecha);
    if (!Number.isNaN(fechaSesion.getTime())) {
      const diasDesde = Math.round((ahora - fechaSesion.getTime()) / 86400000);
      if (diasDesde > umbralSesionDias) {
        const usuario = estado.ultimaSesion.usuario ? estado.ultimaSesion.usuario : 'desconocido';
        avisos.push(
          `Ultima sesion Hilo hace ${diasDesde} dias (>${umbralSesionDias}). Usuario: ${usuario}. Considera /continuar o /sesion para refrescar contexto.`
        );
      }
    } // Fecha mal parseada - skip
  }

  // Check 2: evolutivos en progreso sin actualizar
  const enProgreso = estado.evolutivos && estado.evolutivos.enProgreso;
  if (Array.isArray(enProgreso) && enProgreso.length > 0) {
    for (const ev of enProgreso) {
      // Solo procesar entradas reales (no comentarios/estructura)
      if (!ev || !ev.codigo) continue;

      let fechaRef = null;
      // Preferir fechaInicio, fallback fechaCreacion
      if (ev.fechaInicio) {
        const d = new Date(ev.fechaInicio);
        if (!Number.isNaN(d.getTime())) fechaRef = d;
      }
      if (!fechaRef && ev.fechaCreacion) {
        const d = new Date(ev.fechaCreacion);
        if (!Number.isNaN(d.getTime())) fechaRef = d;
      }
      if (!fechaRef) continue;

      const diasDesde = Math.round((ahora - fechaRef.getTime()) / 86400000);
      if (diasDesde > umbralEvolutivoDias) {
        const titulo = ev.titulo ? ev.titulo : '(sin titulo)';
        avisos.push(
          `Evolutivo ${ev.codigo} '${titulo}' lleva ${diasDesde} dias en progreso (>${umbralEvolutivoDias}). Considera actualizar estado o pausar.`
        );
      }
    }
  }

  if (avisos.length === 0) return 0;

  // Construir aviso (stdout -> contexto Claude)
  const out = ['[hilo-freshness] Hilo puede estar desfasada:'];
  for (const a of avisos) out.push(`  - ${a}`);
  out.push(
    `Umbrales actuales: sesion=${umbralSesionDias} dias, evolutivo=${umbralEvolutivoDias} dias (configurables en _hilo/ESTADO_PROYECTO.json.configuracion.hiloFreshness*).`
  );
  console.log(out.join('\n'));

  return 0;
}

try {
  process.exit(main());
} catch (e) {
  console.error(`[hilo-freshness] error no fatal: ${e.message}`);
  process.exit(0);
}
