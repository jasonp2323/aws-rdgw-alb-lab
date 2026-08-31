################################################################################
# Workload attachment to the shared Transit Gateway
#
# Created in the workload account against the TGW that RAM shared to it, then
# accepted back in the network account. The module is reused with create_tgw
# off so it only builds the attachment -- the TGW itself already exists.
################################################################################

module "workload_tgw_attachment" {
  source  = "terraform-aws-modules/transit-gateway/aws"
  version = "~> 3.3"

  providers = {
    aws = aws.workload
  }

  # Named even though this side creates no TGW: the module derives its RAM
  # share name from it and rejects an empty string.
  name       = "${var.name}-tgw"
  create_tgw = false

  # The RAM share is auto-accepted through AWS Organizations, so there is no
  # share to accept here.
  share_tgw = false

  # Route tables live in the owning account; this side only attaches.
  create_tgw_routes = false

  vpc_attachments = {
    workload = {
      tgw_id     = module.tgw.ec2_transit_gateway_id
      vpc_id     = module.workload_vpc.vpc_id
      subnet_ids = module.workload_vpc.private_subnets

      transit_gateway_default_route_table_association = false
      transit_gateway_default_route_table_propagation = false
    }
  }

  tags = local.tags

  # The TGW has to exist and be shared before the workload account can see it.
  depends_on = [module.tgw]
}

################################################################################
# Acceptance, in the account that owns the Transit Gateway
################################################################################

resource "aws_ec2_transit_gateway_vpc_attachment_accepter" "spokes" {
  provider = aws.network

  for_each = local.spoke_attachment_ids

  transit_gateway_attachment_id = each.value

  # Association and propagation are handled explicitly in network-tgw.tf.
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(local.tags, { Name = "${var.name}-${each.key}" })
}

################################################################################
# Workload VPC routing
#
# Everything leaves via the TGW: the network VPC (10.20.0.0/16) is reachable
# through the spoke route table, and the default route carries SSM, Windows
# Update and general egress to the network account's NAT gateway.
#
# count rather than for_each because route table IDs are unknown at plan time;
# the list length is known, the values are not.
################################################################################

resource "aws_route" "workload_default_to_tgw" {
  provider = aws.workload

  count = length(module.workload_vpc.private_route_table_ids)

  route_table_id         = module.workload_vpc.private_route_table_ids[count.index]
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = module.tgw.ec2_transit_gateway_id

  # A route to a pending attachment is rejected, so wait for acceptance.
  depends_on = [aws_ec2_transit_gateway_vpc_attachment_accepter.spokes]
}
