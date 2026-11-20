#!/usr/bin/env bash
# T-201: runs the OpenBao live tests against a real OpenBao container with the production configuration
# (backend/deploy/openbao/openbao.hcl: raft storage, static-key auto-unseal, TLS, file audit device), set up by setup.sh,
# migrated with the T-200 key tool and the OpenBao key tool. Used by the openbao-live job in .github/workflows/backend-ci.yml;
# runs locally too (needs docker, openssl, jq and a Release build): sh backend/tools/openbao-live.sh
#
# Phases: start + init + setup + import, tests phase 1; docker restart (auto-unseal), phase 2; bao operator seal, phase
# "sealed"; docker stop, phase "stopped". Everything lives in a fresh /tmp folder (the File KMS checks need safe parents,
# and /tmp is root-owned and sticky). The root token never leaves that folder; it is a throwaway CI instance.
set -euo pipefail

IMAGE="${OPENBAO_IMAGE:?set OPENBAO_IMAGE (pinned in the workflow)}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BACKEND="$REPO/backend"
WORKER="$BACKEND/src/Zaghlol.Workers/bin/Release/net10.0/Zaghlol.Workers.dll"
TESTS="$BACKEND/tests/Zaghlol.Infrastructure.Tests/Zaghlol.Infrastructure.Tests.csproj"
NAME="zaghlol-openbao-live"
ADDR="https://127.0.0.1:8200"
W="$(mktemp -d /tmp/zaghlol-openbao.XXXXXX)"
chmod 0700 "$W"
umask 077

[ -f "$WORKER" ] || { echo "build first: dotnet build backend/Zaghlol.sln -c Release" >&2; exit 1; }

