#!/bin/bash
# deploy.sh keeps the last *different* digest as the rollback target when the running image is redeployed.
set -euo pipefail
SRC=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/srv"
cp "$SRC/deploy.sh" "$T/srv/deploy.sh"
printf '#!/bin/bash\nexit 0\n' > "$T/srv/compose.sh"
printf '#!/bin/bash\nexit 0\n' > "$T/bin/docker"
printf '#!/bin/bash\ncat >/dev/null 2>&1 || true\necho "{\\"status\\":\\"ok\\"}"\n' > "$T/bin/curl"
printf '#!/bin/bash\nexit 0\n' > "$T/bin/chown"
# compose ps must report healthy services for the smoke test
cat > "$T/srv/compose.sh" <<'S'
#!/bin/bash
if [ "$1" = ps ]; then printf 'api running healthy\nworker running healthy\ncaddy running \n'; fi
exit 0
S
chmod +x "$T"/srv/*.sh "$T"/bin/*
A=ghcr.io/o/zaghlol-backend@sha256:$(printf 'a%.0s' $(seq 64))
B=ghcr.io/o/zaghlol-backend@sha256:$(printf 'b%.0s' $(seq 64))
export PRODUCTION_ENV="$T/production.env" PATH="$T/bin:$PATH"
printf 'API_DOMAIN=x.test\nBACKEND_IMAGE=%s\nBACKEND_IMAGE_PREVIOUS=%s\n' "$B" "$A" > "$PRODUCTION_ENV"
run() { "$T/srv/deploy.sh" "$1" < /dev/null >/dev/null 2>&1; }
val() { sed -n "s/^$1=//p" "$PRODUCTION_ENV" | tail -n 1; }
run "$B"
[ "$(val BACKEND_IMAGE)" = "$B" ] && [ "$(val BACKEND_IMAGE_PREVIOUS)" = "$A" ] || { echo "FAIL: redeploy lost the previous digest"; exit 1; }
run "$A"
[ "$(val BACKEND_IMAGE)" = "$A" ] && [ "$(val BACKEND_IMAGE_PREVIOUS)" = "$B" ] || { echo "FAIL: normal deploy"; exit 1; }
echo "ok"
