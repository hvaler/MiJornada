# Contrato de Hub — `register_agentdoc` + endpoints DOC

> **Esta es la pieza server-side que gatea todo el flujo.** Sin ella, `docs-agente-sync` corre en modo
> `[SKIP]` (404) — inofensivo, pero no registra nada. Requiere trabajo en `Ovillo.Hub`.

Las 14 tools actuales del Hub (`register_decision`, `register_lesson`, `register_pipeline`, …) **no**
contemplan documentación de agente. DOC-nnn es un tipo de registro nuevo, hermano de QR-nnn.

## 1. Endpoints REST (los que consume el script)

Simétricos a los de calidad (`/v2/sync/quality-batch`, `/v2/stats/quality/{id}`):

| Método | Ruta | Uso |
|---|---|---|
| `GET` | `/v2/stats/docs/{proyectoId}` | Devuelve `{ ultimoNumero, total, ultimoSync }` para numerar DOC-nnn. |
| `POST` | `/v2/sync/docs-batch` | UPSERT de N DOC. Header `X-Hub-Api-Key` (service-key, ADR-045). |

### Payload del POST (lo que emite `Sync-AgentDoc.ps1`)

```jsonc
{
  "proyectoId": "<GUID>",
  "buildId": "12345",
  "generados": [
    {
      "codigo": "DOC-001",
      "entrypoint": "MyCompany.X.Api",
      "docPath": "docs/agente/api.md",
      "srcStamp": "9f3a1c07be22",       // hash del subarbol de fuente AHORA
      "srcStampDoc": "9f3a1c07be22",    // hash sellado en el doc al generarlo
      "drift": "fresh",                  // fresh | stale | orphan
      "tokensEstimados": 2180,
      "gate": "PASS",                    // PASS | WARN
      "generadoCon": "3.16.0",
      "adrRelacionados": [],
      "codeSearchUrl": "https://devops.example.org/.../_search?type=code&text=MyCompany.X.Api"
    }
  ]
}
```

## 2. Tool MCP `register_agentdoc`

Para que un agente (o `/mcp-sync`) publique un DOC vía MCP además del REST batch. Firma alineada con
`register_pipeline`:

```
register_agentdoc(
  proyectoId:  string (GUID),
  codigo:      string,            // DOC-nnn; si se omite, el hub asigna el siguiente
  entrypoint:  string,
  docPath:     string,
  srcStamp:    string,
  srcStampDoc: string,
  drift:       "fresh"|"stale"|"orphan",
  tokensEstimados: int,
  gate:        "PASS"|"WARN",
  generadoCon: string,
  adrRelacionados: string[]
) -> { codigo, upserted: bool }
```

- **Idempotente**: UPSERT por `(ProyectoId, Codigo)` — mismo PK que QR/ADR/pipeline.
- **Atribución**: `devAlias` (per-dev) o `'ci'` (service-key), resuelto de la key igual que QR.

## 3. Esquema de persistencia (sugerido, análogo a QR)

```sql
CREATE TABLE mcp.RegistroDocAgente (
    Id               INT IDENTITY PRIMARY KEY,
    ProyectoId       UNIQUEIDENTIFIER NOT NULL,
    Code           VARCHAR(16)  NOT NULL,     -- DOC-nnn
    Entrypoint       NVARCHAR(200) NOT NULL,
    DocPath          NVARCHAR(400) NOT NULL,
    SrcStamp         VARCHAR(64)  NULL,
    SrcStampDoc      VARCHAR(64)  NULL,
    Drift            VARCHAR(8)   NOT NULL,      -- fresh|stale|orphan
    TokensEstimados  INT          NOT NULL,
    Gate             VARCHAR(4)   NOT NULL,      -- PASS|WARN
    GeneradoCon      VARCHAR(32)  NULL,
    DevAlias         NVARCHAR(120) NULL,
    FechaSync        DATETIME2    NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UQ_DocAgente UNIQUE (ProyectoId, Code)
);
```
Esquema `mcp` como namespace (convención schema-as-namespace). Zero-downtime: tabla nueva + índices,
sin tocar las de QR.

## 4. Dashboard (fase posterior, fuera de esta skill)

El dashboard de calidad (`docs/dashboard/calidad.html`) puede ganar una columna/tarjeta "Contexto de
agente" por proyecto: `% docs fresh`, `nº stale`, `tokens totales de contexto`. Solo-lectura, Chart.js,
colores del tema — mismo patrón que las tarjetas de QR. **No** forma parte de `docs-agente-sync` (que es
solo el productor); es trabajo del repo del Hub/dashboard.

## 5. Orden de implementación recomendado

1. Tabla `mcp.RegistroDocAgente` + endpoints `GET /v2/stats/docs/{id}` y `POST /v2/sync/docs-batch`.
2. Tool MCP `register_agentdoc` (envuelve el mismo UPSERT).
3. Extender `hub-client` (subir de 14 → 15 tools; añadir `register_agentdoc` a su catálogo).
4. Piloto: un proyecto con `docs/agente/` poblada por `/analisis-arquitectura --agente`.
5. (Opcional) tarjeta de dashboard + hornear el step opt-out en `cicd-architect` fase2.

Hasta el paso 1, `docs-agente-sync` es totalmente instalable y corre en modo `[SKIP]` sin romper nada.
