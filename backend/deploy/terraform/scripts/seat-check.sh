#!/usr/bin/env bash
# Prints Kms:HmacKeys:SeatCheck = hex(HMAC-SHA256(K_seat, "zaghlol-kseat-check-v1")) for the pinned K_seat version.
# Run ONCE per environment, after the first `tofu apply` created the key, by an operator who is allowed to MAC with it
# (roles/cloudkms.signerVerifier on hmac-kseat). The result is not a secret (a MAC of a public string): store it in
# settings.auto.tfvars as kseat_check_hex, or in the repository variable KSEAT_CHECK_HEX used by backend-deploy.
#
# usage: seat-check.sh <project-id> <location> <environment>      e.g. seat-check.sh zaghlol-prod-123 europe-west3 prod
set -euo pipefail

project="${1:?project id}"
location="${2:?location}"
environment="${3:?environment (staging|prod)}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
printf '%s' 'zaghlol-kseat-check-v1' >"$work/input"

gcloud kms mac-sign \
  --project="$project" --location="$location" \
  --keyring="zaghlol-${environment}" --key="hmac-kseat" --version=1 \
  --input-file="$work/input" --signature-file="$work/mac" >/dev/null

# 32 bytes -> 64 lower-case hex characters.
xxd -p -c 64 "$work/mac" | tr -d '\n' | tr 'A-F' 'a-f'
echo
