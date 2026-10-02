#!/usr/bin/env bash
# Déploiement d'applications sur ECS Fargate avec la seule CLI AWS.
#
# Usage :
#   ./ecs.sh deploy <application> [version]   construit, pousse et (re)déploie l'application
#   ./ecs.sh list                             liste les applications déployées et leur URL
#   ./ecs.sh url <application>                affiche l'URL publique de l'application
#   ./ecs.sh logs <application>               suit les logs de l'application
#   ./ecs.sh destroy <application>            supprime les ressources de l'application
#   ./ecs.sh destroy_all                      supprime toutes les applications et les ressources partagées
#
# <application> : dossier à la racine du dépôt (nginx, flask, react-2048...) ou chemin
# vers un dossier contenant un Dockerfile. Le nom du dossier sert de nom d'application.
#
# Variables optionnelles :
#   AWS_REGION  défaut : région du profil, sinon eu-west-3
#   PORT        défaut : dernier EXPOSE du Dockerfile, sinon 80
#
# Chaque étape vérifie d'abord si la ressource existe : le script peut être relancé sans risque.
set -eEuo pipefail
trap 'echo "ÉCHEC : la commande ligne $LINENO a échoué (code $?) : $BASH_COMMAND" >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT="docker-training"
export AWS_REGION="${AWS_REGION:-$(aws configure get region || true)}"
export AWS_REGION="${AWS_REGION:-eu-west-3}"

# Ressources partagées par toutes les applications
CLUSTER="$PROJECT-cluster"
ROLE="$PROJECT-task-execution"
EXECUTION_POLICY="arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die()  { echo "$*" >&2; exit 1; }

# Ressources propres à une application : registre, définition de tâche, service, security group, logs
set_app() {
  APP=$(basename "$1" | tr '[:upper:]_' '[:lower:]-')
  REPOSITORY="$PROJECT/$APP"
  FAMILY="$PROJECT-$APP"
  SERVICE="$APP"
  SG_NAME="$PROJECT-$APP-sg"
  LOG_GROUP="/ecs/$PROJECT/$APP"
}

# Résout <application> en dossier de build : d'abord à la racine du dépôt, sinon comme chemin
set_app_dir() {
  if [ -d "$REPO_ROOT/$1" ]; then
    APP_DIR="$REPO_ROOT/$1"
  elif [ -d "$1" ]; then
    APP_DIR="$(cd "$1" && pwd)"
  else
    die "Application introuvable : $1 (ni $REPO_ROOT/$1, ni un dossier existant)"
  fi
  [ -f "$APP_DIR/Dockerfile" ] || die "Pas de Dockerfile dans $APP_DIR"
  set_app "$APP_DIR"
}

detect_port() {
  local port
  port=$(grep -iE '^[[:space:]]*EXPOSE[[:space:]]+[0-9]+' "$APP_DIR/Dockerfile" \
           | tail -1 | awk '{print $2}' | cut -d/ -f1 || true)
  echo "${port:-80}"
}

default_vpc() {
  aws ec2 describe-vpcs --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text
}

security_group_id() {
  aws ec2 describe-security-groups \
    --filters Name=vpc-id,Values="$1" Name=group-name,Values="$2" \
    --query 'SecurityGroups[0].GroupId' --output text
}

cluster_active() {
  [ "$(aws ecs describe-clusters --clusters "$CLUSTER" --query 'clusters[0].status' --output text)" = "ACTIVE" ]
}

service_active() {
  [ "$(aws ecs describe-services --cluster "$1" --services "$2" \
        --query 'services[0].status' --output text 2>/dev/null || echo None)" = "ACTIVE" ]
}

log_group_exists() {
  [ "$(aws logs describe-log-groups --log-group-name-prefix "$1" \
        --query "length(logGroups[?logGroupName=='$1'])" --output text)" != "0" ]
}

delete_security_group() {
  # Après l'arrêt d'une tâche, AWS met jusqu'à plusieurs minutes à libérer son interface réseau
  local waited=0
  while [ "$(aws ec2 describe-network-interfaces --filters Name=group-id,Values="$1" \
              --query 'length(NetworkInterfaces)' --output text)" != "0" ]; do
    [ "$waited" -lt 600 ] || die "Le security group $1 est toujours utilisé après 10 min : relancer la commande plus tard"
    echo "libération de l'interface réseau par AWS ($waited s, souvent 3 à 5 min)..."
    sleep 20
    waited=$((waited + 20))
  done
  aws ec2 delete-security-group --group-id "$1" >/dev/null
  echo "supprimé : $1"
}

