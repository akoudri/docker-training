# Déploiement sur AWS (ECR + ECS Fargate)

Objectif : pousser une image Docker dans un registre privé (**ECR**) puis l'exécuter sur **ECS Fargate**, sans gérer de serveur.

Deux parcours sont proposés, entièrement en ligne de commande :

1. **Pas à pas, avec la CLI AWS** : chaque brique (registre, rôle, cluster, définition de tâche, service) est créée par une commande explicite. Le script [`ecs.sh`](ecs.sh) les enchaîne et permet de déployer **plusieurs applications** du dépôt côte à côte (`nginx`, `flask`, `react-2048`…).
2. **Déclaratif, avec Terraform** : la même infrastructure décrite en code, pour une seule application (par défaut [`../nginx`](../nginx)).

**N'utilisez qu'un parcours à la fois** et faites le nettoyage avant de passer à l'autre : `./ecs.sh destroy_all` supprime aussi les ressources créées par Terraform, ce qui désynchroniserait son état.

> ⚠️ **Coûts** : un service Fargate est facturé tant qu'il tourne. Pensez à faire le [nettoyage](#4-nettoyage) en fin de TP.

---

## 1. Prérequis (communs aux deux parcours)

### 1.1 Client AWS

Installer la CLI AWS v2, **version 2.32 ou plus récente** (`aws --version`) :

- Ubuntu : `./aws-cli-install.sh`
- Autres systèmes : https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

### 1.2 Utilisateur de formation (une fois, par un administrateur du compte)

```bash
aws login --profile admin --region eu-west-3     # session d'un administrateur du compte
AWS_PROFILE=admin ./setup-iam.sh create formation
```

Le script crée :

- la politique `docker-training-policy` ([`iam-policy.json`](iam-policy.json)) : droits limités à ECR, ECS, CloudWatch Logs, aux security groups et aux seuls rôles IAM `docker-training-*` ;
- l'utilisateur `formation`, avec cette politique, `SignInLocalDevelopmentAccess` (nécessaire pour `aws login`) et `IAMUserChangePassword` ;
- un mot de passe console temporaire, affiché à l'écran, à changer à la première connexion ;
- le **VPC par défaut** de la région s'il n'existe pas (il a pu être supprimé, ou ne jamais avoir existé sur un compte créé via AWS Organizations). Les deux parcours y déploient le conteneur.

Évitez de faire le TP avec le compte *root* ou un compte administrateur.

### 1.3 Authentification

```bash
aws login --profile training --region eu-west-3   # ouvre le navigateur : se connecter avec l'utilisateur "formation"
export AWS_PROFILE=training                       # pris en compte par la CLI, les scripts et Terraform
aws sts get-caller-identity                       # vérifie l'identité utilisée
```

La session dure 12 h. Sur une machine sans navigateur (VM distante, SSH), ajouter `--remote` : la CLI affiche une URL à ouvrir ailleurs, puis demande le code obtenu.

Le profil nommé (`--profile training`) évite l'erreur `Profile 'default' is already configured with Access Key credentials` si une clé d'accès est déjà configurée sur le poste. Pensez à refaire l'`export` dans chaque nouveau terminal.

> **Pourquoi pas une clé d'accès ?** Une clé d'accès (`aws configure`) est un identifiant **permanent** stocké en clair dans `~/.aws/credentials` : si elle fuit (commit, poste partagé), elle reste utilisable jusqu'à sa révocation. `aws login` ne fournit que des identifiants **temporaires**, renouvelés automatiquement. AWS recommande d'ailleurs cette méthode à l'écran de création d'une clé.

---

## 2. Parcours pas à pas (CLI AWS)

### 2.1 Commandes

```bash
./ecs.sh deploy nginx              # déploie le dossier ../nginx, version 1.0
./ecs.sh deploy flask              # une deuxième application, à côté de la première (port 5000)
./ecs.sh deploy nginx 1.1          # nouvelle version : nouvelle révision de tâche + redéploiement
./ecs.sh deploy ../../docker-training-solutions/react-2048 2048-1.0   # un dossier hors du dépôt
./ecs.sh list                      # applications déployées, tâches en cours, révision, URL
./ecs.sh url nginx                 # http://<ip-publique>
./ecs.sh logs nginx                # équivalent de "docker logs -f" (Ctrl+C pour quitter)
./ecs.sh destroy nginx             # supprime une application
./ecs.sh destroy_all               # supprime toutes les applications et les ressources partagées
```

