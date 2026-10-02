terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.23" # 6.23+ : prise en charge des identifiants "aws login"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = var.project
    }
  }
}
