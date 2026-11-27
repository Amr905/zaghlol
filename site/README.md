# zaghlol.app static site (FU-195, draft)

Plain HTML + one CSS file. No scripts, external fonts, analytics or trackers (CI checks this). Arabic first (RTL), English below (LTR) on every page.

| Path | Page | App link (`app/lib/app/app_config.dart`) |
|---|---|---|
| `/` | Landing | — |
| `/privacy/` | Privacy policy (standard Arabic + English) | `AppLinks.privacy` |
| `/terms/` | Terms of use (standard Arabic + English) | `AppLinks.terms` |
| `/support/` | FAQ + contact (Egyptian Arabic + English) | `AppLinks.support` (defined, not yet opened from a screen) |
| `/subscription/` | How to cancel in Play / App Store | `AppLinks.manageSubscription` |
| `/get/` | Store buttons | `AppLinks.storePage` |

## Before publishing

1. **Legal review** of `privacy/` and `terms/` (PDPL 151/2020, Consumer Protection Law 181/2018, store rules). The texts follow `docs/06-release/play-data-safety.md`, `app-store-privacy.md`, `docs/03-technical/security-model.md` §2/§2a and SRS BR-SYNC-03; the contradictions found while drafting and how each was resolved are in `docs/06-release/privacy-consistency.md` (linked from `docs/workflow/PO_DECISIONS.md` Part 2, FU-195-legal).
2. **Fill the placeholders** (search for `{{`): `COMPANY_NAME`, `COMPANY_ADDRESS`, `COMMERCIAL_REGISTRY`, `CONTACT_EMAIL`, `SUPPORT_EMAIL`, `DPO`, `EFFECTIVE_DATE`, `HOSTING_LOCATION`, `PURCHASE_RETENTION`, `BANK_REQUEST_RETENTION`, `HELPDESK_PROVIDER`, `TICKET_RETENTION`, `MIN_AGE`, `PREVAILING_LANGUAGE`, `JURISDICTION_CITY`, `PRICE_MONTHLY`, `PRICE_YEARLY`, `PRICE_LIFETIME`, `SUPPORT_RESPONSE_TIME`, `PLAY_STORE_URL`, `APP_STORE_URL`, the online-helper and automatic-category section (`privacy/` section 5a; T-364, T-365): `LLM_PROVIDER_NAME`, `LLM_PROVIDER_REGION` (the provider named in the consent sheet and its processing region), `PENDING_PO` (a block whose PO decision is open: replace with the decided wording or delete it), and the `[LEGAL]` sentences with `LLM_PROVIDER_RETENTION_REVIEW`, `LLM_LEGAL_BASIS_REVIEW`, `LLM_TRANSFER_REVIEW`; and the reviewer notes `LEGAL_BASIS_REVIEW`, `LIFETIME_DEFINITION_REVIEW`, `LIABILITY_REVIEW`, `ZAKAH_REVIEW_BODY` (replace with final text or delete).
3. **Check the in-app paths** named in the support FAQ (e.g. where the support code is shown) against the current build.
4. **Remove the draft banner**: in `assets/site.css` replace the `.draft-banner { … }` rule with `.draft-banner { display: none; }` (or delete the `<div class="draft-banner">` lines).
5. Remove `<meta name="robots" content="noindex">` from `privacy/` and `terms/` if you want them indexed.

Preview locally: open `site/index.html` in a browser, or `python3 -m http.server -d site 8080`.

## Option A: GitHub Pages

1. Repo **Settings → Pages → Build and deployment → Source: GitHub Actions**.
2. **Actions → site-pages → Run workflow** (branch `main`). The workflow runs only on `workflow_dispatch`, so nothing is published until you run it. It refuses to publish while `{{…}}` placeholders remain, unless you tick `allow_placeholders` (draft preview). `README.md` is not published.
3. **Settings → Pages → Custom domain:** `zaghlol.app`, then tick **Enforce HTTPS** once the certificate is issued. Verify the domain under your account's Settings → Pages → Verified domains (TXT record) to stop takeovers.
4. DNS at the registrar for `zaghlol.app`:

   | Type | Name | Value |
   |---|---|---|
   | A | `@` | `185.199.108.153` |
   | A | `@` | `185.199.109.153` |
   | A | `@` | `185.199.110.153` |
   | A | `@` | `185.199.111.153` |
   | AAAA | `@` | `2606:50c0:8000::153`, `2606:50c0:8001::153`, `2606:50c0:8002::153`, `2606:50c0:8003::153` |
   | CNAME | `www` | `<github-user-or-org>.github.io` |
   | TXT | `_github-pages-challenge-<user-or-org>` | value shown by GitHub |

   `.app` is HSTS-preloaded: browsers only open it over HTTPS, so the site is unreachable until the Pages certificate is issued.

Note: the repo is public; Pages on a private repo needs a paid plan.

## Option B: the backend server behind Caddy

Copy `site/` (without `README.md`) to the server, e.g. `/srv/zaghlol-site`, and add:

```caddyfile
zaghlol.app, www.zaghlol.app {
	root * /srv/zaghlol-site
	file_server
	encode zstd gzip
	header {
		Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
		Content-Security-Policy "default-src 'none'; style-src 'self'; img-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
		X-Content-Type-Options nosniff
		Referrer-Policy no-referrer
		-Server
	}
	log {
		output discard
	}
}
```

DNS: `A @ <server IPv4>`, `AAAA @ <server IPv6>` (if any), `CNAME www zaghlol.app.`. Caddy gets the certificate itself (ports 80 and 443 open). `log { output discard }` keeps no visitor IPs; if you want access logs, keep them short and state it in the privacy policy.

Keep the site on a different host or container than the API if possible, so a site change can't affect the backend.
