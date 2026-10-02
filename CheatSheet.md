# Aide-mémoire

Rappel des commandes vues dans la formation, classées par thème.

Syntaxe générale : `docker <type de ressource> <sous-commande> [options] [arguments]`
Sous-commandes communes à toutes les ressources (`image`, `container`, `network`, `volume`) : `ls`, `inspect`, `create`, `rm`, `prune`.

---

## 1. Installation et moteur Docker

```bash
# Ubuntu
sudo apt install docker.io docker-compose-plugin
sudo usermod -aG docker $USER          # utiliser docker sans sudo (se reconnecter ensuite)

# Linux générique
curl -o get-docker.sh https://get.docker.com
chmod +x get-docker.sh && sudo ./get-docker.sh

docker info                            # informations sur le moteur
docker run hello-world                 # test de l'installation

# Piloter un moteur distant
ssh-add <clef_privée>
export DOCKER_HOST=ssh://utilisateur@adresse-ip-distante
```

---

## 2. Gestion des images

### Rechercher, télécharger, lister

```bash
docker search postgres                 # rechercher une image dans le registre
docker pull python                     # télécharger une image (tag latest par défaut)
docker pull python:3.12-slim           # télécharger une version précise (recommandé)
docker images                          # lister les images locales
docker image ls                        # idem
```

### Analyser une image

```bash
docker history python                  # couches de l'image
docker history --no-trunc python       # couches avec les commandes complètes
docker inspect python                  # métadonnées (env, cmd, entrypoint, layers…)
```

### Construire une image

```bash
docker build -t mon-image:1.0 .                      # "." = contexte de build (dossier du Dockerfile)
docker build -t mon-image:1.0 -f chemin/Dockerfile . # Dockerfile situé ailleurs
docker build --build-arg USERNAME=myuser -t mon-image .   # passer une valeur à un ARG
```

Convention de nommage : `registry-url/organisation/image:version`

### Créer une image depuis un conteneur

```bash
docker commit <container_id>           # renvoie l'id de la nouvelle image
docker tag <image_id> mon-image:1.0    # nommer / re-tagger une image
```

### Registres

```bash
docker login <url_registre>            # se connecter à un registre (Docker Hub par défaut)
docker push registre/mon-image:1.0     # publier une image
```

### Supprimer et nettoyer

```bash
docker rmi mon-image:1.0               # supprimer une image
docker image prune                     # supprimer les images non utilisées (dangling)
```

### Exporter / importer (sans registre)

```bash
docker save nginx:alpine | gzip -9 > custom-nginx.tar.gz
gunzip -c custom-nginx.tar.gz | docker load
```

---

## 3. Dockerfile

| Instruction   | Rôle | Exemple |
|---------------|------|---------|
| `FROM`        | Image de base (première instruction) | `FROM node:18-alpine AS builder` |
| `RUN`         | Exécute une commande au build (1 couche par RUN) | `RUN apt-get update && apt-get install -y curl` |
| `COPY`        | Copie depuis le contexte de build | `COPY --chown=app:app . /app` |
| `ADD`         | Comme COPY + décompression tar + URL | `ADD archive.tar.gz /app/` |
| `WORKDIR`     | Répertoire de travail (créé si absent) | `WORKDIR /app` |
| `ENV`         | Variable d'environnement (build + exécution) | `ENV NODE_ENV=production` |
| `ARG`         | Variable disponible uniquement au build | `ARG VERSION=1.0` |
| `EXPOSE`      | Documente le port écouté (ne publie rien) | `EXPOSE 8080/tcp` |
| `VOLUME`      | Déclare un point de montage | `VOLUME ["/data"]` |
| `USER`        | Utilisateur d'exécution (éviter root) | `USER 1001:1001` |
| `LABEL`       | Métadonnées | `LABEL description="My server"` |
| `CMD`         | Commande par défaut (surchargeable par `docker run <image> <cmd>`) | `CMD ["node", "server.js"]` |
| `ENTRYPOINT`  | Exécutable principal (PID 1) ; les arguments de `run` s'y ajoutent | `ENTRYPOINT ["nginx", "-g", "daemon off;"]` |
| `HEALTHCHECK` | Vérification périodique de santé | `HEALTHCHECK --interval=30s CMD curl -f http://localhost/ \|\| exit 1` |
| `STOPSIGNAL`  | Signal d'arrêt (SIGTERM par défaut) | `STOPSIGNAL SIGQUIT` |
| `SHELL`       | Shell par défaut des formes shell | `SHELL ["powershell", "-Command"]` |

