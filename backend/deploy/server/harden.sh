#!/bin/bash
# Server hardening for the single-host deployment (ADR-025, deployment.md "Self-hosted server"). Ubuntu 24.04, run as root.
# Idempotent: safe to run again after every change of this file.
#
#   sudo ./harden.sh              everything below
#   sudo ./harden.sh --dirs-only  only the folders and modes (used on a spare host for the restore drill)
#
# What it does: firewall (ufw: 22, 80, 443 only), SSH keys only, unattended security upgrades, swap off, no core dumps, Docker
# log rotation, the folders under /etc/zaghlol and /var/lib/zaghlol with the owners and modes deployment.md requires, and the
# backup timer. It refuses to turn password logins off when no authorized SSH key exists, so you can't lock yourself out.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }
DIRS_ONLY=0
[ "${1:-}" = "--dirs-only" ] && DIRS_ONLY=1

HERE=$(cd "$(dirname "$0")" && pwd)

# owner:group mode path
mkdir_mode() {
  install -d -m "$1" -o "${2%%:*}" -g "${2##*:}" "$3"
  # install -d doesn't change an existing folder's owner or mode on every version: make it so.
  chown "$2" "$3"
  chmod "$1" "$3"
}

make_dirs() {
  # Settings and secrets (root controls /etc/zaghlol; the key and credential folders are owned as deployment.md says).
  mkdir_mode 0755 0:0 /etc/zaghlol
  mkdir_mode 0700 1654:1654 /etc/zaghlol/kms-production            # File KMS (T-200); the key tool writes keys/ inside
  mkdir_mode 0700 0:0 /etc/zaghlol/backup                          # off-server ssh key and pinned host key
  # OpenBao (T-201), created now so the move needs no new folders. uid 1655 = OpenBao, 1654 = api/worker.
  mkdir_mode 0755 0:0 /etc/zaghlol/openbao
  mkdir_mode 0755 0:0 /etc/zaghlol/openbao/config
  mkdir_mode 0500 1655:1655 /etc/zaghlol/openbao/tls
  mkdir_mode 0500 1655:1655 /etc/zaghlol/openbao/unseal
  mkdir_mode 0700 1655:1655 /etc/zaghlol/openbao-setup-out
  mkdir_mode 0500 1654:1654 /etc/zaghlol/openbao-api
  mkdir_mode 0500 1654:1654 /etc/zaghlol/openbao-worker
  mkdir_mode 0500 1654:1654 /etc/zaghlol/openbao-keytool

  # Data.
  mkdir_mode 0755 0:0 /var/lib/zaghlol
  mkdir_mode 0700 999:999 /var/lib/zaghlol/postgres                # postgres image user
  mkdir_mode 0755 0:0 /var/lib/zaghlol/backup
  mkdir_mode 0700 999:999 /var/lib/zaghlol/backup/wal              # postgres writes archived WAL here
  mkdir_mode 0700 0:0 /var/lib/zaghlol/backup/dumps
  mkdir_mode 0700 0:0 /var/lib/zaghlol/backup/base
  mkdir_mode 0755 1654:1654 /var/lib/zaghlol/catalog               # api writes, caddy reads (public, signed data)
  mkdir_mode 0755 1654:1654 /var/lib/zaghlol/catalog/catalog
  mkdir_mode 0755 0:0 /var/lib/zaghlol/caddy
  mkdir_mode 0700 65532:65532 /var/lib/zaghlol/caddy/data
  mkdir_mode 0700 65532:65532 /var/lib/zaghlol/caddy/config
  mkdir_mode 0755 0:0 /var/lib/zaghlol/openbao
  mkdir_mode 0700 1655:1655 /var/lib/zaghlol/openbao/data
  mkdir_mode 0700 1655:1655 /var/lib/zaghlol/openbao/audit
  mkdir_mode 0755 0:0 /var/lib/zaghlol/observability
  mkdir_mode 0755 65534:65534 /var/lib/zaghlol/observability/prometheus
  mkdir_mode 0755 472:472 /var/lib/zaghlol/observability/grafana
  echo "folders: ok"
}

make_dirs
if [ "$DIRS_ONLY" -eq 1 ]; then exit 0; fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ufw unattended-upgrades rsync jq ca-certificates curl

# Docker must already be installed (docs: runbook step 1). Not rootless, no userns remap (deployment.md: keys' owner check).
command -v docker >/dev/null || { echo "Docker Engine is not installed (see the runbook, step 1)" >&2; exit 1; }
docker compose version >/dev/null || { echo "Docker Compose v2 plugin is missing" >&2; exit 1; }

