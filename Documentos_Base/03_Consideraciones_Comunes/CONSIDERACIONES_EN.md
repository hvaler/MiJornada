# Common Considerations — TEMPLATE (original content retired in the Ovillo fork)

> **Status**: the original content (regulations, GDPR specifics, accessibility law, corporate
> integrations and internal policy of the origin organization) was organization-specific and was
> retired from the fork. See `adr/ADR-F000` (decision #8) in the builder repo. The original is
> available in this repo's git history.

Each organization should write its cross-cutting considerations here. Recommended structure
(mirrors the original):

1. **Applicable regulations** — data-protection laws for your jurisdiction, sector rules,
   internal policy. Table: rule | scope | mandatory.
2. **Data protection** — data categories, legal basis, DPO contact, checklist before handling
   personal data (minimization, encryption, retention, subject rights).
3. **Accessibility** — WCAG level required per app type (the ecosystem audits AA by default in
   `webapp-layout`).
4. **Corporate authentication** — standard IdP and tenant (see `ecosystem.config.identity`).
5. **Core systems and integrations** — domain systems catalog (see
   `ecosystem.config.integrations[]`), owners, maintenance windows.
6. **Audit and traceability** — which events are audited and where.
7. **Internal contacts** — table: topic | owning team | channel.

> Until this document is customized, Claude must NOT assume any specific corporate regulation:
> ask or flag the gap.
