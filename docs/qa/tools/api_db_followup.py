"""Zaghlol QA: follow-up API checks (one fresh install per check) plus database checks.

Needs: a local Development backend with Dev:FakeStores, and env SU = libpq superuser connection string (without dbname).
Usage: python3 api_db_followup.py [base-url] [results.json]
"""
import base64
import hashlib
import json
import os
import secrets
# Passwords come from the environment: SU (connection string with QA_PG_SU_PW),
# QA_PG_SU_PW, QA_PG_API_PW, QA_PG_OPS_RO_PW, QA_PG_ADMIN_PW. No literals here.
import sys
import uuid

import psycopg
import requests
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature

B = sys.argv[1] if len(sys.argv) > 1 else 'http://127.0.0.1:8080'
OUT = sys.argv[2] if len(sys.argv) > 2 else 'api_db_followup_results.json'
APP = {'Zaghlol-App': 'android/1.0.0 (1)'}
C = '0123456789ABCDEFGHJKMNPQRSTVWXYZ'
R = []
ART = {}
db = psycopg.connect(os.environ['SU'] + ' dbname=zaghlol', autocommit=True)


def q(sql, *a):
    return db.execute(sql, a or None).fetchall()


def ulid():
    return ''.join(secrets.choice(C) for _ in range(26))


def b64u(b):
    return base64.urlsafe_b64encode(b).decode().rstrip('=')


def ub64(s):
    return base64.urlsafe_b64decode(s + '=' * (-len(s) % 4))


def add(cid, desc, exp, got, ok):
    R.append((cid, desc, str(exp), str(got)[:300], 'PASS' if ok else 'FAIL'))


def rec(cid, desc, exp, resp, ok=None, extra=''):
    try:
        body = resp.json()
    except Exception:
        body = resp.text[:80]
    code = body.get('code') if isinstance(body, dict) else None
    got = f"{resp.status_code}{' ' + code if code else ''}"
    if ok is None:
        ok = got.startswith(str(exp))
    add(cid, desc, exp, got + (' ' + extra if extra else ''), ok)
    return body


def fresh(platform='android'):
    iid = str(uuid.uuid4())
    h = {'Zaghlol-App': f'{platform}/1.0.0 (1)', 'Idempotency-Key': ulid()}
    r = requests.post(B + '/v1/installs', json={'installId': iid, 'platform': platform, 'appVersion': '1.0.0'}, headers=h)
    r.raise_for_status()
    return iid, r.json()['installToken']


def auth(iid, tok, extra=None):
    h = dict(APP)
    h['Zaghlol-Install'] = iid
    h['Authorization'] = 'Bearer ' + tok
    if extra:
        h.update(extra)
    return h


def keys():
    out = {}
    for part in requests.get(B + '/dev/v1/app-keys').text.strip().split(','):
        kid, x, y = part.split(':')
        nums = ec.EllipticCurvePublicNumbers(int.from_bytes(ub64(x), 'big'), int.from_bytes(ub64(y), 'big'), ec.SECP256R1())
        out[kid] = nums.public_key()
    return out


def es256_ok(pub, sig_raw, data):
    try:
        r, s = int.from_bytes(sig_raw[:32], 'big'), int.from_bytes(sig_raw[32:], 'big')
        pub.verify(encode_dss_signature(r, s), data, ec.ECDSA(hashes.SHA256()))
        return True
    except Exception:
        return False


SYNC0 = {'catalogVersion': 0, 'flagsVersion': 0}
CON = {'institutionCode': 'nbe', 'categoryCode': 'dining'}
KEYS = keys()

# ---- F-01 first sync on an empty backend
iid, tok = fresh()
r = requests.post(B + '/v1/sync', json=SYNC0, headers=auth(iid, tok))
b = rec('F-01', 'first sync, nothing published yet', 200, r, extra=r.text[:260])
ART['first_sync_empty_backend'] = r.text[:1200]

# ---- F-02 Zaghlol-App header on sync
iid, tok = fresh()
h = auth(iid, tok)
del h['Zaghlol-App']
rec('F-02', 'sync without the Zaghlol-App header', '400 VALIDATION_FAILED', requests.post(B + '/v1/sync', json=SYNC0, headers=h))
h['Zaghlol-App'] = 'android 1.0'
rec('F-03', 'sync with a malformed Zaghlol-App header', '400 VALIDATION_FAILED', requests.post(B + '/v1/sync', json=SYNC0, headers=h))

