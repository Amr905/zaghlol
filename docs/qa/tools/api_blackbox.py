"""Zaghlol QA: black-box tests of the backend API (run against a local Development backend with Dev:FakeStores).

Usage: python3 api_blackbox.py [base-url] [results.json]
Each case records: id, description, expected, actual, PASS/FAIL.
"""
import base64
import json
import secrets
import sys
import uuid

import requests

B = sys.argv[1] if len(sys.argv) > 1 else 'http://127.0.0.1:8080'
OUT = sys.argv[2] if len(sys.argv) > 2 else 'api_blackbox_results.json'
APP = {'Zaghlol-App': 'android/1.0.0 (1)'}
C = '0123456789ABCDEFGHJKMNPQRSTVWXYZ'
R = []
ART = {}


def ulid():
    return ''.join(secrets.choice(C) for _ in range(26))


def rec(cid, desc, exp, resp, ok=None, extra=''):
    try:
        body = resp.json()
    except Exception:
        body = resp.text[:80]
    code = body.get('code') if isinstance(body, dict) else None
    got = f"{resp.status_code}{' ' + code if code else ''}"
    if ok is None:
        ok = got.startswith(str(exp))
    R.append((cid, desc, str(exp), got + (' ' + extra if extra else ''), 'PASS' if ok else 'FAIL'))
    return body


def reg(iid=None, platform='android', ver='1.0.0', key=None, hdr=None, body=None):
    iid = iid or str(uuid.uuid4())
    h = dict(APP)
    h['Idempotency-Key'] = key or ulid()
    if hdr:
        h.update(hdr)
    payload = body if body is not None else {'installId': iid, 'platform': platform, 'appVersion': ver}
    return iid, requests.post(B + '/v1/installs', json=payload, headers=h)


def auth(iid, tok, extra=None):
    h = dict(APP)
    h['Zaghlol-Install'] = iid
    h['Authorization'] = 'Bearer ' + tok
    if extra:
        h.update(extra)
    return h


def b64u(b):
    return base64.urlsafe_b64encode(b).decode().rstrip('=')


SYNC0 = {'catalogVersion': 0, 'flagsVersion': 0}
NEW = lambda **kw: {'installId': str(uuid.uuid4()), 'platform': 'android', 'appVersion': '1.0.0', **kw}

# ---- health
rec('API-001', 'GET /v1/health', 200, requests.get(B + '/v1/health'))

# ---- installs
iid, r = reg()
b = rec('API-002', 'register install (valid)', 201, r)
tok = b.get('installToken', '') if isinstance(b, dict) else ''
rec('API-003', 'install token is 43-char base64url (32 bytes)', 'len 43', r, ok=len(tok) == 43, extra=f'len={len(tok)}')
_, r = reg(iid=iid)
rec('API-004', 'register same installId with a new key', '409 INSTALL_EXISTS', r)
_, r = reg(body={'installId': 'not-a-uuid', 'platform': 'android', 'appVersion': '1.0.0'})
rec('API-005', 'installId not a UUID', '400 VALIDATION_FAILED', r)
_, r = reg(body=NEW(platform='windows'))
rec('API-006', 'platform not in enum', '400 VALIDATION_FAILED', r)
_, r = reg(body={'installId': str(uuid.uuid4()), 'platform': 'android'})
rec('API-007', 'missing appVersion', '400 VALIDATION_FAILED', r)
_, r = reg(body=NEW(imei='123456789012345'))
rec('API-008', 'extra field imei (closed schema, BR-SYNC-03)', '400 UNKNOWN_FIELD', r)
_, r = reg(body=NEW(osMajor=14))
rec('API-009', 'extra field osMajor', '400 UNKNOWN_FIELD', r)
_, r = reg(body=NEW(appVersion='99999.0.0'))
rec('API-010', 'appVersion outside pattern (boundary)', '400 VALIDATION_FAILED', r)
_, r = reg(body=NEW(appVersion='9999.9999.9999'))
rec('API-011', 'appVersion at max boundary accepted', 201, r)
r = requests.post(B + '/v1/installs', json=NEW(), headers=dict(APP))
rec('API-012', 'missing Idempotency-Key', '400', r)
_, r = reg(key='not-a-ulid')
rec('API-013', 'malformed Idempotency-Key', '400 VALIDATION_FAILED', r)
r = requests.post(B + '/v1/installs', json=NEW(), headers={'Idempotency-Key': ulid()})
rec('API-014', 'missing Zaghlol-App header', '400', r)
_, r = reg(hdr={'Zaghlol-App': 'android 1.0'})
rec('API-015', 'malformed Zaghlol-App header', '400 VALIDATION_FAILED', r)
h = dict(APP)
h['Idempotency-Key'] = ulid()
h['Content-Type'] = 'text/plain'
r = requests.post(B + '/v1/installs', data=json.dumps(NEW()), headers=h)
rec('API-016', 'wrong content type', '415 UNSUPPORTED_MEDIA_TYPE', r)
h['Content-Type'] = 'application/json'
r = requests.post(B + '/v1/installs', data='{"installId":', headers=h)
rec('API-017', 'malformed JSON', '400 VALIDATION_FAILED', r)
r = requests.post(B + '/v1/installs', data=json.dumps(NEW(pad='x' * 70000)), headers=h)
rec('API-018', 'body larger than 64 KB', '413 PAYLOAD_TOO_LARGE', r)
dup = '{"installId":"%s","installId":"%s","platform":"android","appVersion":"1.0.0"}' % (uuid.uuid4(), uuid.uuid4())
r = requests.post(B + '/v1/installs', data=dup, headers=h)
rec('API-019', 'duplicate JSON property', '400', r)