cleanup() {
  docker logs "$NAME" >"$W/openbao.log" 2>&1 || true
  docker rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

bao() {
  docker exec -e BAO_ADDR="$ADDR" -e BAO_CACERT=/openbao/tls/ca.pem -e HOME=/tmp ${BAO_TOKEN:+-e BAO_TOKEN="$BAO_TOKEN"} "$NAME" bao "$@"
}

# Waits until /v1/sys/health answers 200 (initialised, unsealed, active).
wait_active() {
  for _ in $(seq 1 60); do
    code=$(curl -s -o /dev/null -w '%{http_code}' --cacert "$W/tls/ca.pem" "$ADDR/v1/sys/health" || true)
    [ "$code" = "200" ] && return 0
    sleep 1
  done
  echo "OpenBao did not become active (last status $code)" >&2
  docker logs "$NAME" | tail -n 40 >&2
  return 1
}

run_phase() {
  echo "::group::live tests, phase $1"
  ZAGHLOL_OPENBAO_ADDR="$ADDR" ZAGHLOL_OPENBAO_DIR="$W" ZAGHLOL_OPENBAO_PHASE="$1" \
    dotnet test "$TESTS" -c Release --no-build --filter "Category=OpenBaoLive" --logger "console;verbosity=normal" \
    | tee "$W/phase-$1.log"
  grep -Eq "Passed:[[:space:]]+[1-9]" "$W/phase-$1.log" || { echo "phase $1 ran no test" >&2; exit 1; }
  echo "::endgroup::"
}

echo "::group::TLS (CA + server certificate), unseal key, config"
mkdir -p "$W"/{config,tls,unseal,data,audit,out,creds,filekeys}
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 2 -subj "/CN=zaghlol-ci-openbao-ca" \
  -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -keyout "$W/ca-key.pem" -out "$W/tls/ca.pem" 2>/dev/null
openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -subj "/CN=openbao" \
  -keyout "$W/tls/server-key.pem" -out "$W/server.csr" 2>/dev/null
printf 'subjectAltName=DNS:openbao,DNS:localhost,IP:127.0.0.1\nextendedKeyUsage=serverAuth\nbasicConstraints=critical,CA:FALSE\n' >"$W/ext.cnf"
openssl x509 -req -in "$W/server.csr" -CA "$W/tls/ca.pem" -CAkey "$W/ca-key.pem" -CAcreateserial -days 2 \
  -extfile "$W/ext.cnf" -out "$W/tls/server.pem" 2>/dev/null
# Hex, no newline: a raw 32-byte key could start or end with a white-space byte that the file:// reader may trim.
openssl rand -hex 32 | tr -d '\n' >"$W/unseal/unseal.key"
cp "$BACKEND/deploy/openbao/openbao.hcl" "$W/config/openbao.hcl"
# The CI container is reached on 127.0.0.1 (published port), not the "openbao" network name.
sed -i 's#^api_addr .*#api_addr     = "https://127.0.0.1:8200"#; s#^cluster_addr .*#cluster_addr = "https://127.0.0.1:8201"#' "$W/config/openbao.hcl"
chmod 0400 "$W"/tls/* "$W/unseal/unseal.key"
chmod 0755 "$W/config"
chmod 0644 "$W/config/openbao.hcl"
echo "::endgroup::"

echo "::group::start OpenBao ($IMAGE) with the production configuration"
docker run -d --name "$NAME" --user "$(id -u):$(id -g)" --cap-drop ALL --security-opt no-new-privileges:true \
  -p 127.0.0.1:8200:8200 -e HOME=/tmp \
  -v "$W/config:/openbao/config:ro" -v "$W/tls:/openbao/tls:ro" -v "$W/unseal:/openbao/unseal:ro" \
  -v "$W/data:/openbao/data" -v "$W/audit:/openbao/audit" -v "$W/out:/out" \
  -v "$BACKEND/deploy/openbao:/setup:ro" \
  --entrypoint bao "$IMAGE" server -config=/openbao/config/openbao.hcl >/dev/null
for _ in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --cacert "$W/tls/ca.pem" "$ADDR/v1/sys/health" || true)
  [ "$code" = "501" ] && break # listening, not initialised
  sleep 1
done
[ "$code" = "501" ] || { docker logs "$NAME" >&2; echo "OpenBao did not start (status $code)" >&2; exit 1; }
echo "::endgroup::"

echo "::group::init (static seal: recovery shares 1/1, CI only) and setup.sh"
bao operator init -recovery-shares=1 -recovery-threshold=1 -format=json >"$W/init.json"
BAO_TOKEN="$(jq -r .root_token "$W/init.json")"
export BAO_TOKEN
wait_active
docker exec -e BAO_ADDR="$ADDR" -e BAO_CACERT=/openbao/tls/ca.pem -e HOME=/tmp -e BAO_TOKEN="$BAO_TOKEN" \
  -e ZAGHLOL_KIDS="s2027a e2027a" -e ZAGHLOL_ENVELOPE_KEYS="envelope-2027" -e ZAGHLOL_LEGACY_ENVELOPE_KEYS="envelope" \
  -e ZAGHLOL_BOUND_CIDRS="10.0.0.0/8,172.16.0.0/12,192.168.0.0/16" \
  "$NAME" sh /setup/setup.sh apply /out
# setup.sh is re-runnable: a second run changes nothing and keeps the secret-ids.
docker exec -e BAO_ADDR="$ADDR" -e BAO_CACERT=/openbao/tls/ca.pem -e HOME=/tmp -e BAO_TOKEN="$BAO_TOKEN" \
  -e ZAGHLOL_KIDS="s2027a e2027a" -e ZAGHLOL_ENVELOPE_KEYS="envelope-2027" -e ZAGHLOL_LEGACY_ENVELOPE_KEYS="envelope" \
  -e ZAGHLOL_BOUND_CIDRS="10.0.0.0/8,172.16.0.0/12,192.168.0.0/16" \
  "$NAME" sh /setup/setup.sh apply /out | grep "secret-id kept" >/dev/null
for role in api worker; do
  mkdir -p "$W/creds/$role"
  cp "$W/out/$role/role-id" "$W/out/$role/secret-id" "$W/creds/$role/"
  cp "$W/tls/ca.pem" "$W/creds/$role/ca.pem"
  chmod 0400 "$W/creds/$role"/*
  chmod 0500 "$W/creds/$role"
done
# Keys are not exportable and allow no plaintext backup; the API policy can't export.
[ "$(bao read -field=exportable transit/keys/s2027a)" = "false" ]
[ "$(bao read -field=allow_plaintext_backup transit/keys/envelope-2027)" = "false" ]
echo "::endgroup::"

echo "::group::T-200 File keys (production key tool), then the OpenBao import (BYOK)"
(cd "$W" && dotnet "$WORKER" --generate-keys --environment Staging --out "$W/filekeys/keys" \
  --kid s2026a --kid e2026a --secret seat --secret audit --secret install-pepper --secret envelope >"$W/file-kms.env")
(cd "$W" && dotnet "$WORKER" --openbao-keys --environment Production --address "$ADDR" --ca-file "$W/tls/ca.pem" \
  --token-file "$W/out/keytool-token" --file-keys "$W/filekeys/keys" \
  --import-hmac seat --import-hmac audit --import-hmac install-pepper --import-envelope envelope \
  --kid s2027a --kid e2027a --envelope envelope-2027 >"$W/openbao-kms.env")
cat "$W/openbao-kms.env"
# The imported HMAC keys pin the same fingerprints as T-200 (same key).
for n in seat audit install_pepper; do
  a=$(grep "^Kms__File__Fingerprints__$n=" "$W/file-kms.env" | cut -d= -f2)
  b=$(grep "^Kms__OpenBao__Fingerprints__$n=" "$W/openbao-kms.env" | cut -d= -f2)
  [ -n "$a" ] && [ "$a" = "$b" ] || { echo "pin of $n differs after import" >&2; exit 1; }
done
# Imported keys are not exportable either.
[ "$(bao read -field=exportable transit/keys/seat)" = "false" ]
[ "$(bao read -field=type transit/keys/seat)" = "hmac" ]
# The key-tool token is revoked right after the import, as in the runbook.
bao token revoke "$(cat "$W/out/keytool-token")" >/dev/null
echo "::endgroup::"

run_phase 1

echo "::group::restart (static seal unseals on its own)"
docker restart "$NAME" >/dev/null
wait_active
echo "::endgroup::"
run_phase 2

echo "::group::seal"
bao operator seal
echo "::endgroup::"
run_phase sealed

docker stop "$NAME" >/dev/null
run_phase stopped

# The audit device wrote entries (fields HMAC'd; no secret_id or token in clear).
test -s "$W/audit/audit.log"
secret=$(cat "$W/creds/api/secret-id")
if grep -qF "$secret" "$W/audit/audit.log"; then
  echo "a secret_id appears in clear in the audit log" >&2
  exit 1
fi
echo "OpenBao live tests: all phases passed"
