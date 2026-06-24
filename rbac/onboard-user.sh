#!/usr/bin/env bash
# Onboard a user via the Kubernetes CSR flow and bind least-privilege RBAC.
# Usage (admin kubeconfig in scope): ./onboard-user.sh <username> [group] [namespace]
set -euo pipefail

USER_NAME="${1:?Usage: $0 <username> [group] [namespace]}"
GROUP="${2:-nginx-deployers}"
NAMESPACE="${3:-nginx-app}"
DAYS_VALID="${DAYS_VALID:-365}"
OUT_DIR="${OUT_DIR:-$(dirname "$0")/generated/${USER_NAME}}"

command -v openssl >/dev/null || { echo "openssl is required"; exit 1; }
command -v kubectl >/dev/null || { echo "kubectl is required"; exit 1; }

# Needs an admin kubeconfig (creates/approves the CSR, applies RBAC).
if ! kubectl auth can-i create certificatesigningrequests >/dev/null 2>&1; then
  echo "ERROR: this context cannot create CertificateSigningRequests." >&2
  echo "       Run with an admin kubeconfig (e.g. 'unset KUBECONFIG')." >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"
KEY="${OUT_DIR}/${USER_NAME}.key"
CSR="${OUT_DIR}/${USER_NAME}.csr"
CRT="${OUT_DIR}/${USER_NAME}.crt"
KUBECONFIG_OUT="${OUT_DIR}/${USER_NAME}.kubeconfig"
CSR_NAME="${USER_NAME}-access"

echo "==> [1/6] Generating key and CSR (CN=${USER_NAME}, O=${GROUP})"
openssl genrsa -out "${KEY}" 2048 2>/dev/null
openssl req -new -key "${KEY}" -out "${CSR}" -subj "/CN=${USER_NAME}/O=${GROUP}"

echo "==> [2/6] Submitting CertificateSigningRequest '${CSR_NAME}'"
kubectl delete csr "${CSR_NAME}" --ignore-not-found >/dev/null 2>&1 || true
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${CSR_NAME}
spec:
  request: $(base64 -w0 < "${CSR}" 2>/dev/null || base64 < "${CSR}" | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: $(( DAYS_VALID * 86400 ))
  usages:
  - client auth
EOF

echo "==> [3/6] Approving the CSR"
kubectl certificate approve "${CSR_NAME}"

echo "==> [4/6] Extracting the signed certificate"
for _ in $(seq 1 10); do
  CERT_B64=$(kubectl get csr "${CSR_NAME}" -o jsonpath='{.status.certificate}')
  [[ -n "${CERT_B64}" ]] && break
  sleep 1
done
[[ -n "${CERT_B64}" ]] || { echo "Certificate not issued - is a signer running?"; exit 1; }
echo "${CERT_B64}" | base64 -d > "${CRT}"

echo "==> [5/6] Applying namespace-scoped RBAC"
kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1 || kubectl create namespace "${NAMESPACE}"
sed -e "s/__NAMESPACE__/${NAMESPACE}/g" -e "s/__GROUP__/${GROUP}/g" \
    "$(dirname "$0")/roles/nginx-deployer-role.yaml" | kubectl apply -f -

echo "==> [6/6] Building kubeconfig at ${KUBECONFIG_OUT}"
CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')
API_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CA_DATA=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

cat > "${KUBECONFIG_OUT}" <<EOF
apiVersion: v1
kind: Config
clusters:
- name: ${CLUSTER_NAME}
  cluster:
    server: ${API_SERVER}
    certificate-authority-data: ${CA_DATA}
contexts:
- name: ${USER_NAME}@${CLUSTER_NAME}
  context:
    cluster: ${CLUSTER_NAME}
    namespace: ${NAMESPACE}
    user: ${USER_NAME}
current-context: ${USER_NAME}@${CLUSTER_NAME}
users:
- name: ${USER_NAME}
  user:
    client-certificate-data: $(base64 -w0 < "${CRT}" 2>/dev/null || base64 < "${CRT}" | tr -d '\n')
    client-key-data: $(base64 -w0 < "${KEY}" 2>/dev/null || base64 < "${KEY}" | tr -d '\n')
EOF

cat <<EOF

==> Done. User '${USER_NAME}' (group '${GROUP}') can access namespace '${NAMESPACE}'.
   Hand them only: ${KUBECONFIG_OUT}
   Test:  KUBECONFIG=${KUBECONFIG_OUT} kubectl get pods
   Boundary check (should be Forbidden):
     KUBECONFIG=${KUBECONFIG_OUT} kubectl get pods -n kube-system
EOF
