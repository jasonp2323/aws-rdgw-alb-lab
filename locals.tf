################################################################################
# Shared values
#
# The spoke maps below are the only place a new spoke has to be registered.
# Everything downstream -- TGW route table associations and propagations, the
# ingress the directory security group grants, DNS rule sharing -- iterates over
# them, so adding spoke #2 means adding one entry per map plus that spoke's own
# VPC/attachment file. No existing routing is touched.
################################################################################

locals {
  tags = var.tags

  # Two AZs, taken from whatever the network account offers. The workload VPC
  # reuses the same AZ *names*; both accounts are in the same Region so the
  # names line up, and AZ IDs only matter for latency, not correctness here.
  azs = slice(data.aws_availability_zones.network.names, 0, var.az_count)

  # /20 per subnet, carved deterministically out of each VPC CIDR.
  network_private_subnets  = [for i in range(var.az_count) : cidrsubnet(var.network_vpc_cidr, 4, i)]
  network_public_subnets   = [for i in range(var.az_count) : cidrsubnet(var.network_vpc_cidr, 4, i + var.az_count)]
  workload_private_subnets = [for i in range(var.az_count) : cidrsubnet(var.workload_vpc_cidr, 4, i)]

  ##############################################################################
  # Spoke registry
  ##############################################################################

  # CIDR per spoke. Drives the directory security group ingress.
  spoke_cidrs = {
    workload = var.workload_vpc_cidr
  }

  # TGW attachment ID per spoke. Drives association to the "spoke" route table
  # and propagation into the "shared" route table.
  spoke_attachment_ids = {
    workload = module.workload_tgw_attachment.ec2_transit_gateway_vpc_attachment["workload"].id
  }

  ##############################################################################
  # Active Directory client ports
  #
  # The security group AWS builds for the directory only admits the network VPC's
  # own CIDR, so spokes reaching AD across the TGW have to be added explicitly.
  # Enumerated rather than "allow all from the spoke" so the no-RDP/no-SSH rule
  # holds even inside the identity path.
  # https://learn.microsoft.com/en-us/troubleshoot/windows-server/networking/service-overview-and-network-port-requirements
  ##############################################################################

  ad_ports = {
    dns_tcp      = { protocol = "tcp", from = 53, to = 53, description = "DNS" }
    dns_udp      = { protocol = "udp", from = 53, to = 53, description = "DNS" }
    kerberos_tcp = { protocol = "tcp", from = 88, to = 88, description = "Kerberos" }
    kerberos_udp = { protocol = "udp", from = 88, to = 88, description = "Kerberos" }
    ntp_udp      = { protocol = "udp", from = 123, to = 123, description = "NTP" }
    rpc_epm_tcp  = { protocol = "tcp", from = 135, to = 135, description = "RPC endpoint mapper" }
    netbios_udp  = { protocol = "udp", from = 138, to = 138, description = "NetBIOS datagram" }
    ldap_tcp     = { protocol = "tcp", from = 389, to = 389, description = "LDAP" }
    ldap_udp     = { protocol = "udp", from = 389, to = 389, description = "LDAP" }
    smb_tcp      = { protocol = "tcp", from = 445, to = 445, description = "SMB" }
    smb_udp      = { protocol = "udp", from = 445, to = 445, description = "SMB" }
    kpasswd_tcp  = { protocol = "tcp", from = 464, to = 464, description = "Kerberos password change" }
    kpasswd_udp  = { protocol = "udp", from = 464, to = 464, description = "Kerberos password change" }
    ldaps_tcp    = { protocol = "tcp", from = 636, to = 636, description = "LDAPS" }
    gc_tcp       = { protocol = "tcp", from = 3268, to = 3269, description = "Global catalog" }
    adws_tcp     = { protocol = "tcp", from = 9389, to = 9389, description = "AD Web Services" }
    rpc_dynamic  = { protocol = "tcp", from = 49152, to = 65535, description = "RPC dynamic ports" }
  }

  # Cartesian product of spokes x AD ports, flattened into one map of SG rules.
  ad_ingress_rules = {
    for pair in setproduct(keys(local.spoke_cidrs), keys(local.ad_ports)) :
    "${pair[0]}-${pair[1]}" => {
      cidr        = local.spoke_cidrs[pair[0]]
      protocol    = local.ad_ports[pair[1]].protocol
      from_port   = local.ad_ports[pair[1]].from
      to_port     = local.ad_ports[pair[1]].to
      description = "${local.ad_ports[pair[1]].description} from ${pair[0]} spoke"
    }
  }
}

data "aws_availability_zones" "network" {
  provider = aws.network
  state    = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}
