#!/bin/bash
# Runs ON the server (shipped by the deploy workflow, or by hand): deploy one backend image by digest.
#   ./deploy.sh ghcr.io/amr905/zaghlol-backend@sha256:<digest>      (GHCR read token on stdin if the package is private)
# Steps: pull -> record previous image -> migrate -> recreate api/worker/caddy -> smoke -> on failure put the previous image
# back. Database migrations are expand/contract and N-1 compatible (deployment.md section 3), so the previous image keeps
# working against a migrated schema; a rollback never reverses a migration.
set -euo pipefail

IMAGE=${1:?image reference with digest}
case "$IMAGE" in
  *@sha256:????????????????????????????????????????????????????????????????) ;;
  *) echo "image must be pinned by digest (name@sha256:<64 hex>)" >&2; exit 2 ;;
esac

HERE=$(cd "$(dirname "$0")" && pwd)
ENV_FILE=${PRODUCTION_ENV:-/etc/zaghlol/production.env}
export PRODUCTION_ENV=$ENV_FILE
ZERO=0000000000000000000000000000000000000000000000000000000000000000

compose() { "$HERE/compose.sh" "$@"; }
get_var() { sed -n "s/^$1=//p" "$ENV_FILE" | tail -n 1; }
set_var() {
  # $1 name, $2 value; rewrites the file atomically with the same mode and owner
  tmp=$(mktemp "$ENV_FILE.XXXXXX")
  grep -v "^$1=" "$ENV_FILE" > "$tmp" || true
  printf '%s=%s\n' "$1" "$2" >> "$tmp"
  chmod --reference="$ENV_FILE" "$tmp"
  chown --reference="$ENV_FILE" "$tmp"
  mv "$tmp" "$ENV_FILE"
}

previous=$(get_var BACKEND_IMAGE)
case "$previous" in *"$ZERO"*) previous="" ;; esac
# Redeploying the running image must not make "previous" equal "current": keep the last different digest for rollback.
if [ "$previous" = "$IMAGE" ]; then
  previous=$(get_var BACKEND_IMAGE_PREVIOUS)
  case "$previous" in *"$ZERO"*) previous="" ;; esac
  [ "$previous" != "$IMAGE" ] || previous=""
fi

# Pull with a throwaway docker config so a token on stdin never stays on the server.
if [ ! -t 0 ]; then
  cfg=$(mktemp -d)
  trap 'rm -rf "$cfg"' EXIT
  token=$(cat)
  if [ -n "$token" ]; then
    printf '%s' "$token" | DOCKER_CONFIG=$cfg docker login ghcr.io -u "${GHCR_USER:-token}" --password-stdin >/dev/null
  fi
  DOCKER_CONFIG=$cfg docker pull "$IMAGE" >/dev/null
else
  docker pull "$IMAGE" >/dev/null
fi

smoke() {
  domain=$(get_var API_DOMAIN)
  [ -n "$domain" ] || { echo "API_DOMAIN missing in $ENV_FILE" >&2; return 1; }
  # 1. every api replica and the worker report Docker-healthy and caddy is running (caddy has no healthcheck); a timeout
  #    fails the smoke test so the deploy rolls back. 2. the public path (Caddy, TLS) answers /v1/health.
  ok=0
  for _ in $(seq 1 36); do
    states=$(compose ps --format '{{.Service}} {{.State}} {{.Health}}' api worker caddy)
    bad=$(printf '%s\n' "$states" | grep -E '^(api|worker) ' | grep -vc ' running healthy$' || true)
    api_n=$(printf '%s\n' "$states" | grep -c '^api running healthy$' || true)
    worker_n=$(printf '%s\n' "$states" | grep -c '^worker running healthy$' || true)
    caddy_n=$(printf '%s\n' "$states" | grep -c '^caddy running' || true)
    if [ "$bad" -eq 0 ] && [ "$api_n" -ge 1 ] && [ "$worker_n" -ge 1 ] && [ "$caddy_n" -ge 1 ]; then ok=1; break; fi
    sleep 5
  done
  if [ "$ok" -ne 1 ]; then
    echo "services not healthy after 180 s:" >&2
    printf '%s\n' "$states" >&2
    return 1
  fi
  curl -fsS --max-time 10 --retry 5 --retry-delay 3 --retry-connrefused "https://$domain/v1/health" | grep -q '"status":"ok"'
  # Optional readiness path (empty: the /v1/health body already reports database readiness).
  if [ -n "${SMOKE_READY_PATH:-}" ]; then
    curl -fsS --max-time 10 "https://$domain$SMOKE_READY_PATH" >/dev/null
  fi
}

rollback() {
  if [ -z "$previous" ]; then
    echo "no previous image to roll back to (first deploy); leaving the failed image in place" >&2
    return 1
  fi
  echo "rolling back to the previous image" >&2
  docker pull "$previous" >/dev/null 2>&1 || true
  set_var BACKEND_IMAGE "$previous"
  compose up -d --force-recreate api worker caddy
  smoke && echo "rollback ok: running $previous" >&2
}

set_var BACKEND_IMAGE "$IMAGE"
set_var BACKEND_IMAGE_PREVIOUS "$previous"

compose up -d postgres
compose run --rm migrate || { echo "migration failed; nothing was restarted" >&2; set_var BACKEND_IMAGE "${previous:-$IMAGE}"; exit 1; }

if compose up -d --remove-orphans && smoke; then
  echo "deploy ok: running $IMAGE"
else
  echo "deploy FAILED its smoke test" >&2
  rollback || true
  exit 1
fi
