#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Deploy External Secrets Operator (ESO) to Kubernetes (Docker Desktop)
# ==============================================================================

ESO_NAMESPACE="external-secrets"
ESO_HELM_REPO="https://charts.external-secrets.io"
ESO_CHART_VERSION="0.10.7"

echo ">>> Checking prerequisites..."
command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl not found"; exit 1; }
command -v helm >/dev/null 2>&1    || { echo "ERROR: helm not found"; exit 1; }

CONTEXT=$(kubectl config current-context)
echo ">>> Current kubectl context: ${CONTEXT}"
if [[ "${CONTEXT}" != "docker-desktop" ]]; then
  echo "WARNING: context is not 'docker-desktop'. Continue? [y/N]"
  read -r answer
  [[ "${answer}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
fi

echo ""
echo ">>> Step 1: Add ESO Helm repository..."
helm repo add external-secrets "${ESO_HELM_REPO}" --force-update
helm repo update

echo ""
echo ">>> Step 2: Create namespace '${ESO_NAMESPACE}'..."
kubectl create namespace "${ESO_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo ">>> Step 3: Install ESO controller via Helm..."
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace "${ESO_NAMESPACE}" \
  --version "${ESO_CHART_VERSION}" \
  --set installCRDs=true \
  --set webhook.port=9443 \
  --set image.repository=ghcr.io/external-secrets/external-secrets \
  --set webhook.image.repository=ghcr.io/external-secrets/external-secrets \
  --set certController.image.repository=ghcr.io/external-secrets/external-secrets \
  --wait \
  --timeout 5m

echo ""
echo ">>> Step 4: Verify deployment..."
kubectl rollout status deployment/external-secrets          -n "${ESO_NAMESPACE}"
kubectl rollout status deployment/external-secrets-webhook  -n "${ESO_NAMESPACE}"
kubectl rollout status deployment/external-secrets-cert-controller -n "${ESO_NAMESPACE}"

echo ""
echo ">>> ESO deployed successfully!"
echo "    Pods:"
kubectl get pods -n "${ESO_NAMESPACE}"
echo ""
echo "    CRDs:"
kubectl get crds | grep external-secrets.io