- Préférer la **forme exec** (`["exe", "arg"]`) pour `CMD` / `ENTRYPOINT`.
- `ENTRYPOINT` + `CMD` : ENTRYPOINT = exécutable, CMD = arguments par défaut.
- Surcharger l'entrypoint : `docker run --entrypoint <exe> <image>`.

### Build multi-étapes

```dockerfile
FROM node:18 AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

### .dockerignore

Exclut des fichiers du contexte de build (taille, vitesse, secrets) :

```
node_modules
*.log
.env
.env.*
.git
```

---

## 4. Gestion des conteneurs

### Cycle de vie

```
create ──> Created ──start──> Running ──stop──> Stopped ──rm──> Deleted
                                 │  ▲
                           pause │  │ unpause
                                 ▼  │
                                Paused
run = create + start
```

```bash
docker create --name c1 ubuntu         # créer sans démarrer
docker start c1                        # démarrer (ou redémarrer un conteneur stoppé)
docker run ubuntu                      # create + start (pull automatique si absente)
docker pause c1 / docker unpause c1    # suspendre / reprendre les processus
docker stop c1                         # SIGTERM puis SIGKILL après délai de grâce
docker restart c1
docker kill c1                         # SIGKILL immédiat
docker rm c1                           # supprimer un conteneur arrêté
docker rm -f c1                        # forcer (arrête puis supprime)
docker container prune                 # supprimer tous les conteneurs stoppés
docker container rename c1 c2
```

### Lancer un conteneur

```bash
docker run -it ubuntu:latest bash      # mode interactif (attaché)
docker run -d postgres                 # mode détaché (arrière-plan)
docker run --rm -it ubuntu sleep 5     # supprimé automatiquement à l'arrêt
```

| Option | Rôle |
|--------|------|
| `--name <nom>` | Nommer le conteneur |
| `-d`, `--detach` | Arrière-plan |
| `-it` | Interactif + terminal |
| `--rm` | Suppression automatique à l'arrêt |
| `-p hôte:conteneur` | Publier un port (`-p 1234:1234/udp` pour UDP) |
| `-e CLE=valeur` / `--env-file f` | Variables d'environnement |
| `-v source:/chemin[:ro]` | Monter un volume ou un dossier |
| `--network <réseau>` | Choisir le réseau |
| `-m`, `--memory 512m` | Limite mémoire |
| `--cpus 1.5` | Limite CPU |
| `--cpu-shares 512` | Priorité CPU relative (défaut 1024) |
| `--restart <politique>` | `no` (défaut), `on-failure[:N]`, `always`, `unless-stopped` |

### Exemple complet

```bash
docker run -d \
  --name nginx-container \
  --restart unless-stopped \
  --health-cmd="curl -f http://localhost/ || exit 1" \
  --health-interval=30s --health-timeout=10s \
  --health-retries=3 --health-start-period=5s \
  --log-driver=json-file --log-opt max-size=10m --log-opt max-file=3 \
  -p 80:80 \
  nginx
