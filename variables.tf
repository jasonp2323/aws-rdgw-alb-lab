################################################################################
# Accounts
################################################################################

variable "network_account_id" {
  description = "AWS account ID for the network (identity) account. Also the AWS Organizations management account."
  type        = string
  default     = "172106476397"
}

variable "workload_account_id" {
  description = "AWS account ID for the workload (spoke) account."
  type        = string
  default     = "594775506233"
}

variable "region" {
  description = "Region for every resource in this lab."
  type        = string
  default     = "us-east-1"
}

################################################################################
# Naming / tagging
################################################################################

variable "name" {
  description = "Short name prefix applied to every resource."
  type        = string
  default     = "idiso"
}

variable "tags" {
  description = "Tags applied to everything this configuration creates."
  type        = map(string)
  default = {
    Environment = "lab"
    Project     = "identity-isolation"
  }
}

################################################################################
# Addressing
################################################################################

variable "network_vpc_cidr" {
  description = "CIDR for the network VPC (hosts Managed AD, NAT egress and the Resolver endpoints)."
  type        = string
  default     = "10.20.0.0/16"
}

variable "workload_vpc_cidr" {
  description = "CIDR for the workload VPC. Private subnets only; egress rides the TGW to the network account NAT."
  type        = string
  default     = "10.30.0.0/16"
}

variable "spoke_supernet" {
  description = <<-EOT
    Supernet covering every current and future spoke VPC. The network VPC route tables
    send this whole range at the Transit Gateway, so onboarding a second spoke needs no
    route changes here. Local VPC routes are always more specific, so this never
    shadows the network VPC's own CIDR.
  EOT
  type        = string
  default     = "10.0.0.0/8"
}

variable "az_count" {
  description = "Number of Availability Zones. Managed Microsoft AD requires exactly two subnets in two AZs."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count == 2
    error_message = "This lab is built for exactly 2 AZs; Managed Microsoft AD requires 2 subnets in 2 distinct AZs."
  }
}

################################################################################
# Directory
################################################################################

variable "domain_name" {
  description = "Fully qualified domain name for the AWS Managed Microsoft AD directory."
  type        = string
  default     = "corp.theuptimestudio.co"
}

variable "domain_short_name" {
  description = "NetBIOS short name for the directory."
  type        = string
  default     = "CORP"
}

variable "directory_admin_password" {
  description = <<-EOT
    Password for the directory's built-in Admin account. Not stored by AWS and not
    recoverable -- keep it somewhere you can find it. Set it in terraform.tfvars or
    via TF_VAR_directory_admin_password.
  EOT
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.directory_admin_password) >= 8 && length(var.directory_admin_password) <= 64
    error_message = "Directory password must be between 8 and 64 characters."
  }

  validation {
    condition = length(compact([
      can(regex("[a-z]", var.directory_admin_password)) ? "x" : "",
      can(regex("[A-Z]", var.directory_admin_password)) ? "x" : "",
      can(regex("[0-9]", var.directory_admin_password)) ? "x" : "",
      can(regex("[^a-zA-Z0-9]", var.directory_admin_password)) ? "x" : "",
    ])) >= 3
    error_message = "Directory password must satisfy at least 3 of 4 categories: lowercase, uppercase, digit, special character."
  }
}

################################################################################
# Domain-joined proof instance
################################################################################

variable "instance_type" {
  description = "Instance type for the Windows domain-join proof instance."
  type        = string
  default     = "t3.medium"
}

variable "windows_ami_ssm_parameter" {
  description = "Public SSM parameter resolving to the latest Windows Server 2022 AMI."
  type        = string
  default     = "/aws/service/ami-windows-latest/Windows_Server-2022-English-Full-Base"
}
