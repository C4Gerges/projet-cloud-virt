set -euo pipefail

VM1_IP="192.168.9.101"
VM2_IP="192.168.9.102"
VM3_IP="192.168.9.103"

VM1="vm1"
VM2="vm2"
VM3="vm3"

echo "==> [VM1] Initializing Docker Swarm"
ssh "${VM1}" "docker swarm init --advertise-addr ${VM1_IP} 2>/dev/null || true"

MANAGER_TOKEN=$(ssh "${VM1}" "docker swarm join-token manager -q")
WORKER_TOKEN=$(ssh  "${VM1}" "docker swarm join-token worker  -q")

echo "==> [VM2] Joining as manager"
ssh "${VM2}" "docker swarm join --token ${MANAGER_TOKEN} ${VM1_IP}:2377 2>/dev/null || true"

echo "==> [VM3] Joining as worker"
ssh "${VM3}" "docker swarm join --token ${WORKER_TOKEN} ${VM1_IP}:2377 2>/dev/null || true"

echo "==> Labeling nodes"
ssh "${VM1}" "
  docker node update --label-add role=lb  vm1
  docker node update --label-add role=lb  vm2
  docker node update --label-add role=app vm3
"

echo ""
echo "==> Cluster state:"
ssh "${VM1}" "docker node ls"
echo ""
echo "==> Node labels:"
ssh "${VM1}" "docker node inspect --format '{{ .Description.Hostname }}  labels={{ .Spec.Labels }}' vm1 vm2 vm3"
