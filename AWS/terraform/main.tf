# ---------------------------------------------------------------------------
# Registre privé (ECR)
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "app" {
  name                 = var.project
  image_tag_mutability = "MUTABLE"

  # Permet à "terraform destroy" de supprimer le dépôt même s'il contient des images
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

# ---------------------------------------------------------------------------
# Réseau : VPC par défaut + security group ouvrant le port de l'application
# ---------------------------------------------------------------------------

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "app" {
  name        = "${var.project}-sg"
  description = "Acces HTTP au conteneur ${var.project}"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Application"
    from_port   = var.container_port
    to_port     = var.container_port
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  # Sortie nécessaire pour tirer l'image depuis ECR et envoyer les logs
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------------------------------------------------------------------
# Rôle d'exécution : autorise ECS à tirer l'image et écrire dans CloudWatch
# ---------------------------------------------------------------------------

resource "aws_iam_role" "task_execution" {
  name = "${var.project}-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ---------------------------------------------------------------------------
# Logs du conteneur (équivalent de "docker logs")
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project}"
  retention_in_days = 7
}

# ---------------------------------------------------------------------------
# ECS : cluster, définition de tâche, service
# ---------------------------------------------------------------------------

resource "aws_ecs_cluster" "main" {
  name = "${var.project}-cluster"
}

resource "aws_ecs_task_definition" "app" {
  family                   = var.project
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.task_execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = var.project
    image     = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
    essential = true

    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.app.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "app"
      }
    }
  }])
}

resource "aws_ecs_service" "app" {
  name            = "${var.project}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = true
  }

  # Attend que la tâche soit stable avant de rendre la main
  wait_for_steady_state = true
}
