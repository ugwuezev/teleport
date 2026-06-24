#!/usr/bin/env bash
# Join a worker to the cluster. Run on the worker after 00-prereqs.sh and 10-install-kube.sh.
# Get the join command on the master: sudo kubeadm token create --print-join-command
# then: sudo ./30-join-worker.sh <paste the kubeadm join ... line>
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo $0 <join command>)"; exit 1
fi

if [[ $# -lt 2 || "$1" != "kubeadm" ]]; then
  cat <<'EOF'
ERROR: pass the full join command from the master.
  Master:  sudo kubeadm token create --print-join-command
  Worker:  sudo ./30-join-worker.sh <paste the kubeadm join ... line>
EOF
  exit 1
fi

echo "==> Joining the cluster"
"$@"
echo "==> Joined. From the master: kubectl get nodes -o wide"
