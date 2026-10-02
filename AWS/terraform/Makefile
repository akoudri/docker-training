# Déploiement de bout en bout sur AWS ECS Fargate
#
#   make deploy              crée le registre, pousse l'image (VERSION=1.0) et déploie le service
#   make deploy VERSION=1.1  déploie une nouvelle version
#   make url                 affiche l'URL publique du conteneur
#   make logs                suit les logs du conteneur
#   make destroy             supprime toutes les ressources (à faire en fin de TP !)

VERSION ?= 1.0
CONTEXT ?= ../../nginx
TF      := terraform

# Évaluées à l'usage (après apply), d'où "=" et non ":="
# Région déduite de l'adresse du registre (disponible dès "make registry")
REGION   = $(word 4,$(subst ., ,$(REGISTRY)))
REGISTRY = $(shell $(TF) output -raw registry)
REPO     = $(shell $(TF) output -raw repository_name)
CLUSTER  = $(shell $(TF) output -raw cluster_name)
SERVICE  = $(shell $(TF) output -raw service_name)
LOGGROUP = $(shell $(TF) output -raw log_group)

.PHONY: init registry push apply deploy url logs destroy

init:
	$(TF) init

# Le dépôt ECR doit exister avant de pouvoir y pousser l'image
registry: init
	$(TF) apply -target=aws_ecr_repository.app -auto-approve

push:
	DOCKER_REGISTRY=$(REGISTRY) REPOSITORY=$(REPO) AWS_REGION=$(REGION) ../push-docker.sh $(VERSION) $(CONTEXT)

apply:
	$(TF) apply -var image_tag=$(VERSION)

deploy: registry push apply url

url:
	@TASK=$$(aws ecs list-tasks --region $(REGION) --cluster $(CLUSTER) --service-name $(SERVICE) \
	    --query 'taskArns[0]' --output text) && \
	ENI=$$(aws ecs describe-tasks --region $(REGION) --cluster $(CLUSTER) --tasks $$TASK \
	    --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value" --output text) && \
	IP=$$(aws ec2 describe-network-interfaces --region $(REGION) --network-interface-ids $$ENI \
	    --query 'NetworkInterfaces[0].Association.PublicIp' --output text) && \
	echo "http://$$IP"

logs:
	aws logs tail $(LOGGROUP) --region $(REGION) --follow

destroy:
	$(TF) destroy
