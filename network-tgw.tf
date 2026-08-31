################################################################################
# Transit Gateway (owned by the network account, shared to spokes via RAM)
#
# Default association and propagation are both disabled, so an attachment does
# nothing until it is explicitly wired into one of the two route tables below.
# That is what keeps a spoke from reaching another spoke by accident.
#
#   shared route table  -- associated with the network VPC attachment.
#                          Every attachment propagates into it, so the network
#                          account can reach all spokes.
#   spoke route table   -- associated with every spoke attachment.
#                          Only the network VPC attachment propagates into it,
#                          plus a static default route for NAT egress. Spokes
#                          therefore see the network VPC and the internet, and
#                          nothing else.
#
# The module builds the TGW, the RAM share and the network VPC attachment.
# create_tgw_routes is off because the module models a single route table and
# this design needs two; the tables and their wiring are below.
################################################################################

module "tgw" {
  source  = "terraform-aws-modules/transit-gateway/aws"
  version = "~> 3.3"

  providers = {
    aws = aws.network
  }

  name        = "${var.name}-tgw"
  description = "Identity isolation lab hub"

  # Nothing is associated or propagated implicitly.
  enable_default_route_table_association = false
  enable_default_route_table_propagation = false

  # Spoke attachments are accepted deliberately, in this configuration.
  enable_auto_accept_shared_attachments = false

  # The module's single route table is not used; see the two below.
  create_tgw_routes = false

  vpc_attachments = {
    network = {
      vpc_id     = module.network_vpc.vpc_id
      subnet_ids = module.network_vpc.private_subnets

      transit_gateway_default_route_table_association = false
      transit_gateway_default_route_table_propagation = false
    }
  }

  # Shared to the workload account. Both accounts sit in the same organization
  # with RAM organization sharing enabled, so the share is accepted implicitly
  # and no accepter resource is needed.
  share_tgw                     = true
  ram_name                      = "${var.name}-tgw"
  ram_allow_external_principals = false
  ram_principals                = [var.workload_account_id]

  tags = local.tags
}

################################################################################
# Route tables
################################################################################

resource "aws_ec2_transit_gateway_route_table" "shared" {
  provider = aws.network

  transit_gateway_id = module.tgw.ec2_transit_gateway_id

  tags = merge(local.tags, { Name = "${var.name}-shared" })
}

resource "aws_ec2_transit_gateway_route_table" "spoke" {
  provider = aws.network

  transit_gateway_id = module.tgw.ec2_transit_gateway_id

  tags = merge(local.tags, { Name = "${var.name}-spoke" })
}

################################################################################
# Network VPC attachment -> shared table
################################################################################

resource "aws_ec2_transit_gateway_route_table_association" "network" {
  provider = aws.network

  transit_gateway_attachment_id  = module.tgw.ec2_transit_gateway_vpc_attachment["network"].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.shared.id
}

# Into "shared" so the network account can reach the spokes it learns about.
resource "aws_ec2_transit_gateway_route_table_propagation" "network_into_shared" {
  provider = aws.network

  transit_gateway_attachment_id  = module.tgw.ec2_transit_gateway_vpc_attachment["network"].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.shared.id
}

# Into "spoke" so every spoke learns the network VPC CIDR (10.20.0.0/16).
resource "aws_ec2_transit_gateway_route_table_propagation" "network_into_spoke" {
  provider = aws.network

  transit_gateway_attachment_id  = module.tgw.ec2_transit_gateway_vpc_attachment["network"].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
}

# Centralized egress: anything a spoke cannot resolve locally goes to the
# network VPC, where the NAT gateway picks it up.
resource "aws_ec2_transit_gateway_route" "spoke_default_to_network" {
  provider = aws.network

  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
  transit_gateway_attachment_id  = module.tgw.ec2_transit_gateway_vpc_attachment["network"].id
  destination_cidr_block         = "0.0.0.0/0"
}

################################################################################
# Spoke attachments -> spoke table (associate) and shared table (propagate)
#
# Driven by local.spoke_attachment_ids, so a second spoke is one map entry.
# Both wait on the accepter: a cross-account attachment sits in
# "pendingAcceptance" until the network account accepts it, and route table
# operations against a pending attachment fail.
################################################################################

resource "aws_ec2_transit_gateway_route_table_association" "spokes" {
  provider = aws.network

  for_each = local.spoke_attachment_ids

  transit_gateway_attachment_id  = each.value
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment_accepter.spokes]
}

resource "aws_ec2_transit_gateway_route_table_propagation" "spokes_into_shared" {
  provider = aws.network

  for_each = local.spoke_attachment_ids

  transit_gateway_attachment_id  = each.value
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.shared.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment_accepter.spokes]
}

################################################################################
# Network VPC routing towards the spokes
#
# One route per route table rather than a for_each over the module's output:
# route table IDs are not known at plan time and cannot be used as for_each keys.
# single_nat_gateway gives exactly one private and one public route table.
#
# The public table needs the route too -- return traffic from the NAT gateway to
# a spoke is sourced from the public subnet.
################################################################################

resource "aws_route" "network_private_to_spokes" {
  provider = aws.network

  route_table_id         = module.network_vpc.private_route_table_ids[0]
  destination_cidr_block = var.spoke_supernet
  transit_gateway_id     = module.tgw.ec2_transit_gateway_id

  depends_on = [module.tgw]
}

resource "aws_route" "network_public_to_spokes" {
  provider = aws.network

  route_table_id         = module.network_vpc.public_route_table_ids[0]
  destination_cidr_block = var.spoke_supernet
  transit_gateway_id     = module.tgw.ec2_transit_gateway_id

  depends_on = [module.tgw]
}
