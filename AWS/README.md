# Instructions

## Préalable

- Installer le client AWS sur votre machine
    - Exécuter le script *aws-cli-install.sh" si vous êtes sur ubuntu
- Créer un utilisateur avec les droits suivants(Servie IAM):
    - AmazonEC2ContainerRegistryFullAccess
    - AmazonECS_FullAccess
- Créer une clef d'accès pour le cas d'usage **CLI**
    - Enregistrer le couple access key / secret access key

## Installation de l'image docker dans un registre privé - Service ECR

- Créer un registre docker privé "docker-training"
    - Laisser les paramètres par défaut
    - Enregistrer l'URI du registre (en enlevant la dernière composante) dans la variable d'environnement DOCKER_REGISTRY
- Créer l'image docker à pousser en respectant la convention de nommage suivante:
    - *DOCKER_REGISTRY_URI*/docker-training:*APP_VERSION*
- Lancer la commande "aws config" et entrer les informations demandées
    - Pour la région, entrer la région du cluster (exple: eu-west-3)
- Loguer vous sur votre registre
    - aws ecr get-login-password | docker login --username AWS --password-stdin $DOCKER_REGISTRY
- Pousser votre image
    - docker push $DOCKER_REGISTRY/docker-training:*APP_VERSION* 
- Observer le résultat sur l'interface web AWS

## Instanciation d'un conteneur - Service ECS

- Créer un cluster "ProdCluster"​
    - Sélectionner Fargate comme infrastucture
    - Laisser les paramètres par défaut
- Créer ensuite une tâche
    - Sélectionner "Create new task definition with JSON"
    - Adapter le fichier taskdef.json et copier / coller le contenu dans l'interface de spécification de la tâche"
- Créer un service
    - Retourner ensuite sur le cluster
    - Dans "Deployment Configuration", sélectionner la famille et la révision
    - Donner un nom au service
    - Laisser les autres paramètres par défaut
    - Exécuter et observer le résultat