k = ulid()
i2 = str(uuid.uuid4())
_, r1 = reg(iid=i2, key=k)
t1 = r1.json().get('installToken')
_, r2 = reg(iid=i2, key=k)
b2 = rec('API-020', 'retry with same key and body before first authenticated call', 201, r2)
t2 = b2.get('installToken') if isinstance(b2, dict) else None
rec('API-021', 'the retry issues a different token', 'differs', r2, ok=bool(t1 and t2 and t1 != t2))
r = requests.post(B + '/v1/sync', json=SYNC0, headers=auth(i2, t1))
rec('API-022', 'superseded token is rejected', '401 INSTALL_TOKEN_INVALID', r)
_, r = reg(iid=i2, key=k, ver='1.0.1')
rec('API-023', 'same key with a different body', '409 IDEMPOTENCY_KEY_REUSED', r)

# ---- sync: authentication
r = requests.post(B + '/v1/sync', json=SYNC0, headers=dict(APP))
rec('API-030', 'sync without credentials', '401', r)
r = requests.post(B + '/v1/sync', json=SYNC0, headers=auth(iid, 'A' * 43))
rec('API-031', 'sync with a wrong token', '401 INSTALL_TOKEN_INVALID', r)
i3, r3 = reg()
t3 = r3.json()['installToken']
r = requests.post(B + '/v1/sync', json=SYNC0, headers=auth(iid, t3))
rec('API-032', "another install's token with my install ID", '401 INSTALL_TOKEN_INVALID', r)
r = requests.post(B + '/v1/sync', json=SYNC0, headers=auth(str(uuid.uuid4()), tok))
rec('API-033', 'valid token with an unknown install ID', '401 INSTALL_TOKEN_INVALID', r)

# ---- sync: validation
CON = {'merchantNorm': 'kfc', 'institutionCode': 'nbe', 'categoryCode': 'dining'}
BR = {'institutionName': 'Bank X', 'country': 'EG', 'channel': 'sms'}
cases = [
    ({'flagsVersion': 0}, '400 VALIDATION_FAILED', 'missing catalogVersion'),
    ({**SYNC0, 'catalogVersion': -1}, '400 VALIDATION_FAILED', 'catalogVersion -1'),
    ({**SYNC0, 'catalogVersion': 2147483648}, '400 VALIDATION_FAILED', 'catalogVersion above int32'),
    ({**SYNC0, 'catalogVersion': '0'}, '400 VALIDATION_FAILED', 'catalogVersion as a string'),
    ({**SYNC0, 'balance': '1000.00'}, '400 UNKNOWN_FIELD', 'financial field "balance"'),
    ({**SYNC0, 'transactions': [{'amount': '5'}]}, '400 UNKNOWN_FIELD', 'financial field "transactions"'),
    ({**SYNC0, 'contributions': [{**CON, 'amount': '12.50'}]}, '400 UNKNOWN_FIELD', 'contribution carrying an amount'),
    ({**SYNC0, 'contributions': [CON] * 51}, '400 VALIDATION_FAILED', '51 contributions (max 50)'),
    ({**SYNC0, 'bankRequests': [{**BR, 'country': 'eg'}]}, '400 VALIDATION_FAILED', 'country in lower case'),
    ({**SYNC0, 'bankRequests': [{**BR, 'channel': 'email'}]}, '400 VALIDATION_FAILED', 'channel not in enum'),
    ({**SYNC0, 'bankRequests': [{**BR, 'message': 'Your card 1234 was charged EGP 50'}]}, '400 UNKNOWN_FIELD',
     'bank request carrying a message body'),
    ({**SYNC0, 'bankRequests': [BR] * 11}, '400 VALIDATION_FAILED', '11 bank requests (max 10)'),
    ({**SYNC0, 'pricesAsOf': '2026-11-02 09:00'}, '400 VALIDATION_FAILED', 'pricesAsOf not RFC 3339 Z'),
]
for n, (body, exp, d) in enumerate(cases):
    r = requests.post(B + '/v1/sync', json=body, headers=auth(iid, tok))
    rec(f'API-{40 + n:03d}', 'sync: ' + d, exp, r)