- **Application** : un dossier à la racine du dépôt contenant un `Dockerfile`, ou le chemin d'un tel dossier. Le nom du dossier devient le nom de l'application.
- **Port** : le dernier `EXPOSE` du Dockerfile (80 par défaut). Pour le forcer : `PORT=8080 ./ecs.sh deploy ...`.
- **Ressources** : chaque application a son registre, sa définition de tâche, son service, son security group et ses logs. Le cluster et le rôle d'exécution sont partagés.

| Ressource | Nom (application `nginx`) | Portée |
|-----------|---------------------------|--------|
| Registre ECR | `docker-training/nginx` | application |
| Groupe de logs | `/ecs/docker-training/nginx` | application |
| Security group | `docker-training-nginx-sg` | application |
| Définition de tâche | `docker-training-nginx` | application |
| Service ECS | `nginx` | application |
| Cluster ECS | `docker-training-cluster` | partagée |
| Rôle d'exécution IAM | `docker-training-task-execution` | partagée |

Chaque étape vérifie d'abord si la ressource existe : le script peut être relancé sans risque.
En cas d'erreur, il s'arrête en affichant `ÉCHEC : la commande ligne ... a échoué` : corriger la cause, puis relancer la même commande.

Sortie attendue de `./ecs.sh deploy nginx` (2 à 4 minutes) :

```
Profil : training | Région : eu-west-3
Application : nginx (/.../docker-training/nginx) | version 1.0 | port 80
==> Registre ECR : docker-training/nginx
==> Build et push de l'image docker-training/nginx:1.0
...
==> Rôle d'exécution IAM (partagé) : docker-training-task-execution
==> Groupe de logs CloudWatch : /ecs/docker-training/nginx
==> Security group docker-training-nginx-sg (port 80 ouvert)
==> Cluster ECS (partagé) : docker-training-cluster
==> Définition de tâche docker-training-nginx (nouvelle révision)
docker-training-nginx:1
==> Service ECS : nginx
==> Attente de la stabilisation du service (1 à 3 minutes)
==> Application nginx disponible
http://15.236.xx.xx
```

Vérifier :

```bash
curl -i $(./ecs.sh url nginx)      # HTTP/1.1 200 OK + page nginx
./ecs.sh list
```

> **Suppression** : `destroy` attend l'arrêt des tâches, puis la libération de leur interface réseau par AWS avant de supprimer le security group. Cette dernière étape prend souvent **3 à 5 minutes** : c'est normal.

### 2.2 Ce que fait le script

Les commandes ci-dessous sont celles exécutées par `ecs.sh deploy nginx` (simplifiées) ; on peut aussi les lancer une par une pour observer chaque étape.

```bash
export AWS_REGION=eu-west-3
APP=nginx
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export DOCKER_REGISTRY=$ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com
```

**1. Registre privé (ECR)** et envoi de l'image :

```bash
aws ecr create-repository --repository-name docker-training/$APP --image-scanning-configuration scanOnPush=true
REPOSITORY=docker-training/$APP ./push-docker.sh 1.0 ../$APP   # build linux/amd64 + docker login + docker push
aws ecr describe-images --repository-name docker-training/$APP  # images présentes
aws ecr describe-image-scan-findings --repository-name docker-training/$APP --image-id imageTag=1.0
```

`push-docker.sh` fait l'équivalent de :

```bash
docker build --platform linux/amd64 -t $DOCKER_REGISTRY/docker-training/$APP:1.0 ../$APP
aws ecr get-login-password | docker login --username AWS --password-stdin $DOCKER_REGISTRY
docker push $DOCKER_REGISTRY/docker-training/$APP:1.0
```

