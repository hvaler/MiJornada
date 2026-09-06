# Permisos e infraestructura CI/CD — PLANTILLA (inventario original retirado en el fork Ovillo)

> **Estado**: el documento original era el *handoff a Sistemas* del ecosistema origen, con su
> inventario real de servidores, pools de agentes, capabilities y feeds internos. Ese inventario
> era específico de la organización y se retiró (ver `adr/ADR-F000`; original en el historial
> git). `/cicd-init` sigue generando una copia adaptada en `05_CICD/PERMISOS_CICD.md`.

Qué debe contener la versión de TU organización (estructura del original):

1. **Colección/organización de la plataforma CI/CD** (`cicd.platform` + URL) y proyecto.
2. **Pool(s) de agentes** — nombre, tipo (build vs deploy), servidores donde corren.
3. **Capabilities de routing de deploy** — etiqueta por agente (ej. `DeployTarget=<env>-<tipo>`),
   alineadas con `ecosystem.config.cicd.environments[].deployTarget`.
4. **Cuenta de servicio de los agentes** y permisos requeridos (deploy local, IIS/systemd,
   carpetas de backup).
5. **Feeds de paquetes internos** — ruta/URL accesible DESDE los agentes (no solo desde la red
   de usuarios).
6. **Variable groups / secret stores** — quién los crea, quién autoriza pipelines.
7. **Aprobadores por entorno** (`environments[].approvers`) y environments/gates de la
   plataforma.
8. **Retention y disco** — política de artefactos (invariante G10).

> `/cicd-init` deriva los valores reales del pool configurado en vez de asumir este documento:
> la plantilla es la lista de peticiones a Sistemas, no la fuente de verdad del runtime.
