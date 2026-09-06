---
name: webapp-layout
description: >
  Generates web layouts following configurable corporate design standards (theme tokens):
  institutional colors (#33475B), responsive layout, header/footer/sidebar
  components, dark mode, print styles, and WCAG 2.1 AA accessibility.
  USE FOR: generating web layouts, configurable corporate design, institutional colors,
  responsive UI, Bootstrap components, crear layout, diseño web, interfaz usuario,
  pagina web.
  DO NOT USE FOR: API endpoints (use api-integration-patterns), business logic,
  backend services (use generador-crud).
---

# Webapp Layout - Estándares de Diseño Web (tema configurable)

Este skill contiene los estándares de diseño web de la la organización.
Usar estos patrones garantiza consistencia visual y cumplimiento de normativas de accesibilidad.

---

## Cuándo Usar Este Skill

1. **Crear nuevo layout** - Usar templates de `templates/_Layout.cshtml`
2. **Modificar header/footer** - Seguir patrones en `patterns/layout-estandar.md`
3. **Aplicar colores** - Consultar `patterns/colores-corporativos.md`
4. **Hacer responsive** - Seguir `patterns/responsive.md`
5. **Verificar accesibilidad** - Aplicar `patterns/accesibilidad.md`

---

## Archivos de Referencia

### Patterns (Guías de diseño)

| Archivo | Descripción |
|---------|-------------|
| `patterns/colores-corporativos.md` | Paleta de colores del tema (theme.*) |
| `patterns/layout-estandar.md` | Estructura de layout (header, sidebar, footer) |
| `patterns/responsive.md` | Breakpoints y adaptación móvil |
| `patterns/accesibilidad.md` | Guía WCAG 2.1 AA |

### Templates (Código listo para usar)

| Archivo | Descripción |
|---------|-------------|
| `templates/_Layout.cshtml` | Layout principal con estructura completa |
| `templates/_Header.cshtml` | Header con logo y menú usuario |
| `templates/_Footer.cshtml` | Footer con información legal |
| `templates/_Sidebar.cshtml` | Sidebar colapsable con navegación |
| `templates/site.css` | Estilos CSS completos |

---

## Estructura del Layout

```
+------------------------------------------------------------------+
|  HEADER (60px)                                                    |
|  [Logo] [Título App]              [Usuario] [Cerrar]     |
+------------------------------------------------------------------+
|         |                                                         |
| SIDEBAR |  CONTENIDO PRINCIPAL                                    |
| (250px) |                                                         |
|         |  [Breadcrumbs: Inicio > Módulo > Página]               |
| [Menu]  |                                                         |
| [Items] |  <main>                                                 |
|         |    @RenderBody()                                        |
|         |  </main>                                                |
|         |                                                         |
+---------+---------------------------------------------------------+
|  FOOTER (40px)                                                    |
|  la organización | v1.0.0 | Política Privacidad   |
+------------------------------------------------------------------+
```

---

## Colores Rápidos

```css
/* Colores principales */
--brand-primary:        #33475B;  /* Principal */
--brand-primary-light:  #0066CC;  /* Enlaces, acentos */
--brand-neutral-dark: #333333;  /* Texto principal */
--brand-neutral-light:  #F5F5F5;  /* Fondos secundarios */
--brand-white:      #FFFFFF;  /* Fondos principales */
--brand-error:       #CC0000;  /* Errores, alertas críticas */
--brand-exito:       #28A745;  /* Éxito, confirmaciones */
--brand-warning:     #FFC107;  /* Advertencias */
```

---

## Instrucciones para Claude

### Al crear un nuevo layout:

1. **Leer** `templates/_Layout.cshtml` como base
2. **Incluir** `templates/site.css` en wwwroot/css/
3. **Adaptar** el menú del sidebar según módulos del proyecto
4. **Verificar** contraste de colores (mínimo 4.5:1)
5. **Probar** responsive en los 3 breakpoints

### Al modificar estilos:

1. **Consultar** `patterns/colores-corporativos.md` antes de usar colores
2. **Usar** variables CSS definidas, no valores hardcodeados
3. **Mantener** consistencia con el resto de la aplicación
4. **Verificar** accesibilidad después de cambios

### Al añadir componentes:

1. **Seguir** la estructura HTML semántica (header, nav, main, footer)
2. **Incluir** atributos ARIA donde corresponda
3. **Asegurar** navegación por teclado
4. **Añadir** estados de focus visibles

---

## Ejemplo de Uso

```csharp
// En _ViewImports.cshtml
@using MiProyecto.Web
@addTagHelper *, Microsoft.AspNetCore.Mvc.TagHelpers

// En _ViewStart.cshtml
@{
    Layout = "_Layout";
}
```

```html
<!-- En cualquier vista -->
@{
    ViewData["Title"] = "Mi Página";
    ViewData["Breadcrumb"] = new[] { "Inicio", "Módulo", "Mi Página" };
}

<div class="page-content">
    <h1>@ViewData["Title"]</h1>
    <!-- Contenido -->
</div>
```

---

## Checklist de Verificación

Antes de dar por terminado un layout, verificar:

- [ ] Logo (theme.logoUrl) en header
- [ ] Colores corporativos aplicados
- [ ] Sidebar funcional (colapsa en tablet/móvil)
- [ ] Footer con versión e información legal
- [ ] Responsive en 3 breakpoints (>1200, 768-1200, <768)
- [ ] Contraste de colores 4.5:1 mínimo
- [ ] Navegación por teclado funcional
- [ ] Skip to content link presente
- [ ] Roles ARIA en landmarks (banner, navigation, main, contentinfo)

---

*Skill webapp-layout v3.7.0 - Estándares de diseño web (tema configurable)*
