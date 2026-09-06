# Fases de adopcion CI/CD — Referencia rapida

> Para guia humana detallada ver `Documentos_Base/08_CICD/GUIA_FASES_ADOPCION.md`.

## Arbol de decision

```
¿Tienes acceso TFS + BUILDERS autorizado al proyecto?
├── NO  → Fase 0 (solo Ovillo local)
└── SI  → ¿Tienes agentes <ENV>_DEPLOY online en todos los servers destino?
         ├── NO  → Fase 1 (build validation only)
         └── SI  → ¿Existe grupo aprobadores TFS con ≥2 miembros?
                  ├── NO  → Fase 1 (crear grupo en paralelo)
                  └── SI  → Fase 2 (pipeline completo CD)
```

## Tabla comparativa

| Aspecto | Fase 0 | Fase 1 | Fase 2 |
|---|---|---|---|
| `azure-pipelines.yml` | NO | SI (minimal) | SI (completo) |
| Build remoto en TFS | NO | SI | SI |
| Tests en CI | NO (local /verify) | SI | SI |
| Build validation branch policy | NO | SI | SI |
| Deploy DEV auto | Manual | NO | SI |
| Deploy DEMO manual gate | Manual | NO | SI (`ManualValidation@0`) |
| Deploy PROD group approval | Manual | NO | SI (Environment + ≥2 approvers) |
| Triple rollback (R15) | Manual | NO | SI |
| Variable Group secretos | Manual config | Opcional | SI con fail-fast |
| Retention rules (R17) | NO | SI master 30d/5 | SI master 30d/5 + otras 7d/1 |
| Coverage gate (R18) | Manual | SI | SI |
| Runbook (R19) | `RUNBOOK_DEPLOY_MANUAL.md` | Minimal | `RUNBOOK.md` 6 secciones |
| Hub MCP register | NO | SI | SI |
| Esfuerzo inicial | 0h | ~2h | ~6h |

## Que genera `/cicd-init` por fase

### Fase 0

```
05_CICD/
├── README.md
└── RUNBOOK_DEPLOY_MANUAL.md     ← procedimiento deploy manual paso a paso
```

NO toca: `azure-pipelines.yml`, Hub MCP, TFS pipeline definition.

### Fase 1

```
azure-pipelines.yml              ← stage Build unico (sin CD)
05_CICD/
├── README.md
├── PIPELINE_BUILD.md
└── LIMITACIONES_TFS_2020.md     ← copia checksum-tracked
```

Vue+Vite: sin gate de cobertura .NET (Mira es .NET); usar el coverage propio del stack JS.
Registra pipeline TFS via FASE 2.5. Registra en Hub MCP via FASE 2.6.

### Fase 2

```
azure-pipelines.yml              ← Build + DeployDev + DeployDemo + DeployProd
05_CICD/
├── README.md
├── PIPELINE_DEV.md
├── PIPELINE_DEMO.md
├── PIPELINE_PROD.md
├── RUNBOOK.md                   ← 6 secciones adaptadas al proyecto
├── LIMITACIONES_TFS_2020.md
└── SECRETOS.md                  ← si VG creado
04_Pruebas/
└── (R18 usa umbrales de cobertura; sin fichero .crap-exceptions.json)
```

Registra pipeline + crea Variable Group (si opt-in) + registra en Hub MCP.

## Promocion entre fases

`/cicd-init` es idempotente. Re-ejecutar en proyecto con instalacion previa activa modo edicion (FASE 0.5) con 5 opciones:

1. **Añadir nuevo stage** — promocion Fase 1 → Fase 2 (añadir DeployDev/Demo/Prod sin tocar Build)
2. **Modificar stage existente** — cambiar approver, capability, secrets...
3. **Regenerar SOLO docs** — `05_CICD/` se actualiza, YAML intacto
4. **Actualizar YAML completo** — preserva marcadores `# CUSTOM:` ... `# /CUSTOM`
5. **Salir sin cambios**

Backup automatico: `azure-pipelines.yml.bak.YYYYMMDD-HHmmss` antes de cualquier escritura.

## Anti-patrones

- ❌ **Saltar de Fase 0 a Fase 2** sin haber pasado por Fase 1. Posible pero arriesgado — primer fallo PROD sera catastrofico sin practica.
- ❌ **Pedir Fase 2 sin agentes `<ENV>_DEPLOY`** — FASE 0.4 pre-flight bloquea con D1-D3.
- ❌ **Tratar Fase 0 como "no CI/CD"** — la primera barrera (`/verify` 7 fases local) es CI/CD real.
- ❌ **Editar YAML ignorando R1-R25** — el agent `cicd-pipeline-reviewer` lo detecta, pero la disciplina humana es mas barata.

---

*Referencia rapida v3.11.0 — `Documentos_Base/08_CICD/GUIA_FASES_ADOPCION.md`*
