#!/usr/bin/env node
// multi-rol-coordination.js - Aviso de coordinacion en proyectos colaborativos
// Evento: PostToolUse[Edit]
// Exit 0 (no bloquea) - solo aviso pasivo
// Version: 1.0.0-node (port de multi-rol-coordination.ps1 v1.0.0 - item J4 bloque J, ADR-034 -, ADR-F006)
//
// Logica:
//   - Si el proyecto tiene >1 miembro en equipo.miembros[]
//   - Y se edita un archivo en _hilo/EVOLUTIVOS/, _hilo/ESTADO_PROYECTO.json (campo evolutivos),
//     o se modifica un evolutivo no asignado al usuario actual
//   - Mostrar recordatorio: "Considera notificar a {otros_devs} de los cambios en {evolutivo}"
//
// Identificacion del usuario actual: git config user.name (matching contra git_author_name OR nombre)
//
// Anti-ruido:
//   - Solo dispara si equipo.miembros[].Count >= 2 (proyectos colaborativos)
//   - No dispara si el evolutivo esta sin asignar (asignadoA = null)
//
// Nota: este hook solo LEE _hilo/*.json; no escribe. Si en el futuro escribiera,
// usar SIEMPRE helpers.writeHiloJson (FB-004/FB-007).

'use strict';

const fs = require('fs');
const path = require('path');
const h = require(path.join(__dirname, 'lib', 'helpers'));

function main() {
  const hookData = h.readHookInput();
  if (!hookData) return 0;

  const filePath = h.getFilePath(hookData);
  if (!filePath) return 0;

  // Solo aplica a archivos de Hilo relacionados con evolutivos
  const normalized = filePath.replace(/\\/g, '/');
  const isEvolutivoFile =
    /_hilo\/EVOLUTIVOS\//i.test(normalized) ||
    /_hilo\/ESTADO_PROYECTO\.json$/i.test(normalized) ||
    /_hilo\/FUNCIONALIDADES\.md$/i.test(normalized);
  if (!isEvolutivoFile) return 0;

  // Localizar ESTADO_PROYECTO.json
  const repoRoot = h.projectDir();
  const estadoFile = path.join(repoRoot, '_hilo', 'ESTADO_PROYECTO.json');
  if (!fs.existsSync(estadoFile)) return 0;

  const estado = h.readJsonSafe(estadoFile);
  if (!estado) return 0;

  // Verificar proyecto colaborativo (>=2 miembros reales con campo 'usuario')
  if (!estado.equipo || !Array.isArray(estado.equipo.miembros)) return 0;
  const miembrosReales = estado.equipo.miembros.filter(
    (m) => m && m.usuario && !/^ejemplo_/i.test(String(m.usuario))
  );
  if (miembrosReales.length < 2) return 0;

  // Identificar usuario git actual
  let gitUser = null;
  const gu = h.gitReadOnly(['config', 'user.name'], repoRoot);
  if (gu.exitCode === 0 && gu.stdOut) gitUser = gu.stdOut.trim();
  if (!gitUser) return 0;

  // Resolver usuario git a entrada en equipo.miembros (matching git_author_name OR nombre)
  const miembroActual = miembrosReales.find(
    (m) => m.git_author_name === gitUser || m.nombre === gitUser
  );
  if (!miembroActual) {
    // Usuario git no encontrado en equipo.miembros - posible miembro fantasma
    // No disparar aviso (eso lo cubre hilo-coherence-checker R2)
    return 0;
  }

  const usuarioActualAlias = miembroActual.usuario;

  // Leer evolutivos en progreso
  if (!estado.evolutivos || !Array.isArray(estado.evolutivos.enProgreso)) return 0;
  const evolutivosActivos = estado.evolutivos.enProgreso.filter((ev) => ev && ev.codigo);
  if (evolutivosActivos.length === 0) return 0;

  // Identificar otros miembros (no el actual)
  const otrosMiembros = miembrosReales.filter((m) => m.usuario !== usuarioActualAlias);
  if (otrosMiembros.length === 0) return 0;

  // Determinar si la edicion toca un evolutivo no asignado al usuario actual
  const evolutivosAjenos = evolutivosActivos.filter(
    (ev) => ev.asignadoA && ev.asignadoA !== usuarioActualAlias
  );

  // Si edita ESTADO_PROYECTO.json o FUNCIONALIDADES.md global: avisar genericamente
  // Si edita EVOLUTIVOS/{CODIGO}.md: identificar el evolutivo especifico
  let evolutivoEditado = null;
  const mFile = normalized.match(/_hilo\/EVOLUTIVOS\/([^/]+)\.md$/i);
  if (mFile) {
    const codigoArchivo = mFile[1];
    evolutivoEditado = evolutivosActivos.find((ev) => ev.codigo === codigoArchivo) || null;
  }

  // Construir aviso solo si hay caso real de coordinacion
  const avisos = [];

  if (evolutivoEditado && evolutivoEditado.asignadoA && evolutivoEditado.asignadoA !== usuarioActualAlias) {
    // Editando evolutivo asignado a otro
    const owner = evolutivosActivos.find((ev) => ev.codigo === evolutivoEditado.codigo);
    const ownerMiembro = miembrosReales.find((m) => m.usuario === owner.asignadoA);
    const ownerNombre = ownerMiembro ? ownerMiembro.nombre : owner.asignadoA;
    avisos.push(
      `Editaste ${evolutivoEditado.codigo} '${evolutivoEditado.titulo}' que esta asignado a ${ownerNombre} (${owner.asignadoA}).`
    );
    avisos.push(`  Considera notificar a ${ownerNombre} por Teams/email de los cambios.`);
  } else if (/_hilo\/ESTADO_PROYECTO\.json$/i.test(normalized) && evolutivosAjenos.length > 0) {
    // Editando ESTADO_PROYECTO global con evolutivos ajenos activos
    avisos.push(
      `Editaste _hilo/ESTADO_PROYECTO.json. Hay ${evolutivosAjenos.length} evolutivo(s) activos asignados a otros miembros:`
    );
    for (const ev of evolutivosAjenos) {
      const ownerMiembro = miembrosReales.find((m) => m.usuario === ev.asignadoA);
      const ownerNombre = ownerMiembro ? ownerMiembro.nombre : ev.asignadoA;
      avisos.push(`  - ${ev.codigo} '${ev.titulo}' -> ${ownerNombre}`);
    }
    avisos.push('  Si tus cambios afectan alguno, notifica al responsable.');
  }

  if (avisos.length === 0) return 0;

  console.log(
    `[multi-rol-coordination] Aviso de coordinacion (proyecto con ${miembrosReales.length} miembros activos):`
  );
  for (const a of avisos) console.log(a);

  return 0;
}

try {
  process.exit(main());
} catch (e) {
  console.error(`[multi-rol-coordination] error no fatal: ${e.message}`);
  process.exit(0);
}