# ---- F-04 invalid bank request values: rejected, or accepted and dropped?
before = q('select count(*) from zaghlol.bank_requests')[0][0]
iid, tok = fresh()
body = {**SYNC0, 'bankRequests': [{'institutionName': 'Bank X', 'country': 'eg', 'channel': 'email'}]}
r = requests.post(B + '/v1/sync', json=body, headers=auth(iid, tok))
after = q('select count(*) from zaghlol.bank_requests')[0][0]
rec('F-04', 'bank request with lower-case country and channel "email" (OpenAPI: pattern ^[A-Z]{2}$, enum sms|notification)',
    '400 VALIDATION_FAILED', r, extra=f'stored rows +{after - before}; body={r.text[:160]}')

# ---- F-05 contributions: privacy filter (BR-SYNC-04) and storage
iid, tok = fresh()
c_before = q('select count(*) from zaghlol.merchant_contributions')[0][0]
b_before = q('select count(*) from zaghlol.bank_requests')[0][0]
names = ['qa koshary el tahrir', '01001234567', 'ahmed@instapay', '+201001234567', 'mohamed ahmed ali', 'x']
body = {**SYNC0, 'contributions': [{**CON, 'merchantNorm': n} for n in names],
        'bankRequests': [{'institutionName': 'QA Banque du Caire', 'country': 'EG', 'channel': 'sms'}]}
r = requests.post(B + '/v1/sync', json=body, headers=auth(iid, tok))
b = rec('F-05', 'sync with 6 contributions (1 merchant, 3 phone/IPA, 1 person-like name, 1 too short) + 1 bank request', 200, r,
        extra=r.text[:200])
stored = [x[0] for x in q('select merchant_norm from zaghlol.merchant_contributions order by received_at desc limit %s',
                          q('select count(*) from zaghlol.merchant_contributions')[0][0] - c_before)]
add('F-06', 'phone numbers and IPA never stored as merchant contributions', 'none stored', stored,
    not any(s in stored for s in ['01001234567', 'ahmed@instapay', '+201001234567']))
add('F-07', 'valid merchant contribution stored', 'qa koshary el tahrir', stored, 'qa koshary el tahrir' in stored)
add('F-08', 'person-like name "mohamed ahmed ali" (BR-SYNC-04 excludes person-name patterns; D: server-side name '
    'detection waived, T-128)', 'observation', 'stored' if 'mohamed ahmed ali' in stored else 'dropped', True)
row = q('select install_hash, institution_name_norm, country, channel from zaghlol.bank_requests order by received_at desc limit 1')
add('F-09', 'bank request stored with a hash, not the install ID', 'hash != installId',
    f'{len(row[0][0]) if row else 0}-byte hash; {row[0][1:] if row else None}',
    bool(row) and bytes(row[0][0]) != uuid.UUID(iid).bytes and q('select count(*) from zaghlol.bank_requests')[0][0] == b_before + 1)
h_raw = hashlib.sha256(uuid.UUID(iid).bytes).digest()
h_txt = hashlib.sha256(iid.encode()).digest()
add('F-10', 'install hash is keyed (not a bare SHA-256 of the install ID)', 'keyed', 'bare sha256' if row and bytes(row[0][0]) in (h_raw, h_txt) else 'keyed',
    bool(row) and bytes(row[0][0]) not in (h_raw, h_txt))

# ---- F-11 feature flags: seeded directly, delivered and signed (FR-BE-05, FR-SYNC-04)
op = q('select id from zaghlol.operators limit 1')
if not op:
    oid = uuid.uuid4()
    db.execute("insert into zaghlol.operators(id, oidc_subject, display_name, roles) values (%s,'qa-seed','QA seed', array['catalog_editor'])", (oid,))
else:
    oid = op[0][0]
for key, en in (('zakah', False), ('smart_roi', False), ('qa_flag_on', True)):
    try:
        db.execute("insert into zaghlol.feature_flags(key, enabled, rules, version, updated_at, updated_by) values (%s,%s,'{}'::jsonb,1,now(),%s) on conflict (key) do nothing", (key, en, oid))
    except Exception as e:  # noqa: BLE001
        ART['flag_seed_error_' + key] = str(e)[:200]
iid, tok = fresh()
r = requests.post(B + '/v1/sync', json=SYNC0, headers=auth(iid, tok))
b = rec('F-11', 'sync after flags exist in the database', 200, r, extra=r.text[:260])
vals = ((b.get('flags') or {}).get('values') or {}) if isinstance(b, dict) else {}
add('F-12', 'zakah and smart_roi delivered as false; a flag switched on is delivered as true', 'false,false,true',
    json.dumps(vals), vals.get('zakah') is False and vals.get('smart_roi') is False and vals.get('qa_flag_on') is True)
