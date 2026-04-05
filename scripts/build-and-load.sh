#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Build Rust app Docker image และ load เข้า Docker Desktop k8s
# ==============================================================================

IMAGE_NAME="eso-demo"
IMAGE_TAG="latest"

echo ">>> Building Docker image ${IMAGE_NAME}:${IMAGE_TAG}..."
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" .

echo ""
echo ">>> Image built:"
docker images "${IMAGE_NAME}:${IMAGE_TAG}"

echo ""
echo ">>> Image '${IMAGE_NAME}:${IMAGE_TAG}' พร้อมใช้งานกับ Docker Desktop k8s แล้ว"
echo "    (imagePullPolicy: Never จะใช้ local image โดยตรง)"
echo ""
echo ">>> Deploy ด้วย:"
echo "    kubectl apply -f k8s/deployment.yaml"