r = requests.post(B + '/v1/sync', json=SYNC0, headers=auth(iid, tok, {'Zaghlol-Time-Nonce': 'short'}))
rec('API-055', 'malformed time nonce', '400 VALIDATION_FAILED', r)

# ---- sync: first effective call, then throttle
nonce = b64u(secrets.token_bytes(16))
body = {**SYNC0,
        'contributions': [{**CON, 'merchantNorm': 'koshary el tahrir'},
                          {**CON, 'merchantNorm': '01001234567'},
                          {**CON, 'merchantNorm': 'ahmed@instapay'}],
        'bankRequests': [{'institutionName': 'Banque du Caire', 'country': 'EG', 'channel': 'sms'}]}
r = requests.post(B + '/v1/sync', json=body, headers=auth(iid, tok, {'Zaghlol-Time-Nonce': nonce}))
b = rec('API-060', 'first sync (valid, with contributions and a bank request)', 200, r)
ART['sync_first'] = r.text[:3000]
ART['sync_first_bytes'] = len(r.content)
rec('API-061', 'sync 200 carries Zaghlol-Signature', 'header', r, ok='Zaghlol-Signature' in r.headers)
if isinstance(b, dict):
    fl = (b.get('flags') or {}).get('values', {})
    rec('API-062', 'time nonce echoed in the signed body', 'echo', r, ok=b.get('timeNonce') == nonce)
    rec('API-063', 'flags default off: zakah, smart_roi', 'false/false', r,
        ok=fl.get('zakah') is False and fl.get('smart_roi') is False, extra=json.dumps(fl))
    rec('API-064', 'phone-number and IPA contributions dropped (BR-SYNC-04): accepted = 1', 'contributions 1', r,
        ok=(b.get('accepted') or {}).get('contributions') == 1, extra=json.dumps(b.get('accepted')))
    cat = b.get('catalog') or {}
    rec('API-065', 'catalog block present for catalogVersion 0', 'catalog', r, ok=b.get('catalog') is not None,
        extra=json.dumps({x: cat.get(x) for x in ['fromVersion', 'toVersion', 'mode', 'fullUrl']}))
    rec('API-066', 'prices block returned (observation)', 'any', r, ok=True, extra=json.dumps(b.get('prices'))[:140])
r = requests.post(B + '/v1/sync', json=SYNC0, headers=auth(iid, tok))
b = rec('API-067', 'second sync inside 24 h', 200, r)
if isinstance(b, dict):
    rec('API-068', 'throttled body: only serverTime/nextSyncNotBefore/timeNonce, under 2 KB', 'keys', r,
        ok=set(b.keys()) <= {'serverTime', 'nextSyncNotBefore', 'timeNonce'} and len(r.content) < 2048,
        extra=','.join(b.keys()) + f' {len(r.content)}B')

# ---- entitlement
r = requests.get(B + '/v1/entitlement', headers=auth(iid, tok))
rec('API-070', 'entitlement for an install with no purchase', 200, r, extra=r.text[:120])
r = requests.get(B + '/v1/entitlement', headers=dict(APP))
rec('API-071', 'entitlement without credentials', '401', r)


# ---- purchases
def verify(body, key=None):
    return requests.post(B + '/v1/purchases/verify', json=body, headers=auth(iid, tok, {'Idempotency-Key': key or ulid()}))


