#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# switch-vault.sh — สลับ secret provider ระหว่าง Azure Key Vault และ AWS SM
#
# การใช้งาน:
#   ./scripts/switch-vault.sh azure   ← ดึง secret จาก Azure Key Vault
#   ./scripts/switch-vault.sh aws     ← ดึง secret จาก AWS Secrets Manager
#   ./scripts/switch-vault.sh status  ← ดู provider ที่ใช้งานอยู่
#
# หลักการ: ทั้ง 2 provider สร้าง K8s Secret ชื่อ 'demo-app-secret' เหมือนกัน
# Rust app อ่าน env var จาก secret นี้ → ไม่ต้องเปลี่ยน app เลย
# ==============================================================================

DEMO_NAMESPACE="eso-demo"
EXTERNAL_SECRET_NAME="demo-secret"
DEPLOYMENT_NAME="eso-demo"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/../k8s"

# --------------------------------------------------------------------------
# helper: ดู provider ปัจจุบัน
# --------------------------------------------------------------------------
current_provider() {
  local store
  store=$(kubectl get externalsecret "${EXTERNAL_SECRET_NAME}" \
    -n "${DEMO_NAMESPACE}" \
    -o jsonpath='{.spec.secretStoreRef.name}' 2>/dev/null || echo "none")

  case "${store}" in
    azure-keyvault-store)       echo "azure" ;;
    aws-secretsmanager-store)   echo "aws"   ;;
    none)                       echo "none"  ;;
    *)                          echo "unknown (${store})" ;;
  esac
}

# --------------------------------------------------------------------------
# helper: แสดงสถานะ
# --------------------------------------------------------------------------
show_status() {
  local provider
  provider=$(current_provider)
  echo ">>> Current provider: ${provider}"
  echo ""

  if [[ "${provider}" == "none" ]]; then
    echo "    ไม่มี ExternalSecret ที่ active อยู่"
    return
  fi

  echo ">>> ExternalSecret:"
  kubectl get externalsecret "${EXTERNAL_SECRET_NAME}" -n "${DEMO_NAMESPACE}" \
    -o custom-columns="NAME:.metadata.name,STORE:.spec.secretStoreRef.name,READY:.status.conditions[0].status,REFRESHED:.status.refreshTime" \
    2>/dev/null || true

  echo ""
  echo ">>> K8s Secret (demo-app-secret):"
  kubectl get secret demo-app-secret -n "${DEMO_NAMESPACE}" 2>/dev/null \
    || echo "    (ยังไม่ถูกสร้าง)"

  echo ""
  echo ">>> Deployment:"
  kubectl get deployment "${DEPLOYMENT_NAME}" -n "${DEMO_NAMESPACE}" 2>/dev/null \
    || echo "    (ยังไม่ถูก deploy)"
}

# --------------------------------------------------------------------------
# main switch
# --------------------------------------------------------------------------
PROVIDER="${1:-}"

if [[ -z "${PROVIDER}" ]]; then
  echo "Usage: $0 azure|aws|status"
  echo ""
  show_status
  exit 0
fi

if [[ "${PROVIDER}" == "status" ]]; then
  show_status
  exit 0
fi

if [[ "${PROVIDER}" != "azure" && "${PROVIDER}" != "aws" ]]; then
  echo "ERROR: provider ต้องเป็น 'azure' หรือ 'aws'"
  exit 1
fi

CURRENT=$(current_provider)
if [[ "${CURRENT}" == "${PROVIDER}" ]]; then
  echo ">>> Already using provider: ${PROVIDER}"
  show_status
  exit 0
fi

echo ">>> Switching: ${CURRENT} → ${PROVIDER}"
echo ""

# 1. ลบ ExternalSecret เดิม (ESO จะลบ K8s Secret ที่ owns ด้วย เพราะ creationPolicy: Owner)
echo ">>> Step 1: ลบ ExternalSecret เดิม (และ demo-app-secret ที่ ESO owns)..."
kubectl delete externalsecret "${EXTERNAL_SECRET_NAME}" \
  -n "${DEMO_NAMESPACE}" \
  --ignore-not-found \
  --wait=true

# รอให้ K8s Secret ถูกลบ (max 30s)
echo "          รอให้ demo-app-secret ถูกลบ..."
for i in $(seq 1 30); do
  if ! kubectl get secret demo-app-secret -n "${DEMO_NAMESPACE}" &>/dev/null; then
    echo "          demo-app-secret ถูกลบแล้ว"
    break
  fi
  sleep 1
  if [[ "${i}" -eq 30 ]]; then
    echo "          WARNING: demo-app-secret ยังคงอยู่ ลบ manual..."
    kubectl delete secret demo-app-secret -n "${DEMO_NAMESPACE}" --ignore-not-found
  fi
done

# 2. Apply ExternalSecret ของ provider ใหม่
echo ""
echo ">>> Step 2: Apply ExternalSecret สำหรับ ${PROVIDER}..."
case "${PROVIDER}" in
  azure)
    kubectl apply -f "${K8S_DIR}/azure-external-secret.yaml"
    ;;
  aws)
    kubectl apply -f "${K8S_DIR}/aws-external-secret.yaml"
    ;;
esac

# 3. รอให้ ESO sync และ secret พร้อม
echo ""
echo ">>> Step 3: รอให้ ESO sync secret จาก ${PROVIDER}..."
for i in $(seq 1 60); do
  READY=$(kubectl get externalsecret "${EXTERNAL_SECRET_NAME}" \
    -n "${DEMO_NAMESPACE}" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
  if [[ "${READY}" == "True" ]]; then
    echo "          ExternalSecret Ready!"
    break
  fi
  printf "          รอ... (%ds)\r" "${i}"
  sleep 1
  if [[ "${i}" -eq 60 ]]; then
    echo ""
    echo "WARNING: timeout รอ ExternalSecret ดู status ด้วย:"
    echo "         kubectl describe externalsecret ${EXTERNAL_SECRET_NAME} -n ${DEMO_NAMESPACE}"
  fi
done

# 4. Restart Deployment เพื่อรับ secret ใหม่
echo ""
echo ">>> Step 4: Restart Deployment '${DEPLOYMENT_NAME}'..."
if kubectl get deployment "${DEPLOYMENT_NAME}" -n "${DEMO_NAMESPACE}" &>/dev/null; then
  kubectl rollout restart deployment/"${DEPLOYMENT_NAME}" -n "${DEMO_NAMESPACE}"
  kubectl rollout status deployment/"${DEPLOYMENT_NAME}" -n "${DEMO_NAMESPACE}" --timeout=60s
else
  echo "          (Deployment ยังไม่มี ข้ามขั้นตอนนี้)"
fi

# 5. แสดงผลสุดท้าย
echo ""
echo "============================================================"
echo " Switch สำเร็จ: ${CURRENT} → ${PROVIDER}"
echo "============================================================"
echo ""
show_status

echo ""
echo ">>> Log ของ Rust app:"
echo "    kubectl logs -l app=${DEPLOYMENT_NAME} -n ${DEMO_NAMESPACE} --tail=20"
