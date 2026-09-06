# Caso de estudio: iMat2 (GestionAcademica)

> Primer caso real CI/CD en producción del equipo del ecosistema origen. Validó empíricamente el patrón BUILDERS+capability pero NO siguió las 25 reglas R1-R25 (no existían cuando se construyó). **Piloto de la migración v3.12.0** vía `cicd-classic-migrator`.

## Características técnicas

| Aspecto | Valor |
|---|---|
| **Proyecto** | iMat2 — Integración Enrollments 2 (GestionAcademica) |
| **Stack** | .NET 10 |
| **Pipelines existentes** | 8 canalizaciones TFS Classic (NO YAML) |
| **Pool** | BUILDERS self-hosted (mismo patrón del ecosistema) |
| **Servidor BD** | SQL Server 2017 (parque de la organización) |
| **Servidores deploy** | DEV (devwww), PRE (demowww), PROD (strify01 + strify02 rolling) |
| **Auth** | Azure AD (Microsoft Entra ID) |
| **Trigger PRE/PROD** | Tags semver+contador: `tag_mainback_X.Y.Z_(N)` |

## Las 8 canalizaciones

```
Front Back
 ├── Build (separadas: Front Vue / Back .NET)
 ├── DeployDev (auto, push a master)
 ├── DeployPre (manual, trigger por tag)
 └── DeployProd (manual, trigger por tag, 2 servers serie)
```

Total: 2 stacks × 4 stages = 8 canalizaciones Classic.

## Gap identificado (vs Ovillo v3.11.0)

iMat2 cubre las **3 etapas básicas** que el pack del colega también cubrió:
- ✅ Build / Restore / Build / Publish / PublishArtifact
- ✅ Deploy real en Release pipeline separada
- ✅ Pool BUILDERS

iMat2 **NO cubre 6 etapas** que `/verify` Ovillo local SÍ cubre:
- ❌ Tests (no hay `dotnet test` en el pipeline; los tests están en `/verify` local)
- ❌ Security audit (no hay scan SAST; está en skill `security-audit` local)
- ❌ Format check (no hay `dotnet format --verify`; está en `/verify`)
- ❌ Anti-patterns linter R12 (no existe en pipeline)
- ❌ Diff review (no hay code-review automatizado en pipeline)
- ❌ Coverage gate R18 (sin tests/cobertura)

**Esto confirmó empíricamente el modelo de doble barrera** (`analisis-integracion-cicd.html`):
- **Barrera 1**: Ovillo local (`/verify` 7 fases pre-push) — covers 9/15 etapas
- **Barrera 2**: Pipeline TFS (Build + Deploy) — covers 6/15 etapas restantes

## Particularidades a respetar en la migración v3.12.0

### 1. Tags semver+contador como triggers PRE/PROD

iMat2 usa el formato `tag_mainback_X.Y.Z_(N)` donde:
- `mainback` = stack Backend `.NET` (vs `mainfront` para Vue)
- `X.Y.Z` = semver
- `(N)` = build counter (incrementa en cada tag)

Equivalente YAML:

```yaml
trigger:
  branches:
    include:
      - refs/tags/tag_mainback_*    # PRE
      - refs/tags/tag_prod_mainback_*  # PROD
```

⚠️ El parser debe preservar este formato exacto (regex `tag_(main|prod_main)(back|front)_\d+\.\d+\.\d+_\(\d+\)`) durante la migración.

### 2. Separación estricta Front/Back × 3 entornos

NO mezclar Front y Back en mismo pipeline. La migración debe generar:

```
azure-pipelines.front.yml      ← stage Build (Vue) + DeployDev/Pre/Prod Front
azure-pipelines.back.yml       ← stage Build (.NET) + DeployDev/Pre/Prod Back
```

O usar un único `azure-pipelines.yml` con stages condicionados por `parameters.stack`.

### 3. Multi-server PROD rolling sin Environment groups

iMat2 hace rolling deploy en 2 servers PROD (strify01 → strify02) **sin** usar Environment + group approval — la aprobación es manual del JP via tag.

La migración v3.12.0 debe ofrecer dos opciones:
- **Opción A**: mantener tag-trigger (compatible iMat2 actual)
- **Opción B**: migrar a Environment + group approval (R15 + R1 Ovillo estándar)

Recomendación: opción B con aprovacion por grupo `iMat2-Approvers-Prod`.

### 4. Pool BUILDERS — sin cambios

iMat2 ya usa BUILDERS, NO necesita cambio. La migración solo añade capability `DeployTarget=<env>` a los agentes destino (puede hacerse en paralelo con la migración del pipeline).

## Riesgos de la migración

| Riesgo | Mitigación |
|---|---|
| Romper deploys de producción en curso | Validación side-by-side: ejecutar Classic + YAML en paralelo 2 sprints antes de retirar Classic |
| Perder history de builds Classic | NO borrar pipelines Classic — solo marcar "deprecated" en TFS UI hasta validar 1 mes |
| Tags semver no se interpretan igual en YAML | Tests extensivos con tags reales antes de mergear |
| Equipo iMat2 sin onboarding Ovillo | Sesión de formación pre-migración (~2h) |

## Cronograma propuesto v3.12.0

1. **Sprint 1**: Análisis exhaustivo de las 8 canalizaciones Classic, mapeo manual a YAML
2. **Sprint 2**: Implementar skill `cicd-classic-migrator` con el algoritmo de migración
3. **Sprint 3**: Validación side-by-side iMat2 en DEV (Classic + YAML simultáneos)
4. **Sprint 4**: Validación PRE
5. **Sprint 5**: Validación PROD con rollback plan
6. **Sprint 6**: Retirada de Classic + retrospectiva

Estimación: ~12 semanas (Q3 2026).

## Análisis publicado

Ver detalle completo en:
- `Publicacion/docs/referencia/analisis/analisis-integracion-cicd.html#caso-imat2` (actualizado 2026-04-13)
- ADR-025 § Actualización 2026-04-13 (en `_estado/DECISIONES.md` del constructor Ovillo)

## Memoria del proyecto (a crear)

Cuando arranque el piloto v3.12.0, crear:
- `memory/cicd_imat2_pipeline.md` con notas operativas del piloto

---

*Case study v3.11.0 — Para piloto v3.12.0.*
