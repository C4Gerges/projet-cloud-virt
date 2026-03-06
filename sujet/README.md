# Contexte

Ce projet a pour but de déployer une application fournie de la manière la plus
automatisée et résiliante possible. L'application permet à ses utilisateurs
d'héberger des images, en les redimensionnant au passage dans différentes
tailles. Le projet est à réaliser individuellement.

# Détails de l'application

L'application comporte de trois composants :

- un _backend_ se chargant de sauvegarder les images téléversées, ainsi que de
  servir les images hébergées
- un _worker_ se chargant de redimensionner les images téléversées dans
  différentes tailles
- un _frontend_, sous la forme d'une interface web, pour permettre aux
  utilisateurs d'envoyer les images

Les images sont stockées dans un espace de stockage compatible S3.

Le backend utilise la bibliothèque Python
[_Celery_](https://docs.celeryq.dev/en/stable/) pour envoyer des tâches à
exécuter au _worker_ via une file de message.

Tous ces composants sont _scalables_ horizontalement : plusieurs instances du
_backend_, du _worker_ ou du _frontend_ peuvent cohéxister et se partager la
charge.

Le code de l'application est disponible à ces trois adresses (pour simplifier le
_fork_ du dépôt) :

- <https://github.com/sandhose/projet-cloud-virt>
- <https://git.unistra.fr/qgliech/projet-cloud-virt>
- <https://gitlab.com/sandhose/projet-cloud-virt>

Vous trouverez dans ce dépôt :

- le code du _backend_ et du _worker_ dans le sous-dossier `api/`
- le code du _frontend_ dans le sous-dossier `web/`
- ce sujet dans le sous-dossier `sujet/`

Chacun de ces sous-dossier a un fichier `README.md` expliquant certains détails
de leur fonctionnement.

# Détails de l'infrastructure

Votre fournisseur _Cloud_ vous fournit, pour chaque étudiant :

