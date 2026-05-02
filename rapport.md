# Rapport de déploiement — Cloud et Virtualisation

> CHARBEL GERGES 22202037
> M1 SIRIS — Mai 2026

---

## 1. Vue d'ensemble de l'infrastructure

L'infrastructure repose sur trois machines virtuelles dans un réseau privé `192.168.9.0/24`.

| VM | IP | Rôle |
|----|-----|------|
| vm1 | 192.168.9.101 | HAProxy + Keepalived MASTER + Swarm manager |
| vm2 | 192.168.9.102 | HAProxy + Keepalived BACKUP + Swarm manager |
| vm3 | 192.168.9.103 | Swarm manager (workload applicatif) |
| VIP | 192.168.9.110 | IP flottante gérée par Keepalived |

Le trafic entrant arrive via la VIP `192.168.9.110` (port 8081), pris en charge par HAProxy, puis distribué aux conteneurs orchestrés par Docker Swarm. Les images sont tirées depuis **Docker Hub** (`docker.io/<user>/cloud-virt-*`), et les services externe (RabbitMQ, S3) sont hébergés par le fournisseur cloud.

### Services applicatifs

| Service | Image Docker Hub | Réplicas | Port publié |
|---------|-----------------|----------|-------------|
| frontend | `<user>/cloud-virt-frontend:${IMAGE_TAG}` | 2 | 3000 (mode host) |
| api | `<user>/cloud-virt-api:${IMAGE_TAG}` | 3 | 8080 (mode host) |
| worker | `<user>/cloud-virt-worker:${IMAGE_TAG}` | 3 | — |

Chaque service a au maximum **1 réplica par nœud** (`max_replicas_per_node: 1`), garantissant une vraie distribution physique.

---

## 2. Script de déploiement — `deploy.sh`

Tout le déploiement est automatisé via un unique script `scripts/deploy.sh`. Il enchaîne les étapes suivantes :

### Étapes du script

**1. Kernel + watchdog (toutes les VMs)**
Configure le redémarrage automatique en cas de kernel panic (`kernel.panic=10`, `vm.panic_on_oom=1`) et active le watchdog systemd (60 s). Ces paramètres sont persistés dans `/etc/sysctl.d/99-autoreboot.conf`.

**2. Configuration Swarm**
Applique les labels de placement (`role=lb` sur vm1/vm2, `role=app` sur vm3) et promeut vm2 et vm3 comme managers :
```bash
docker node update --label-add role=lb vm1
docker node promote vm2 vm3
```

**3. Déploiement HAProxy**
Copie `haproxy/haproxy.cfg` sur vm1 et vm2, valide la configuration (`haproxy -c`), puis recharge ou démarre le service :
```bash
scp haproxy/haproxy.cfg vm1:/tmp/haproxy.cfg
ssh vm1 "sudo systemctl reload haproxy"
```

**4. Déploiement Keepalived**
Détecte automatiquement l'interface réseau de chaque VM (`ip route get`), injecte le nom de l'interface dans les configs, puis configure vm1 en MASTER (priorité 100) et vm2 en BACKUP (priorité 90).

**5. Déploiement de la stack Docker**
Copie `docker-stack.yml`, `.env` et `config/frontend-config.json` sur vm1, puis lance :
```bash
docker stack deploy -c docker-stack.yml app
```

**6. Vérification**
Attend 40 s (health checks), affiche l'état des services et teste les endpoints HTTP via `curl`.

### Utilisation
```bash
./deploy.sh
```

Le script est idempotent : on peut le rejouer sans risque pour mettre à jour la configuration.

---

## 3. Déploiement d'une nouvelle version

### Procédure

1. Construire et pousser les nouvelles images sur **Docker Hub** :
```bash
docker build -t <user>/cloud-virt-api:v2 api/ && docker push <user>/cloud-virt-api:v2
docker build -t <user>/cloud-virt-frontend:v2 web/ && docker push <user>/cloud-virt-frontend:v2
docker build -t <user>/cloud-virt-worker:v2 api/ -f api/Dockerfile.worker && docker push <user>/cloud-virt-worker:v2
```

2. Mettre à jour `IMAGE_TAG` dans le fichier `.env` sur vm1 :
```bash
IMAGE_TAG=v2
```

3. Redéployer la stack (ou relancer `deploy.sh`) :
```bash
docker stack deploy -c docker-stack.yml app
```

### Rolling update automatique

Docker Swarm met à jour les réplicas **un par un** avec les paramètres suivants :

| Paramètre | API | Worker | Frontend |
|-----------|-----|--------|----------|
| `parallelism` | 1 | 1 | 1 |
| `delay` | 15 s | 10 s | 10 s |
| `order` | stop-first | stop-first | stop-first |
| `failure_action` | rollback | rollback | rollback |

Si un réplica échoue son health check (`/health` pour l'API), Swarm déclenche automatiquement un **rollback** vers l'image précédente.

`start-first` aurait été préférable mais il nécessite d'avoir de la capacité disponible sur le nœud. (J'ai parfois eu des problèmes de mémoires) 

---

## 4. Maintenance planifiée d'un nœud

Exemple : redémarrage de vm3 suite à une mise à jour système.

### Étapes

**1. Drainer le nœud** (evacue les conteneurs sans interruption)
```bash
docker node update --availability drain vm3
```
Vérifier que les réplicas sont redistribués sur vm1/vm2 :
```bash
docker stack services app
```

**2. Effectuer la maintenance**
```bash
ssh vm3 "sudo apt update && sudo apt upgrade -y && sudo reboot"
```

