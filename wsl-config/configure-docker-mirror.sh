#!/usr/bin/env bash
# ==============================================================================
#  Configure Docker registry mirrors for Ubuntu-24.04 (WSL)
#
#  Context: clash routes registry-1.docker.io / production.cloudflare.docker.com
#  DIRECT, and those are unreachable from this network. auth.docker.io works.
#  So the vanilla Docker Hub pull path cannot work; use a reachable mirror.
#
#  Verified reachable before writing:
#    https://docker.m.daocloud.io/v2/  -> 401 (working mirror)
#    https://docker.1ms.run/v2/        -> 401 (working mirror)
#
#  Usage: wsl.exe -d Ubuntu-24.04 -u root -- bash /mnt/e/Git/wsl-config/configure-docker-mirror.sh
#
#  NOTE: ASCII-only output on purpose.
# ==============================================================================
set -euo pipefail

echo "===== 1. write /etc/docker/daemon.json ====="
mkdir -p /etc/docker
if [ -f /etc/docker/daemon.json ]; then
    cp /etc/docker/daemon.json "/etc/docker/daemon.json.bak-$(date +%Y%m%d-%H%M%S)"
    echo "  existing daemon.json backed up"
fi
cat > /etc/docker/daemon.json <<'EOF'
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://docker.1ms.run"
  ]
}
EOF
cat /etc/docker/daemon.json

echo
echo "===== 2. restart docker ====="
systemctl restart docker
sleep 5
echo "  docker.service: $(systemctl is-active docker)"

echo
echo "===== 3. verify mirrors registered ====="
docker info 2>/dev/null | grep -A4 'Registry Mirrors' || echo "  (none reported)"

echo
echo "===== 4. pull test ====="
if docker run --rm hello-world; then
    echo
    echo "PULL OK"
else
    echo
    echo "PULL FAILED - trying explicit pull for more detail"
    docker pull hello-world || true
fi

echo
echo "===== 5. docker group membership ====="
id linminkunwu

echo
echo "DONE."
