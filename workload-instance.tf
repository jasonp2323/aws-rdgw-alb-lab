################################################################################
# Windows Server 2022 proof instance
#
# Exists to demonstrate one thing: an instance in the workload account, with no
# domain controller anywhere near it, joins corp.theuptimestudio.co over the
# Transit Gateway using a directory it does not own.
#
# Reached exclusively through SSM Session Manager. No key pair, no inbound rules,
# no public IP -- the SSM agent dials out through the network account's NAT.
################################################################################

module "workload_instance_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 6.0"

  providers = {
    aws = aws.workload
  }

  name        = "${var.name}-workload-win"
  description = "Domain-joined proof instance: egress only, no inbound"
  vpc_id      = module.workload_vpc.vpc_id

  # Deliberately empty. Session Manager is an outbound connection from the
  # agent, so nothing needs to reach this instance.
  ingress_rules = {}

  egress_rules = {
    all = {
      cidr_ipv4   = "0.0.0.0/0"
      ip_protocol = "-1"
      description = "SSM, Windows Update and the domain join, all via the TGW"
    }
  }

  tags = local.tags
}

module "workload_instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 6.4"

  providers = {
    aws = aws.workload
  }

  name = "${var.name}-workload-win"

  ami_ssm_parameter = var.windows_ami_ssm_parameter
  instance_type     = var.instance_type

  subnet_id              = module.workload_vpc.private_subnets[0]
  vpc_security_group_ids = [module.workload_instance_sg.id]

  # No key pair: there is no way in other than Session Manager.
  key_name = null

  create_iam_instance_profile = true
  iam_role_name               = "${var.name}-workload-win"
  iam_role_description        = "Session Manager access and seamless domain join"
  iam_role_policies = {
    ssm       = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    directory = "arn:aws:iam::aws:policy/AmazonSSMDirectoryServiceAccess"
  }

  metadata_options = {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device = {
    type      = "gp3"
    size      = 50
    encrypted = true
  }

  tags = local.tags
}

################################################################################
# Seamless domain join
#
# The AWS-managed document does the work; Terraform only has to point it at the
# right directory. directoryId is the *shared* directory ID -- the identifier
# minted in the workload account when the network account shared the directory,
# not the network account's own d-xxxx.
#
# dnsIpAddresses is passed explicitly so the join does not depend on DNS having
# converged first, though the resolver rule makes it work either way.
################################################################################

resource "aws_ssm_association" "domain_join" {
  provider = aws.workload

  name             = "AWS-JoinDirectoryServiceDomain"
  association_name = "${var.name}-domain-join"

  targets {
    key    = "InstanceIds"
    values = [module.workload_instance.id]
  }

  parameters = {
    directoryId    = aws_directory_service_shared_directory.workload.shared_directory_id
    directoryName  = var.domain_name
    dnsIpAddresses = join(",", aws_directory_service_directory.this.dns_ip_addresses)
  }

  depends_on = [
    aws_directory_service_shared_directory_accepter.workload,
    aws_route53_resolver_rule_association.workload,
    aws_route.workload_default_to_tgw,
  ]
}
