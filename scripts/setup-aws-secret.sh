#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Create Kubernetes Secret for AWS credentials และ SecretStore สำหรับ AWS SM
# ==============================================================================

DEMO_NAMESPACE="eso-demo"
ENV_FILE="$(dirname "$0")/../.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: .env file not found at ${ENV_FILE}"
  echo "       Copy .env.example to .env and fill in your AWS credentials."
  exit 1
fi

# shellcheck source=/dev/null
source "${ENV_FILE}"

: "${AWS_ACCESS_KEY_ID:?Missing AWS_ACCESS_KEY_ID in .env}"
: "${AWS_SECRET_ACCESS_KEY:?Missing AWS_SECRET_ACCESS_KEY in .env}"
: "${AWS_REGION:?Missing AWS_REGION in .env}"

echo ">>> Creating namespace '${DEMO_NAMESPACE}'..."
kubectl create namespace "${DEMO_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo ">>> Creating AWS credentials secret 'aws-secret-credentials' in '${DEMO_NAMESPACE}'..."
kubectl create secret generic aws-secret-credentials \
  --namespace "${DEMO_NAMESPACE}" \
  --from-literal=access-key-id="${AWS_ACCESS_KEY_ID}" \
  --from-literal=secret-access-key="${AWS_SECRET_ACCESS_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo ">>> Patching AWS SecretStore with region '${AWS_REGION}'..."
# Patch region ใน manifest ก่อน apply
sed "s/ap-southeast-1/${AWS_REGION}/" \
  "$(dirname "$0")/../k8s/aws-secret-store.yaml" | kubectl apply -f -

echo ""
echo ">>> SecretStore status:"
kubectl get secretstore aws-secretsmanager-store -n "${DEMO_NAMESPACE}"

echo ""
echo ">>> Done. ทดสอบ switch ไปใช้ AWS ด้วย:"
echo "    ./scripts/switch-vault.sh aws"