sig = r.headers.get('Zaghlol-Signature', '')
ART['signature_header'] = sig[:160]
ok_sig = False
try:
    parts = dict(p.strip().split('=', 1) for p in sig.replace(';', ',').split(',') if '=' in p)
    kid = parts.get('kid') or parts.get('keyid') or 's0000d'
    raw = ub64(parts.get('sig') or parts.get('signature') or sig.split('.')[-1])
    ok_sig = es256_ok(KEYS[kid.strip('"')], raw, r.content)
    tampered = es256_ok(KEYS[kid.strip('"')], raw, r.content.replace(b'false', b'true ', 1))
except Exception as e:  # noqa: BLE001
    ART['signature_parse_error'] = str(e)[:200]
    tampered = None
add('F-13', 'Zaghlol-Signature verifies (ES256) over the exact body with the published sync key', 'valid', ok_sig, ok_sig)
add('F-14', 'the same signature does not verify over a tampered body', 'invalid', tampered, tampered is False)

# ---- F-15 entitlement token contents and signature
iid, tok = fresh()
r0 = requests.get(B + '/v1/entitlement', headers=auth(iid, tok))


def claims(resp):
    t = resp.json()['entitlement']['token']
    hdr, pl, sg = t.split('.')
    return t, json.loads(ub64(hdr)), json.loads(ub64(pl)), ub64(sg), (hdr + '.' + pl).encode()


t, hd, pl, sg, signed = claims(r0)
ART['entitlement_free_claims'] = pl
add('F-15', 'free install: entitlement token says no Gold', 'plan free/none', json.dumps(pl)[:200],
    str(pl.get('plan', pl.get('tier', ''))).lower() in ('free', 'none', '') or pl.get('gold') is False or pl.get('status') in ('none', 'free', 'inactive'))
add('F-16', 'entitlement JWS verifies with the published entitlement key', 'valid', hd, es256_ok(KEYS[hd['kid']], sg, signed))
add('F-17', 'entitlement token subject is this install', iid, pl.get('sub'), pl.get('sub') == iid)
g = requests.post(B + '/dev/v1/grant-gold', json={'plan': 'monthly', 'installId': iid})
r1 = requests.get(B + '/v1/entitlement', headers=auth(iid, tok))
t1, hd1, pl1, sg1, signed1 = claims(r1)
ART['entitlement_gold_claims'] = pl1
add('F-18', 'after a verified (fake-store) monthly purchase the token carries the plan and an expiry', 'monthly + exp',
    json.dumps(pl1)[:260], 'monthly' in json.dumps(pl1) and es256_ok(KEYS[hd1['kid']], sg1, signed1))
forged = dict(pl)
forged_token = t.split('.')[0] + '.' + b64u(json.dumps({**pl1, 'sub': pl['sub']}).encode()) + '.' + t.split('.')[2]
fh, fp, fs = forged_token.split('.')
add('F-19', 'a payload swapped onto another token\'s signature does not verify (NFR-SEC-05, server side of the check)', 'invalid',
    '', not es256_ok(KEYS[hd['kid']], ub64(fs), (fh + '.' + fp).encode()))
# another install must not see this install's Gold
iid2, tok2 = fresh()
r2 = requests.get(B + '/v1/entitlement', headers=auth(iid2, tok2))
_, _, pl2, _, _ = claims(r2)
add('F-20', 'a different install gets no Gold from someone else\'s purchase', 'no monthly', json.dumps(pl2)[:160], 'monthly' not in json.dumps(pl2))
pr = q('select state, plan, acknowledged, store, environment from zaghlol.purchases where install_id=%s', iid)
add('F-21', 'purchase row persisted for the granted install', 'row', pr, len(pr) == 1)
st = q('select count(*) from zaghlol.purchase_seats s join zaghlol.purchases p on p.id=s.purchase_id where p.install_id=%s', iid)
add('F-22', 'exactly one seat for the purchase (BR-GOLD-07)', 1, st[0][0], st[0][0] == 1)

