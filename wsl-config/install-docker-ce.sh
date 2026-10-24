#!/usr/bin/env bash
# ==============================================================================
#  Install native docker-ce inside Ubuntu-24.04 (WSL)
#
#  Why: Docker Desktop registers a fifth WSL distro, keeps its disk image on C:,
#  auto-starts the WSL VM, and conflicts with mirrored networking mode.
#
#  Usage (from Windows):
#    wsl.exe -d Ubuntu-24.04 -u root -- bash /mnt/e/Git/wsl-config/install-docker-ce.sh
#
#  NOTE: ASCII-only output on purpose. Non-ASCII console output is decoded as
#        GBK by the caller and gets mangled.
# ==============================================================================
set -euo pipefail

PROXY="http://127.0.0.1:7897"

echo "===== 0. preflight ====="
. /etc/os-release
echo "  distro      : $ID $VERSION_ID ($VERSION_CODENAME)"
echo "  arch        : $(dpkg --print-architecture)"
echo "  http_proxy  : ${http_proxy:-<unset>}"
echo "  docker.sock : $(ls -la /var/run/docker.sock 2>/dev/null || echo '<none>')"
echo "  dockerd     : $(command -v dockerd || echo '<not installed>')"

echo
echo "===== 1. remove Docker Desktop CLI symlinks ====="
for f in /usr/bin/docker /usr/bin/docker-compose /usr/bin/docker-buildx \
         /usr/local/bin/docker /usr/bin/docker-credential-desktop \
         /usr/bin/docker-credential-wincred /usr/bin/hub-tool; do
    if [ -L "$f" ]; then
        tgt="$(readlink "$f")"
        case "$tgt" in
            *docker-desktop*)
                echo "  removing symlink: $f -> $tgt"
                rm -f "$f"
                ;;
            *)
                echo "  keeping symlink (not docker-desktop): $f -> $tgt"
                ;;
        esac
    fi
done
echo "  /usr/bin/docker now: $(ls -la /usr/bin/docker 2>/dev/null || echo '<absent>')"

echo
echo "===== 2. prerequisites ====="
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg

echo
echo "===== 3. add Docker apt repository ====="
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
cat /etc/apt/sources.list.d/docker.list
apt-get update -qq

echo
echo "===== 4. install docker-ce ====="
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo
echo "===== 5. daemon proxy (systemd drop-in) ====="
mkdir -p /etc/systemd/system/docker.service.d
cat > /etc/systemd/system/docker.service.d/proxy.conf <<EOF
[Service]
Environment="HTTP_PROXY=${PROXY}"
Environment="HTTPS_PROXY=${PROXY}"
Environment="NO_PROXY=localhost,127.0.0.1,::1,*.local"
EOF
cat /etc/systemd/system/docker.service.d/proxy.conf

echo
echo "===== 6. add user to docker group ====="
usermod -aG docker linminkunwu && echo "  linminkunwu added to docker group"

echo
echo "===== 7. enable and start ====="
systemctl daemon-reload
systemctl enable docker
systemctl restart docker
sleep 4
echo "  docker.service: $(systemctl is-active docker)"
echo "  containerd    : $(systemctl is-active containerd 2>/dev/null || echo 'n/a')"

echo
echo "===== 8. verify ====="
docker --version
docker compose version
echo "  --- daemon proxy in effect ---"
systemctl show docker --property=Environment

echo
echo "===== 9. pull test (goes through proxy) ====="
docker run --rm hello-world

echo
echo "DONE."
