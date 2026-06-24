#!/usr/bin/env bash
# Install kubeadm/kubelet/kubectl from pkgs.k8s.io. Run on every node.
# Override the version with K8S_MINOR=v1.35.
set -euo pipefail

K8S_MINOR="${K8S_MINOR:-v1.36}"

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo $0)"; exit 1
fi

echo "==> Installing Kubernetes ${K8S_MINOR} components"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl gnupg

echo "==> Adding the pkgs.k8s.io apt repository"
mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" \
  >/etc/apt/sources.list.d/kubernetes.list

apt-get update -y
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl   # pin versions
systemctl enable --now kubelet

echo "==> Installed:"
kubeadm version -o short
kubectl version --client -o yaml | grep -m1 gitVersion || true
echo "==> Done. Control plane: 20-init-control-plane.sh; workers: 30-join-worker.sh."
