# Backend Data Model (PostgreSQL 17)

**Principle:** the backend stores only what BR-SYNC-03 allows. It holds **no** transactions, messages, amounts, balances, budgets, assets or user rules. Personal data is limited to:
- the pseudonymous install ID;
- the optional account (provider subject ID, plus an e-mail if the provider returns one);
- store purchase identifiers;
- truncated IPs in short-lived logs.

All of it is covered by the retention rules in §4 (NFR-PRIV-06).

Conventions:
- **IDs:** `uuid` (v7) primary keys.
- **Time:** `timestamptz` everywhere.
- **Naming:** snake_case.
- **Migrations:** EF Core, applied by a deploy job.
- **Schema:** all objects live in schema `zaghlol` (not `public`), owned by `migrator`.
- **Database roles:** separate roles for API (`app_rw`), workers (`worker_rw`), operators (`ops_ro` + audited `ops_rw` via the admin API only) and migrations (`migrator`). The API uses `app_rw` for `/v1/*` and `ops_rw` for `/admin/v1/*` (two connection strings). Roles are created by `backend/deploy/db/bootstrap-roles.sql` (not by migrations); per-table grants are in the migrations (T-122 design note, `GrantMatrix.cs`). Each group has its own login (`zaghlol_api` → `app_rw`, `zaghlol_admin` → `ops_rw`, `zaghlol_worker` → `worker_rw`, `zaghlol_ops_ro` → `ops_ro`), so the two API connection strings really are two privilege sets.
- **Hardening CHECKs not repeated below:**
  - Every SHA-256 / HMAC `bytea` column has `CHECK (octet_length(col) = 32)`; `idempotency_key` has `char_length = 26`.
  - `purchase_events.cause` has a regex CHECK for exactly the listed values (`rtdn:` / `assn:` + `[A-Za-z0-9_]{1,64}`).
  - Formats (T-122 round 2, SEC F8): `installs.app_version` and `daily_active_counts.app_version` match `'^[0-9]{1,4}(\.[0-9]{1,4}){1,3}([+-][0-9A-Za-z.-]{1,32})?$'` (OpenAPI `appVersion`, which allows `-` in the suffix); `bank_requests.country ~ '^[A-Z]{2}$'`; `store_notifications.last_error ~ '^[A-Z0-9_]{1,64}$'`; `char_length(store_key) <= 512` on `purchases` and `store_notifications`.
- **Invariant triggers (SEC F9):** BEFORE UPDATE triggers raise SQLSTATE 23514 when `installs.seat_key_hash` is replaced or cleared without a tombstone, when `installs.seat_key_trusted` goes true → false, or when `purchases.attach_reclaim_used_at` is cleared or changed. With the two BEFORE DELETE backstops (§2 comments) they are the only functions in the schema.
- **`audit_log` row-level security (SEC F4):** readers (`ops_ro`, `ops_rw`, `worker_rw`) see every row; `ops_rw` may only insert rows stamped now (no backdating); `worker_rw` may delete only rows past their retention age (§4). There is no UPDATE policy, and no role has UPDATE.
- **Crypto is computed in the application, never in the DB:** no `pgcrypto`; hashes, keyed hashes (`IKeyedHasher`) and envelope ciphertexts (`IEnvelopeCipher`) arrive as `bytea`.

## 1. ER overview

```mermaid
erDiagram
  installs ||--o{ purchases : "made on"
  accounts ||--o{ account_installs : links
  installs ||--o{ account_installs : links
  accounts ||--o{ purchases : "linked to"
  purchases ||--o{ purchase_events : history
  purchases ||--|| purchase_seats : "one seat"
  purchases ||--o{ seat_claimants : "pending claimants"
  store_notifications }o--o| purchases : updates
  catalog_versions ||--o{ catalog_changes : contains
  merchant_contributions }o--|| contribution_aggregates : "rolls up"
```

## 2. Tables

