#!/bin/bash
# deploy.sh — Déploiement complet du projet cloud-virt
# Usage: ./deploy.sh

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
fail() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
step() { echo -e "\n${CYAN}══════════════════════════════════════${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}══════════════════════════════════════${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ─── 1. Kernel auto-reboot + systemd watchdog ────────────────────────────────
configure_kernel() {
    local vm=$1
    log "[$vm] Kernel panic + watchdog..."
    ssh "$vm" bash <<'EOF'
        sudo sysctl -w kernel.panic=10 vm.panic_on_oom=1 > /dev/null
        echo -e 'kernel.panic = 10\nvm.panic_on_oom = 1' | sudo tee /etc/sysctl.d/99-autoreboot.conf > /dev/null
        sudo mkdir -p /etc/systemd/system.conf.d
        printf '[Manager]\nRuntimeWatchdogSec=60\nRebootWatchdogSec=10min\n' \
            | sudo tee /etc/systemd/system.conf.d/watchdog.conf > /dev/null
        sudo systemctl daemon-reload
EOF
}

# ─── 2. Labels Swarm + promotion managers ────────────────────────────────────
configure_swarm() {
    step "Configuration Swarm"
    log "Labels des nœuds..."
    ssh vm1 "docker node update --label-add role=lb vm1" 2>/dev/null || true
    ssh vm1 "docker node update --label-add role=lb vm2" 2>/dev/null || true
    ssh vm1 "docker node update --label-add role=app vm3" 2>/dev/null || true

    log "Promotion vm2 et vm3 comme managers..."
    ssh vm1 "docker node promote vm2 vm3 2>/dev/null || true"

    log "État du Swarm :"
    ssh vm1 "docker node ls"
}

# ─── 3. HAProxy ──────────────────────────────────────────────────────────────
deploy_haproxy() {
    step "Déploiement HAProxy"
    for vm in vm1 vm2; do
        log "[$vm] Copie et rechargement HAProxy..."
        scp "$PROJECT_DIR/projet-cloud-virt/haproxy/haproxy.cfg" "$vm:/tmp/haproxy.cfg"
        ssh "$vm" bash <<'EOF'
            sudo cp /tmp/haproxy.cfg /etc/haproxy/haproxy.cfg
            sudo haproxy -c -f /etc/haproxy/haproxy.cfg || exit 1
            if sudo systemctl is-active --quiet haproxy; then
                sudo systemctl reload haproxy
            else
                sudo systemctl enable --now haproxy
            fi
EOF
        log "[$vm] HAProxy OK"
    done
}

# ─── 4. Keepalived ───────────────────────────────────────────────────────────
deploy_keepalived() {
    step "Déploiement Keepalived"

    # Détection automatique de l'interface réseau
    IFACE_VM1=$(ssh vm1 "ip route get 192.168.9.1 2>/dev/null | grep -oP 'dev \K\S+' | head -1")
    IFACE_VM2=$(ssh vm2 "ip route get 192.168.9.1 2>/dev/null | grep -oP 'dev \K\S+' | head -1")
    log "Interface vm1: $IFACE_VM1 | vm2: $IFACE_VM2"

    # vm1 — MASTER
    log "[vm1] Déploiement keepalived MASTER..."
    sed "s/IFACE/$IFACE_VM1/g" "$PROJECT_DIR/projet-cloud-virt/keepalived/keepalived-master.conf" \
        | ssh vm1 "sudo tee /etc/keepalived/keepalived.conf > /dev/null"
    ssh vm1 "sudo systemctl enable keepalived && sudo systemctl restart keepalived"
    log "[vm1] Keepalived MASTER OK"

    # vm2 — BACKUP
    log "[vm2] Déploiement keepalived BACKUP..."
    sed "s/IFACE/$IFACE_VM2/g" "$PROJECT_DIR/projet-cloud-virt/keepalived/keepalived-backup.conf" \
        | ssh vm2 "sudo tee /etc/keepalived/keepalived.conf > /dev/null"
    ssh vm2 "sudo systemctl enable keepalived && sudo systemctl restart keepalived"
    log "[vm2] Keepalived BACKUP OK"

    log "VIP 192.168.9.110 active sur vm1, bascule sur vm2 si vm1 tombe."
}

# ─── 5. Docker stack ─────────────────────────────────────────────────────────
deploy_stack() {
    step "Déploiement Docker Stack"

    log "Copie des fichiers sur vm1..."
    ssh vm1 "mkdir -p ~/projet-cloud-virt/config"
    scp "$PROJECT_DIR/projet-cloud-virt/docker-stack.yml"              vm1:~/projet-cloud-virt/docker-stack.yml
    scp "$PROJECT_DIR/projet-cloud-virt/.env"                          vm1:~/projet-cloud-virt/.env
    scp "$PROJECT_DIR/projet-cloud-virt/config/frontend-config.json"   vm1:~/projet-cloud-virt/config/frontend-config.json

    log "Déploiement du stack..."
    ssh vm1 "cd ~/projet-cloud-virt && set -a && source .env && set +a && docker stack deploy -c docker-stack.yml app"
    log "Stack déployé"
}

# ─── 6. Vérification ─────────────────────────────────────────────────────────
verify() {
    step "Vérification"
    log "Attente de 40s pour les health checks..."
    sleep 40

    echo ""
    log "Services :"
    ssh vm1 "docker stack services app"

    echo ""
    log "Test routing HAProxy (port 80) :"
    ssh vm1 "curl -sf --max-time 5 -H 'Host: gerges.maurice-cloud.fr' http://localhost/ | head -1 && echo '→ Frontend OK' || echo '→ Frontend KO'"
    ssh vm1 "curl -sf --max-time 5 -H 'Host: api.gerges.maurice-cloud.fr' http://localhost/health && echo ' → API OK' || echo '→ API KO'"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    step "Déploiement cloud-virt"

    step "Kernel + Watchdog (toutes les VMs)"
    for vm in vm1 vm2 vm3; do
        configure_kernel "$vm"
    done

    configure_swarm
    deploy_haproxy
    deploy_keepalived
    deploy_stack
    verify

    step "Déploiement terminé"
    log "Frontend : https://gerges.maurice-cloud.fr"
    log "API      : https://api.gerges.maurice-cloud.fr/health"
}

main "$@"
