#!/usr/bin/env bash
# Install cert-manager and a self-signed internal CA (no public DNS needed).
set -euo pipefail

CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.18.2}"

echo "==> Installing cert-manager ${CERT_MANAGER_VERSION}"
kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"

echo "==> Waiting for cert-manager to be Ready"
kubectl -n cert-manager rollout status deploy/cert-manager --timeout=180s
kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=180s
kubectl -n cert-manager rollout status deploy/cert-manager-cainjector --timeout=180s

echo "==> Creating the internal CA issuers"
kubectl apply -f "$(dirname "$0")/issuers.yaml"

echo "==> Waiting for the internal CA certificate"
kubectl -n cert-manager wait --for=condition=Ready certificate/internal-ca --timeout=120s

echo "==> Done. ClusterIssuer 'internal-ca-issuer' can now sign app certs."
