# Open Questions & Spec Conflicts

Seeded by the Lead during setup from a read of spec v4. The `requirements-analyst` owns this file in Phase 1: expand, add recommendations, and mark each BLOCKING or NON-BLOCKING.

| ID | Area | Issue | Initial recommendation | Status |
|----|------|-------|------------------------|--------|
| OQ-01 | Scope | §5 defines 14 screens; §13 defines 16 differently numbered screens (adds Smart ROI coach, Assets, Zakah, iOS wizard). Which set is canonical? | Treat §13 (16 screens) as canonical; map §5 content onto it. | OPEN |
| OQ-02 | Monetization | Paid tier named "Zaghlol Gold" (§2, §5) and "Zaghlol Pro" (§13). Pricing given only for Gold. | Use "Zaghlol Gold", 49/399/899 EGP. | OPEN |
| OQ-03 | Android policy | Google Play only allows `READ_SMS`/`RECEIVE_SMS` for default SMS handlers or approved exception use cases. Core ingestion may be rejected. | Architect to produce an ADR: permission declaration strategy, NotificationListener fallback, manual share/paste fallback. | OPEN — likely BLOCKING |
| OQ-04 | iOS feasibility | `ILMessageFilterExtension` runs only for unknown senders and cannot write to a shared container; Shortcuts automations need user setup per trigger. | Validate the iOS channel list; drop or re-scope channels that can't persist data. | OPEN |
| OQ-05 | Offline vs live data | Net worth and Zakah need gold (21K/24K) and FX prices; spec says 100% offline / zero backend. | Manual price entry + optional public price fetch with no user data sent. Decide in ADR. | OPEN |
| OQ-06 | AI chat | "Ask Zaghlol" chat with in-chat charts, no backend. | MVP: intent/template engine over SQLite; on-device LLM as later option. | OPEN |
| OQ-07 | Bottom nav | §10 bottom bar (Home, Charts, FAB, Assets & Zakah, Smart Coach) omits Budget, Subscriptions, Settings placement. | UX designer to reconcile in IA. | OPEN |
| OQ-08 | Schema | Two wealth schemas: `WealthAssets` (§9) and `WealthAssets_v2` (§11.1). | Use v2; drop v1. | OPEN |
| OQ-09 | Domain review | Zakah rules (nisab, hawl, stock treatment, debt deduction) need Shariah review; ROI rules recommend specific funds/products. | Get a named reviewer; add in-app disclaimer; avoid naming specific financial products. | OPEN |
| OQ-10 | MVP scope | Spec is large (38 banks, 12 charts, voice, OCR, PDF import, Zakah, chat, IAP, backup, social share). | Define MVP = Android SMS ingestion for top ~8 banks + InstaPay + manual/voice cash + categories + budget + 4 core charts + home. | OPEN — BLOCKING |
| OQ-11 | Backup scope | `drive.appdata` scope hides backups from the user's visible Drive; spec says "directly to user's Google Drive". | Confirm appdata (private) vs visible folder. | OPEN |
| OQ-12 | Voice | On-device `ar-EG` speech recognition availability varies by device/OS; free tier limited to 15 voice logs/month. | Confirm offline requirement for voice and fallback behaviour. | OPEN |

**OQ-10 Zakah scholar sign-off: as shipped in T-168** (full list in `docs/04-tasks/tasks/T-167.md` "For the scholar"): no debts are read or deducted; every asset is zakatable, no jewelry opt-out; account hawl starts the day the account was added; last parsed balance; asset hawl from `acquired_at` or the day added; certificates at principal, funds at manual value; real estate, cars and others excluded; items 5 and 10 are engine only.

### OQ (2026-11-11, from T-112 review): manual FX override
FR-WLT-03 allows a manual price override; it is unclear whether the user may also override an FX rate. `fx_rates` has no source column, so a manual rate would be wiped by the next sync. Launch behaviour: price-only override; the "≈" view is labelled approximate and stale. A manual FX override needs a schema change and a new task. **PO to decide.**

### ASK-LLM (2026-11-26): free-form questions through an LLM (`ask-llm.md`, D-88…D-91)

| ID | Question | Recommended default | Status |
|----|----------|---------------------|--------|
| OQ-ASK-01 | Investment illustrations and Egyptian FRA licensing: do "your savings would have equalled X g of gold / ≈ USD / a certificate at an example rate" answers count as regulated investment advice? Who signs off the disclaimer (ar standard + en)? | Legal review before `ask_llm_invest` is turned on; build behind the sub-flag, illustrations only, no named products (D-38), mandatory disclaimer. | **BLOCKING for turning on `ask_llm_invest`**; NON-BLOCKING for build |
| OQ-ASK-02 | Stock-index illustration (e.g. EGX30): is there a licensed price feed we can redistribute? | No index line until a licensed feed is contracted (add to the D-41 provider talks); gold, USD and certificate only. | NON-BLOCKING |
| OQ-ASK-03 | LLM provider: contract terms (no retention / no training), processing region and PDPL 151/2020 cross-border transfer of the question text. | Shortlist the cheapest two providers offering contractual zero retention and no training; pick by the 40-question evaluation (`ask-llm.md` §10.1); legal confirms cross-border basis and the policy text. | **BLOCKING for turning on `ask_llm`** |
| OQ-ASK-04 | Should the phone also mask amounts and percentages the user types (send "{n1}" and keep values locally)? | No: scrub only phones, e-mails, InstaPay addresses and card/account numbers (FR-LLM-03); the notice says typed text is sent (PO decision 1). Revisit if evaluation shows masking keeps accuracy. | NON-BLOCKING |
| OQ-ASK-05 | Monthly provider spend cap (amount) and who receives the 80 % alert. | PO sets a USD cap before launch; alert to the operator mailbox; graceful `service_paused` at 100 %. | NON-BLOCKING (needed before flag on) |
| OQ-ASK-06 | Are suggestions and investment illustrations available on Free (within 5 questions) or Gold only? | Same plans on both tiers; the quota is the only difference (growth goal, D-08). | NON-BLOCKING |
| OQ-ASK-07 | May the LLM's sentence templates be shown at all in v1, or only the app's own templates? | Allowed for data, what-if and suggestion plans after validation (FR-LLM-35); app-owned only for investment and refusals (BR-LLM-04). | NON-BLOCKING |
| OQ-ASK-08 | Refusals that show distress (debt, self-harm cues): which Egyptian support line or wording? | Domain/legal review supplies one approved line; until then a neutral "talk to someone you trust" line with no number. | NON-BLOCKING |
