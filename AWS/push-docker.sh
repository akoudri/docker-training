#!/usr/bin/env bash
# Construit l'image et la pousse dans le registre ECR.
#
# Usage : DOCKER_REGISTRY=<compte>.dkr.ecr.<region>.amazonaws.com ./push-docker.sh [version] [contexte_build]
#   version         tag de l'image (défaut : 1.0)
#   contexte_build  dossier contenant le Dockerfile (défaut : ../nginx)
#
# Variables optionnelles : REPOSITORY (défaut : docker-training), AWS_REGION
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

: "${DOCKER_REGISTRY:?Définir DOCKER_REGISTRY (ex : 123456789012.dkr.ecr.eu-west-3.amazonaws.com)}"
VERSION="${1:-1.0}"
CONTEXT="${2:-$SCRIPT_DIR/../nginx}"
REPOSITORY="${REPOSITORY:-docker-training}"
IMAGE="$DOCKER_REGISTRY/$REPOSITORY:$VERSION"

# Fargate tourne en x86_64 : on force la plateforme (indispensable sur Mac Apple Silicon)
docker build --platform linux/amd64 -t "$IMAGE" "$CONTEXT"

aws ecr get-login-password ${AWS_REGION:+--region "$AWS_REGION"} \
  | docker login --username AWS --password-stdin "$DOCKER_REGISTRY"

docker push "$IMAGE"
echo "Image poussée : $IMAGE"