```

### Lister et interagir

```bash
docker ps                              # conteneurs actifs
docker ps -a                           # tous, y compris arrêtés
docker container ls -as                # tous + taille
docker attach c1                       # se rattacher à un conteneur détaché
# Ctrl+P puis Ctrl+Q                   # se détacher sans arrêter le conteneur
# Ctrl+D (ou exit)                     # quitter le shell principal => arrêt du conteneur
docker exec -it c1 bash                # ouvrir un shell supplémentaire dans le conteneur
docker cp c1:/chemin/conteneur /chemin/hote    # copie conteneur -> hôte
docker cp /chemin/hote c1:/chemin/conteneur    # copie hôte -> conteneur (-L pour suivre les liens)
```

---

## 5. Troubleshooting et supervision

```bash
docker logs c1                         # logs du conteneur (conservés toute sa vie)
docker logs -f c1                      # suivre en temps réel
docker logs --tail 100 --since 10m c1  # dernières lignes / période
docker exec -it c1 sh                  # entrer dans le conteneur pour diagnostiquer
docker top c1                          # processus du conteneur
docker stats                           # CPU / mémoire / réseau / IO en temps réel
docker container inspect c1            # configuration détaillée (réseau, volumes, env, état…)
docker diff c1                         # Afficher ce qui a été modifié sur le conteneur
docker inspect -f '{{.State.Health.Status}}' c1              # état de santé
docker inspect -f '{{.State.ExitCode}}' c1                   # code de sortie
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' c1   # IP
docker events                          # flux d'événements du moteur
docker system df                       # espace disque utilisé par Docker
docker system prune                    # nettoyage global (conteneurs, réseaux, images dangling)
```

Démarche type quand un conteneur ne démarre pas :

1. `docker ps -a` → statut et code de sortie
2. `docker logs <c>` → message d'erreur
3. `docker inspect <c>` → commande, env, montages, ports
4. `docker run --rm -it --entrypoint sh <image>` → explorer l'image à la main

### Debug réseau avec netshoot

Les images de production (alpine, distroless, slim) n'embarquent généralement ni `curl`, ni `ping`, ni `dig`.
Plutôt que de les installer dans le conteneur cible, on lance à côté un conteneur jetable
[`nicolaka/netshoot`](https://github.com/nicolaka/netshoot) qui contient tous les outils réseau
(`curl`, `dig`, `nslookup`, `ping`, `nc`, `ss`, `ip`, `tcpdump`, `iperf3`, `mtr`, `nmap`, `termshark`…).

```bash
# Se placer dans la pile réseau d'un conteneur existant (même IP, mêmes ports, même DNS)
docker run --rm -it --network container:c1 nicolaka/netshoot

# ... et voir aussi ses processus
docker run --rm -it --network container:c1 --pid container:c1 nicolaka/netshoot

# Rejoindre un réseau Docker pour tester la résolution DNS et la connectivité entre services
docker run --rm -it --network training nicolaka/netshoot

# Diagnostiquer depuis la pile réseau de l'hôte
docker run --rm -it --network host nicolaka/netshoot

# Commande ponctuelle sans shell interactif
docker run --rm --network training nicolaka/netshoot dig database
```

Commandes utiles une fois dans netshoot :

```bash
ip addr / ip route                     # interfaces, IP, passerelle
cat /etc/resolv.conf                   # serveur DNS utilisé (127.0.0.11 = DNS embarqué Docker)
dig database / nslookup database       # résolution d'un nom de conteneur / service
ping database                          # connectivité ICMP
nc -zv database 5432                   # le port est-il ouvert ?
curl -v http://app:5000/               # tester une API HTTP
ss -tulpn                              # ports en écoute (avec --network container:c1)
tcpdump -i eth0 port 5432              # capturer le trafic
tcpdump -i eth0 -w /tmp/c1.pcap        # capturer dans un fichier (à récupérer avec docker cp)
iperf3 -s / iperf3 -c <ip>             # débit entre deux conteneurs
```

Avec Docker Compose, on peut ajouter un service de debug qui partage le réseau d'un autre service :

```yaml
  netshoot:
    image: nicolaka/netshoot
    network_mode: "service:app"          # même pile réseau que le service app
    command: sleep infinity
```

```bash
docker compose exec netshoot bash
```

Monitoring avec **cAdvisor** (interface sur `http://localhost:8080`) :

```yaml
cadvisor:
  image: gcr.io/cadvisor/cadvisor:latest
  ports:
    - "8080:8080"
  volumes:
    - /:/rootfs:ro
    - /var/run:/var/run:rw
    - /sys:/sys:ro
    - /var/lib/docker/:/var/lib/docker:ro
```

---

## 6. Gestion des réseaux

| Type | Usage |
|------|-------|
| `bridge` | Par défaut, mono-hôte (interface `docker0`, 172.17.0.0/16) |
| bridge personnalisé | Isoler des groupes de conteneurs, **DNS par nom de conteneur** |
| `host` | Pas d'isolation réseau, performances max |
| `overlay` | Multi-hôtes (Swarm) |
| `macvlan` / `ipvlan` | Conteneur visible directement sur le réseau physique |
| `none` | Aucun réseau |