- du stockage type S3
- une file de message [RabbitMQ](https://www.rabbitmq.com)
- trois machines virtuelles
- une IP flottante
- des tunnels HTTP vers vos machines virtuelles et votre IP flottante

## Connexion aux machines virtuelles

Les machines virtuelles sont accessibles par SSH via un hôte bastion, accessible
depuis le réseau de l'université, donc connecté au wifi de l'université ou via
le VPN :
<https://documentation.unistra.fr/Catalogue/Infrastructures-reseau/osiris/VPN/co/guide.html>

Le bastion est accessible par SSH à `student@bastion.maurice-cloud.fr`. Vous
devriez pouvoir accéder à votre machine virtuelle par SSH de cette manière :

```sh
ssh -J student@bastion.maurice-cloud.fr ubuntu@vm1.$ID.internal.maurice-cloud.fr
```

où `$ID` est votre identifiant (communiqué par mail).

Pour simplifier l'accès, vous pouvez ajouter à votre fichier de configuration
SSH (`~/.ssh/config`) la section suivante:

```sshconfig
Host bastion-cloud
	Hostname bastion.maurice-cloud.fr
	User student

Host vm1
	Hostname vm1.$ID.internal.maurice-cloud.fr
	User ubuntu
	ProxyJump bastion-cloud

Host vm2
	Hostname vm2.$ID.internal.maurice-cloud.fr
	User ubuntu
	ProxyJump bastion-cloud

Host vm3
	Hostname vm3.$ID.internal.maurice-cloud.fr
	User ubuntu
	ProxyJump bastion-cloud
```

(en remplaçant `$ID` par votre identifiant)

Puis, vous pourrez directement accéder à vos machines virtuelles via `ssh vm1`,
`ssh vm2` ou `ssh vm3`.

Les informations de connexion vous ont été envoyées individuellement par mail.

## Réseau des machines virtuelles

Vos trois machines virtuelles sont connectées à un réseau privé qui vous est
propre.

Chaque machine virtuelle a une IP dans ce réseau privé (`192.168.$N.0/24` où
`$N` est votre numéro d'étudiant). Les adresses IP de vos machines sont :

- VM1 : `192.168.$N.101` (`vm1.$ID.internal.maurice-cloud.fr`)
- VM2 : `192.168.$N.102` (`vm2.$ID.internal.maurice-cloud.fr`)
- VM3 : `192.168.$N.103` (`vm3.$ID.internal.maurice-cloud.fr`)

Vous disposez d'une IP flottante (`192.168.$N.110`) qui peut être assignée
dynamiquement à l'une de vos machines virtuelles.

Pour assigner l'IP flottante, vous pouvez utiliser un outil tel que
[`keepalived`](https://www.redhat.com/sysadmin/keepalived-basics) pour l'ajouter
dynamiquement à l'une des machines virtuelles.

## Tunnels HTTP(S)

Votre fournisseur de _Cloud_ a mis en place des proxy HTTPS vers votre IP
flottante et vos machines virtuelles, avec terminaison TLS.

Ainsi, si votre identifiant est `alice` :

- `https://app-vm1.alice.maurice-cloud.fr/` transmet le trafic vers votre VM1
  sur le port `8080` (`192.168.$N.101:8080`)
- `https://app-vm2.alice.maurice-cloud.fr/` transmet le trafic vers votre VM2
  sur le port `8080` (`192.168.$N.102:8080`)
- `https://app-vm3.alice.maurice-cloud.fr/` transmet le trafic vers votre VM3
  sur le port `8080` (`192.168.$N.103:8080`)
- `https://alice.maurice-cloud.fr/` et `https://*.alice.maurice-cloud.fr/` (tout
  ce qui ne correspond pas à un `-vmN`) transmet le trafic vers votre IP
  flottante sur le port `8081` (`192.168.$N.110:8081`)

Le préfixe avant `-vmN` est libre : `https://foo-vm1.alice.maurice-cloud.fr/`
fonctionne aussi bien que `https://bar-vm1.alice.maurice-cloud.fr/`.

## File de message

Votre fournisseur _Cloud_ vous donne accès à une instance de RabbitMQ, une file
de message. Son interface web est accessible sur
<https://rabbitmq.maurice-cloud.fr>. Cette instance est commune à tous les
étudiants, mais chaque étudiant a accès à un _virtual host_ isolé du reste.

Depuis vos machines virtuelles, la file est accessible via le protocole AMQP :

```
amqp://<username>:<password>@rabbitmq.maurice-cloud.fr:5672/<vhost>
```

où `<username>` et `<password>` sont les identifiants fournis par votre
fournisseur cloud, et `<vhost>` est le nom qui vous a été assigné.

## Stockage S3

Votre fournisseur _Cloud_ vous donne accès à un espace de stockage
[AWS S3](https://aws.amazon.com/s3/). Chaque étudiant dispose d'un compte AWS
avec une paire d'identifiants (_access key id_ et _secret access key_)
permettant de créer et gérer des _buckets_ nommés
`cloud-virt-mai-<identifiant>-*`.

Un accès à la console AWS est également fourni.

## Registre d'images de conteneurs

Votre fournisseur _Cloud_ ne fournit malheuresement pas de registre d'image de
conteneurs. Vous pouvez cependant vous tourner vers des options gratuites telles
que :

- Docker Hub : <https://hub.docker.com/>
- GitHub Container Registry : <https://ghcr.io/>
- GitLab.com : <https://gitlab.com/>
- Quay.io : <https://quay.io>

# Modalité de rendu et critères d'évaluation

Le projet est volontairement souple sur la manière de déployer cette
application. Par exemple, vous n'êtes pas obligés d'utiliser Docker pour tous
les composants de votre déploiement.

Vous expliquerez dans **un rapport** le fonctionnement de votre déploiement, et
justifirez vos choix. Vous deverez notamment expliquer :

- comment se passerait le déploiement d'une nouvelle version de l'application ;
- la procédure pour effectuer une maintenance planifiée d'un nœud (par exemple :
  redémarrage suite à une mise à jour du système) ;
- les étapes pour ajouter ou supprimer un nœud de votre infrastructure ;
- l'impact de différents scénarios de panne ;
- tout ce qui vous paraît pertinent à savoir pour quelqu'un qui devrait ensuite
  maintenir cette infrastructure à votre place.

Vous serez évalués entre autre sur :

- vos images Docker, si vous en utilisez ;
- la lisibilité de vos scripts et fichiers de configuration ;
- le niveau général d'automatisation ;
- la résilience de votre déploiement ;
- la pertinence de vos choix techniques.

En plus du rapport, vous fournirez **un dépôt Git** contenant vos scripts et
fichiers de configurations, ainsi que le code de l'application si vous l'avez
modifié.
