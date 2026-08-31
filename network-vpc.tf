################################################################################
# Network account VPC
#
# Public + private subnets across two AZs with a single NAT gateway. The NAT is
# the egress point for this account *and*, via the Transit Gateway, for every
# spoke -- spokes have no internet gateway of their own.
#
# The TGW attachment lands in the private subnets (see network-tgw.tf). With a
# single NAT the module builds one shared private route table, so there is no
# asymmetric-routing hazard and no need for dedicated TGW subnets in a lab.
################################################################################

module "network_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7"

  providers = {
    aws = aws.network
  }

  name = "${var.name}-network"
  cidr = var.network_vpc_cidr

  azs             = local.azs
  private_subnets = local.network_private_subnets
  public_subnets  = local.network_public_subnets

  private_subnet_names = [for az in local.azs : "${var.name}-network-private-${az}"]
  public_subnet_names  = [for az in local.azs : "${var.name}-network-public-${az}"]

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  # DHCP options are managed in network-ad.tf instead: they have to point at the
  # directory's DNS IPs, which do not exist until the directory is built, and the
  # directory in turn needs this VPC's subnets.
  enable_dhcp_options = false

  # Leave the default security group with no rules rather than leaving it open.
  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []

  tags = local.tags
}