```bash
docker network ls
docker network create training                       # bridge personnalisé
docker network create -d <driver> <nom>
docker network inspect training
docker network connect training c2                   # ajouter un conteneur existant
docker network disconnect training c2
docker network rm training
docker network prune

docker run -d --name c1 --network training nginx
docker run -d --network host nginx
docker run -d --network none mon-image

# macvlan
docker network create -d macvlan --subnet=192.168.1.0/24 \
  --gateway=192.168.1.1 -o parent=eth0 mon-reseau-macvlan
docker run --network mon-reseau-macvlan --ip 192.168.1.100 nginx
```

Publication de ports :

```bash
docker run -d -p 6543:5432 -e POSTGRES_USER=training -e POSTGRES_PASSWORD=training \
  -e POSTGRES_DB=training --name mydb postgres
psql -U training -h localhost -p 6543 -W training
```

---

## 7. Gestion des volumes

```bash
docker volume create mon_volume
docker volume ls
docker volume inspect mon_volume
docker volume rm mon_volume
docker volume prune                    # supprime les volumes inutilisés

docker run -d -v mon_volume:/chemin/complet ubuntu          # volume nommé (persistant)
docker run -it -v /tmp/myfolder:/myfolder:ro ubuntu bash    # bind mount (lecture seule avec :ro)
docker run -d -v /myfolder --name m1 ubuntu sleep infinity  # volume anonyme
docker run -it --volumes-from m1 --name m2 ubuntu bash      # partager les volumes de m1

# Volume en RAM (tmpfs, 100 Mo)
docker volume create --driver local --opt type=tmpfs --opt device=tmpfs --opt o=size=100m my_tmpfs
```

Stockage par défaut des volumes : `/var/lib/docker/volumes/`.

---

## 8. Docker Compose

```bash
docker compose up -d                   # créer et démarrer tous les services
docker compose up -d --build           # reconstruire les images avant
docker compose ps                      # lister les services
docker compose logs -f <service>
docker compose exec <service> sh
docker compose stop <service>          # arrêter un service
docker compose start <service>
docker compose restart <service>
docker compose down                    # arrêter et supprimer conteneurs + réseaux
docker compose down -v                 # ... et les volumes
docker compose config                  # afficher le fichier résolu (variables interpolées)
docker compose --env-file .env.prod up -d
```

Squelette :

```yaml
volumes:
  db-data:

services:
  database:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}   # interpolé depuis .env
    volumes:
      - db-data:/var/lib/postgresql/data
    ports:
      - "5432:5432"

  app:
    build: ./flask
    depends_on:
      - database
    ports:
      - "5000:5000"
```

Le fichier `.env` (à côté du `docker-compose.yml`) contient des paires `CLE=valeur` utilisables via `${CLE}`.

---

## 9. Sécurité

```bash
docker run --user 1000 nginx                         # ne pas tourner en root
docker run --read-only alpine                        # système de fichiers en lecture seule
docker run --cap-drop ALL --cap-add NET_ADMIN alpine # capacités Linux minimales
docker run --security-opt no-new-privileges alpine   # options de sécurité
docker run --privileged alpine                       # accès total à l'hôte : à éviter
```

Bonnes pratiques :

- Images officielles, tags précis (pas `latest`), voire digest `image@sha256:...`
- Scanner les images (Trivy, Clair, Docker Scout)
- Builds multi-étapes pour réduire la surface d'attaque
- `USER` non-root dans le Dockerfile, `HEALTHCHECK`
- Aucun secret dans le Dockerfile ni dans l'image (`.dockerignore`, gestionnaire de secrets)
- Montages en lecture seule (`:ro`) quand c'est possible

### Mode rootless

```bash
grep CONFIG_USER_NS /boot/config-$(uname -r)   # vérifier les user namespaces
sudo apt install -y uidmap
dockerd-rootless-setuptool.sh install
export DOCKER_HOST=unix:///run/user/1000/docker.sock
sudo loginctl enable-linger $USER

sudo systemctl stop docker
systemctl --user start docker
systemctl --user enable docker
```

Limites : pas de `--privileged`, ports < 1024 inaccessibles par défaut, réseaux limités.

---

## 10. Nettoyage rapide

```bash
docker container prune                 # conteneurs arrêtés
docker image prune                     # images dangling
docker image prune -a                  # toutes les images non utilisées
docker volume prune                    # volumes non utilisés
docker network prune                   # réseaux non utilisés
docker system prune -a --volumes       # tout (attention !)
```
