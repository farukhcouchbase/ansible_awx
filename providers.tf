terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
  access_key = "AKIAUW4RA4E7IXYIWZKN"
  secret_key = "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"
}