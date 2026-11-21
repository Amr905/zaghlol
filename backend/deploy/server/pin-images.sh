#!/bin/sh
# Prints the image variables for production.env with digests resolved from the registries (needs docker with buildx and
# network access; run it on any machine, then paste the lines into /etc/zaghlol/production.env). Re-run to bump images,
# review the diff, deploy. BACKEND_IMAGE is not resolved here: the deploy workflow supplies it (GHCR digest).
set -eu

resolve() {
  # $1 variable name, $2 repository:tag
  digest=$(docker buildx imagetools inspect "$2" --format '{{.Manifest.Digest}}')
  case "$digest" in
    sha256:[0-9a-f]*) printf '%s=%s@%s\n' "$1" "$2" "$digest" ;;
    *) echo "could not resolve $2" >&2; return 1 ;;
  esac
}

resolve POSTGRES_IMAGE postgres:17
resolve CADDY_IMAGE caddy:2.10
resolve OTEL_COLLECTOR_IMAGE otel/opentelemetry-collector-contrib:0.116.1
resolve PROMETHEUS_IMAGE prom/prometheus:v3.5.0
resolve ALERTMANAGER_IMAGE prom/alertmanager:v0.28.1
resolve GRAFANA_IMAGE grafana/grafana:12.2.0
