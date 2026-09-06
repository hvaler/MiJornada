/* =============================================================================
   dashboard.js - Plantilla base de panel Ovillo
   - Tema claro/oscuro con data-bs-theme en <html> (persiste + prefers-color-scheme)
   - Colapso del sidebar (escritorio) + off-canvas (<820px)
   - Chart.js: re-render con la paleta del tema activo (Chart.js NO reacciona solo)
   - Buscador con atajo Ctrl/Cmd + K
   Sin dependencias de Node en runtime. Bootstrap 5.3 + Chart.js servidos desde wwwroot/lib.
   ============================================================================= */
(function () {
  "use strict";
  var html = document.documentElement;
  var THEME_KEY = "dash-theme";

  /* ---------- TEMA ---------- */
  function preferredTheme() {
    var saved = localStorage.getItem(THEME_KEY);
    if (saved === "light" || saved === "dark") return saved;
    return (window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches) ? "dark" : "light";
  }
  function applyTheme(theme) {
    html.setAttribute("data-bs-theme", theme);
    var ic = document.getElementById("themeIcon");
    if (ic) ic.className = theme === "dark" ? "bi bi-sun" : "bi bi-moon-stars";
    Panel.charts.retheme();   // re-render de los graficos con la paleta nueva
  }
  function toggleTheme() {
    var next = html.getAttribute("data-bs-theme") === "dark" ? "light" : "dark";
    localStorage.setItem(THEME_KEY, next);
    applyTheme(next);
  }

  /* ---------- SIDEBAR ---------- */
  function isMobile() { return window.matchMedia("(max-width: 820px)").matches; }
  function toggleSidebar() {
    var app = document.getElementById("app");
    if (!app) return;
    if (isMobile()) app.classList.toggle("sb-open");
    else app.classList.toggle("collapsed");
  }
  function closeOffcanvas() {
    var app = document.getElementById("app");
    if (app) app.classList.remove("sb-open");
  }

  /* ---------- CHART.JS (paleta segun tema) ---------- */
  function cssVar(name) { return getComputedStyle(html).getPropertyValue(name).trim(); }
  var Panel = window.Panel = window.Panel || {};
  Panel.charts = (function () {
    var registry = [];   // { canvasId, build(palette) -> Chart config }
    var instances = {};

    function palette() {
      // Colores de datos de marca + ejes/grid/texto segun tema activo
      return {
        brand: cssVar("--brand-600") || "#0066CC",
        teal: cssVar("--c-teal") || "#17a2b8",
        green: cssVar("--c-green") || "#2faa6e",
        amber: cssVar("--c-amber") || "#e0921f",
        purple: cssVar("--c-purple") || "#6f5bd6",
        danger: cssVar("--danger") || "#CC0000",
        text: cssVar("--text-muted") || "#5b6b82",
        grid: cssVar("--border") || "#e2e8f1",
        series: [cssVar("--brand-600"), cssVar("--c-teal"), cssVar("--c-green"),
                 cssVar("--c-amber"), cssVar("--c-purple")]
      };
    }
    // Aplica color de ejes/leyenda comun (los charts pueden sobreescribir)
    function themedOptions(opts, p) {
      opts = opts || {};
      opts.responsive = true; opts.maintainAspectRatio = false;
      opts.plugins = opts.plugins || {};
      opts.plugins.legend = opts.plugins.legend || {};
      opts.plugins.legend.labels = Object.assign({ color: p.text, font: { family: "Inter", size: 11 } },
                                                  (opts.plugins.legend.labels || {}));
      if (opts.scales) {
        Object.keys(opts.scales).forEach(function (k) {
          var s = opts.scales[k]; s.grid = Object.assign({ color: p.grid }, s.grid || {});
          s.ticks = Object.assign({ color: p.text, font: { size: 10 } }, s.ticks || {});
        });
      }
      return opts;
    }

    return {
      // register(canvasId, fn) donde fn(palette, themedOptions) devuelve la config de Chart
      register: function (canvasId, fn) { registry.push({ id: canvasId, fn: fn }); },
      renderAll: function () { this.retheme(); },
      retheme: function () {
        if (typeof Chart === "undefined") return;
        var p = palette();
        registry.forEach(function (r) {
          var el = document.getElementById(r.id);
          if (!el) return;
          if (instances[r.id]) { try { instances[r.id].destroy(); } catch (e) {} }
          var cfg = r.fn(p, function (o) { return themedOptions(o, p); });
          instances[r.id] = new Chart(el, cfg);
        });
      }
    };
  })();

  /* ---------- INIT ---------- */
  document.addEventListener("DOMContentLoaded", function () {
    applyTheme(preferredTheme());

    var tBtn = document.getElementById("themeBtn"); if (tBtn) tBtn.addEventListener("click", toggleTheme);
    var cBtn = document.getElementById("collapseBtn"); if (cBtn) cBtn.addEventListener("click", toggleSidebar);
    var ov = document.getElementById("overlay"); if (ov) ov.addEventListener("click", closeOffcanvas);

    // Atajo Ctrl/Cmd + K -> foco al buscador
    document.addEventListener("keydown", function (e) {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        var s = document.getElementById("globalSearch"); if (s) s.focus();
      }
    });

    // Si el SO cambia de tema y el usuario no fijo preferencia, seguir al SO
    if (window.matchMedia) {
      window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", function (e) {
        if (!localStorage.getItem(THEME_KEY)) applyTheme(e.matches ? "dark" : "light");
      });
    }

    Panel.charts.renderAll();
  });
})();
