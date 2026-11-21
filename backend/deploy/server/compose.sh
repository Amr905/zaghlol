#!/bin/sh
# docker compose for the production stack with the right files. Optional parts are switched on by marker files, so the
# deploy workflow, the backup scripts and a person all start the same stack:
#   touch /etc/zaghlol/use-openbao        add ../openbao/docker-compose.openbao.yml (after the OpenBao move, T-201)
#   touch /etc/zaghlol/use-observability  add observability/docker-compose.observability.yml and --profile otel
# Usage: ./compose.sh up -d | ps | logs api | run --rm migrate ...
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ENV_FILE=${PRODUCTION_ENV:-/etc/zaghlol/production.env}

files="-f $HERE/docker-compose.prod.yml"
profile=""
if [ -f /etc/zaghlol/use-openbao ]; then files="$files -f $HERE/../openbao/docker-compose.openbao.yml"; fi
if [ -f /etc/zaghlol/use-observability ]; then
  files="$files -f $HERE/observability/docker-compose.observability.yml"
  profile="--profile otel"
fi
# shellcheck disable=SC2086 # the file list is a fixed word list built above
exec docker compose --project-directory "$HERE" --env-file "$ENV_FILE" $profile $files "$@"
