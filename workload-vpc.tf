################################################################################
# Workload account VPC
#
# Private subnets only -- no internet gateway, no NAT. Everything outbound
# (SSM Session Manager, Windows Update, the AD join) leaves through the Transit
# Gateway and the network account's NAT gateway.
################################################################################

module "workload_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7"

  providers = {
    aws = aws.workload
  }

  name = "${var.name}-workload"
  cidr = var.workload_vpc_cidr

  azs             = local.azs
  private_subnets = local.workload_private_subnets

  private_subnet_names = [for az in local.azs : "${var.name}-workload-private-${az}"]

  # No public subnets, so no IGW and no NAT: egress is the network account's job.
  create_igw         = false
  enable_nat_gateway = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []

  tags = local.tags
}
