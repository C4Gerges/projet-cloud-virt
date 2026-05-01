set -euo pipefail

STACK="app"
MANAGER="vm1"

usage() {
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# \?//'
    exit 1
}

cmd="${1:-}"
shift || true

case "${cmd}" in

status)
    echo "=== Nodes ==="
    ssh "${MANAGER}" "docker node ls"
    echo ""
    echo "=== Services ==="
    ssh "${MANAGER}" "docker stack services ${STACK}"
    echo ""
    echo "=== Tasks (last 20) ==="
    ssh "${MANAGER}" "docker stack ps ${STACK} --no-trunc | head -21"
    ;;

drain)
    NODE="${1:?drain requires a node name (vm1|vm2|vm3)}"
    echo "==> Draining ${NODE} (containers will be rescheduled on other nodes)"
    ssh "${MANAGER}" "docker node update --availability drain ${NODE}"
    echo "==> Current state:"
    ssh "${MANAGER}" "docker node ls"
    echo ""
    echo "    Run '${NODE}' maintenance, then: $0 undrain ${NODE}"
    ;;

undrain)
    NODE="${1:?undrain requires a node name (vm1|vm2|vm3)}"
    echo "==> Restoring ${NODE} to active"
    ssh "${MANAGER}" "docker node update --availability active ${NODE}"
    ssh "${MANAGER}" "docker node ls"
    ;;

scale)
    SERVICE="${1:?scale requires: <service> <replicas>}"
    REPLICAS="${2:?scale requires: <service> <replicas>}"
    echo "==> Scaling ${STACK}_${SERVICE} to ${REPLICAS} replicas"
    ssh "${MANAGER}" "docker service scale ${STACK}_${SERVICE}=${REPLICAS}"
    ;;

update)
    TAG="${1:?update requires an image tag (e.g. v1.1)}"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    REGISTRY="${REGISTRY:?Set REGISTRY env var (e.g. export REGISTRY=ghcr.io/gerges)}"

    echo "==> Building and pushing images with tag ${TAG}"
    bash "${SCRIPT_DIR}/04-deploy.sh" "${REGISTRY}" "${TAG}"
    ;;

rollback)
    SERVICE="${1:?rollback requires a service name (frontend|api|worker)}"
    echo "==> Rolling back ${STACK}_${SERVICE} to previous version"
    ssh "${MANAGER}" "docker service rollback ${STACK}_${SERVICE}"
    echo ""
    ssh "${MANAGER}" "docker service ps ${STACK}_${SERVICE} --no-trunc | head -10"
    ;;

*)
    usage
    ;;
esac