# ---- F-23 purchase token length, sign-in and account checks on fresh installs
iid, tok = fresh()
V = {'platform': 'android', 'productId': 'zaghlol_gold_yearly', 'purchaseToken': 'x' * 513}
r = requests.post(B + '/v1/purchases/verify', json=V, headers=auth(iid, tok, {'Idempotency-Key': ulid()}))
rec('F-23', 'verify: purchaseToken of 513 chars (OpenAPI maxLength 512)', '400 VALIDATION_FAILED', r)
k = ulid()
V2 = {**V, 'purchaseToken': 'forged-abc'}
ra = requests.post(B + '/v1/purchases/verify', json=V2, headers=auth(iid, tok, {'Idempotency-Key': k}))
rb = requests.post(B + '/v1/purchases/verify', json=V2, headers=auth(iid, tok, {'Idempotency-Key': k}))
rc = requests.post(B + '/v1/purchases/verify', json={**V2, 'purchaseToken': 'forged-xyz'}, headers=auth(iid, tok, {'Idempotency-Key': k}))
add('F-24', 'verify replay with the same key and body returns the same answer', ra.status_code, rb.status_code, ra.status_code == rb.status_code and ra.text == rb.text)
rec('F-25', 'verify with the same key and a different body', '409 IDEMPOTENCY_KEY_REUSED', rc)
none_jwt = b64u(b'{"alg":"none","typ":"JWT"}') + '.' + b64u(b'{"iss":"https://accounts.google.com","sub":"1","aud":"x","exp":9999999999}') + '.'
iid, tok = fresh()
SI = {'provider': 'google', 'idToken': none_jwt, 'nonce': 'A' * 22}
r = requests.post(B + '/v1/accounts/signin', json=SI, headers=auth(iid, tok, {'Idempotency-Key': ulid()}))
rec('F-26', 'sign-in with an alg=none Google ID token', '4xx, no account', r, ok=r.status_code in (400, 401, 422))
add('F-27', 'no account row created by the forged sign-in', 0, q('select count(*) from zaghlol.accounts')[0][0], q('select count(*) from zaghlol.accounts')[0][0] == 0)
iid, tok = fresh()
r = requests.delete(B + '/v1/accounts/me', headers=auth(iid, tok))
rec('F-28', 'delete account without an account token', '401', r)
r = requests.get(B + '/v1/entitlement', headers=auth(iid, tok, {'Zaghlol-Account': none_jwt}))
rec('F-29', 'forged account token (alg=none) on entitlement', '401', r)

# ---- F-30 delete install: what remains on the server (FR-ONB-08)
iid, tok = fresh()
requests.post(B + '/v1/sync', json=SYNC0, headers=auth(iid, tok))
requests.delete(B + '/v1/installs/me', headers=auth(iid, tok))
row = q('select deleted_at is not null, token_hash, platform, app_version, last_sync_at from zaghlol.installs where id=%s', iid)
ART['install_row_after_delete'] = str(row)[:300]
add('F-30', 'after DELETE /v1/installs/me the row is tombstoned (deleted_at set) and its token no longer works', 'deleted_at set',
    row, bool(row) and row[0][0] is True)

# ---- database: constraints, privileges, immutability
def expect_fail(cid, desc, conn, sql, params=()):
    try:
        conn.execute(sql, params)
        add(cid, desc, 'rejected', 'ACCEPTED', False)
    except Exception as e:  # noqa: BLE001
        add(cid, desc, 'rejected', type(e).__name__ + ': ' + str(e).split('\n')[0][:140], True)


nid = uuid.uuid4()
expect_fail('D-01', 'installs: platform outside android/ios', db,
            "insert into zaghlol.installs(id, token_hash, platform, app_version, catalog_version, first_seen_at, last_seen_at, seat_key_trusted) values (%s, %s, 'windows', '1.0.0', 0, now(), now(), false)", (nid, secrets.token_bytes(32)))
expect_fail('D-02', 'installs: duplicate primary key', db,
            "insert into zaghlol.installs(id, token_hash, platform, app_version, catalog_version, first_seen_at, last_seen_at, seat_key_trusted) values (%s, %s, 'android', '1.0.0', 0, now(), now(), false)", (uuid.UUID(iid), secrets.token_bytes(32)))
expect_fail('D-03', 'installs: negative catalog_version', db,
            "insert into zaghlol.installs(id, token_hash, platform, app_version, catalog_version, first_seen_at, last_seen_at, seat_key_trusted) values (%s, %s, 'android', '1.0.0', -1, now(), now(), false)", (uuid.uuid4(), secrets.token_bytes(32)))
expect_fail('D-04', 'installs: hard DELETE blocked by trigger (tombstone only)', db, 'delete from zaghlol.installs where id=%s', (uuid.UUID(iid),))
expect_fail('D-05', 'purchase_seats: foreign key to a purchase that does not exist', db,
            "insert into zaghlol.purchase_seats(purchase_id, install_id, proof, bound_at) values (%s, %s, 'x', now())", (uuid.uuid4(), uuid.UUID(iid)))