V = {'platform': 'android', 'productId': 'zaghlol_gold_yearly', 'purchaseToken': 'forged-token-123'}
r = verify(V)
rec('API-080', 'verify a forged purchase token', '4xx, no Gold', r, ok=400 <= r.status_code < 500)
r = requests.get(B + '/v1/entitlement', headers=auth(iid, tok))
rec('API-080b', 'no Gold after the forged token', 200, r, extra=r.text[:120])
r = verify({k2: v for k2, v in V.items() if k2 != 'purchaseToken'})
rec('API-081', 'verify: missing purchaseToken', '400 VALIDATION_FAILED', r)
r = verify({**V, 'productId': 'BAD PRODUCT'})
rec('API-082', 'verify: productId outside pattern', '400 VALIDATION_FAILED', r)
r = verify({**V, 'purchaseToken': 'x' * 513})
rec('API-083', 'verify: purchaseToken 513 chars (max 512)', '400 VALIDATION_FAILED', r)
r = verify({**V, 'platform': 'web'})
rec('API-084', 'verify: unknown platform', '400 VALIDATION_FAILED', r)
r = verify({**V, 'platform': 'ios'})
rec('API-085', 'verify: iOS discriminator with Android fields', '400', r)
r = requests.post(B + '/v1/purchases/verify', json=V, headers={**APP, 'Idempotency-Key': ulid()})
rec('API-086', 'verify without credentials', '401', r)
RS = {'platform': 'android', 'purchases': [{'productId': 'zaghlol_gold_yearly', 'purchaseToken': 'x'}]}
r = requests.post(B + '/v1/purchases/restore', json=RS, headers=auth(iid, tok, {'Idempotency-Key': ulid()}))
rec('API-087', 'restore without attestation', '400 VALIDATION_FAILED', r)

# ---- dev grant (Development only) and the entitlement it produces
r = requests.post(B + '/dev/v1/grant-gold', json={'plan': 'yearly', 'installId': iid})
rec('API-090', 'dev grant-gold yearly (Development + Dev:FakeStores only)', 200, r, extra=r.text[:110])
r = requests.get(B + '/v1/entitlement', headers=auth(iid, tok))
rec('API-091', 'entitlement after the grant', 200, r)
ART['entitlement_after_grant'] = r.text[:1500]
rec('API-092', 'entitlement response is signed', 'header', r, ok='Zaghlol-Signature' in r.headers)


# ---- accounts
def signin(body):
    return requests.post(B + '/v1/accounts/signin', json=body, headers=auth(iid, tok, {'Idempotency-Key': ulid()}))


SI = {'provider': 'google', 'idToken': 'a.b.c', 'nonce': 'A' * 22}
none_jwt = b64u(b'{"alg":"none","typ":"JWT"}') + '.' + \
    b64u(b'{"iss":"https://accounts.google.com","sub":"1","aud":"x","exp":9999999999}') + '.'
r = signin(SI)
rec('API-100', 'sign-in with a forged ID token', '400/401', r, ok=r.status_code in (400, 401))
r = signin({**SI, 'provider': 'facebook'})
rec('API-101', 'sign-in: provider not in enum', '400 VALIDATION_FAILED', r)
r = signin({**SI, 'nonce': 'short'})
rec('API-102', 'sign-in: nonce too short', '400 VALIDATION_FAILED', r)
r = signin({**SI, 'email': 'x@example.com'})
rec('API-103', 'sign-in: client-supplied email field', '400 UNKNOWN_FIELD', r)
r = signin({**SI, 'idToken': none_jwt})
rec('API-104', 'sign-in with an alg=none token', '400/401', r, ok=r.status_code in (400, 401))
r = requests.delete(B + '/v1/accounts/me', headers=auth(iid, tok))
rec('API-106', 'delete account without an account token', '401', r)
r = requests.get(B + '/v1/entitlement', headers=auth(iid, tok, {'Zaghlol-Account': none_jwt}))
rec('API-107', 'forged account token (alg=none) on entitlement', '401', r)

# ---- store notifications
PUSH = {'message': {'data': 'e30=', 'messageId': '1'}, 'subscription': 'x'}
r = requests.post(B + '/v1/notifications/google', json=PUSH)
rec('API-110', 'Google RTDN push without a Pub/Sub OIDC token', '401/403', r, ok=r.status_code in (401, 403))
r = requests.post(B + '/v1/notifications/google', json=PUSH, headers={'Authorization': 'Bearer ' + none_jwt})
rec('API-111', 'Google RTDN push with an alg=none bearer', '401/403', r, ok=r.status_code in (401, 403))
r = requests.post(B + '/v1/notifications/apple', json={'signedPayload': 'a.b.c'})
rec('API-112', 'Apple notification with a forged signedPayload', '400/401/403', r, ok=r.status_code in (400, 401, 403))

