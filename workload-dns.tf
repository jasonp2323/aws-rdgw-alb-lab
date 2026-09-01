################################################################################
# Workload DNS
#
# Associating the shared rule is the whole workload-side DNS configuration. The
# workload VPC keeps the Amazon resolver at VPC+2 as its DNS server -- no DHCP
# option set here -- and the rule peels off just corp.theuptimestudio.co and
# forwards it to the domain controllers in the network account. Everything else
# resolves normally.
################################################################################

resource "aws_route53_resolver_rule_association" "workload" {
  provider = aws.workload

  resolver_rule_id = aws_route53_resolver_rule.corp.id
  vpc_id           = module.workload_vpc.vpc_id

  # The rule is not visible in this account until RAM has shared it. Both
  # associations are required and neither depends on the other: the principal
  # association grants this account the share, the resource association puts the
  # rule *into* it. Waiting on only one races the other and fails with
  # RSLVR-00703 "resolver rule does not exist".
  depends_on = [
    aws_ram_principal_association.resolver_rule,
    aws_ram_resource_association.resolver_rule,
  ]
}