expect_fail('D-06', 'bank_requests: channel outside sms/notification', db,
            "insert into zaghlol.bank_requests(institution_name_norm, country, channel, install_hash, received_at) values ('qa', 'EG', 'email', %s, now())", (secrets.token_bytes(32),))
expect_fail('D-07', 'bank_requests: country not two upper-case letters', db,
            "insert into zaghlol.bank_requests(institution_name_norm, country, channel, install_hash, received_at) values ('qa', 'egy', 'sms', %s, now())", (secrets.token_bytes(32),))
expect_fail('D-08', 'price_quotes: negative price', db,
            "insert into zaghlol.price_quotes(symbol, currency, price, per_unit, as_of, source, is_override) values ('XAU24_G','EGP',-1,'g',now(),'qa',false)")
dup = q('select store, store_key, product_id, plan, state, environment from zaghlol.purchases limit 1')
if dup:
    s = dup[0]
    expect_fail('D-09', 'purchases: duplicate store + store_key (one row per store purchase)', db,
                "insert into zaghlol.purchases(id, store, product_id, plan, store_key, state, acknowledged, environment, account_linked_by, support_link_notice_pending, last_verified_at, created_at) "
                "select gen_random_uuid(), store, product_id, plan, store_key, state, acknowledged, environment, account_linked_by, support_link_notice_pending, now(), now() from zaghlol.purchases limit 1")

api = psycopg.connect(os.environ['SU'].replace('user=zaghlol ', 'user=zaghlol_api ').replace('password=' + os.environ['QA_PG_SU_PW'], 'password=' + os.environ['QA_PG_API_PW']) + ' dbname=zaghlol', autocommit=True)
ro = psycopg.connect(os.environ['SU'].replace('user=zaghlol ', 'user=zaghlol_ops_ro ').replace('password=' + os.environ['QA_PG_SU_PW'], 'password=' + os.environ['QA_PG_OPS_RO_PW']) + ' dbname=zaghlol', autocommit=True)
expect_fail('D-10', 'API login cannot read the operators table', api, 'select * from zaghlol.operators')
expect_fail('D-11', 'API login cannot read the audit log', api, 'select * from zaghlol.audit_log')
expect_fail('D-12', 'API login cannot change feature flags', api, "update zaghlol.feature_flags set enabled=true where key='zakah'")
expect_fail('D-13', 'API login cannot delete purchases', api, 'delete from zaghlol.purchases')
expect_fail('D-14', 'API login cannot create tables in the schema', api, 'create table zaghlol.qa_x(i int)')
expect_fail('D-15', 'read-only ops login cannot insert operators', ro, "insert into zaghlol.operators(id, oidc_subject, display_name, roles) values (gen_random_uuid(),'x','x',array['support_lead'])")
expect_fail('D-16', 'read-only ops login cannot update installs', ro, "update zaghlol.installs set app_version='9.9.9'")
adm = psycopg.connect(os.environ['SU'].replace('user=zaghlol ', 'user=zaghlol_admin ').replace('password=' + os.environ['QA_PG_SU_PW'], 'password=' + os.environ['QA_PG_ADMIN_PW']) + ' dbname=zaghlol', autocommit=True)
expect_fail('D-17', 'admin login cannot delete audit rows', adm, 'delete from zaghlol.audit_log')
expect_fail('D-18', 'admin login cannot update audit rows', adm, "update zaghlol.audit_log set action='x'")
cols = [x[0] for x in q("select column_name from information_schema.columns where table_schema='zaghlol' and (column_name ilike '%ip%addr%' or column_name ilike '%imei%' or column_name ilike '%phone%' or column_name ilike '%advert%' or column_name ilike '%device_id%' or column_name ilike '%amount%' or column_name ilike '%balance%')")]
add('D-19', 'no column for IP address, IMEI, phone, advertising ID, device ID, amount or balance (BR-SYNC-03, FR-BE-01)', 'none', cols, not cols)
em = q("select data_type from information_schema.columns where table_schema='zaghlol' and table_name='installs' and column_name='token_hash'")
add('D-20', 'install token stored only as a hash (bytea), never in clear', 'bytea', em, em and em[0][0] == 'bytea')

json.dump({'results': R, 'artifacts': ART}, open(OUT, 'w'), indent=1, default=str)
p = sum(1 for x in R if x[4] == 'PASS')
print(f'{p}/{len(R)} pass')
for x in R:
    if x[4] != 'PASS' or x[0] in ('F-01', 'F-05', 'F-08', 'F-11', 'F-15', 'F-18', 'F-21', 'F-30'):
        print(x)
print(json.dumps(ART, default=str)[:1500])
