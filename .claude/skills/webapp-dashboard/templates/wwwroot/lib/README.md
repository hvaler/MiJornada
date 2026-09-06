# wwwroot/lib - librerias del panel (locales)

Estas librerias se sirven **locales** desde IIS para que el panel funcione en intranets
o redes restringidas sin depender de un CDN en runtime.

## Poblarla

```powershell
pwsh .\FETCH-LIBS.ps1        # baja Bootstrap 5.3 + Chart.js + Bootstrap Icons + fuentes
# powershell .\FETCH-LIBS.ps1   # tambien va con Windows PowerShell 5.1
```

Estructura resultante (lo que espera `dashboard.html`):

```
lib/
├── bootstrap/        bootstrap.min.css, bootstrap.bundle.min.js   (5.3.3)
├── chart/            chart.umd.min.js                              (4.4.1)
├── bootstrap-icons/font/  bootstrap-icons.min.css + fonts/*.woff2,woff  (1.11.3)
└── fonts/            fonts.css (incluido) + space-grotesk/jetbrains-mono/inter .woff2 (opcionales)
```

## Versiones (pineadas en FETCH-LIBS.ps1)

| Lib | Version | Fuente |
|---|---|---|
| Bootstrap | 5.3.3 | jsDelivr (npm) |
| Chart.js | 4.4.1 | jsDelivr (npm) |
| Bootstrap Icons | 1.11.3 | jsDelivr (npm) |
| Fuentes (Space Grotesk / JetBrains Mono / Inter) | latest | fontsource (jsDelivr) - opcionales |

## Si no hay internet en scaffold-time

Descargar a mano desde jsDelivr y colocar en las rutas de arriba. Las **fuentes son
opcionales**: si faltan, `dashboard.css` cae a `system-ui` (cuerpo) y `ui-monospace`
(cifras), y el panel se ve correcto igual.

> NO commitear binarios de estas librerias al repo de la plantilla (engordan el ZIP).
> Se bajan por proyecto consumidor con FETCH-LIBS.
