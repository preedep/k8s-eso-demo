#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Teardown ESO and all demo resources
# ==============================================================================

ESO_NAMESPACE="external-secrets"
DEMO_NAMESPACE="eso-demo"

echo ">>> This will remove ESO and all demo resources. Continue? [y/N]"
read -r answer
[[ "${answer}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

echo ""
echo ">>> Removing demo namespace '${DEMO_NAMESPACE}'..."
kubectl delete namespace "${DEMO_NAMESPACE}" --ignore-not-found

echo ""
echo ">>> Uninstalling ESO Helm release..."
helm uninstall external-secrets -n "${ESO_NAMESPACE}" --ignore-not-found

echo ""
echo ">>> Removing ESO namespace..."
kubectl delete namespace "${ESO_NAMESPACE}" --ignore-not-found

echo ""
echo ">>> Removing ESO CRDs..."
kubectl get crds | grep external-secrets.io | awk '{print $1}' | xargs -r kubectl delete crd

echo ""
echo ">>> Teardown complete."
