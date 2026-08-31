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

  # The rule is not visible in this account until RAM has shared it.
  depends_on = [aws_ram_principal_association.resolver_rule]
}
