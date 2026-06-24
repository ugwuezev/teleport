#!/usr/bin/env bash
# Prepare an Ubuntu 22.04 host for kubeadm: containerd + kernel settings. Run on every node.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo $0)"; exit 1
fi

echo "==> [1/5] Disabling swap"
swapoff -a
sed -i.bak '/\sswap\s/s/^/#/' /etc/fstab || true

echo "==> [2/5] Loading kernel modules"
cat <<'EOF' >/etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

echo "==> [3/5] Setting sysctl params"
cat <<'EOF' >/etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system >/dev/null

echo "==> [4/5] Installing containerd"
export DEBIAN_FRONTEND=noninteractive
# Wait for the boot-time apt lock and retry transient failures.
apt_retry() {
  for attempt in 1 2 3; do
    if apt-get -o DPkg::Lock::Timeout=300 "$@"; then return 0; fi
    echo "    apt-get $1 failed (attempt ${attempt}/3) - retrying in 10s..."; sleep 10
  done
  echo "ERROR: apt-get $* failed after 3 attempts." >&2; return 1
}
apt_retry update -y
apt_retry install -y ca-certificates curl gnupg apt-transport-https containerd

echo "==> [5/5] Configuring containerd (systemd cgroup driver)"
mkdir -p /etc/containerd
containerd config default >/etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

if ! systemctl is-active --quiet containerd || [[ ! -S /run/containerd/containerd.sock ]]; then
  echo "ERROR: containerd is not running after install - check 'systemctl status containerd'." >&2
  exit 1
fi

echo "==> Prerequisites complete. Run 10-install-kube.sh next."
