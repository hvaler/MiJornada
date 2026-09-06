# Tokens de diseño y temas — webapp-dashboard

Referencia de los tokens CSS (`wwwroot/css/dashboard.css`) y de cómo funciona el cambio de tema.

## Tokens de marca (fijos, no cambian con el tema)

| Variable | Valor | Uso |
|---|---|---|
| `--brand` | `#33475B` | Navy institucional. Ancla del sidebar (ambos temas). |
| `--brand-600` | `#0066CC` | Interactivo: enlaces, acentos, foco, item activo. |
| `--danger` | `#CC0000` | **Solo** alertas y estados críticos (uso comedido). |

## Paleta de datos (gráficos)

| Variable | Valor |
|---|---|
| `--c-teal` | `#17a2b8` |
| `--c-green` | `#2faa6e` |
| `--c-amber` | `#e0921f` |
| `--c-purple` | `#6f5bd6` |

`dashboard.js` (`Panel.charts`) lee estas variables y construye `palette.series` para los datasets.

## Superficies por tema (cambian con `data-bs-theme`)

| Variable | light | dark |
|---|---|---|
| `--surface` | `#eef2f7` | `#0a1120` |
| `--surface-2` | `#ffffff` | `#121b2e` |
| `--card` | `#ffffff` | `#121b2e` |
| `--text` | `#0f172a` | `#e6edf6` |
| `--text-muted` | `#5b6b82` | `#93a4bd` |
| `--border` | `#e2e8f1` | `#1e2a40` |
| `--shadow` / `--shadow-lg` | suaves | profundas |

> **Regla**: el sidebar usa sus propios tokens `--sb-*` (navy) que **no** dependen del tema.
> Solo el área de contenido (superficies, texto, bordes, sombras) cambia con `data-bs-theme`.

## Tipografía

| Variable | Stack | Uso |
|---|---|---|
| `--font-body` | `Inter, system-ui, Segoe UI, ...` | Cuerpo |
| `--font-display` | `Space Grotesk, <body>` | Títulos `h1/h2/h3/.display` |
| `--font-mono` | `JetBrains Mono, ui-monospace, ...` | **Todas las cifras** (`.mono`, `.metric-num`) |

Fuentes locales en `wwwroot/lib/fonts/` (woff2). Si faltan, los fallbacks del stack aplican.

## Métricas de layout

`--sidebar-w 264px`, `--sidebar-w-collapsed 74px`, `--topbar-h 60px`, `--radius 14px`, `--radius-sm 10px`.

## Cambio de tema (Bootstrap 5.3 nativo)

1. `dashboard.js` resuelve el tema inicial: `localStorage['dash-theme']` → si no, `prefers-color-scheme`.
2. Escribe `data-bs-theme="light|dark"` en `<html>` (Bootstrap recolorea sus componentes; nuestras
   variables de superficie cambian por el selector `[data-bs-theme="..."]`).
3. El botón de tema persiste la elección y llama a `Panel.charts.retheme()`.

## Chart.js + tema (clave)

Chart.js **no** reacciona al cambio de `data-bs-theme`. Patrón de la plantilla:

```js
// Registrar (no instancia aun); fn recibe la paleta del tema + un helper themed()
Panel.charts.register("miCanvas", function (p, themed) {
  return { type: "line",
    data: { labels: [...], datasets: [{ borderColor: p.brand, data: [...] }] },
    options: themed({ scales: { y: {}, x: {} } })   // themed() pinta ejes/leyenda segun tema
  };
});
```

`Panel.charts.retheme()` (llamado al iniciar y en cada toggle) **destruye y recrea** cada gráfico
registrado con la paleta actual — así los colores de ejes/grid/series siguen al tema.

## Accesibilidad / marca

- Contraste: navy `#33475B` sobre claro y texto claro sobre navy cumplen AA.
- `--danger` reservado a lo crítico (no decorativo).
- Botones de la topbar con `aria-label`; el item activo del sidebar marca con barra + color (no solo color).
