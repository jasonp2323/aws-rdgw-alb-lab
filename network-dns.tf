################################################################################
# Route 53 Resolver
#
# Two endpoints and one forwarding rule.
#
#   inbound   -- the documented ingress point into this VPC's DNS. Anything
#                reachable over the TGW (or later, a VPN/Direct Connect) can
#                query it for corp.theuptimestudio.co.
#   outbound  -- required machinery, not decoration: a FORWARD rule must name an
#                outbound endpoint, and that endpoint has to live in the same
#                account as the rule.
#
# The rule targets the directory's DNS IPs rather than the inbound endpoint's
# IPs. Pointing it at the inbound endpoint would resolve nothing on its own --
# the inbound endpoint answers out of this VPC's resolver, which has no
# knowledge of the AD zone until this very rule is associated with the VPC. That
# arrangement either dead-ends or, once the rule is associated with the network
# VPC, loops back on itself. Targeting the domain controllers directly is the
# one hop that actually resolves. See README.md.
#
# No community module covers Resolver endpoints or rules.
################################################################################

module "resolver_inbound_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 6.0"

  providers = {
    aws = aws.network
  }

  name        = "${var.name}-resolver-inbound"
  description = "DNS from anything reachable over the Transit Gateway"
  vpc_id      = module.network_vpc.vpc_id

  ingress_rules = {
    dns_tcp = {
      cidr_ipv4   = var.spoke_supernet
      ip_protocol = "tcp"
      from_port   = 53
      to_port     = 53
      description = "DNS over TCP from spokes"
    }
    dns_udp = {
      cidr_ipv4   = var.spoke_supernet
      ip_protocol = "udp"
      from_port   = 53
      to_port     = 53
      description = "DNS over UDP from spokes"
    }
  }

  egress_rules = {
    dns_tcp = {
      cidr_ipv4   = var.network_vpc_cidr
      ip_protocol = "tcp"
      from_port   = 53
      to_port     = 53
      description = "DNS over TCP to the domain controllers"
    }
    dns_udp = {
      cidr_ipv4   = var.network_vpc_cidr
      ip_protocol = "udp"
      from_port   = 53
      to_port     = 53
      description = "DNS over UDP to the domain controllers"
    }
  }

  tags = local.tags
}

module "resolver_outbound_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 6.0"

  providers = {
    aws = aws.network
  }

  name        = "${var.name}-resolver-outbound"
  description = "Forwards AD queries to the domain controllers"
  vpc_id      = module.network_vpc.vpc_id

  egress_rules = {
    dns_tcp = {
      cidr_ipv4   = var.network_vpc_cidr
      ip_protocol = "tcp"
      from_port   = 53
      to_port     = 53
      description = "DNS over TCP to the domain controllers"
    }
    dns_udp = {
      cidr_ipv4   = var.network_vpc_cidr
      ip_protocol = "udp"
      from_port   = 53
      to_port     = 53
      description = "DNS over UDP to the domain controllers"
    }
  }

  tags = local.tags
}

resource "aws_route53_resolver_endpoint" "inbound" {
  provider = aws.network

  name               = "${var.name}-inbound"
  direction          = "INBOUND"
  security_group_ids = [module.resolver_inbound_sg.id]

  dynamic "ip_address" {
    for_each = module.network_vpc.private_subnets
    content {
      subnet_id = ip_address.value
    }
  }

  tags = merge(local.tags, { Name = "${var.name}-inbound" })
}

resource "aws_route53_resolver_endpoint" "outbound" {
  provider = aws.network

  name               = "${var.name}-outbound"
  direction          = "OUTBOUND"
  security_group_ids = [module.resolver_outbound_sg.id]

  dynamic "ip_address" {
    for_each = module.network_vpc.private_subnets
    content {
      subnet_id = ip_address.value
    }
  }

  tags = merge(local.tags, { Name = "${var.name}-outbound" })
}

resource "aws_route53_resolver_rule" "corp" {
  provider = aws.network

  name                 = replace("${var.name}-${var.domain_name}", ".", "-")
  domain_name          = var.domain_name
  rule_type            = "FORWARD"
  resolver_endpoint_id = aws_route53_resolver_endpoint.outbound.id

  dynamic "target_ip" {
    for_each = aws_directory_service_directory.this.dns_ip_addresses
    content {
      ip = target_ip.value
    }
  }

  tags = merge(local.tags, { Name = var.domain_name })
}

# Associating the rule with the network VPC is what gives the inbound endpoint
# something to answer with: without it, a query arriving on the inbound endpoint
# would fall through to public DNS.
resource "aws_route53_resolver_rule_association" "network" {
  provider = aws.network

  resolver_rule_id = aws_route53_resolver_rule.corp.id
  vpc_id           = module.network_vpc.vpc_id
}

################################################################################
# Share the rule with the spokes
#
# A resolver rule is shared, not copied: the spoke associates the owner's rule
# with its own VPC. Organization sharing means no accepter is required.
################################################################################

resource "aws_ram_resource_share" "resolver_rule" {
  provider = aws.network

  name                      = "${var.name}-resolver-rule"
  allow_external_principals = false

  tags = merge(local.tags, { Name = "${var.name}-resolver-rule" })
}

resource "aws_ram_resource_association" "resolver_rule" {
  provider = aws.network

  resource_arn       = aws_route53_resolver_rule.corp.arn
  resource_share_arn = aws_ram_resource_share.resolver_rule.arn
}

resource "aws_ram_principal_association" "resolver_rule" {
  provider = aws.network

  principal          = var.workload_account_id
  resource_share_arn = aws_ram_resource_share.resolver_rule.arn
}