# ---- admin API
ADMIN = [('get', '/admin/v1/flags/zakah'), ('put', '/admin/v1/flags/zakah'), ('get', '/admin/v1/contributions'),
         ('post', '/admin/v1/catalog/publish'), ('post', '/admin/v1/support/entitlement:lookup'),
         ('post', '/admin/v1/support/seat:move'), ('post', '/admin/v1/support/purchase:detach'),
         ('get', '/admin/v1/bank-requests'), ('get', '/admin/v1/metrics/daily-active'),
         ('put', '/admin/v1/prices/override'), ('get', '/admin/v1/catalog/draft/merchant')]
for n, (m, p) in enumerate(ADMIN):
    r = requests.request(m, B + p, json={} if m != 'get' else None)
    rec(f'API-{120 + n}', f'admin {m.upper()} {p} with no token', '401', r)
r = requests.put(B + '/admin/v1/flags/zakah', json={'enabled': True}, headers={'Authorization': 'Bearer ' + tok})
rec('API-135', 'admin flag change with an install token', '401', r)
r = requests.put(B + '/admin/v1/flags/zakah', json={'enabled': True}, headers={'Authorization': 'Bearer ' + none_jwt})
rec('API-136', 'admin flag change with an alg=none JWT', '401', r)

# ---- generic behaviour
rec('API-140', 'unknown route', '404 NOT_FOUND', requests.get(B + '/v1/nope'))
rec('API-141', 'wrong method', '405 METHOD_NOT_ALLOWED', requests.put(B + '/v1/health'))
r = requests.get(B + '/v1/catalog/0/full')
rec('API-142', 'catalog version 0 (minimum is 1)', '400/404', r, ok=r.status_code in (400, 404))
rec('API-143', 'unknown catalog version', '404 CATALOG_VERSION_UNKNOWN', requests.get(B + '/v1/catalog/999999/full'))
r = requests.get(B + '/v1/catalog/abc/full')
rec('API-144', 'non-numeric catalog version', '400/404', r, ok=r.status_code in (400, 404))
r = requests.get(B + "/v1/catalog/1%27%20OR%201=1--/full")
rec('API-145', 'SQL-injection-shaped catalog version', '400/404', r, ok=r.status_code in (400, 404))
rec('API-146', 'no Swagger UI exposed', '404', requests.get(B + '/swagger/index.html'))
rec('API-147', 'no /metrics on the public port', '404', requests.get(B + '/metrics'))
r = requests.get(B + '/v1/health')
hs = {k2.lower(): v for k2, v in r.headers.items()}
rec('API-148', 'no Server / X-Powered-By banner', 'absent', r, ok='x-powered-by' not in hs and 'server' not in hs,
    extra=str({k2: hs[k2] for k2 in hs if k2 in ('server', 'x-powered-by')}))
_, r = reg(body=NEW(secretField='SENSITIVE-VALUE-XYZ'))
rec('API-150', 'error body does not echo request data', 'no echo', r,
    ok='SENSITIVE-VALUE-XYZ' not in r.text and 'secretField' not in r.text, extra=r.text[:150])

# ---- delete install
rec('API-160', 'delete install', 202, requests.delete(B + '/v1/installs/me', headers=auth(i3, t3)))
r = requests.post(B + '/v1/sync', json=SYNC0, headers=auth(i3, t3))
rec('API-161', 'token is dead after delete', '401 INSTALL_TOKEN_INVALID', r)
_, r = reg(iid=i3)
rec('API-162', 're-register a deleted install ID', '409 INSTALL_EXISTS', r)
rec('API-163', 'delete install without credentials', '401', requests.delete(B + '/v1/installs/me', headers=dict(APP)))

json.dump({'results': R, 'artifacts': ART, 'context': {'installId': iid, 'deletedInstallId': i3}}, open(OUT, 'w'), indent=1)
p = sum(1 for x in R if x[4] == 'PASS')
print(f'{p}/{len(R)} pass')
for x in R:
    if x[4] != 'PASS' or x[0] in ('API-065', 'API-066', 'API-070', 'API-080', 'API-080b', 'API-090'):
        print(x)