```sql
-- Installs (FR-BE-01)
CREATE TABLE installs (
  id uuid PRIMARY KEY,                         -- generated on device (random, not hardware-derived)
  token_hash bytea NOT NULL,                   -- SHA-256 of the install token issued at registration
  platform text NOT NULL CHECK (platform IN ('android','ios')),
  app_version text NOT NULL,                   -- no OS version: not on the BR-SYNC-03 allow-list (FU-013)
  catalog_version integer NOT NULL DEFAULT 0,
  first_seen_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,                      -- FR-ONB-08 tombstone (row purged after 30 days)
  last_sync_at timestamptz,                    -- T-128: last effective (claimed) POST /v1/sync; NULL = never synced. Drives the
                                               -- server-side 24 h throttle (backend-api §4.2); last_seen_at drives retention
  -- Registration retry (backend-api §4.1, R3-6): no response with a token is ever stored. Both columns are cleared at the
  -- install's first authenticated call or after 24 h; while set, a same-key same-body replay gets a fresh token.
  registration_key_hash bytea,                 -- SHA-256(Idempotency-Key)
  registration_body_sha256 bytea,
  -- iOS seat key registered by this install (backend-api §4.3, R4-1(1), D-62): HMAC-SHA256(K_seat, 'install' || 0x00 ||
  -- installId || publicKey) of element 0 of its first valid seatKeys. Set once, never replaced; a later restore or sign-in
  -- with another element 0 gets 400 SEAT_KEY_MISMATCH. Cleared when the install is tombstoned. Never a raw key.
  seat_key_hash bytea,
  seat_key_trusted boolean NOT NULL DEFAULT false  -- set ONLY by an App Attest-covered request (R5-2): a restore whose assertion
                                               -- covered this key as element 0. iOS sign-in has no App Attest (D-66), so
                                               -- it never sets it. Verify and sign-in register the key UNTRUSTED. Only
                                               -- false -> true. Gates the over-cap sign-in rebind (D-65(a), backend-api §4.3)
);
CREATE INDEX ix_installs_last_seen ON installs(last_seen_at);
CREATE UNIQUE INDEX ux_installs_token_hash ON installs(token_hash);  -- T-124 (migration InstallTokenHashUnique): install auth is one lookup by hash

-- Optional accounts (FR-ACCT, FR-BE-09)
CREATE TABLE accounts (
  id uuid PRIMARY KEY,
  provider text NOT NULL CHECK (provider IN ('google','apple')),
  provider_subject text NOT NULL,              -- 'sub' claim
  email text,                                  -- only if returned (A-47); support lookup only
  created_at timestamptz NOT NULL DEFAULT now(), last_sign_in_at timestamptz,
  apple_refresh_token_enc bytea,               -- needed to revoke on account deletion (Apple requirement); KMS-encrypted
  UNIQUE (provider, provider_subject)
);
CREATE TABLE account_installs (
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  install_id uuid NOT NULL REFERENCES installs(id) ON DELETE CASCADE,
  linked_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (account_id, install_id)
);

-- Purchases (FR-BE-02)
CREATE TABLE purchases (
  id uuid PRIMARY KEY,
  store text NOT NULL CHECK (store IN ('google_play','app_store')),
  product_id text NOT NULL,                    -- zaghlol_gold_monthly | _yearly | _lifetime
  plan text NOT NULL CHECK (plan IN ('monthly','yearly','lifetime')),
  -- Google: purchase token (unique key per Google guidance). Apple: originalTransactionId.
  store_key text NOT NULL,
  linked_purchase_token text,                  -- Google upgrade/downgrade chain
  install_id uuid REFERENCES installs(id) ON DELETE SET NULL,  -- purchasing install (set by verify, never by restore)
  account_id uuid REFERENCES accounts(id) ON DELETE SET NULL,  -- set at sign-in from the buying install or by a support attach; restore never changes it
  account_linked_by text CHECK (account_linked_by IN ('signin','support')),  -- NULL when unlinked; only 'support' links can be detached (§5.3)
  attach_reclaim_used_at timestamptz,          -- D-58: the free account-attach reclaim happened; NEVER cleared, not even when the account is deleted
  dispute_frozen_until timestamptz,            -- D-64/D-65(b): set to now + 30 d by every successful support correction (restarts);
                                               -- while in the future, non-correction support moves and links get 409 ADMIN_CONFLICT;
                                               -- set to NULL only by a support_lead unfreeze from a different operator (R5-5(b))
  support_link_notice_pending boolean NOT NULL DEFAULT false,  -- R4-7(2): set by a support attach; cleared when the buying
                                               -- install proves delivery (a sync with entitlementIssuedAt >= support_link_notice_iat,
                                               -- R5-7), or by a detach. Not cleared when the notice is merely sent
  support_link_notice_iat timestamptz,         -- R5-7: iat of the newest entitlement token sent together with supportNotice
  state text NOT NULL CHECK (state IN ('pending','active','in_grace','on_hold','paused','canceled_active','expired','refunded','revoked')),
                                               -- Google label rule (T-133, PlayStateMapping.Settle): a Play read of 'expired'
                                               -- keeps a stored 'refunded'/'revoked' (Play has no refunded subscription state);
                                               -- an entitling read always overwrites
  expires_at timestamptz,                      -- NULL for lifetime
  acknowledged boolean NOT NULL DEFAULT false, -- Google; must be true within 3 days (BR-GOLD-06). Always true for app_store
                                               -- (Apple has no server acknowledgement; the app finishes the transaction, T-131)
  ack_next_attempt_at timestamptz,             -- T-130 M-1: the ack sweeper defers a row it can't finish (pending, unknown
                                               -- product/state, Play error) until then; NULL = never deferred. Only worker_rw writes it
  environment text NOT NULL CHECK (environment IN ('production','sandbox')),
  last_payment_at timestamptz,                 -- T-131 (Apple only): purchaseDate of the newest PURCHASE-reason transaction a
                                               -- binding-checked verify has seen; advancing it = a new payment (D-59/D-61(a)).
                                               -- Only app_rw updates it (never restore or T-134 notifications); no transaction ID stored
  obfuscated_install_ref text,                 -- = StoreBindingRef(install_id): Play obfuscatedAccountId / Apple appAccountToken
                                               -- (canonical lower-case UUID for Apple)
  last_verified_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (store, store_key),
  CHECK ((account_id IS NULL) = (account_linked_by IS NULL))
);
-- ON DELETE SET NULL on account_id must also clear account_linked_by: done by the account-deletion service in the same
-- transaction (a BEFORE DELETE trigger on accounts enforces it as a backstop; it clears account_id AND account_linked_by,
-- because the FK action fires only after the row is gone and would violate the CHECK, and never touches attach_reclaim_used_at).
CREATE INDEX ix_purchases_install ON purchases(install_id);
CREATE INDEX ix_purchases_account ON purchases(account_id);
CREATE INDEX ix_purchases_unacked ON purchases(created_at) WHERE store = 'google_play' AND acknowledged = false;

CREATE TABLE purchase_events (                 -- audit trail of state transitions (no raw receipts)
  id uuid PRIMARY KEY, purchase_id uuid NOT NULL REFERENCES purchases(id) ON DELETE CASCADE,
  from_state text, to_state text NOT NULL, cause text NOT NULL,   -- verify | restore | seat_bind | seat_move:<restore|signin|support|account_attach|verify>
                                                                    -- | seat_rebind:<restore|signin> | seat_rebind_over_cap:<restore|signin>
                                                                    -- | rtdn:<type> | assn:<type> | sweep
                                                                    -- Seat rows (T-184): from_state = to_state = the purchase's
                                                                    -- state; exactly one row per bind, move, rebind or over-cap
                                                                    -- rebind, plus the over-cap sign-in refusal; none for a no-op
                                                                    -- (unchanged, refused, claimant added, account required)
  occurred_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE store_notifications (             -- FR-BE-03, idempotent ingest
  id uuid PRIMARY KEY,
  store text NOT NULL, external_id text NOT NULL,   -- Pub/Sub messageId | ASSN notificationUUID | Google jobs (T-133):
                                                    -- 'voided:' || hex(sha256(orderId,token,voidedTime)) | 'sweep:' || purchase id || ':' || expiry epoch
  type text NOT NULL,                               -- RTDN notificationType / ASSN notificationType
  subtype text,                                     -- ASSN subtype (always NULL for google_play)
  product_id text,                                  -- subscriptionId / sku / productId
  store_key text,                                   -- purchase token (Google) | originalTransactionId (Apple), to re-read state
  environment text CHECK (environment IN ('production','sandbox')),  -- NULL for google_play (known only from Play's read)
  event_time timestamptz,                           -- eventTimeMillis / signedDate
  received_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz, attempts integer NOT NULL DEFAULT 0,
  last_error text,                                  -- error code only; never payload text
  payload_digest bytea NOT NULL,                    -- SHA-256 of the received body, for dedupe/forensics
                                                    -- (Apple: of the signedPayload string, T-134; Google: of the decoded
                                                    -- message.data bytes, or of the job key for voided rows, T-133)
  next_attempt_at timestamptz,                      -- T-134: processing back-off; NULL = never failed. Only worker_rw writes it
  UNIQUE (store, external_id),
  CHECK (type ~ '^[A-Z0-9_]{1,64}$'),
  CHECK (subtype IS NULL OR subtype ~ '^[A-Z0-9_]{1,64}$'),
  CONSTRAINT ck_store_notifications_google_shape CHECK (store <> 'google_play' OR (subtype IS NULL AND environment IS NULL
    AND (external_id ~ '^[A-Za-z0-9_-]{1,100}$' OR external_id ~ '^voided:[0-9a-f]{64}$'
         OR external_id ~ '^sweep:[0-9a-f-]{36}:[0-9]{1,12}$')))   -- T-133, migration GoogleNotifications
);
CREATE INDEX ix_store_notifications_due ON store_notifications (store, next_attempt_at NULLS FIRST, received_at)
  WHERE processed_at IS NULL;                       -- T-134 (T-133 reuses it)
-- Grants (T-134, migration AppleNotifications): worker_rw gains INSERT on store_notifications (Get Notification History
-- reconciliation) and UPDATE (product_id, plan) on purchases (an upgrade notification re-plans the row). worker_rw never
-- updates environment, obfuscated_install_ref, install_id or last_payment_at, and has only SELECT on purchase_seats, so a
-- notification can't move a seat. The worker never inserts purchases.
-- T-133 adds no grant: the Google worker statement writes only state, expires_at and last_verified_at (WHERE store =
-- 'google_play' AND last_verified_at < @read_at); a Google row never changes product_id or plan.
-- Only these extracted columns are written, after authentication (backend-api §4.5). The raw envelope is NEVER stored;
-- fields not listed above (including unknown third-party fields) are not persisted anywhere.

-- Effective entitlement is computed, not stored: view over purchases for an install or account
-- Seat (D-52, FR-GOLD-08, BR-GOLD-07): the ONE install that may hold Gold from a purchase, across platforms (FR-GOLD-07).
-- Exactly one row per purchase (created by the first verify). Every change runs in the verify / restore / sign-in / support
-- transaction under SELECT … FOR UPDATE on this row (backend-api §4.3, §4.6, §5.3).
CREATE TABLE purchase_seats (
  purchase_id uuid PRIMARY KEY REFERENCES purchases(id) ON DELETE CASCADE,
  install_id uuid REFERENCES installs(id) ON DELETE SET NULL,   -- holder; NULL = vacant (install deleted or purged)
  proof text CHECK (proof IN ('binding','attested','basic','account','support','device')), -- how the holder got it; NULL when vacant
  bound_at timestamptz,                               -- when the current holder got the seat
  last_moved_at timestamptz,                          -- exact time of the last move; server-side only, never sent to the app
  next_move_at timestamptz,                           -- ceil_hour(last_moved_at + 30 d); the ONLY value the cooldown check uses and
                                                      -- the only one returned (409, tokens, verify, sign-in) (R3-4). NULL = never moved.
                                                      -- Set by restore/sign-in/verify(plan change) moves, support moves (D-56) and the
                                                      -- account-attach reclaim (D-61(b)). Unchanged by the first bind, a same-holder refresh
                                                      -- and a same-iPhone rebind (D-55). A Google upgrade successor copies its predecessor's.
  device_key_hash bytea,                              -- D-55: HMAC-SHA256(K_seat, purchase_id || seat-key public key) of the holder's
                                                      -- REGISTERED key (installs.seat_key_hash, R4-1(1)); NULL when the holder has
                                                      -- none. KEPT when the seat goes vacant (so "Delete everything" + restore on
                                                      -- the same iPhone is a rebind). Only a seatKeys element at position >= 1 can
                                                      -- match it for a rebind
  device_key_trusted boolean NOT NULL DEFAULT false,  -- copied from the NEW holder's installs.seat_key_trusted whenever device_key_hash is
                                                      -- written, a support move included (from the target install, never kept from
                                                      -- the previous holder; false when device_key_hash is NULL or on a move back, R5-4);
                                                      -- an over-cap SIGN-IN rebind needs it (restore doesn't)
  recent_rebinds timestamptz[] NOT NULL DEFAULT '{}', -- D-63: times of same-iPhone rebinds in the rolling 30 days; pruned under the
                                                      -- seat lock before each check; at most 2. Over the cap: over-cap rebind that
                                                      -- restarts the window and is never refused (D-65(a)); for sign-in only when
                                                      -- device_key_trusted, otherwise an ordinary move
  CHECK ((install_id IS NULL) = (proof IS NULL)),
  CHECK ((last_moved_at IS NULL) = (next_move_at IS NULL)),
  CHECK (next_move_at IS NULL OR date_trunc('hour', next_move_at, 'UTC') = next_move_at),  -- whole UTC hour in any session time zone
  CHECK (cardinality(recent_rebinds) <= 2)
);
CREATE INDEX ix_purchase_seats_install ON purchase_seats(install_id);
-- Seat service (T-184): every change locks the purchases row FOR UPDATE, then this row FOR UPDATE, in the caller's transaction
-- (Zaghlol.Application/Seats/SeatService). A Google successor inherits the predecessor's holder, proof, move times and
-- recent_rebinds, but device_key_hash starts NULL (false): it is keyed by purchase_id, so the predecessor's value could never match.
-- A same-iPhone rebind sets proof = 'device' ('basic' stays 'basic', so the 2-day token limit holds).
-- A BEFORE DELETE trigger on installs vacates the seat (install_id, proof, bound_at := NULL) so the holder/proof CHECK holds;
-- device_key_hash, device_key_trusted, last_moved_at, next_move_at and recent_rebinds are kept (D-55).
-- Invariant (FR-GOLD-08 acceptance): at most one holder per purchase, by construction (primary key).

-- Pending claimants (R3-4, R4-4): installs refused ONLY by the cooldown (they passed attestation, store and account checks),
-- or plan-change payers kept off an account-linked seat by the account rule (verify only; a support move still needs the
-- target to be linked to the account).
-- The only valid support-move targets besides the holder (attach only) and a correction's source install (backend-api §5.3).
CREATE TABLE seat_claimants (
  purchase_id uuid NOT NULL REFERENCES purchases(id) ON DELETE CASCADE,
  install_id uuid NOT NULL REFERENCES installs(id) ON DELETE CASCADE,
  claimed_at timestamptz NOT NULL,                    -- refreshed when the same install is refused again; ignored after 7 days
  channel text NOT NULL CHECK (channel IN ('restore','signin','verify')),
  device_key_hash bytea,                              -- per-purchase hash of the claimant's registered seat key, copied to the seat
                                                      -- by a support move
  PRIMARY KEY (purchase_id, install_id)
);
-- At most 3 rows per purchase: the insert runs under the seat's FOR UPDATE lock and deletes the oldest row when a fourth
-- install is refused. Rows older than 7 days are ignored by every read and deleted by the purger.

-- App Attest keys (iOS restore attestation, ADR-012 Amendment (2026-11-05) Part B). No device identifier is stored (FR-GOLD-09).
CREATE TABLE app_attest_keys (
  key_id bytea PRIMARY KEY,                     -- SHA-256 of the credential public key (= keyId)
  install_id uuid NOT NULL UNIQUE REFERENCES installs(id) ON DELETE CASCADE,  -- one key per install; re-attest replaces it
  public_key bytea NOT NULL, sign_count bigint NOT NULL,
  environment text NOT NULL CHECK (environment IN ('production','development')),
  attested_at timestamptz NOT NULL DEFAULT now()
);

-- Effective entitlement is computed, not stored: purchases whose seat the install holds
-- The entitlement service includes a row with account_id set only when the request carries a valid account token for
-- that account; otherwise the purchase is reported 'paused' (D-61(c)).
CREATE VIEW v_entitlements AS
  SELECT s.install_id, p.id AS purchase_id, p.plan, p.state, p.expires_at, p.store, p.account_id, s.proof, s.next_move_at
  FROM purchase_seats s JOIN purchases p ON p.id = s.purchase_id
  WHERE s.install_id IS NOT NULL AND p.state IN ('active','in_grace','canceled_active');

CREATE TABLE replay_guard (                    -- single-use proofs (ADR-016 amendment 2, ADR-012 Amendment (2026-11-05) Part B)
  key_hash bytea PRIMARY KEY,                   -- SHA-256(nonce claim) | SHA-256(Play Integrity token). Nonces are required for both providers (R2-9)
  kind text NOT NULL CHECK (kind IN ('signin_google','signin_apple','play_integrity')),
  expires_at timestamptz NOT NULL               -- token exp, or +15 min for Play Integrity; rows purged after expiry
);

-- Idempotency (backend-api §1, R2-8, R3-6): verify and sign-in only (registerInstall uses installs.registration_* instead).
-- A stored result is returned only for the same install, operation, key and body, and only while expires_at > now().
CREATE TABLE idempotency_records (
  install_id uuid NOT NULL,                     -- from the install token; no FK, but DELETE /v1/installs/me deletes the rows
  operation_id text NOT NULL CHECK (operation_id IN ('verifyPurchase','signIn')),
  idempotency_key text NOT NULL,                -- ULID from the Idempotency-Key header (CSPRNG random part)
  body_sha256 bytea NOT NULL,                   -- SHA-256 of the request body bytes; a mismatch gives 409 IDEMPOTENCY_KEY_REUSED
  status integer NOT NULL CHECK (status = 0 OR status BETWEEN 200 AND 299 OR status IN (409, 422)),
                                                -- 0 = claimed by a running request (T-130, FU-052 S-2); otherwise the final result
  response_body_enc bytea NOT NULL,             -- final result only (2xx/409/422), KMS-envelope-encrypted with context
                                                -- idem/v2/<installId>/<operationId>/<b64u(SHA-256(key))> (holds tokens); empty while claimed
  claim_id uuid,                                -- the running request's lease; CHECK ((status = 0) = (claim_id IS NOT NULL))
  account_id uuid,                              -- signIn: the account whose token the stored body holds; DELETE /v1/accounts/me
                                                -- deletes these rows
  expires_at timestamptz NOT NULL,              -- final: created + 24 h; claim: now + 60 s (the lease). Every lookup requires
                                                -- expires_at > now(); an expired claim is taken over by the next request
  PRIMARY KEY (install_id, operation_id, idempotency_key)
);
CREATE INDEX ix_idempotency_account ON idempotency_records(account_id) WHERE account_id IS NOT NULL;

-- Signing keys: NOT a table (T-123 design note, 2026-11-06). The key ring (kid, purpose sync|entitlement, status
-- next|active|retired, KMS key reference, public JWK) is deploy-time configuration managed with the KMS keys (T-140), so no
-- DB write can change which key signs.

-- Catalog (FR-BE-06, FR-SYNC-02)
CREATE TABLE catalog_versions (
  version integer PRIMARY KEY, published_at timestamptz NOT NULL, published_by uuid NOT NULL,
  notes text, full_snapshot_url text NOT NULL, full_snapshot_sha256 bytea NOT NULL
);
CREATE TABLE catalog_categories (code text PRIMARY KEY, parent_code text REFERENCES catalog_categories(code),
  name_ar text NOT NULL, name_en text NOT NULL, icon text NOT NULL, color text NOT NULL, bucket text NOT NULL,
  sort integer NOT NULL, version integer NOT NULL, deleted boolean NOT NULL DEFAULT false);
CREATE TABLE catalog_merchants (id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY, canonical text NOT NULL UNIQUE,
  name_ar text, name_en text, category_code text NOT NULL REFERENCES catalog_categories(code),
  version integer NOT NULL, deleted boolean NOT NULL DEFAULT false);
-- alias_norm is exactly the app `merchant_norm` key (parsing-engine §5): [a-z0-9] words separated by single spaces, produced by the same algorithm (tools/catalog_build, shared golden vectors), never re-keyed once stored.
CREATE TABLE catalog_aliases (merchant_id integer NOT NULL REFERENCES catalog_merchants(id), alias_norm text NOT NULL,
  match text NOT NULL, version integer NOT NULL, deleted boolean NOT NULL DEFAULT false, PRIMARY KEY (alias_norm, merchant_id));
CREATE TABLE catalog_keywords (keyword_norm text NOT NULL, lang text NOT NULL, category_code text NOT NULL,
  weight integer NOT NULL, version integer NOT NULL, deleted boolean NOT NULL DEFAULT false, PRIMARY KEY (keyword_norm, lang));
-- keyword_norm uses the same normalization as alias_norm: [a-z0-9] words with single spaces for Latin keywords, folded Arabic (alef/ya/ta-marbuta, no tatweel or harakat) for `ar`.
-- Keyword identity is (keyword, lang), the same key the sync `keyword` op uses (FU-009): one category per keyword per language.
-- A delta from version a→b = all rows with version in (a, b], including tombstones (deleted = true).
-- Published versions are immutable; edits happen in the draft workspace (catalog_drafts, below) and publish atomically.
-- Draft keys and tombstones: backend-api.md §5.2. A draft DELETE becomes deleted = true at publish; merchant ids are the
-- identity values of catalog_drafts.seq (allocated by POST /admin/v1/catalog/draft/merchants) and are never reused.
CREATE TABLE catalog_drafts (seq integer NOT NULL GENERATED ALWAYS AS IDENTITY, entity text NOT NULL
    CHECK (entity IN ('categories','merchants','aliases','keywords')),
  entry_key text NOT NULL, body jsonb NOT NULL, deleted boolean NOT NULL DEFAULT false,
  published boolean NOT NULL DEFAULT false, changed boolean NOT NULL, updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (entity, entry_key));
-- T-125. The whole editable catalog, one row per entry (a working copy that also holds tombstones, so a PUT can revive one).
-- entry_key is the DECODED key: categories `dining`; merchants `812`; aliases `812:koshary el tahrir` (alias part = the exact `merchant_norm` form, `^[a-z0-9]+( [a-z0-9]+)*$`); keywords `ar:text`.
-- body holds the non-key fields (camelCase JSON, backend-api §5.2). `published` = the entry has been written to the live tables;
-- `changed` = it differs from them (new, edited or tombstoned since the last publish). A DELETE of a never-published entry
-- removes the row. seq is the merchant id allocator: an identity needs no sequence grant (FU-026), the id is the row's seq, and
-- it is never reused. The live catalog_merchants identity stays unused: publish writes ids with OVERRIDING SYSTEM VALUE.
-- Grants: ops_rw SELECT/INSERT/UPDATE/DELETE, ops_ro SELECT. Unique index on seq (paging order).

-- Feature flags (FR-BE-05)
CREATE TABLE feature_flags (
  key text PRIMARY KEY,                         -- zakah, smart_roi, roi_named_products, …
  enabled boolean NOT NULL DEFAULT false,
  rules jsonb NOT NULL DEFAULT '{}',            -- {platforms:[], min_app_version:"1.4.0", rollout_percent:0..100}
  version integer NOT NULL, updated_at timestamptz NOT NULL, updated_by uuid NOT NULL
);

-- Prices (FR-BE-04)
CREATE TABLE price_quotes (symbol text NOT NULL, currency text NOT NULL, price numeric(20,6) NOT NULL,
  per_unit text NOT NULL, as_of timestamptz NOT NULL, source text NOT NULL, is_override boolean NOT NULL DEFAULT false,
  override_expires_at timestamptz,              -- set when is_override; default now() + 24 h, at most 7 days; then the feed applies again
  feed_price numeric(20,6),                     -- T-127: the last feed value, kept while an override is in force (served again at expiry)
  feed_as_of timestamptz,                       -- T-127: when the feed value was fetched; staleness (> 24 h) is judged on this
  PRIMARY KEY (symbol, currency),
  CHECK (price > 0 AND (feed_price IS NULL OR feed_price > 0)),
  CHECK (is_override = (override_expires_at IS NOT NULL)));
-- T-127. Effective value at time t: an override with override_expires_at > t, else feed_price (a row from before feed_price existed and
-- not an override counts as its own feed value). The worker always writes feed_*, and price/as_of/source only where no unexpired override
-- is in force. Gold symbols XAU24_G, XAU21_G, XAU18_G in EGP and USD (per gram); fx_rates.base is always USD.
CREATE TABLE fx_rates (base text NOT NULL, quote text NOT NULL, rate numeric(24,12) NOT NULL,
  as_of timestamptz NOT NULL, source text NOT NULL, PRIMARY KEY (base, quote));

-- Contributions (FR-BE-07, BR-SYNC-04)
CREATE TABLE merchant_contributions (
  id uuid PRIMARY KEY,
  merchant_norm text NOT NULL, institution_code text NOT NULL, category_code text NOT NULL,
  install_hash bytea NOT NULL,                  -- HMAC(install_id, pepper) — counts distinct installs without joining
  received_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (merchant_norm, institution_code, install_hash),
  -- Backstop only, narrower than the API filter (ContributionPrivacy, security-model.md §6), which runs first on the same stored text.
  -- No run of 6 digits in the scripts listed here (ASCII, Arabic-Indic, Extended Arabic-Indic, fullwidth), separated by up to three
  -- whitespace, dot, comma, slash, underscore, Arabic comma or dash characters (FU-018; '010 1234 5678' and '01 / 23 / 45' are runs); no '@' (e-mail, InstaPay address); at most 64 characters.
  CHECK (char_length(merchant_norm) <= 64 AND merchant_norm !~ '([0-9٠-٩۰-۹０-９][[:space:].,/_،-]{0,3}){6,}' AND position('@' in merchant_norm) = 0),
  CHECK (institution_code ~ '^[a-z0-9_]{1,64}$'),   -- OpenAPI InstitutionCode alphabet (lowercase slug)
  CHECK (category_code ~ '^[a-z0-9_]{1,64}$')       -- OpenAPI CategoryCode alphabet (no dots)
);
CREATE TABLE contribution_aggregates (
  merchant_norm text NOT NULL, institution_code text NOT NULL,
  distinct_installs integer NOT NULL, top_category_code text NOT NULL, category_votes jsonb NOT NULL,
  status text NOT NULL CHECK (status IN ('collecting','ready_for_review','promoted','rejected')),
  reviewed_by uuid, reviewed_at timestamptz,
  PRIMARY KEY (merchant_norm, institution_code)
);   -- ready_for_review when distinct_installs ≥ 5 (A-48); 'collecting' rows are never returned by the admin API

-- "Request my bank" (FR-BE-10)
CREATE TABLE bank_requests (
  institution_name_norm text NOT NULL, country text NOT NULL, channel text NOT NULL CHECK (channel IN ('sms','notification')),
  CHECK (char_length(institution_name_norm) <= 64 AND institution_name_norm !~ '([0-9٠-٩۰-۹０-９][[:space:].,/_،-]{0,3}){6,}'
         AND position('@' in institution_name_norm) = 0),
  install_hash bytea NOT NULL, received_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (institution_name_norm, country, channel, install_hash)
);

-- Anonymous aggregate counters (OQ-01, ADR-021)
CREATE TABLE daily_active_counts (day date NOT NULL, platform text NOT NULL, app_version text NOT NULL,
  installs integer NOT NULL, PRIMARY KEY (day, platform, app_version));
-- T-128: each claimed sync adds its install to (UTC day, platform, app version) in the same transaction as the claim, through
-- zaghlol.count_daily_active(p_platform text, p_app_version text): SECURITY DEFINER (owner migrator), search_path fixed, EXECUTE
-- for app_rw only. It can only add 1, to the row of the database's own UTC date ((now() AT TIME ZONE 'UTC')::date; the caller
-- can't choose a day), and only for platform 'android' or 'ios' (SQLSTATE 22023 otherwise). Migration CountDailyActiveServerDay
-- (T-128 SEC S3) replaced the first form, which took the day as an argument. app_rw keeps no table privilege here (cannot read
-- the counters or write a count, T-122 SEC F10).

-- Operators & audit (FR-BE-08)
CREATE TABLE operators (id uuid PRIMARY KEY, oidc_subject text NOT NULL UNIQUE, display_name text NOT NULL,
  roles text[] NOT NULL, disabled_at timestamptz);
CREATE TABLE audit_log (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  operator_id uuid NOT NULL REFERENCES operators(id),   -- operators are disabled, never deleted
  action text NOT NULL, target text NOT NULL, details jsonb NOT NULL, at timestamptz NOT NULL DEFAULT now(),
  -- No e-mail or order ID under any key at any depth, in any letter case, and no '@' anywhere (D-57, NFR-PRIV-07)
  CHECK (NOT jsonb_path_exists(details, 'lax $.** ? (@.type() == "object").keyvalue() ? (@.key like_regex "^(e-?mail|order_?id)$" flag "i")')
         AND details::text !~ '@'),
  CHECK (position('@' in target) = 0));
-- Support lookups: target = install id, or 'email:' || hex(HMAC-SHA256(K_audit, NFC(trim(lower(email))))); details.account_id
-- = the matched account. Never the e-mail. Pseudonymous personal data (see §3, §4).
-- Support seat moves and detaches (backend-api §5.3, D-57, FR-BE-11): action IN ('support_seat_move','support_detach'),
-- target = purchase id, details = {from_install, to_install, reason_code, ticket_ref, attached_account_id?, detached_account_id?,
-- corrects_audit_id?, ownership_check: 'order_id', ownership_outcome: pass|fail|unavailable|not_run, outcome}; outcome includes
-- 'dispute_frozen' for a refusal during a D-64 freeze (audited, D-65(b)). Exactly one row per call,
-- naming the operator. Never an e-mail, an ORDER ID or free text. Same 1-year retention as lookups.
-- Support-lead unfreeze (backend-api §5.3, R5-5(b)): action = 'support_unfreeze', target = purchase id, details =
-- {ticket_ref, freeze_audit_id, frozen_until, ownership_check: 'order_id', ownership_outcome, outcome: unfrozen|noop|
-- refused|ownership_failed|upstream_unavailable}. operator_id must differ from freeze_audit_id's operator. Same 1-year retention.
```

