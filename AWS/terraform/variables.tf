variable "region" {
  description = "Région AWS de déploiement"
  type        = string
  default     = "eu-west-3"
}

variable "project" {
  description = "Préfixe utilisé pour nommer toutes les ressources (et nom du dépôt ECR)"
  type        = string
  default     = "docker-training"
}

variable "image_tag" {
  description = "Tag de l'image à déployer (doit avoir été poussé dans ECR au préalable)"
  type        = string
  default     = "1.0"
}

variable "container_port" {
  description = "Port écouté par l'application dans le conteneur"
  type        = number
  default     = 80
}

variable "cpu" {
  description = "Unités CPU de la tâche Fargate (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Mémoire de la tâche Fargate, en Mo"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Nombre de conteneurs à faire tourner"
  type        = number
  default     = 1
}

variable "allowed_cidr" {
  description = "Plage d'adresses autorisée à joindre le conteneur"
  type        = string
  default     = "0.0.0.0/0"
}
