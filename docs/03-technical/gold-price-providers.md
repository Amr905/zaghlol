# Gold and FX price providers (T-127, D-41)

Status: **research input for the PO's D-41 decision. Nothing here is chosen.** The backend is pluggable (`Prices:Providers`); `goldapi` and `metalpriceapi` adapters exist so a choice can be switched on by configuration and a secret, with no code change. Researched 2026-11-18 from public vendor pages. "Not stated" means the page I could read did not say; those items must be confirmed with the vendor before go-live.

## What the app needs

Per gram in EGP and USD for 24K, 21K and 18K, plus USD to EGP and a few other FX rates, refreshed about hourly, served to app users through our own signed sync (so the data is redistributed to users: terms matter).

## Comparison

| Provider | EGP / karats | Update frequency | Price | Terms that matter | Key |
|---|---|---|---|---|---|
| [MetalpriceAPI](https://metalpriceapi.com/pricing) | "150+ world currencies"; EGP not named on the pages read. Spot only (XAU, USDXAU): karats and grams are derived by us | Free: daily. Essential 30 min, Basic 10 min, up to 15 s on higher plans | Free $0 (100 req/month); Essential $5 (1,000/month); Basic $12 (10,000/month); Basic Plus $20 (50,000/month) (yearly billing) | [Free plan is non-commercial and needs attribution](https://metalpriceapi.com/faq); [reselling or redistributing data needs written consent; paid subscribers may display it on their own sites while subscribed; use of stored data for commercial ends is barred after cancelling](https://metalpriceapi.com/terms). App-display and server-side caching are not addressed: **ask** | `api_key` query param |
| [GoldAPI.io](https://github.com//goldapi-io) | About 70 currencies listed (EGP not in the excerpt I could read); `GET /api/XAU/{CUR}`; karat fields not documented on that page (adapter assumes `price_gram_24k/21k/18k`, from memory of the vendor docs: **verify**) | Not stated | Not stated (pricing page not fetchable here) | Not stated | `x-access-token` header |
| [Metals-API](https://metals-api.com/) | 150+ currencies, EGP not named; gold in USD per ounce (`USDXAU`) | Delayed market data; interval not stated | [Bronze $39.99/month (5,000 calls, 10 min) up to Rhodium; Silver $79.99 (60 s)](https://metals-api.com/) | Terms page not fetchable here; **ask** about redistribution | key from dashboard |
| [XAUS](https://xaus.com/api) (gold-api.com could not be fetched) | Any ISO 4217 code in its FX feed, 160+ (`?currency=EGP` to test); no karats | Spot cached 60 s; FX cached 12 h | Free, no key; 60 req/min per IP | [Free for reasonable use; mid-market and indicative, not for settlement; contact them above 10,000 requests/day](https://xaus.com/api). No formal ToS page found | none |
| [goldpricez.com (Egypt page)](https://goldpricez.com/eg) | Shows EGP per gram for 24/22/18/14/10K (no 21K on that page) | "Refresh every minute" | A consumer site with an API link ([`/about/api`](https://goldpricez.com/about/api)), not reviewed | The page states no reuse rules and links a Terms page I did not read | unknown |
| Local Egyptian sites (isagha, goldbullioneg, etc.) | The real retail 21K price | Intraday | no API found | **Not reviewed; do not scrape.** Contract or written permission only (this is the D-41 "local feed") | n/a |

## The local premium problem

A spot-based feed (MetalpriceAPI, Metals-API, XAUS) converts the world ounce price at the USD/EGP rate. Egyptian shop prices carry a local premium or discount to that and follow the parallel-market rate when it differs. So a spot-derived 21K price will not match what a user sees at a jeweller. Only a local feed fixes that. The operator override (T-127) is the stop-gap, and copy should say "approximate".

## Recommendation (for the PO)

1. **Launch with a spot provider on a paid plan: MetalpriceAPI Essential or Basic** (hourly polling is about 720 calls/month, inside Essential's 1,000; Basic gives headroom and 10 min data). It is the only one whose pricing and tiers I could verify end to end. The free tier is unusable: non-commercial and daily. Before paying, get written confirmation of (a) EGP coverage, (b) that caching and showing prices to app users through our backend is permitted. If (b) is refused, GoldAPI.io or a local contract is the fallback.
2. **Keep D-41 open for a local feed** (a signed agreement with an Egyptian bullion source) and put it first in `Prices:Providers` when it exists. The normalizer takes the first provider that supplies a symbol, so the spot provider stays as the fallback.
3. Do not use XAUS in production: no terms document and "indicative" prices. Fine for development.

## Backend design

`Prices:Providers` is an ordered list (first provider to supply a symbol wins; failures are isolated; nothing fetched leaves the last good values, which turn `stale` after 24 h).

| Setting | Meaning |
|---|---|
| `Prices:Providers` | e.g. `metalpriceapi` or `goldapi,metalpriceapi` or `fake` (not in Production) |
| `Prices:MetalpriceApi:ApiKey`, `Prices:GoldApi:ApiKey` | **Secrets**: environment variables `Prices__MetalpriceApi__ApiKey` etc. from the secrets manager, never a file. Missing key stops startup. |
| `Prices:MetalpriceApi:FxCurrencies` | Extra FX codes, default `SAR,EUR,GBP,KWD` |
| `Prices:IntervalMinutes` | Fetch period (default 60). Each HTTP adapter is wrapped in a cache whose TTL is this minus 1 minute, so restarts and extra runs don't burn quota |
| `Prices:Bounds:MinUsdPerOunce` / `MaxUsdPerOunce` / `MinEgpPerUsd` / `MaxEgpPerUsd` | Sanity bounds, defaults 500 / 20,000 / 5 / 500. A value outside them throws; the job isolates it and keeps the last good value |

Derivation (all `decimal`, rounding to 2 dp away from zero):

- per gram (24K) = price per troy ounce / 31.1034768
- 24K EGP per gram = 24K USD per gram x USD/EGP (MetalpriceAPI) or the vendor's own EGP figure (GoldAPI)
- price(k) = price(24K) x k / 24, so 21K = x 21/24 and 18K = x 18/24 (done by `PriceNormalizer`)
- GoldAPI: USD/EGP = EGP ounce price / USD ounce price (two calls per fetch, no FX call)
- USD ounce price from MetalpriceAPI is `USDXAU`, or 1 / `XAU` if only the inverse is returned

Errors from the adapters carry fixed text only: no URL (MetalpriceAPI puts the key in the query string), no body, no key.

## Verification status of the adapters

Request and response shapes in the contract tests follow the vendors' public docs as I know them; the **GoldAPI field names and MetalpriceAPI `USDXAU` key are not confirmed against a live account**. Before go-live, with a real key, run one fetch in staging and compare to the vendor dashboard.
