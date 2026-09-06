# Patrón - Base de Conocimiento

> **Patrón** es el indice de conocimiento estatico del ecosistema **Ovillo**.
> Cataloga y organiza toda la documentacion de referencia, reglas y patrones disponibles.

---

## Por que "Patrón"

El nombre **Patrón** proviene del hueso atlas (C1), la primera vertebra cervical que permite
a la cabeza moverse y orientarse para ver el mundo. De la misma forma, Patrón permite a Claude
**orientarse** en la base de conocimiento del proyecto: saber que documentacion existe, donde
encontrarla y cuando consultarla.

Patrón no es un repositorio de documentos (esos estan en `Documentos_Base/`, `.claude/rules/` y
`.claude/skills/`). Patrón es el **mapa** que los indexa y los hace accesibles.

---

## Que Indexa Patrón

| Fuente | Contenido | Archivos |
|--------|-----------|----------|
| `Documentos_Base/01_Estructura_Tecnica/` | Infraestructura, seguridad, arquitectura | ~4 |
| `Documentos_Base/02_Diseno_Usabilidad/` | Guia de estilos UI, colores del tema | ~2 |
| `Documentos_Base/03_Consideraciones_Comunes/` | RGPD, normativa, accesibilidad | ~2 |
| `Documentos_Base/04_Plantillas_Documentacion/` | Plantillas de docs tecnicas | ~3 |
| `Documentos_Base/05_Plantillas_SQL/` | Plantillas SQL Server | ~7 |
| `Documentos_Base/06_Observabilidad/` | OpenTelemetry, Serilog, metricas | ~1 |
| `Documentos_Base/07_Resiliencia/` | Polly v8+, Health Checks | ~1 |
| `.claude/rules/` | Reglas condicionales por tipo de archivo | ~10 |
| `.claude/skills/*/patterns/` | Patrones de skills | ~15 |

**Total**: ~45 documentos de referencia indexados.

---

## Estructura del Indice

El archivo `INDICE.json` contiene un manifiesto estructurado con:

- **Ruta** al documento
- **Titulo** descriptivo
- **Tags** para busqueda semantica
- **Tipo**: guia, plantilla, regla o patron
- **Categoria** tematica

---

## Como Consultarlo

### Actual (v3.0.0)
Claude lee `PATRON.md` y `INDICE.json` para saber que documentacion esta disponible.
Cuando necesita informacion sobre un tema (ej: "seguridad", "testing", "SQL"), consulta
el indice y luego lee el archivo correspondiente.

### Futuro (servidor MCP)
`INDICE.json` esta preparado para ser consumido por un servidor MCP dedicado que permita
busqueda semantica sobre toda la base de conocimiento.

---

## Relacion con el Ecosistema Ovillo

```
Ovillo (ecosistema completo)
  |
  +-- Hilo (_hilo/)        --> Memoria dinamica (cambia con cada proyecto)
  |     "Que ha pasado en ESTE proyecto"
  |
  +-- Patrón (_patron/)        --> Conocimiento estatico (igual para todos los proyectos)
  |     "Que sabe Ovillo sobre como desarrollar"
  |
  +-- Documentos_Base/       --> Los documentos reales (Patrón los indexa)
  +-- .claude/rules/         --> Las reglas reales (Patrón las indexa)
  +-- .claude/skills/        --> Los skills reales (Patrón los indexa)
```

### Diferencia clave Hilo vs Patrón

| Aspecto | Hilo | Patrón |
|---------|-------|-------|
| **Contenido** | Estado de ESTE proyecto | Conocimiento general del ecosistema |
| **Cambia** | En cada sesion | Solo con nuevas versiones de Ovillo |
| **Ejemplo** | "El proyecto usa .NET 10 con EF Core" | "Asi se configura EF Core en .NET 10" |
| **Equivalente** | Memoria de trabajo | Enciclopedia de referencia |

---

## Archivos en _patron/

| Archivo | Proposito |
|---------|-----------|
| `PATRON.md` | Este archivo - Descripcion del componente |
| `INDICE.json` | Manifiesto estructurado de toda la documentacion |

---

*Base de Conocimiento Patrón - Ovillo v3.7.0*
