# ADR-014: Gold & FX price source

| | |
|---|---|
| Status | Proposed — needs product-owner choice (OQ-02) |
| Date | 2026-11-03 |
| Deciders | Product owner (approval), solution-architect |
| References | FR-BE-04, FR-WLT-03 |

## Context
FR-BE-04 / FR-WLT-03 need gold per gram for 24K/21K/18K in EGP and USD, plus FX for all supported currencies, from a source licensed for redistribution. Egyptian local gold prices (dealer market) can differ from spot × official FX, especially during FX stress.

## Options considered
1. **Spot XAU + FX from a commercial API (e.g. Metals-API / GoldAPI-type providers, Open Exchange Rates-type FX) and compute karat prices (24K = spot/31.1035 g; 21K = 0.875×; 18K = 0.75×)** — Licensable, global, reliable; may diverge from Cairo dealer prices.
2. **A local Egyptian gold-market feed (dealer/association prices) + official CBE FX** — Matches what users see in shops; licensing and API availability must be confirmed.
3. **Scraping public websites** — Not licensable; brittle. Rejected.

## Decision
**Pluggable `IPriceProvider` with two adapters.** Primary for gold in EGP: a **licensed local-market feed if one can be contracted** (option 2). Otherwise spot-derived with the operator able to set a local premium (option 1). FX from a licensed FX API. The backend fetches every 60 min and serves the cached result. Prices are labelled stale after 24 h. Operator override exists for incidents. **The product owner must pick and contract the provider (OQ-02).**

## Consequences
Prices are used only for gold value and the optional ≈ view, so small divergence is acceptable when labelled with source and time.