# --- Deploy user for the GitHub workflow (optional): put its PUBLIC key in /etc/zaghlol/deploy.pub first ---
# It may run exactly one command as root (deploy.sh). Note that it can also replace that script through /opt/zaghlol/deploy and
# is in the docker group, so this key is as sensitive as root access: keep it only in the protected GitHub environment.
install -d -m 0755 -o 0 -g 0 /opt/zaghlol
if [ -s /etc/zaghlol/deploy.pub ]; then
  id zaghlol-deploy >/dev/null 2>&1 || useradd --create-home --shell /bin/bash zaghlol-deploy
  usermod -aG docker zaghlol-deploy
  install -d -m 0700 -o zaghlol-deploy -g zaghlol-deploy /home/zaghlol-deploy/.ssh
  install -m 0600 -o zaghlol-deploy -g zaghlol-deploy /etc/zaghlol/deploy.pub /home/zaghlol-deploy/.ssh/authorized_keys
  install -d -m 0755 -o zaghlol-deploy -g zaghlol-deploy /opt/zaghlol/deploy
  echo 'zaghlol-deploy ALL=(root) NOPASSWD: /opt/zaghlol/deploy/server/deploy.sh' > /etc/sudoers.d/zaghlol-deploy
  chmod 0440 /etc/sudoers.d/zaghlol-deploy
  visudo -cf /etc/sudoers.d/zaghlol-deploy >/dev/null
  echo "deploy user: ok"
else
  echo "deploy user: skipped (no /etc/zaghlol/deploy.pub)"
fi

# --- SSH: keys only ---
have_key=0
for f in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys; do
  if [ -s "$f" ]; then have_key=1; fi
done
if [ "$have_key" -eq 1 ]; then
  cat > /etc/ssh/sshd_config.d/10-zaghlol.conf <<'CONF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
PermitRootLogin prohibit-password
PubkeyAuthentication yes
X11Forwarding no
MaxAuthTries 3
CONF
  sshd -t
  systemctl reload ssh
  echo "ssh: keys only"
else
  echo "ssh: NOT changed, no authorized_keys file found; add your key, then run again" >&2
fi

# --- Firewall: only 22, 80, 443 reach the host. Docker publishes only caddy's 80/443 (and 443/udp) anyway. ---
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 443/udp
ufw --force enable
echo "firewall: ok"

# --- Unattended security upgrades (no automatic reboot: schedule it; containers restart on their own) ---
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'CONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
CONF
cat > /etc/apt/apt.conf.d/52zaghlol-unattended <<'CONF'
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
CONF
echo "upgrades: ok"

# --- Swap off: key pages must never reach a disk in clear (deployment.md). For encrypted swap instead, see the runbook. ---
swapoff -a
sed -i -E 's/^([^#].*[[:space:]]swap[[:space:]].*)$/# disabled by zaghlol harden.sh: \1/' /etc/fstab
echo "swap: off"

# --- No core dumps anywhere (the processes hold keys in memory) ---
cat > /etc/sysctl.d/60-zaghlol-nocore.conf <<'CONF'
fs.suid_dumpable = 0
kernel.core_pattern = |/bin/false
CONF
sysctl --system >/dev/null
install -d /etc/systemd/coredump.conf.d
cat > /etc/systemd/coredump.conf.d/zaghlol.conf <<'CONF'
[Coredump]
Storage=none
ProcessSizeMax=0
CONF
cat > /etc/security/limits.d/60-zaghlol-nocore.conf <<'CONF'
* hard core 0
CONF
echo "core dumps: off"

# --- Docker log rotation (restarts Docker only when the file changes) ---
want='{"log-driver":"json-file","log-opts":{"max-size":"10m","max-file":"5"}}'
if [ -f /etc/docker/daemon.json ]; then
  merged=$(jq -S --argjson w "$want" '. * $w' /etc/docker/daemon.json)
else
  merged=$(printf '%s' "$want" | jq -S .)
fi
if [ ! -f /etc/docker/daemon.json ] || [ "$merged" != "$(jq -S . /etc/docker/daemon.json)" ]; then
  install -d /etc/docker
  printf '%s\n' "$merged" > /etc/docker/daemon.json
  systemctl restart docker
fi
echo "docker logs: rotated"

# --- Backup timer ---
if [ -d "$HERE/backup" ]; then
  install -m 0644 "$HERE"/backup/zaghlol-backup.service "$HERE"/backup/zaghlol-backup-failed.service "$HERE"/backup/zaghlol-backup.timer /etc/systemd/system/
  systemctl daemon-reload
  if [ -f /etc/zaghlol/backup.env ]; then
    systemctl enable --now zaghlol-backup.timer
    echo "backup timer: enabled"
  else
    echo "backup timer: installed but not enabled (create /etc/zaghlol/backup.env from backup/backup.env.example, then run again)"
  fi
fi

echo "harden: done"
