# Jerarquía de Configuración - Claude Code (Ovillo)

## Resumen

La configuración sigue una jerarquía de 3 niveles, donde el más específico tiene prioridad:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     JERARQUÍA DE CONFIGURACIÓN                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   PRIORIDAD 1 (máxima)                                                      │
│   └── .claude/user-config.json                                              │
│       • Configuración PERSONAL del desarrollador                            │
│       • NO se commitea (está en .gitignore)                                │
│       • Cada desarrollador tiene la suya                                    │
│                                                                             │
│   PRIORIDAD 2                                                               │
│   └── _hilo/ESTADO_PROYECTO.json → configuracion                        │
│       • Configuración del PROYECTO                                          │
│       • SÍ se commitea (compartida por el equipo)                          │
│       • Define los defaults para todo el equipo                            │
│                                                                             │
│   PRIORIDAD 3 (mínima)                                                      │
│   └── Valores por defecto del sistema                                       │
│       • nivelIntegracionGit: "medio"                                        │
│       • confirmarPush: true                                                 │
│       • autoCheckoutMain: true                                              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Ejemplo Práctico

### Escenario: Equipo de 4 Personas

**Configuración del proyecto** (`ESTADO_PROYECTO.json`):
```json
{
  "configuracion": {
    "nivelIntegracionGit": "medio"
  }
}
```

**Configuraciones personales**:

| Desarrollador | user-config.json | Nivel Efectivo |
|---------------|------------------|----------------|
| Juan | `"nivelIntegracionGit": "alto"` | **alto** (personal) |
| María | `"nivelIntegracionGit": "basico"` | **basico** (personal) |
| Pedro | *(no tiene archivo)* | **medio** (proyecto) |
| Ana | `"nivelIntegracionGit": "medio"` | **medio** (personal) |

### Resultado

- **Juan** → Claude ejecuta Git automáticamente
- **María** → Claude solo sugiere comandos
- **Pedro** → Claude pregunta confirmación (usa config del proyecto)
- **Ana** → Claude pregunta confirmación (igual que proyecto, pero explícito)

## Archivos Involucrados

### `.claude/user-config.json` (Personal - NO se commitea)

```json
{
  "usuario": {
    "nombre": "jgarcia",
    "email": "jgarcia@example.com"
  },
  "preferencias": {
    "nivelIntegracionGit": "alto",
    "confirmarPush": true,
    "autoCheckoutMain": true,
    "mostrarSugerenciasGit": false,
    "formatoCommit": "[{codigo}] {tipo}: {mensaje}"
  },
  "notificaciones": {
    "verbosidad": "minimal"
  }
}
```

### `_hilo/ESTADO_PROYECTO.json` (Proyecto - SÍ se commitea)

```json
{
  "configuracion": {
    "nivelIntegracionGit": "medio",
    "convencionRamas": "feature/{codigo}",
    "prefijoCommit": "[{codigo}]",
    "ramaBase": "main"
  }
}
```

### `.gitignore` (Debe incluir)

```gitignore
# Configuración personal de Claude (NO commitear)
.claude/user-config.json
```

## Cómo Crear Configuración Personal

### Opción 1: Comando (recomendado)

```bash
/mi-config crear
```

Claude te guiará para crear tu configuración.

### Opción 2: Manual

1. Copiar la plantilla:
   ```bash
   cp .claude/user-config.template.json .claude/user-config.json
   ```

2. Editar con tus preferencias

3. Verificar que está en .gitignore

## Lógica de Lectura (para desarrolladores de Claude Code)

```javascript
/**
 * Obtiene una configuración respetando la jerarquía
 * @param {string} clave - Ruta de la configuración (ej: "preferencias.nivelIntegracionGit")
 * @param {any} defaultValue - Valor por defecto si no existe en ningún nivel
 * @returns {any} - El valor de la configuración
 */
function obtenerConfiguracion(clave, defaultValue) {
  // PRIORIDAD 1: Configuración personal
  try {
    const userConfig = JSON.parse(fs.readFileSync('.claude/user-config.json', 'utf8'));
    const valor = obtenerValorAnidado(userConfig, clave);
    if (valor !== undefined) {
      return { valor, origen: 'personal' };
    }
  } catch (e) {
    // No existe o error de lectura
  }

  // PRIORIDAD 2: Configuración del proyecto
  try {
    const estado = JSON.parse(fs.readFileSync('_hilo/ESTADO_PROYECTO.json', 'utf8'));
    const valor = obtenerValorAnidado(estado.configuracion, clave);
    if (valor !== undefined) {
      return { valor, origen: 'proyecto' };
    }
  } catch (e) {
    // No existe o error de lectura
  }

  // PRIORIDAD 3: Default
  return { valor: defaultValue, origen: 'default' };
}

// Ejemplo de uso:
const { valor: nivel, origen } = obtenerConfiguracion('nivelIntegracionGit', 'medio');
console.log(`Nivel Git: ${nivel} (${origen})`);
// Output: "Nivel Git: alto (personal)" o "Nivel Git: medio (proyecto)"
```

## Comandos Relacionados

| Comando | Descripción |
|---------|-------------|
| `/mi-config` | Ver configuración actual |
| `/mi-config crear` | Crear configuración personal |
| `/mi-config nivel {nivel}` | Cambiar nivel de integración Git |
| `/mi-config reset` | Eliminar configuración personal |

## Preguntas Frecuentes

### ¿Qué pasa si borro mi user-config.json?

Se usará la configuración del proyecto automáticamente.

### ¿Puedo tener un nivel diferente al resto del equipo?

Sí, ese es el objetivo. Tu configuración personal tiene prioridad.

### ¿Se sube mi configuración al repositorio?

No, `.claude/user-config.json` está en `.gitignore`.

### ¿Qué pasa si cambio de ordenador?

Deberás crear tu configuración personal de nuevo con `/mi-config crear`.

### ¿Puedo copiar mi configuración a otro proyecto?

Sí, puedes copiar el archivo `.claude/user-config.json` a otros proyectos que usen Claude Code (Ovillo).
