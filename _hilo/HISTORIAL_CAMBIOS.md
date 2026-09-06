# Historial de Cambios (Changelog)

> **INSTRUCCIONES PARA CLAUDE**: Este archivo se actualiza automaticamente con /commit y /prepara-entrega.
> Documenta todos los cambios significativos del proyecto.

Seguimos el formato [Keep a Changelog](https://keepachangelog.com/es-ES/1.0.0/):
**Added** / **Changed** / **Deprecated** / **Removed** / **Fixed** / **Security**.

---

## [Unreleased]

Todo el codigo de la aplicacion esta aqui: escrito, **sin compilar ni una vez**. No hay ninguna
version publicada, por eso `version_actual` es `0.0.0` aunque el `.csproj` declare `1.0.0`.

### Added

- Aplicacion de escritorio .NET 8 WinForms completa (5 ficheros en `03_Desarrollo/`): maquina de
  estados de la jornada, persistencia en JSON local, autenticacion MSAL con codigo de dispositivo,
  llamada a Microsoft Graph `setUserPreferredPresence`, interfaz con anillo GDI+ e icono de
  bandeja, y modo de prueba `--minutos N`.
- Incorporacion del proyecto al ecosistema Ovillo: `ecosystem.config.json` y el sistema Hilo
  completo (`ESTADO_PROYECTO.json`, `CONTEXTO_TECNICO.md`, `DEPENDENCIAS.md`,
  `FUNCIONALIDADES.md`, `DEUDA_TECNICA.md`, `DECISIONES.md`, `LECCIONES.md`) — @hvaler
- Repositorio Git con remoto en GitHub (`hvaler/MiJornada`, privado) — @hvaler

### Removed

- `03_Desarrollo/Vault y sus Secretos.md`: guia corporativa de Azure Key Vault del proyecto
  MyCompany.ConectaPDI, ajena a este repositorio — @hvaler

### Changed

- Los documentos de traspaso se reubican: `CONTEXTO.md` y `mi-jornada-traspaso.md` a
  `06_Documentacion/`, `LEEME.md` a `03_Desarrollo/` — @hvaler

### Pendiente para la primera version

- **EV-001**: primera compilacion y correccion de errores. Hasta entonces no hay nada liberable.

---

## Historial de Versiones

| Version | Fecha | Tipo | Descripcion |
|---------|-------|------|-------------|
| — | — | — | Sin versiones publicadas todavia |

---

## Antes de este repositorio

El proyecto es la tercera implementacion de la misma idea. Las dos anteriores no vivian en Git:

| Fecha | Hito |
|---|---|
| (previo) | Script de PowerShell con `Start-Sleep`. Funcionaba, pero moria al cerrar la consola |
| 2026-09-06 | Solucion Power Apps + Power Automate + SharePoint validada de punta a punta, y aparcada el mismo dia por coste de licencia (ADR-001) |
| 2026-09-06 | Se escribe esta aplicacion de escritorio y se incorpora al ecosistema Ovillo |

Detalle completo en `06_Documentacion/mi-jornada-traspaso.md`.

---

**Ultima actualizacion**: 2026-09-06
