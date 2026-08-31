terraform {
  required_version = "1.16.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.62.0"
    }
  }
  cloud {
    organization = "jpaquette2323-Lab"

    workspaces {
      name = "aws-rdgw-alb-lab"
    }
  }
}

provider "aws" {
  alias   = "network"
  profile = "network"
  region  = "us-east-1"
}

provider "aws" {
  alias   = "workload"
  profile = "workload"
  region  = "us-east-1"
}