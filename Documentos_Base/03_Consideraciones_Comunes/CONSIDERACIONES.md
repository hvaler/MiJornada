# Consideraciones Comunes — PLANTILLA (contenido original retirado en el fork Ovillo)

> **Estado**: el contenido original (normativa, RGPD, accesibilidad RD 1112/2018, integraciones
> corporativas y regulación interna del ecosistema origen) era específico de esa
> organización y se retiró del fork. Ver `adr/ADR-F000` (decisión #8) del repo constructor.
> El original está en el historial git de este repo.

Cada organización debe redactar aquí sus consideraciones transversales. Estructura recomendada
(la que usaba el original):

1. **Marco normativo aplicable** — leyes de protección de datos de tu jurisdicción (RGPD/
   equivalente), normativa sectorial, política interna. Tabla: norma | ámbito | obligatoriedad.
2. **Protección de datos** — categorías de datos tratados, base legal, contacto del DPO,
   checklist antes de tratar datos personales (minimización, cifrado, retención, derechos).
3. **Accesibilidad** — nivel WCAG exigido por tipo de aplicación (el ecosistema audita AA por
   defecto en `webapp-layout`).
4. **Autenticación corporativa** — el IdP y tenant estándar (ver `ecosystem.config.identity`).
5. **Sistemas core y sus integraciones** — catálogo de sistemas del dominio (ver
   `ecosystem.config.integrations[]`), owners y ventanas de mantenimiento.
6. **Auditoría y trazabilidad** — qué eventos se auditan y dónde.
7. **Contactos internos** — tabla: tema | equipo responsable | canal.

> Mientras este documento no se personalice, Claude NO debe asumir ninguna normativa u
> obligación corporativa concreta: preguntar o señalar el hueco.
