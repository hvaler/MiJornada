---
globs:
  - "**/*Client.cs"
  - "**/Integrations/**/*.cs"
  - "**/External/**/*.cs"
description: Activacion condicional para consultar docs externas via Context7 cuando se edita codigo de integracion con sistemas externos configurados
---

# Reglas para Integracion con Dominios Externos (Context7)

> **Esta regla es una plantilla**. El catalogo de sistemas externos se define en DOS niveles:
> `ecosystem.config.json → integrations[]` (organizacion) y
> `_hilo/ESTADO_PROYECTO.json → dominiosExternos[]` (proyecto — gana si ambos definen el mismo
> sistema). **Sin catalogo (default del fork: vacio), esta regla NO dispara** (cero fetches
> Context7 automaticos, cero asunciones de sistemas propietarios).

**Origen**: item J1 bloque J, ADR-034 del ecosistema origen. Generalizada en el fork (ADR-F002).

---

## Cuando aplica

Cuando Claude edita archivos cuyo path casa con el `folderPattern`/`carpetaPattern` de una
entrada del catalogo (tipicamente `**/{namespacePrefix}.{Proyecto}.{CarpetaPattern}/**/*.cs`),
debe **consultar Context7** para obtener docs actualizadas de la API externa correspondiente.

## Configuracion

Nivel organizacion (`ecosystem.config.json`):

```json
{
  "integrations": [
    {
      "name": "Oracle HCM Cloud",
      "kind": "rest",
      "folderPattern": "HCM.Services",
      "context7Library": "oracle/oracle-hcm-cloud-rest-api",
      "reason": "API con updates trimestrales - el schema cambia 4x al ano"
    }
  ]
}
```

Nivel proyecto (`_hilo/ESTADO_PROYECTO.json`, campo opcional `dominiosExternos` — mismo shape
con claves en espanol: `nombre`, `carpetaPattern`, `context7Library`, `razon`, y opcionales
`anchorTopics[]` / `skipPaths[]`):

```json
{
  "dominiosExternos": [
    {
      "nombre": "API de facturacion del proveedor X",
      "carpetaPattern": "Facturacion.Services",
      "context7Library": "proveedor-x/facturacion-api",
      "razon": "API versionada trimestralmente",
      "anchorTopics": ["authentication", "rate-limiting"],
      "skipPaths": ["**/Facturacion.Services.Tests/**"]
    }
  ]
}
```

Si ambos catalogos estan vacios o ausentes: esta regla NO genera fetches Context7 automaticos.

## Comportamiento

Cuando Claude detecta edicion en un path que casa con un `folderPattern` del catalogo:

1. Resolver el catalogo efectivo (proyecto sobre organizacion).
2. Para cada entrada que matchea el path actual:
   - Antes de generar codigo, invocar `mcp__context7__resolve-library-id` con `context7Library`
   - Luego `mcp__context7__get-library-docs` con el ID resuelto (y `topic` si hay `anchorTopics`)
   - Usar la doc obtenida para validar firma de endpoints, schemas, tipos
3. Si Context7 no esta disponible o el library-id no resuelve: continuar con caution (no fallar)

## Cuando NO disparar

- Si el archivo es un test (`**/*Tests.cs`, `**/Tests/**`) o esta en `skipPaths`
- Si la edicion es trivial (typo fix, comment, rename variable local)
- Si el usuario explicitamente dice "no consultes docs" o similar
- Si ya se consulto Context7 para esa libreria en los ultimos 5 mensajes (cache local de sesion)

## Razon de existir esta regla

Las APIs externas de una organizacion suelen tener ciclos de cambio rapidos (SaaS con updates
trimestrales, estandares con versiones anuales). Sin consultar docs frescas, Claude puede:
- Usar endpoints deprecated
- Asumir schemas que ya no existen
- Configurar auth obsoleto

Context7 fetch dirigido en el momento adecuado elimina este riesgo sin penalizar performance
(solo se invoca cuando se toca codigo del dominio especifico). Si la organizacion tiene un
mirror interno de Context7, configurarlo en `mcp.context7Url`.

## Anti-patrones

- **NO disparar para CADA archivo .cs del proyecto** — solo para los del dominio especifico (matching estricto)
- **NO consultar Context7 si la edicion es estructural** (refactor de nombres, etc.) — solo cuando se toca logica de integracion
- **NO inventar `context7Library`** — usar IDs reales que Context7 resuelve (consultar `resolve-library-id` primero)
- **NO hardcodear el catalogo en hooks ni reglas** — vive en `ecosystem.config.integrations[]`
  y `ESTADO_PROYECTO.dominiosExternos[]` para que cada organizacion/proyecto lo customice

## Sinergia con otros componentes

- Skill `api-integration-patterns` cubre el patron generico de integracion (HttpClient, OAuth2,
  retry). Esta regla complementa con docs domain-especificas del catalogo configurado.
- Skill `security-audit` puede usar docs Context7 para verificar que se aplican los patrones de
  auth especificos de cada API externa.

---

*Regla condicional plantilla Ovillo - generalizada desde ADR-034 (catalogo configurable, ADR-F002).*
