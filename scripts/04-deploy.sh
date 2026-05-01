set -euo pipefail

REGISTRY="${1:?Usage: $0 <registry> [image-tag]}"
IMAGE_TAG="${2:-latest}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${SCRIPT_DIR}/.."

echo "==> Building and pushing images (tag: ${IMAGE_TAG})"

docker build \
    -t "${REGISTRY}/cloud-virt-frontend:${IMAGE_TAG}" \
    "${REPO_DIR}/web"
docker push "${REGISTRY}/cloud-virt-frontend:${IMAGE_TAG}"

docker build \
    -t "${REGISTRY}/cloud-virt-api:${IMAGE_TAG}" \
    -f "${REPO_DIR}/api/Dockerfile.api" \
    "${REPO_DIR}/api"
docker push "${REGISTRY}/cloud-virt-api:${IMAGE_TAG}"

docker build \
    -t "${REGISTRY}/cloud-virt-worker:${IMAGE_TAG}" \
    -f "${REPO_DIR}/api/Dockerfile.worker" \
    "${REPO_DIR}/api"
docker push "${REGISTRY}/cloud-virt-worker:${IMAGE_TAG}"

echo ""
echo "==> Deploying stack to Docker Swarm"

set -o allexport
source "${REPO_DIR}/.env"
set +o allexport

REGISTRY="${REGISTRY}" IMAGE_TAG="${IMAGE_TAG}" \
    docker stack deploy \
        --compose-file "${REPO_DIR}/docker-stack.yml" \
        --with-registry-auth \
        app

echo ""
echo "==> Deployment complete. Service status:"
docker stack services app
