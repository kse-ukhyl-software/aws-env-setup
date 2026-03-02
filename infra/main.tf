terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.23.0"
    }
  }

  backend "s3" {
    bucket         = "cicd-security-tf-state-8148"
    key            = "tf-state-setup"
    region         = "eu-central-1"
    encrypt        = true
    dynamodb_table = "cicd-security-tf-state-lock"
  }
}

provider "aws" {
  region = "eu-central-1"

  default_tags {
    tags = {
      Environment = terraform.workspace
      Project     = var.project
      Contact     = var.contact
      ManageBy    = "Terraform/setup"
    }
  }
}

locals {
  prefix = var.prefix
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
