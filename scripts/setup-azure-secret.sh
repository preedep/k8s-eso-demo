#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Create Kubernetes Secret for Azure Service Principal credentials
# Reads from .env file (do NOT commit .env)
# ==============================================================================

DEMO_NAMESPACE="eso-demo"
ENV_FILE="$(dirname "$0")/../.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: .env file not found at ${ENV_FILE}"
  echo "       Copy .env.example to .env and fill in your Azure credentials."
  exit 1
fi

# shellcheck source=/dev/null
source "${ENV_FILE}"

: "${AZURE_TENANT_ID:?Missing AZURE_TENANT_ID in .env}"
: "${AZURE_CLIENT_ID:?Missing AZURE_CLIENT_ID in .env}"
: "${AZURE_CLIENT_SECRET:?Missing AZURE_CLIENT_SECRET in .env}"
: "${AZURE_KEYVAULT_URL:?Missing AZURE_KEYVAULT_URL in .env}"

echo ">>> Creating namespace '${DEMO_NAMESPACE}'..."
kubectl create namespace "${DEMO_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo ">>> Creating Azure SP secret 'azure-secret-sp' in '${DEMO_NAMESPACE}'..."
kubectl create secret generic azure-secret-sp \
  --namespace "${DEMO_NAMESPACE}" \
  --from-literal=ClientID="${AZURE_CLIENT_ID}" \
  --from-literal=ClientSecret="${AZURE_CLIENT_SECRET}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo ">>> Patching SecretStore with vault URL and tenant ID..."
kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: azure-keyvault-store
  namespace: ${DEMO_NAMESPACE}
spec:
  provider:
    azurekv:
      authType: ServicePrincipal
      vaultUrl: "${AZURE_KEYVAULT_URL}"
      tenantId: "${AZURE_TENANT_ID}"
      authSecretRef:
        clientId:
          name: azure-secret-sp
          key: ClientID
        clientSecret:
          name: azure-secret-sp
          key: ClientSecret
EOF

echo ""
echo ">>> SecretStore status:"
kubectl get secretstore azure-keyvault-store -n "${DEMO_NAMESPACE}"

echo ""
echo ">>> Done. Now apply the ExternalSecret:"
echo "    kubectl apply -f k8s/azure-external-secret.yaml"