# Supprime un service et attend qu'il soit inactif (ses tâches sont arrêtées)
delete_service() {
  local tasks
  if service_active "$CLUSTER" "$1"; then
    tasks=$(aws ecs list-tasks --cluster "$CLUSTER" --service-name "$1" --query 'taskArns[]' --output text)
    aws ecs delete-service --cluster "$CLUSTER" --service "$1" --force >/dev/null
    echo "service supprimé : $1"
    if [ -n "$tasks" ]; then
      echo "arrêt des tâches en cours..."
      # shellcheck disable=SC2086
      aws ecs wait tasks-stopped --cluster "$CLUSTER" --tasks $tasks
    fi
    aws ecs wait services-inactive --cluster "$CLUSTER" --services "$1"
  fi
}

deregister_task_definitions() {
  local arn
  for arn in $(aws ecs list-task-definitions --family-prefix "$1" --status ACTIVE \
                 --query 'taskDefinitionArns[]' --output text); do
    aws ecs deregister-task-definition --task-definition "$arn" >/dev/null
    echo "révision désenregistrée : ${arn##*/}"
  done
}

service_url() {
  local task eni ip
  task=$(aws ecs list-tasks --cluster "$CLUSTER" --service-name "$1" --desired-status RUNNING \
    --query 'taskArns[0]' --output text)
  [ "$task" != "None" ] || { echo "(aucune tâche en cours)"; return; }
  eni=$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$task" \
    --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value" --output text)
  ip=$(aws ec2 describe-network-interfaces --network-interface-ids "$eni" \
    --query 'NetworkInterfaces[0].Association.PublicIp' --output text)
  local port
  port=$(task_port "$task")
  if [ "$port" = "80" ]; then echo "http://$ip"; else echo "http://$ip:$port"; fi
}

task_port() {
  local taskdef
  taskdef=$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$1" \
    --query 'tasks[0].taskDefinitionArn' --output text)
  aws ecs describe-task-definition --task-definition "$taskdef" \
    --query 'taskDefinition.containerDefinitions[0].portMappings[0].containerPort' --output text
}

require_cluster() {
  cluster_active || die "Cluster $CLUSTER introuvable dans la région $AWS_REGION : lancer d'abord ./ecs.sh deploy <application>"
}

# ---------------------------------------------------------------------------

cmd_deploy() {
  [ -n "${1:-}" ] || die "Usage : ./ecs.sh deploy <application> [version]"
  set_app_dir "$1"
  local version="${2:-1.0}" port="${PORT:-$(detect_port)}"
  local account registry vpc subnets sg taskdef_file taskdef_arn

  account=$(aws sts get-caller-identity --query Account --output text)
  registry="$account.dkr.ecr.$AWS_REGION.amazonaws.com"
  echo "Application : $APP ($APP_DIR) | version $version | port $port"

  step "Registre ECR : $REPOSITORY"
  if ! aws ecr describe-repositories --repository-names "$REPOSITORY" >/dev/null 2>&1; then
    aws ecr create-repository --repository-name "$REPOSITORY" \
      --image-scanning-configuration scanOnPush=true >/dev/null
  fi

  step "Build et push de l'image $REPOSITORY:$version"
  DOCKER_REGISTRY="$registry" REPOSITORY="$REPOSITORY" "$SCRIPT_DIR/push-docker.sh" "$version" "$APP_DIR"

  step "Rôle d'exécution IAM (partagé) : $ROLE"
  if ! aws iam get-role --role-name "$ROLE" >/dev/null 2>&1; then
    aws iam create-role --role-name "$ROLE" --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [{"Effect": "Allow", "Principal": {"Service": "ecs-tasks.amazonaws.com"}, "Action": "sts:AssumeRole"}]
    }' >/dev/null
    aws iam attach-role-policy --role-name "$ROLE" --policy-arn "$EXECUTION_POLICY"
    # Un rôle IAM tout juste créé met quelques secondes à être utilisable par ECS
    aws iam wait role-exists --role-name "$ROLE"
    sleep 10
  fi

  step "Groupe de logs CloudWatch : $LOG_GROUP"
  if ! log_group_exists "$LOG_GROUP"; then
    aws logs create-log-group --log-group-name "$LOG_GROUP"
    aws logs put-retention-policy --log-group-name "$LOG_GROUP" --retention-in-days 7
  fi

  step "Security group $SG_NAME (port $port ouvert)"
  vpc=$(default_vpc)
  if [ "$vpc" = "None" ]; then
    die "Aucun VPC par défaut dans la région $AWS_REGION.
