#!/usr/bin/env bash
# Install Argo CD and register the Nginx app for GitOps.
# Run: ./install-argocd.sh   (override the repo with REPO_URL=...)
set -euo pipefail

ARGOCD_VERSION="${ARGOCD_VERSION:-stable}"
REPO_URL="${REPO_URL:-https://github.com/ugwuezev/teleport.git}"
REPO_REVISION="${REPO_REVISION:-main}"

echo "==> Installing Argo CD (${ARGOCD_VERSION})"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
# Server-side apply: Argo CD CRDs exceed kubectl's 256 KB annotation limit.
kubectl apply --server-side --force-conflicts -n argocd -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "==> Waiting for the Argo CD API server"
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s

echo "==> Registering the Nginx Application (repo: ${REPO_URL}, rev: ${REPO_REVISION})"
sed -e "s#__REPO_URL__#${REPO_URL}#g" -e "s#__REPO_REVISION__#${REPO_REVISION}#g" \
    "$(dirname "$0")/application.yaml" | kubectl apply -f -

echo
echo "==> Argo CD installed. Access the UI:"
echo "    kubectl -n argocd port-forward svc/argocd-server 8080:443"
echo "    Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