**3. Remettre en service**
```bash
docker node update --availability active vm3
```
Swarm replace progressivement les réplicas sur vm3.

### Cas particulier : vm1 ou vm2

Ces nœuds portent HAProxy et Keepalived. Avant de drainer vm1, forcer la bascule de la VIP sur vm2 en arrêtant HAProxy :
```bash
ssh vm1 "sudo systemctl stop haproxy"
```
Keepalived détecte l'arrêt (~2 s) et transfère automatiquement la VIP sur vm2.

---

## 5. Ajout ou suppression d'un nœud

### Ajouter un nœud (ex : vm4)

```bash
# Récupérer le token manager
docker swarm join-token manager

# Sur vm4 — rejoindre le Swarm
docker swarm join --token <token> 192.168.9.101:2377

# Attribuer un label
docker node update --label-add role=app vm4

# Ajouter vm4 dans haproxy.cfg (backends frontend_servers et api_servers)
# Puis recharger HAProxy sur vm1 et vm2
ssh vm1 "sudo systemctl reload haproxy"
ssh vm2 "sudo systemctl reload haproxy"
```

### Supprimer un nœud

```bash
# 1. Drainer
docker node update --availability drain <nœud>

# 2. Retirer du Swarm
docker node rm <nœud>

# 3. Retirer l'entrée dans haproxy.cfg et recharger HAProxy
sudo vim /etc/haproxy/haproxy.cfg
# Supprimer la ligne "server <nœud> 192.168.9.10X:... check inter 5s"
# dans les backends frontend_servers et api_servers

ssh vm1 "sudo systemctl reload haproxy"
ssh vm2 "sudo systemctl reload haproxy"
```

---

## 6. Impact des scénarios de panne

| Scénario | Impact | Rétablissement |
|----------|--------|----------------|
| **Panne vm3** | Perte d'1 réplica API et d'1 worker. HAProxy retire le serveur du pool après ~5 s. Service dégradé mais fonctionnel. | Automatique : Swarm replace les réplicas sur vm1/vm2. |
| **Panne vm1 (MASTER)** | HAProxy vm1 tombe. Keepalived bascule la VIP sur vm2 (~2 s). Légère coupure transitoire. | Automatique via VRRP. vm1 reprend le rôle MASTER au redémarrage. |
| **Panne vm2 (BACKUP)** | Perte du LB secondaire. vm1 continue seul. Aucune interruption visible. | Automatique au redémarrage. |
| **Panne vm1 + vm2** | Plus de load balancer. Service inaccessible. | Rétablir HAProxy manuellement sur au moins un nœud. |

---

## 7. Informations pour la maintenance

### Accès SSH

Configurer `~/.ssh/config` avec le bastion, puis : `ssh vm1`, `ssh vm2`, `ssh vm3`.

### Commandes clés

```bash
# État du cluster Swarm
docker node ls

# État des services
docker stack services app

# Logs d'un service
docker service logs app_api --follow

# Redéploiement complet
./deploy.sh
```

### Variables d'environnement sensibles

Le fichier `.env` sur vm1 (`~/projet-cloud-virt/.env`) contient :

```
REGISTRY=docker.io/<user>
IMAGE_TAG=latest
RABBITMQ_URL=amqps://<user>:<pass>@rabbitmq.maurice-cloud.fr:5671/<vhost>
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_REGION_NAME=eu-west-3
S3_BUCKET_NAME=cloud-virt-mai-<id>-images
```

### Résilience automatique

- **Kernel panic** : redémarrage automatique après 10 s (`kernel.panic=10`)
- **OOM** : redémarrage automatique (`vm.panic_on_oom=1`)
- **Watchdog systemd** : redémarre les services bloqués (60 s)
- **Restart policy Swarm** : `on-failure`, max 3 tentatives par conteneur
- **Health check API** : `GET /health` toutes les 15 s, timeout 5 s, 3 retries

---

## 8. Justification des choix techniques

**Docker Swarm** a été préféré à Kubernetes pour sa simplicité sur 3 nœuds : un seul fichier `docker-stack.yml`, pas de plan de contrôle séparé, rolling updates et health checks natifs.

**HAProxy** gère le load balancing HTTP avec health checks actifs (`option httpchk`) sur les deux backends (frontend et API). Il est déployé hors Swarm sur vm1 et vm2 pour ne pas dépendre de l'orchestrateur qu'il est censé alimenter.

**Keepalived** assure la haute disponibilité du point d'entrée via VRRP. La bascule de la VIP est conditionnée à la santé de HAProxy (`vrrp_script check_haproxy`), ce qui garantit qu'une panne HAProxy déclenche bien le failover.

**Docker Hub** est utilisé comme registre public pour les images. La variable `REGISTRY` dans `.env` permet de changer de registre sans modifier `docker-stack.yml`.

**3 Dockerfiles distincts** (frontend, api, worker) plutôt qu'une image unique pour plusieurs raisons. D'abord la séparation des responsabilités : le frontend est une image nginx servant des fichiers statiques, l'api est un serveur Gunicorn/Flask, le worker est un processus Celery — ce sont des runtimes différents qui n'ont pas à partager une image. Ensuite le scaling indépendant : on peut avoir 2 réplicas frontend et 3 réplicas api/worker sans embarquer du code inutile dans chaque conteneur. Enfin la sécurité : chaque image n'embarque que les dépendances strictement nécessaires à son rôle, réduisant la surface d'attaque.

**La séparation des rôles** (vm1/vm2 = LB, vm3 = app) permet de drainer un nœud applicatif sans impacter le routage, et inversement.
