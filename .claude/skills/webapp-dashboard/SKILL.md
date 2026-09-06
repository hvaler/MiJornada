---
name: webapp-dashboard
description: >
  Plantilla base de PANEL ADMINISTRATIVO (dashboard) reutilizable para los paneles
  internos de las apps .NET de la organización: sidebar navy fijo colapsable, topbar sticky,
  modo oscuro nativo Bootstrap 5.3 (data-bs-theme), graficos Chart.js que re-renderizan
  con la paleta del tema, layout full-width, tokens de marca del tema. USE FOR scaffoldar
  un panel de control / cuadro de mando / admin dashboard interno (KPIs, graficos de
  tendencia, tablas) servido desde wwwroot en IIS. DO NOT USE FOR el layout web general
  de una app (cabecera/pie/sidebar de sitio publico -> webapp-layout), ni para el dashboard
  de calidad del CONSTRUCTOR (ese es Publicacion/docs/dashboard/calidad.html), ni para
  componentes sueltos. Keywords: dashboard, panel administrativo, cuadro de mando, admin
  panel, sidebar colapsable, dark mode, data-bs-theme, Bootstrap 5.3, Chart.js, KPI, full-width.
---

# webapp-dashboard

Scaffold de **panel administrativo** para apps internas de la organización. HTML estatico servible
desde `wwwroot` (IIS), **full-width**, con todos los assets **locales** (sin CDN en runtime).

Complementa a `webapp-layout` (layout de sitio web general): esta skill es para **paneles de
control / cuadros de mando** (KPIs + graficos + tablas), no para el chrome de un sitio publico.

## Que incluye (templates/)

```
templates/wwwroot/
├── dashboard.html              shell completo (sidebar + topbar + KPIs + 3 charts demo + tabla)
├── css/dashboard.css           tokens de marca + superficies por tema + layout full-width
├── js/dashboard.js             tema (persist + prefers-color-scheme), colapso, off-canvas,
│                               Chart.js re-render por tema, atajo Ctrl/Cmd+K
└── lib/                        FETCH-LIBS.ps1 + README + fonts/fonts.css
                                (baja Bootstrap 5.3, Chart.js, Bootstrap Icons, fuentes a wwwroot/lib)
```

## Como scaffoldar en un proyecto

1. Copiar `templates/wwwroot/*` al `wwwroot/` de la app (o a la carpeta estatica servida por IIS).
2. Poblar las librerias locales (una vez, con internet):
   ```powershell
   pwsh wwwroot/lib/FETCH-LIBS.ps1
   ```
3. Abrir `dashboard.html` (o renombrarlo a `index.html`). Personalizar marca, navegacion y
   registrar tus graficos con `Panel.charts.register(canvasId, fn)`.

## Diseno y marca

- **Sidebar navy en AMBOS temas** (`--brand #33475B`): es lo mas reconocible de la marca; solo
  cambian las superficies del area de contenido con `data-bs-theme`.
- Acento interactivo `--brand-600 #0066CC`. `--danger #CC0000` SOLO para alertas/criticos.
- Paleta de datos para graficos: teal `#17a2b8`, verde `#2faa6e`, ambar `#e0921f`, purpura `#6f5bd6`.
- Tipografia: cuerpo `Inter`/system-ui, display `Space Grotesk` (titulos), **mono `JetBrains Mono`
  para TODAS las cifras de metricas** (encaja con un panel de codigo). Fuentes locales con fallback.
- Tokens, superficies, bordes y sombras: variables CSS que cambian con el tema (ver
  `references/tokens-y-temas.md`).

## Tema claro/oscuro (Bootstrap 5.3 nativo)

- El conmutador escribe `data-bs-theme="light|dark"` en `<html>`, **persiste** en localStorage
  y cae a `prefers-color-scheme` si no hay preferencia guardada.
- **Chart.js NO reacciona solo** al cambio de tema: `dashboard.js` re-renderiza los graficos con
  la paleta del tema activo (`Panel.charts.retheme()`), leyendo los colores de las variables CSS.

## Responsive

- Escritorio: sidebar colapsable a **solo-iconos** (boton de plegado en la topbar).
- `< 820px`: el sidebar pasa a **off-canvas** con overlay.
- El area de contenido es **full-width** (sin max-width): ocupa todo el ancho horizontal.

## Hosting / assets

- Todo **local** en `wwwroot/lib` (Bootstrap 5.3 + Chart.js + Bootstrap Icons + fuentes) -> funciona
  en IIS de intranet aunque el cliente no alcance un CDN. `FETCH-LIBS.ps1` los baja en scaffold-time.
- Rutas **relativas**, sin dependencias de Node en runtime.
- Iconografia: **Bootstrap Icons** (set libre). Sin librerias de pago.

## Notas

- Es plantilla: los binarios de las librerias NO se commitean (se bajan por proyecto con FETCH-LIBS).
- Para reutilizar en Razor: el shell HTML se porta facil a un `_Layout.cshtml` (mover `<head>`/scripts).
- Origen: spec de panel administrativo del ecosistema origen. El dashboard de calidad del constructor
  (`calidad.html`) podra re-skinearse sobre esta base mas adelante.
