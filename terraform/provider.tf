provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "tetris-devsecops"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
