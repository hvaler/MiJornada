# Migración TFS Classic (.xaml/.xoml) → YAML — guía manual

> Heredado de la skill `cicd-classic-migrator`, **retirada en v3.18.0 (ADR-053)** tras 6
> versiones como placeholder sin piloto. La migración automatizada NUNCA se implementó;
> este documento fija el camino **manual guiado** que era la vía [B] del placeholder y la
> única real. Si algún día un proyecto pide la automatización, este documento + el caso
> iMat2 son el punto de partida (camino de resurrección en ADR-053).

## Detección (cuándo aplica esta guía)

- Archivos `**/*.xaml` (build templates Classic)
- Archivos `**/*.xoml` (process orchestrator legacy)
- Carpeta `**/BuildProcessTemplates/` (TFS Classic process templates)
- El hook `pre-cicd-init.js` y la FASE 0 de `/cicd-init` detectan estos marcadores y
  ABORTAN el wizard apuntando aquí (el bootstrap greenfield no debe pisar un Classic vivo).

## Camino manual (el único soportado)

1. **Documenta** el pipeline Classic actual: steps, triggers, deploy targets, variables.
2. **Ejecuta `/cicd-init` en modo greenfield** ignorando el Classic existente — el YAML
   resultante sigue el patrón canónico del ecosistema (R1-R25, 3 fases de adopción).
3. **Validación side-by-side**: ejecutar Classic + YAML en paralelo 1-2 sprints. En PROD,
   mínimo 1 semana verde antes de retirar el Classic.
4. Una vez validado, **archiva** los `.xaml`/`.xoml` en `_legacy_classic/` (no borrar del
   repo: son la documentación del comportamiento anterior).
5. **Retira el pipeline Classic en TFS UI** marcándolo "deprecated" primero — NO borrar la
   definición hasta consolidar (se pierde el history de builds).

## Mapeo de referencia (Classic → YAML)

| Classic | YAML canónico del ecosistema |
|---|---|
| `dotnet.MSBuild` | `DotNetCoreCLI@2` (build) — o `VSBuild@1` en netfx (R23) |
| `dotnet.VSTest` | `dotnet test --collect:"XPlat Code Coverage"` |
| `dotnet.Publish` | `dotnet publish` + `PublishBuildArtifacts@1` |
| Agent pools Classic / deployment groups | `pool: BUILDERS` + capability `DeployTarget=<valor real>` (R1) |
| Triggers manuales por tag | `trigger.tags` o modelo on-demand `DeployEnv` (R20) |
| Tags semver+contador (`tag_mainback_X.Y.Z_(N)`) | mantener formato si el equipo los usa como gate PRE/PROD (caso iMat2) |

## Anti-patrones (NUNCA)

- ❌ Migrar sin validación side-by-side previa (rompe deploy en producción).
- ❌ Borrar `.xaml`/`.xoml` antes de que el YAML lleve ≥1 semana validado en DEV/DEMO/PROD.
- ❌ Asumir que el Classic cumplía R1-R25 — funcionaba por convención implícita; el YAML
  nuevo debe auditarse con el agent `cicd-pipeline-reviewer`.
- ❌ Migrar muchas canalizaciones en un solo PR — fragmentar por entorno o por stack
  (iMat2: 8 canalizaciones).

## Caso real: iMat2 (GestionAcademica)

Ver `imat2-case-study.md` (mismo directorio): 8 canalizaciones Classic (build + 3 entornos
× 2 stacks Front/Back + 1 release), pool BUILDERS, tags semver+contador como triggers
PRE/PROD. Análisis publicado:
`Publicacion/docs/referencia/analisis/analisis-integracion-cicd.html#caso-imat2`.

## Referencias

- ADR-042 § D3 (la migración Classic se separó del bootstrap `/cicd-init`)
- ADR-053 (retirada de la skill placeholder + camino de resurrección)
- Reglas `cicd-runtime.md` (R1-R25) — aplican al YAML resultante, NO al Classic
