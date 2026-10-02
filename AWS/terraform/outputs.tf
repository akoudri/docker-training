output "region" {
  value = var.region
}

output "registry" {
  description = "Adresse du registre, à utiliser pour docker login"
  value       = split("/", aws_ecr_repository.app.repository_url)[0]
}

output "repository_name" {
  value = aws_ecr_repository.app.name
}

output "repository_url" {
  description = "URI complète du dépôt ECR"
  value       = aws_ecr_repository.app.repository_url
}

output "cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "service_name" {
  value = aws_ecs_service.app.name
}

output "log_group" {
  value = aws_cloudwatch_log_group.app.name
}
