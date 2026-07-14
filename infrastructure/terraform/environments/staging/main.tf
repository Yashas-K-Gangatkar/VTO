# Terraform: Staging environment
# Multi-AZ, smaller scale. One region (us-east-1).

terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }

  backend "s3" {
    # Configured via -backend-config flags in CI
    # bucket         = "vto-tfstate"
    # key            = "staging/terraform.tfstate"
    # region         = "us-east-1"
    # dynamodb_table = "vto-tfstate-lock"
    encrypt = true
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "git_sha" {
  type    = string
  default = "unknown"
}

variable "name_prefix" {
  type    = string
  default = "vto-staging"
}

locals {
  tags = {
    Project     = "vto"
    Environment = "staging"
    GitSha      = var.git_sha
    ManagedBy   = "terraform"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.tags
  }
}

# ============================================================
# Network
# ============================================================
module "vpc" {
  source       = "../../modules/vpc"
  name_prefix  = var.name_prefix
  cidr_block   = "10.1.0.0/16"
  azs          = ["${var.aws_region}a", "${var.aws_region}b"]
  tags         = local.tags
}

# ============================================================
# Data stores
# ============================================================
# (RDS, ElastiCache, MSK, S3 modules to be added as they're written)

# ============================================================
# Compute (ECS Fargate for stateless services)
# ============================================================
# (ECS module to be added)

# ============================================================
# GPU pool (EC2 ASG for inference)
# ============================================================
# (gpu-pool module to be added)