Le créer une fois, avec un profil administrateur :
  AWS_PROFILE=admin aws ec2 create-default-vpc --region $AWS_REGION"
  fi
  subnets=$(aws ec2 describe-subnets --filters Name=vpc-id,Values="$vpc" \
    --query 'Subnets[].SubnetId' --output text | tr '\t' ',')
  sg=$(security_group_id "$vpc" "$SG_NAME")
  if [ "$sg" = "None" ]; then
    sg=$(aws ec2 create-security-group --group-name "$SG_NAME" --vpc-id "$vpc" \
      --description "Acces HTTP a $APP" --query GroupId --output text)
  fi
  if [ "$(aws ec2 describe-security-groups --group-ids "$sg" \
        --query "length(SecurityGroups[0].IpPermissions[?FromPort==\`$port\`])" --output text)" = "0" ]; then
    aws ec2 authorize-security-group-ingress --group-id "$sg" \
      --protocol tcp --port "$port" --cidr 0.0.0.0/0 >/dev/null
  fi

  step "Cluster ECS (partagé) : $CLUSTER"
  if ! cluster_active; then
    aws ecs create-cluster --cluster-name "$CLUSTER" >/dev/null
  fi

  step "Définition de tâche $FAMILY (nouvelle révision)"
  # Passer par un fichier : la CLI installée via snap ne sait pas lire file:///dev/stdin
  taskdef_file=$(mktemp)
  FAMILY="$FAMILY" APP="$APP" PORT="$port" LOG_GROUP="$LOG_GROUP" \
  IMAGE="$registry/$REPOSITORY:$version" EXECUTION_ROLE_ARN="arn:aws:iam::$account:role/$ROLE" \
    envsubst '${FAMILY} ${APP} ${IMAGE} ${PORT} ${LOG_GROUP} ${AWS_REGION} ${EXECUTION_ROLE_ARN}' \
    < "$SCRIPT_DIR/taskdef.template.json" > "$taskdef_file"
  taskdef_arn=$(aws ecs register-task-definition --cli-input-json "file://$taskdef_file" \
    --query 'taskDefinition.taskDefinitionArn' --output text)
  rm -f "$taskdef_file"
  echo "${taskdef_arn##*/}"

  step "Service ECS : $SERVICE"
  if service_active "$CLUSTER" "$SERVICE"; then
    aws ecs update-service --cluster "$CLUSTER" --service "$SERVICE" \
      --task-definition "$taskdef_arn" --force-new-deployment >/dev/null
  else
    aws ecs create-service --cluster "$CLUSTER" --service-name "$SERVICE" \
      --task-definition "$taskdef_arn" --desired-count 1 --launch-type FARGATE \
      --network-configuration "awsvpcConfiguration={subnets=[$subnets],securityGroups=[$sg],assignPublicIp=ENABLED}" \
      >/dev/null
  fi

  step "Attente de la stabilisation du service (1 à 3 minutes)"
  aws ecs wait services-stable --cluster "$CLUSTER" --services "$SERVICE"

  step "Application $APP disponible"
  service_url "$SERVICE"
}

cmd_list() {
  local arn name status running desired taskdef
  require_cluster
  printf '%-20s %-10s %-8s %-28s %s\n' APPLICATION STATUT TÂCHES RÉVISION URL
  for arn in $(aws ecs list-services --cluster "$CLUSTER" --query 'serviceArns[]' --output text); do
    name=${arn##*/}
    read -r status running desired taskdef < <(aws ecs describe-services --cluster "$CLUSTER" --services "$name" \
      --query 'services[0].[status,runningCount,desiredCount,taskDefinition]' --output text)
    printf '%-20s %-10s %-8s %-28s %s\n' "$name" "$status" "$running/$desired" "${taskdef##*/}" "$(service_url "$name")"
  done
}

cmd_url() {
  [ -n "${1:-}" ] || die "Usage : ./ecs.sh url <application>"
  set_app "$1"
  require_cluster
  service_active "$CLUSTER" "$SERVICE" || die "Application $APP non déployée (voir ./ecs.sh list)"
  service_url "$SERVICE"
}

cmd_logs() {
  [ -n "${1:-}" ] || die "Usage : ./ecs.sh logs <application>"
  set_app "$1"
  log_group_exists "$LOG_GROUP" || die "Aucun log pour $APP (groupe $LOG_GROUP absent)"
  aws logs tail "$LOG_GROUP" --follow
}

cmd_destroy() {
  [ -n "${1:-}" ] || die "Usage : ./ecs.sh destroy <application>"
  set_app "$1"
  local vpc sg

  step "Service $SERVICE"
  cluster_active && delete_service "$SERVICE"

  step "Définitions de tâche $FAMILY"
  deregister_task_definitions "$FAMILY"

  step "Groupe de logs $LOG_GROUP"
  log_group_exists "$LOG_GROUP" && aws logs delete-log-group --log-group-name "$LOG_GROUP"

  step "Registre ECR $REPOSITORY (images comprises)"
  if aws ecr describe-repositories --repository-names "$REPOSITORY" >/dev/null 2>&1; then
    aws ecr delete-repository --repository-name "$REPOSITORY" --force >/dev/null
  fi

  step "Security group $SG_NAME"
  vpc=$(default_vpc)
  if [ "$vpc" != "None" ]; then
    sg=$(security_group_id "$vpc" "$SG_NAME")
    [ "$sg" = "None" ] || delete_security_group "$sg"
  fi

  step "Application $APP supprimée"
  echo "Le cluster et le rôle d'exécution, partagés, sont conservés (./ecs.sh destroy_all pour tout supprimer)."
}

# Balaye toutes les ressources dont le nom commence par "docker-training",
# y compris celles d'applications dont on ne connaît plus le nom
cmd_destroy_all() {
  local arn name family sg group repo

  step "Services"
  if cluster_active; then
    for arn in $(aws ecs list-services --cluster "$CLUSTER" --query 'serviceArns[]' --output text); do
      delete_service "${arn##*/}"
    done
  fi

  step "Définitions de tâche"
  for family in $(aws ecs list-task-definition-families --family-prefix "$PROJECT" --status ACTIVE \
                    --query 'families[]' --output text); do
    deregister_task_definitions "$family"
  done

  step "Cluster $CLUSTER"
  if cluster_active; then
    aws ecs delete-cluster --cluster "$CLUSTER" >/dev/null
  fi

  step "Groupes de logs"
  for group in $(aws logs describe-log-groups --log-group-name-prefix "/ecs/$PROJECT" \
                   --query 'logGroups[].logGroupName' --output text); do
    aws logs delete-log-group --log-group-name "$group"
    echo "supprimé : $group"
  done

  step "Registres ECR"
  for repo in $(aws ecr describe-repositories \
                  --query "repositories[?starts_with(repositoryName, '$PROJECT')].repositoryName" --output text); do
    aws ecr delete-repository --repository-name "$repo" --force >/dev/null
    echo "supprimé : $repo"
  done

  step "Rôle d'exécution $ROLE"
  if aws iam get-role --role-name "$ROLE" >/dev/null 2>&1; then
    aws iam detach-role-policy --role-name "$ROLE" --policy-arn "$EXECUTION_POLICY"
    aws iam delete-role --role-name "$ROLE"
  fi

  step "Security groups"
  for sg in $(aws ec2 describe-security-groups --filters "Name=group-name,Values=$PROJECT-*" \
                --query 'SecurityGroups[].GroupId' --output text); do
    delete_security_group "$sg"
  done

  step "Terminé"
}

usage() { sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

[ -n "${1:-}" ] || usage

# Rappelle l'identité et la région utilisées : la cause la plus fréquente d'erreur
# est un terminal où "export AWS_PROFILE=training" n'a pas été fait
echo "Profil : ${AWS_PROFILE:-default} | Région : $AWS_REGION" >&2

command="$1"; shift
case "$command" in
  deploy)      cmd_deploy "$@" ;;
  list)        cmd_list ;;
  url)         cmd_url "$@" ;;
  logs)        cmd_logs "$@" ;;
  destroy)     cmd_destroy "$@" ;;
  destroy_all) cmd_destroy_all ;;
  *)           usage ;;
esac