## 3. Constraints that protect privacy

| Concern | Mechanism |
|---|---|
| Contributions carry no phone, card or account number and no e-mail or InstaPay address; person names, short amounts and dates are not detected by the server | API validation (BR-SYNC-04, `security-model.md` §6): the server drops text with a commercial at, a run of 6 digits of any Unicode digit script (up to 3 non-letter separators between digits) or over 64 characters, on the normalized text it stores. It does **not** detect person names, and short amounts and dates (`250.00`, `12/05`, `99 egp`) pass the 6-digit rule: that residual is PO-accepted and covered by the app's own filter, the A-48 threshold (at least 5 distinct installs before review) and mandatory operator review before promotion (T-129). The DB backstop, narrower than the API filter, rejects a run of 6 digits in ASCII, Arabic-Indic `٠-٩`, Extended `۰-۹` or fullwidth `０-９`, separated by up to three whitespace, dot, comma, slash, underscore, Arabic-comma or dash characters (FU-018), rejects any `@`, and caps the length at 64 (the same CHECK on `bank_requests.institution_name_norm`). `institution_code` and `category_code` must be lowercase slugs |
| Direct read-only DB access | `ops_ro` (login `zaghlol_ops_ro`, break-glass only, T-140) can't read `accounts.email`, `accounts.provider_subject`, `purchases.store_key`, `purchases.linked_purchase_token`, `store_notifications.store_key`, token hashes, refresh tokens or stored responses. Support lookups go through the audited admin API (`ops_rw`) |
| Wrong credentials | Each runtime process checks at startup that its login is a member of exactly its own group and is not a superuser, the schema owner or `migrator`, and stops otherwise; readiness reports 503 until the App login passes the same check |
| Distinct counts without tracking | `install_hash` = HMAC-SHA256 with a pepper held in the KMS; it can't be joined back to `installs` without the pepper |
| No device identifiers | No column exists for IMEI, ad ID or phone number; DTOs reject unknown fields |
| Purchase link to a person | Store receives `obfuscatedAccountId`/`appAccountToken` = HMAC(install_id), never e-mail |
| Support lookups by e-mail | The e-mail travels only in a POST body (`backend-api.md` §5.2). The audit row stores `HMAC-SHA256(K_audit, NFC(trim(lower(email))))` plus the matched `account_id`, never the e-mail. `K_audit` is a dedicated KMS key, separate from the `install_hash` pepper, so the value can't be reversed by a dictionary attack without the KMS. It is still **pseudonymous personal data** and falls under the audit retention (§4) |
| ID token / attestation replay | `replay_guard` keeps only hashes, until the token's `exp` (Play Integrity: 15 min) |
| Idempotent replays | `idempotency_records` returns a stored result only for the same install, operation, key and body hash, and only while `expires_at > now()`; bodies are encrypted and purged after 24 h, and deleted at once with their install or account. `POST /v1/installs` stores no token-bearing response at all (R3-6) |
| Same-iPhone recognition (D-55, D-62) | Only keyed hashes under `K_seat`, a dedicated KMS key: `purchase_seats.device_key_hash` / `seat_claimants.device_key_hash` = HMAC-SHA256(`K_seat`, purchase_id ‖ public key), and `installs.seat_key_hash` = HMAC-SHA256(`K_seat`, "install" ‖ 0x00 ‖ installId ‖ public key) (R4-1(1)); UUIDs as 36-character lower-case text, the key as its raw 65-byte point (T-182). `K_seat` is not rotated on a schedule (the hashes can't be recomputed without raw keys); emergency rotation clears these columns once (`deployment.md` §3). No raw public key, no Secure Enclave data. At rest, rows for different purchases can't be joined; the per-install hash sits on the install's own row. In transit the raw keys of up to 5 installs of one iPhone are visible to the running API (accepted, D-62); they are never logged |
| Time nonce (R4-2) | No column: the `Zaghlol-Time-Nonce` value is echoed in the signed response and never stored or logged |
| Store order IDs (D-57) | Never stored: no column, no audit field, no log; checked live with the store and dropped |
| Device attestation (D-45) | Only `app_attest_keys` (public key, counter) and Play verdict checks; no device identifier (IMEI, ad ID, serial, phone number) and no verdict payload is stored (FR-GOLD-09) |
| Third-party envelopes | Pub/Sub, ASSN and Apple callback bodies are open, but only the listed fields are read, after authentication. `store_notifications` stores only its explicit extracted columns and `payload_digest`, never the raw envelope or unknown fields |

## 4. Retention (NFR-PRIV-06, A-50)

| Data | Retention | Job |
|---|---|---|
| `installs` inactive (no sync) | 12 months, then deleted (cascades links; purchases keep `install_id = NULL` for store reconciliation) | `RetentionPurger` daily |
| Deleted installs | Tombstone (`deleted_at`) 30 days, then hard delete | same |
| Deleted accounts | No tombstone: `DELETE /v1/accounts/me` hard-deletes the row at once (cascading `account_installs`; the trigger clears the purchase links). Audit rows naming the account keep their own retention (below) | API (T-135) |
| `store_notifications` | 90 days | same |
| `merchant_contributions` raw rows | Deleted when the aggregate is promoted/rejected, or after 180 days | same |
| `bank_requests` | 24 months (aggregate counts kept) | same |
| Request logs | ≤ 30 days, IPs truncated to /24 (v4) or /48 (v6) | logging pipeline |
| `audit_log`, support-lookup, support-seat-move, support-detach and support-unfreeze rows (HMAC e-mail pseudonym, install IDs, `account_id`: pseudonymous personal data) | **Exactly 1 year from creation, then deleted** (D-47, FR-BE-11, NFR-PRIV-07). Account deletion neither shortens nor extends it: the row stays until its own 1-year mark (FR-ACCT-04), so it is gone at most 1 year after the account is deleted | `RetentionPurger` daily (`action IN ('support_lookup','support_seat_move','support_detach','support_unfreeze') AND at < now() - interval '1 year'`) |
| `audit_log`, all other operator actions | 3 years | `RetentionPurger` |
| `replay_guard` | Until `expires_at` | `RetentionPurger` |
| `purchase_seats` | With its purchase. The holder becomes NULL when its install is deleted or purged; `device_key_hash` stays with the seat (D-55) and is deleted with the purchase | — |
| `seat_claimants` | 7 days (ignored after that by every read); deleted with the install | `RetentionPurger` |
| `installs.seat_key_hash` | With the install: cleared at tombstone, deleted with the row | API + `RetentionPurger` |
| `purchase_seats.recent_rebinds`, `purchases.dispute_frozen_until`, `purchases.support_link_notice_pending`, `purchases.support_link_notice_iat` | With the purchase; rebind times older than 30 days are pruned on every seat check | — |
| `idempotency_records` | 24 h (never served after `expires_at`); deleted at once with its install or account | `RetentionPurger` + delete endpoints |
| `installs.registration_*` | Cleared at first authenticated call or after 24 h | API + `RetentionPurger` |
| DB backups (PITR) | 14 days | provider |

**Retention indexes (T-122):** `installs(last_seen_at)`; `installs(deleted_at) WHERE deleted_at IS NOT NULL`; `installs(first_seen_at) WHERE registration_key_hash IS NOT NULL`; `store_notifications(received_at)`; `merchant_contributions(received_at)`; `bank_requests(received_at)`; `audit_log(at)` plus `audit_log(at) WHERE action IN ('support_lookup','support_seat_move','support_detach','support_unfreeze')`; `replay_guard(expires_at)`; `seat_claimants(claimed_at)`; `idempotency_records(expires_at)`.

**Foreign-key indexes (EF convention, T-122):** `ix_account_installs_install_id`, `ix_seat_claimants_install_id`, `ix_purchase_events_purchase_id`, `ix_catalog_categories_parent_code`, `ix_catalog_merchants_category_code`, `ix_catalog_aliases_merchant_id`, `ix_audit_log_operator_id`. They serve the cascades and the purges. The unique contribution key is named `ux_merchant_contributions_identity` (the convention name would exceed PostgreSQL's 63-byte limit).

**`audit_log` purges are enforced by the database too:** the `worker_rw` DELETE policy admits only rows past these ages (support actions 1 year, others 3 years), so a purger bug can't erase recent evidence.

## 5. Capacity check (NFR-BE-04)

At 500k installs and 100k daily syncs:
- **Data size:** `installs` ≈ 500k × 150 B ≈ 75 MB, `purchases` ≈ 50k rows. Total DB < 1 GB.
- **Load:** peak sync ≈ 100k/day → about 5 req/s average, about 50 req/s at peak. That is comfortably two small API replicas.
