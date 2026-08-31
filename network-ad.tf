################################################################################
# AWS Managed Microsoft AD
#
# The whole point of the lab: identity lives here, in the network account, and
# the workload account never hosts a domain controller. Standard edition, two
# domain controllers placed in the two private subnets (AWS requires exactly two
# subnets in two distinct AZs).
#
# Creation takes roughly 20-45 minutes. There is no community module for this.
################################################################################

resource "aws_directory_service_directory" "this" {
  provider = aws.network

  name       = var.domain_name
  short_name = var.domain_short_name
  password   = var.directory_admin_password
  type       = "MicrosoftAD"
  edition    = "Standard"

  vpc_settings {
    vpc_id     = module.network_vpc.vpc_id
    subnet_ids = slice(module.network_vpc.private_subnets, 0, 2)
  }

  tags = merge(local.tags, { Name = var.domain_name })
}

################################################################################
# DHCP options for the network VPC
#
# Points this VPC at the domain controllers so anything built here resolves and
# joins the domain natively. AWS Managed Microsoft AD forwards anything outside
# its own zone to the Amazon resolver at VPC+2, so public DNS still works.
#
# Managed here rather than through the VPC module: the directory has to exist to
# know its DNS IPs, and the directory needs the VPC's subnets.
################################################################################

resource "aws_vpc_dhcp_options" "network" {
  provider = aws.network

  domain_name         = var.domain_name
  domain_name_servers = aws_directory_service_directory.this.dns_ip_addresses

  tags = merge(local.tags, { Name = "${var.name}-network-ad-dns" })
}

resource "aws_vpc_dhcp_options_association" "network" {
  provider = aws.network

  vpc_id          = module.network_vpc.vpc_id
  dhcp_options_id = aws_vpc_dhcp_options.network.id
}

################################################################################
# Let the spokes talk to the domain controllers
#
# The security group AWS creates for a directory only admits the primary CIDR of
# the VPC hosting it, so spoke traffic arriving over the TGW is dropped by
# default. Ports are enumerated per local.ad_ports rather than opened wholesale,
# which keeps RDP (3389) and SSH (22) closed on the identity path too.
################################################################################

resource "aws_vpc_security_group_ingress_rule" "ad_from_spokes" {
  provider = aws.network

  for_each = local.ad_ingress_rules

  security_group_id = aws_directory_service_directory.this.security_group_id

  cidr_ipv4   = each.value.cidr
  ip_protocol = each.value.protocol
  from_port   = each.value.from_port
  to_port     = each.value.to_port
  description = each.value.description

  tags = local.tags
}

################################################################################
# Share the directory with the workload account
#
# Required for seamless domain join across an account boundary: the consumer
# account gets its own shared directory ID, which is what the SSM join document
# is pointed at.
#
# HANDSHAKE rather than ORGANIZATIONS so the whole exchange stays inside
# Terraform -- the ORGANIZATIONS method needs Directory Service trusted access
# turned on in the organization first.
################################################################################

resource "aws_directory_service_shared_directory" "workload" {
  provider = aws.network

  directory_id = aws_directory_service_directory.this.id
  method       = "HANDSHAKE"
  notes        = "Identity isolation lab: seamless EC2 domain join from the workload account"

  target {
    id   = var.workload_account_id
    type = "ACCOUNT"
  }
}

resource "aws_directory_service_shared_directory_accepter" "workload" {
  provider = aws.workload

  shared_directory_id = aws_directory_service_shared_directory.workload.shared_directory_id
}
