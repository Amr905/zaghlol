# ADR-015: Backend hosting provider & region

| | |
|---|---|
| Status | Proposed — needs product-owner + legal decision (OQ-16, CR-03) |
| Date | 2026-11-03 |
| Deciders | Product owner (approval), solution-architect |
| References | deployment §3; https://cms.law/en/are/legal-updates/egypt-s-pdpl-executive-regulations-issued-one-year-compliance-countdown-begins |

## Context
Egypt's PDPL Executive Regulations (Decision 816/2025, issued 1 Nov 2025, one-year grace period ending about 1 Nov 2026) require a PDPC licence. Transfers to locations outside Egypt (including cloud) need a cross-border permit and protections no lower than Egypt's. The backend holds limited personal data (pseudonymous install IDs, optional e-mail, purchase IDs). Two AWS Gulf regions have been offline since attacks earlier in 2026, and no hyperscaler has an Egypt region.

## Options considered
1. ****EU region of a hyperscaler (e.g. Frankfurt)** + PDPC licence with cross-border permit** — Mature managed services (Postgres HA, KMS, CDN); about 60–80 ms from Egypt; EU protection level eases the permit case.
2. **Egyptian local hosting provider** — No cross-border permit; local residency. Fewer managed services (KMS/HSM, managed PG HA) and more ops effort.
3. **Gulf region (UAE / Bahrain / Saudi)** — Low latency; currently availability risk; also cross-border.

## Decision
**Recommend option 1**, provider-neutral by design (containers + managed Postgres + KMS + CDN via OpenTofu), so switching to option 2 stays cheap if legal advice requires local hosting. Start the PDPC licence and DPO appointment now (CR-03).

## Consequences
The product owner chooses the provider and region. Legal confirms the licence path. Cost is indicative: low hundreds of USD per month.
