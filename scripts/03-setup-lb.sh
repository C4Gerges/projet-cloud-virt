set -euo pipefail

ROLE="${1:?Usage: $0 <master|backup>}"

if [[ "${ROLE}" != "master" && "${ROLE}" != "backup" ]]; then
    echo "Error: role must be 'master' or 'backup'" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${SCRIPT_DIR}/.."

IFACE=$(ip -4 route | awk '/192\.168\.9\.0/{print $3}')
if [[ -z "${IFACE}" ]]; then
    echo "Error: could not detect the private network interface" >&2
    exit 1
fi
echo "==> Detected private NIC: ${IFACE}"

echo "==> Installing HAProxy and Keepalived"
apt-get update -qq
apt-get install -y haproxy keepalived

echo "==> Configuring HAProxy"
cp "${REPO_DIR}/haproxy/haproxy.cfg" /etc/haproxy/haproxy.cfg
systemctl enable haproxy
systemctl restart haproxy

echo "==> Configuring Keepalived (${ROLE})"
sed "s/IFACE/${IFACE}/g" "${REPO_DIR}/keepalived/keepalived-${ROLE}.conf" \
    > /etc/keepalived/keepalived.conf

echo "net.ipv4.ip_nonlocal_bind = 1" > /etc/sysctl.d/99-keepalived.conf
sysctl --system

systemctl enable keepalived
systemctl restart keepalived

echo ""
echo "==> Load balancer (${ROLE}) is up."
echo "    Interface:      ${IFACE}"
echo "    HAProxy stats:  http://$(hostname -I | awk '{print $1}'):9000/stats  (admin/cloudvirt)"
echo "    Keepalived VIP: 192.168.9.110"
