/*====
Variables used across all modules
======*/
locals {
  production_availability_zones = "us-east-1a"
}

provider "aws" {
  region = var.region
  #profile = "duduribeiro"
}

resource "aws_key_pair" "key" {
  key_name   = "production_key"
  public_key = file("production_key.pub")
}

module "totalapp" {
  source               = "./modules/ecs"
  environment          = "production"
  vpc_cidr             = "10.0.0.0/16"
  public_subnets_cidr  = "10.0.1.0/24"
  private_subnets_cidr = "10.0.10.0/24"
  region               = var.region
  availability_zones   = local.production_availability_zones
  key_name             = "production_key"
  allocated_storage    = "20"
  database_name        = var.production_database_name
  database_username    = var.production_database_username
  database_password    = var.production_database_password
  instance_class       = "db.t2.micro"
  repository_name     = "openjobs/production"
  secret_key_base     = "${var.production_secret_key_base}"
}
