# Patrones para Monorepo

> Skill: git-best-practices | Version: 3.5.0

Estrategias para gestionar repositorios monoliticos con multiples proyectos.

---

## Cuando Usar Monorepo

| Criterio | Monorepo | Multi-repo |
|----------|----------|------------|
| Dependencias compartidas | Fuertes | Debiles/ninguna |
| Deploy sincronizado | Si | No |
| Equipos | 1-3 equipos | Equipos independientes |
| CI/CD | Centralizado | Por proyecto |
| Ejemplo | API + Frontend + Shared | Microservicios independientes |

---

## Estructura Recomendada

```
monorepo/
├── .github/
│   ├── workflows/
│   │   ├── api.yml          # CI solo para API
│   │   ├── frontend.yml     # CI solo para frontend
│   │   └── shared.yml       # CI para librerias compartidas
│   └── CODEOWNERS
├── src/
│   ├── api/                  # Proyecto API .NET 10
│   │   ├── MyCompany.App.Api/
│   │   └── MyCompany.App.Api.sln
│   ├── frontend/             # Proyecto frontend
│   │   ├── package.json
│   │   └── src/
│   └── shared/               # Librerias compartidas
│       ├── MyCompany.App.Domain/
│       └── MyCompany.App.Shared/
├── docs/
├── tools/
│   └── scripts/
├── .gitignore
├── .gitattributes
├── CODEOWNERS
└── README.md
```

---

## CODEOWNERS

```
# .github/CODEOWNERS
# Cada seccion es propiedad de un equipo

# Global
* @myorg/platform-leads

# API
/src/api/ @myorg/backend-team
*.cs @myorg/backend-team

# Frontend
/src/frontend/ @myorg/frontend-team
*.tsx @myorg/frontend-team
*.ts @myorg/frontend-team

# Shared libraries (require senior review)
/src/shared/ @myorg/architects

# Infrastructure
/.github/ @myorg/devops
/tools/ @myorg/devops

# Documentation
/docs/ @myorg/tech-writers
```

---

## Sparse Checkout (Git 2.25+)

Para trabajar solo con una parte del monorepo:

```bash
# Clonar con sparse checkout
git clone --sparse https://github.com/myorg/monorepo.git
cd monorepo

# Añadir solo las carpetas necesarias
git sparse-checkout set src/api src/shared

# Ahora solo tienes src/api/ y src/shared/
# Las demas carpetas no se descargan

# Añadir mas carpetas
git sparse-checkout add docs

# Ver que esta incluido
git sparse-checkout list
```

---

## Path Filters en CI/CD

### GitHub Actions

```yaml
# .github/workflows/api.yml
on:
  push:
    paths:
      - 'src/api/**'
      - 'src/shared/**'
    branches: [main]
  pull_request:
    paths:
      - 'src/api/**'
      - 'src/shared/**'
```

### Azure DevOps

```yaml
trigger:
  paths:
    include:
      - src/api/*
      - src/shared/*
    exclude:
      - docs/*
      - '**/*.md'
```

---

## Partial Clone (Git 2.22+)

Para repositorios muy grandes:

```bash
# Clone sin blobs (se descargan bajo demanda)
git clone --filter=blob:none https://github.com/myorg/monorepo.git

# Clone sin arboles ni blobs
git clone --filter=tree:0 https://github.com/myorg/monorepo.git
```

---

## Mantenimiento

```bash
# Git 2.52 - Geometric maintenance (optimo para monorepos)
git maintenance start

# Configurar mantenimiento automatico
git config maintenance.auto true
git config maintenance.strategy incremental

# Repack con path-walk (Git 2.51+, packs mas pequenos)
git repack -d --path-walk
```

---

*Pattern v3.7.0*