> `--platform linux/amd64` est indispensable sur un Mac Apple Silicon : Fargate exécute par défaut des conteneurs x86_64, et une image `arm64` ne démarrerait pas (`exec format error`).

**2. Rôle d'exécution** (partagé) : autorise ECS à tirer les images et à écrire les logs.

```bash
aws iam create-role --role-name docker-training-task-execution --assume-role-policy-document \
  '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
aws iam attach-role-policy --role-name docker-training-task-execution \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
```

**3. Logs** :

```bash
aws logs create-log-group --log-group-name /ecs/docker-training/$APP
aws logs put-retention-policy --log-group-name /ecs/docker-training/$APP --retention-in-days 7
```

**4. Réseau** : VPC par défaut, et un security group qui ouvre le port de l'application. Sans cette règle, le conteneur tourne mais n'est pas joignable.

Si la région n'a pas de VPC par défaut (`describe-vpcs` renvoie `None`), le créer une fois avec un profil administrateur : `aws ec2 create-default-vpc` (fait automatiquement par `setup-iam.sh`).

```bash
VPC=$(aws ec2 describe-vpcs --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text)
SUBNETS=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC --query 'Subnets[].SubnetId' --output text | tr '\t' ',')
SG=$(aws ec2 create-security-group --group-name docker-training-$APP-sg --vpc-id $VPC \
  --description "Acces HTTP" --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id $SG --protocol tcp --port 80 --cidr 0.0.0.0/0
```

**5. Cluster** (partagé) :

```bash
aws ecs create-cluster --cluster-name docker-training-cluster
```

**6. Définition de tâche** : [`taskdef.template.json`](taskdef.template.json) décrit le conteneur (image, port, CPU/mémoire, logs). `envsubst` remplace les variables `${...}`.

```bash
FAMILY=docker-training-$APP PORT=80 LOG_GROUP=/ecs/docker-training/$APP \
IMAGE=$DOCKER_REGISTRY/docker-training/$APP:1.0 \
EXECUTION_ROLE_ARN=arn:aws:iam::$ACCOUNT:role/docker-training-task-execution \
  envsubst < taskdef.template.json > /tmp/taskdef.json
aws ecs register-task-definition --cli-input-json file:///tmp/taskdef.json
```

Chaque `register-task-definition` crée une nouvelle **révision** (`docker-training-nginx:1`, `:2`…).

> Passer le JSON par un fichier, et non par un pipe (`envsubst ... | aws ... file:///dev/stdin`) : la CLI installée via snap lit alors un contenu vide et répond `Invalid JSON received`.

**7. Service** : maintient une tâche en vie, avec une IP publique.

```bash
aws ecs create-service --cluster docker-training-cluster --service-name $APP \
  --task-definition docker-training-$APP --desired-count 1 --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SG],assignPublicIp=ENABLED}"
aws ecs wait services-stable --cluster docker-training-cluster --services $APP
```

Pour une nouvelle version : enregistrer une nouvelle révision, puis
`aws ecs update-service --cluster docker-training-cluster --service $APP --task-definition docker-training-$APP`.

### 2.3 En cas de problème

```bash
# Pourquoi la dernière tâche de l'application s'est-elle arrêtée ?
TASK=$(aws ecs list-tasks --cluster docker-training-cluster --service-name $APP --desired-status STOPPED \
  --query 'taskArns[0]' --output text)
aws ecs describe-tasks --cluster docker-training-cluster --tasks $TASK \
  --query 'tasks[0].{raison:stoppedReason,conteneur:containers[0].reason,code:containers[0].exitCode}'

# Événements du service (placement, déploiement, erreurs)
aws ecs describe-services --cluster docker-training-cluster --services $APP \
  --query 'services[0].events[:5].message'

./ecs.sh logs $APP                 # sortie du conteneur
```

