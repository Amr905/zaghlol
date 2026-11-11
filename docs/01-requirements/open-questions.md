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

### OQ (2026-11-11, from T-112 review): manual FX override
FR-WLT-03 allows a manual price override; it is unclear whether the user may also override an FX rate. `fx_rates` has no source column, so a manual rate would be wiped by the next sync. Launch behaviour: price-only override; the "≈" view is labelled approximate and stale. A manual FX override needs a schema change and a new task. **PO to decide.**
