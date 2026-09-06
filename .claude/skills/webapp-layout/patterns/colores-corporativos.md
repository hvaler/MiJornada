# Colores Corporativos (tokens de tema)

> Paleta oficial de colores para aplicaciones web de la la organización.

---

## Colores Principales

### Color primario (Principal)
```css
--brand-primary: #33475B;
```
- **Uso**: Header, sidebar, botones primarios, títulos principales
- **RGB**: 0, 51, 102
- **HSL**: 210°, 100%, 20%

### Azul Claro (Secundario)
```css
--brand-primary-light: #0066CC;
```
- **Uso**: Enlaces, hover states, iconos, acentos
- **RGB**: 0, 102, 204
- **HSL**: 210°, 100%, 40%

### Azul Hover
```css
--brand-primary-hover: #004D99;
```
- **Uso**: Estados hover de botones primarios
- **RGB**: 0, 77, 153
- **HSL**: 210°, 100%, 30%

---

## Colores Neutros

### Gris Oscuro (Texto)
```css
--brand-neutral-dark: #333333;
```
- **Uso**: Texto principal, párrafos
- **RGB**: 51, 51, 51
- **Contraste con blanco**: 12.6:1

### Gris Medio
```css
--brand-neutral-medio: #666666;
```
- **Uso**: Texto secundario, placeholders
- **RGB**: 102, 102, 102
- **Contraste con blanco**: 5.7:1

### Gris Claro (Fondo)
```css
--brand-neutral-light: #F5F5F5;
```
- **Uso**: Fondos secundarios, cards, separadores
- **RGB**: 245, 245, 245

### Blanco
```css
--brand-white: #FFFFFF;
```
- **Uso**: Fondo principal, texto sobre azul
- **RGB**: 255, 255, 255

---

## Colores de Estado

### Error / Alerta Crítica
```css
--brand-error: #CC0000;
```
- **Uso**: Mensajes de error, validaciones fallidas, alertas críticas
- **RGB**: 204, 0, 0
- **Contraste con blanco**: 6.5:1

### Éxito
```css
--brand-exito: #28A745;
```
- **Uso**: Confirmaciones, operaciones exitosas
- **RGB**: 40, 167, 69
- **Contraste con blanco**: 4.5:1

### Advertencia
```css
--brand-warning: #FFC107;
```
- **Uso**: Avisos, información importante
- **RGB**: 255, 193, 7
- **Nota**: Usar texto oscuro (#333) sobre este fondo

### Información
```css
--brand-info: #17A2B8;
```
- **Uso**: Información contextual, tooltips
- **RGB**: 23, 162, 184
- **Contraste con blanco**: 4.5:1

---

## Variables CSS Completas

```css
:root {
    /* Principales */
    --brand-primary: #33475B;
    --brand-primary-light: #0066CC;
    --brand-primary-hover: #004D99;
    --brand-primary-light: #E6F0FF;

    /* Neutros */
    --brand-neutral-dark: #333333;
    --brand-neutral-medio: #666666;
    --brand-neutral-light: #F5F5F5;
    --brand-white: #FFFFFF;
    --brand-borde: #DDDDDD;

    /* Estados */
    --brand-error: #CC0000;
    --brand-error-bg: #FFE6E6;
    --brand-exito: #28A745;
    --brand-exito-bg: #E6F4EA;
    --brand-warning: #FFC107;
    --brand-warning-bg: #FFF8E1;
    --brand-info: #17A2B8;
    --brand-info-bg: #E1F5FE;

    /* Sombras */
    --brand-sombra-sm: 0 1px 2px rgba(0, 0, 0, 0.1);
    --brand-sombra-md: 0 4px 6px rgba(0, 0, 0, 0.1);
    --brand-sombra-lg: 0 10px 15px rgba(0, 0, 0, 0.1);
}
```

---

## Combinaciones de Contraste

### Texto sobre fondos (WCAG AA - 4.5:1 mínimo)

| Fondo | Color Texto | Ratio | Estado |
|-------|-------------|-------|--------|
| Blanco (#FFF) | Azul (#33475B) | 12.6:1 | OK |
| Blanco (#FFF) | Gris oscuro (#333) | 12.6:1 | OK |
| Blanco (#FFF) | Gris medio (#666) | 5.7:1 | OK |
| Azul (#33475B) | Blanco (#FFF) | 12.6:1 | OK |
| Gris claro (#F5F5F5) | Azul (#33475B) | 11.5:1 | OK |
| Gris claro (#F5F5F5) | Gris oscuro (#333) | 11.5:1 | OK |
| Warning (#FFC107) | Gris oscuro (#333) | 8.5:1 | OK |

### Colores que NO cumplen contraste

| Combinación | Ratio | Problema |
|-------------|-------|----------|
| Blanco + Azul claro (#0066CC) | 4.1:1 | Usar solo para elementos grandes |
| Gris claro + Gris medio | 3.1:1 | No usar para texto |

---

## Uso en Componentes

### Botones

```css
/* Botón primario */
.btn-brand-primary {
    background-color: var(--brand-primary);
    color: var(--brand-white);
    border: none;
}

.btn-brand-primary:hover {
    background-color: var(--brand-primary-hover);
}

/* Botón secundario */
.btn-brand-secondary {
    background-color: var(--brand-white);
    color: var(--brand-primary);
    border: 2px solid var(--brand-primary);
}
```

### Enlaces

```css
a {
    color: var(--brand-primary-light);
    text-decoration: none;
}

a:hover {
    color: var(--brand-primary);
    text-decoration: underline;
}

a:focus {
    outline: 2px solid var(--brand-primary-light);
    outline-offset: 2px;
}
```

### Alertas

```css
.alert-error {
    background-color: var(--brand-error-bg);
    border-left: 4px solid var(--brand-error);
    color: var(--brand-neutral-dark);
}

.alert-success {
    background-color: var(--brand-exito-bg);
    border-left: 4px solid var(--brand-exito);
}
```

---

## Reglas de Uso

1. **Nunca usar** colores fuera de esta paleta sin aprobación
2. **Siempre usar** variables CSS, no valores hardcodeados
3. **Verificar contraste** antes de crear nuevas combinaciones
4. **El color primario** es el color principal, usarlo con moderación
5. **Evitar** texto gris medio sobre fondos claros para contenido importante

---

*Última actualización: Enero 2026*