| Symptôme | Piste |
|----------|-------|
| `InvalidParameterValue` sur `DescribeSecurityGroups` (`vpc-id`), ou « Aucun VPC par défaut » | La région n'a pas de VPC par défaut : `aws ec2 create-default-vpc` avec un profil administrateur |
| « Cluster introuvable » ou « Application non déployée » | Le déploiement ne s'est pas terminé (relancer `./ecs.sh deploy <application>`), ou mauvais profil/région (voir la ligne `Profil : ... \| Région : ...`) |
| `destroy` bloqué sur « libération de l'interface réseau » | Normal pendant 3 à 5 min ; au-delà de 10 min, le script s'arrête : relancer la même commande plus tard |
| `Invalid JSON received` sur `register-task-definition` | JSON passé via `/dev/stdin` avec la CLI snap : utiliser un fichier |
| `CannotPullContainerError` | Nom ou tag d'image incorrect, ou rôle d'exécution manquant |
| `exec format error` dans les logs | Image construite pour `arm64` : reconstruire avec `--platform linux/amd64` |
| `ECS was unable to assume the role` | Rôle tout juste créé, pas encore propagé : relancer `./ecs.sh deploy <application>` |
| Tâche `RUNNING` mais page inaccessible | Le port écouté par l'application diffère de celui du Dockerfile : redéployer avec `PORT=...` |
| `AccessDenied` sur une action | Action absente de `iam-policy.json` : l'ajouter, puis `aws iam create-policy-version ... --set-as-default` |

---

## 3. Parcours automatisé (Terraform)

Le dossier [`terraform/`](terraform) décrit la même infrastructure que le parcours CLI, pour une seule application :

| Ressource | Rôle |
|-----------|------|
| `aws_ecr_repository` | Registre privé, scan des images à l'envoi |
| `aws_security_group` | Ouvre le port de l'application dans le VPC par défaut |
| `aws_iam_role` | Rôle d'exécution (tirer l'image, écrire les logs) |
| `aws_cloudwatch_log_group` | Logs du conteneur, conservés 7 jours |
| `aws_ecs_cluster`, `aws_ecs_task_definition`, `aws_ecs_service` | Exécution sur Fargate avec IP publique |

Prérequis supplémentaires : [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.5, `make`, Docker.
Le provider AWS utilisé (≥ 6.23) reconnaît directement les sessions ouvertes avec `aws login`.

### 3.1 Déployer

```bash
cd terraform
make deploy                 # registre ECR -> build & push de l'image -> déploiement -> affichage de l'URL
```

`make deploy` enchaîne quatre étapes, que l'on peut aussi lancer une par une :

| Commande | Action |
|----------|--------|
| `make registry` | `terraform init` puis création du seul dépôt ECR (il doit exister avant le push) |
| `make push` | Build `linux/amd64`, login et push via `../push-docker.sh` |
| `make apply` | Création du reste de l'infrastructure (Terraform demande confirmation) |
| `make url` | Affiche `http://<ip-publique>` du conteneur |

Options :

```bash
make deploy VERSION=1.1                 # déployer une nouvelle version de l'image
make deploy CONTEXT=../../flask         # déployer une autre image (Flask : mettre container_port = 5000 dans terraform.tfvars)
```

Pour changer la région, le nom du projet ou le port, copier `terraform.tfvars.example` en `terraform.tfvars` et l'adapter.
Si vous changez `project`, adaptez aussi le préfixe `docker-training-*` dans [`iam-policy.json`](iam-policy.json).

### 3.2 Observer

```bash
make url                    # adresse publique du conteneur
make logs                   # équivalent de "docker logs -f", via CloudWatch
terraform output            # registre, cluster, service...
terraform state list        # ressources gérées par Terraform
```

---

## 4. Nettoyage

**Terraform** :

```bash
cd terraform
make destroy                # supprime toutes les ressources, images ECR comprises
```

**CLI** :

```bash
./ecs.sh destroy nginx      # une application : service, révisions, logs, registre, security group
./ecs.sh destroy_all        # toutes les applications + cluster et rôle d'exécution partagés
```

`destroy_all` supprime toutes les ressources dont le nom commence par `docker-training`, y compris celles d'applications oubliées.

**Session et utilisateur** :

```bash
aws logout --profile training
AWS_PROFILE=admin ./setup-iam.sh delete formation   # en fin de formation : utilisateur et politique
```
