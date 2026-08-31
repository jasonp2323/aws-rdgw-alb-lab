################################################################################
# Network account
################################################################################

output "network_vpc_id" {
  description = "Network VPC ID."
  value       = module.network_vpc.vpc_id
}

output "transit_gateway_id" {
  description = "Transit Gateway shared with the spokes."
  value       = module.tgw.ec2_transit_gateway_id
}

output "tgw_route_table_ids" {
  description = "The two Transit Gateway route tables that enforce the hub-and-spoke policy."
  value = {
    shared = aws_ec2_transit_gateway_route_table.shared.id
    spoke  = aws_ec2_transit_gateway_route_table.spoke.id
  }
}

output "directory_id" {
  description = "Managed Microsoft AD directory ID in the network account."
  value       = aws_directory_service_directory.this.id
}

output "directory_dns_ip_addresses" {
  description = "Domain controller DNS IPs. The Resolver rule forwards to these."
  value       = aws_directory_service_directory.this.dns_ip_addresses
}

output "directory_security_group_id" {
  description = "Security group AWS created for the domain controllers, opened here to the spoke CIDRs."
  value       = aws_directory_service_directory.this.security_group_id
}

output "resolver_inbound_endpoint_ip_addresses" {
  description = "Inbound Resolver endpoint IPs -- the ingress point for DNS from outside this VPC."
  value       = [for ip in aws_route53_resolver_endpoint.inbound.ip_address : ip.ip]
}

output "resolver_rule_id" {
  description = "Forwarding rule for the AD zone, shared to the workload account."
  value       = aws_route53_resolver_rule.corp.id
}

################################################################################
# Workload account
################################################################################

output "workload_vpc_id" {
  description = "Workload VPC ID."
  value       = module.workload_vpc.vpc_id
}

output "workload_tgw_attachment_id" {
  description = "Workload VPC attachment, accepted in the network account."
  value       = module.workload_tgw_attachment.ec2_transit_gateway_vpc_attachment["workload"].id
}

output "shared_directory_id" {
  description = "Directory ID as seen from the workload account. This is what the SSM join document uses."
  value       = aws_directory_service_shared_directory.workload.shared_directory_id
}

output "workload_instance_id" {
  description = "Domain-joined proof instance."
  value       = module.workload_instance.id
}

output "session_manager_command" {
  description = "Open a shell on the proof instance."
  value       = "aws ssm start-session --target ${module.workload_instance.id} --profile workload --region ${var.region}"
}
