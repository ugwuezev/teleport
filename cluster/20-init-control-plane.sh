#!/usr/bin/env bash
# Initialise the control plane with kubeadm and install the Calico CNI. Run once on the master.
# Env: POD_CIDR, APISERVER_ADDR (advertise IP), CALICO_VERSION, SINGLE_NODE=true to untaint.
set -euo pipefail

POD_CIDR="${POD_CIDR:-192.168.0.0/16}"
CALICO_VERSION="${CALICO_VERSION:-v3.28.2}"
SINGLE_NODE="${SINGLE_NODE:-false}"

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo -E $0)"; exit 1
fi

INIT_ARGS=(--pod-network-cidr="${POD_CIDR}")
if [[ -n "${APISERVER_ADDR:-}" ]]; then
  INIT_ARGS+=(--apiserver-advertise-address="${APISERVER_ADDR}")
fi

if [[ ! -S /run/containerd/containerd.sock ]]; then
  echo "ERROR: containerd is not running. Run cluster/00-prereqs.sh on this node first." >&2
  exit 1
fi

echo "==> Pre-pulling control-plane images"
kubeadm config images pull

echo "==> Running kubeadm init ${INIT_ARGS[*]}"
kubeadm init "${INIT_ARGS[@]}"

# Admin kubeconfig for the invoking user.
TARGET_USER="${SUDO_USER:-root}"
TARGET_HOME=$(eval echo "~${TARGET_USER}")
echo "==> Writing admin kubeconfig to ${TARGET_HOME}/.kube/config"
mkdir -p "${TARGET_HOME}/.kube"
cp -f /etc/kubernetes/admin.conf "${TARGET_HOME}/.kube/config"
chown "$(id -u "${TARGET_USER}"):$(id -g "${TARGET_USER}")" "${TARGET_HOME}/.kube/config"
export KUBECONFIG=/etc/kubernetes/admin.conf

echo "==> Installing Calico ${CALICO_VERSION} (Tigera operator)"
kubectl create -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml"

# Wait for the operator CRD before applying the Installation (avoids a silent race).
echo "==> Waiting for the Tigera Installation CRD"
kubectl wait --for=condition=established --timeout=90s crd/installations.operator.tigera.io

# Full VXLAN so pod traffic works on cloud networks (e.g. Azure) within one subnet.
cat <<EOF | kubectl apply -f -
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: ${POD_CIDR}
      encapsulation: VXLAN
      natOutgoing: Enabled
      nodeSelector: all()
EOF

echo "==> Waiting for nodes to become Ready"
kubectl wait --for=condition=Ready node --all --timeout=180s || \
  echo "Nodes not Ready yet - check 'kubectl get pods -n calico-system'."

if [[ "${SINGLE_NODE}" == "true" ]]; then
  echo "==> SINGLE_NODE=true: removing control-plane taint"
  kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true
fi

echo
echo "==> Control plane ready. Add a worker with:"
echo "      kubeadm token create --print-join-command"
