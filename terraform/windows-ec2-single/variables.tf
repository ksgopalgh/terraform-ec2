variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ca-central-1"
}

variable "aws_profile" {
  description = "Optional AWS profile for provider authentication. Keep null when using environment credentials."
  type        = string
  default     = null
}

variable "target_account_id" {
  description = "Optional account guardrail. If set, plan/apply fails when caller account does not match."
  type        = string
  default     = null
}

variable "use_existing_network" {
  description = "If true, use existing VPC/subnet instead of creating new network resources."
  type        = bool
  default     = true
}

variable "existing_vpc_id" {
  description = "Existing VPC ID to use when use_existing_network=true."
  type        = string
  default     = null
}

variable "existing_subnet_id" {
  description = "Existing subnet ID to use when use_existing_network=true. Must be IPv6-enabled if assign_ipv6_address_count > 0."
  type        = string
  default     = null
}

variable "existing_vpc_ipv6_cidr" {
  description = "Optional IPv6 CIDR for existing VPC. If omitted, it is discovered via data source."
  type        = string
  default     = null
}

variable "name_prefix" {
  description = "Prefix applied to created resources."
  type        = string
  default     = "win-auto"
}

variable "availability_zone" {
  description = "Optional AZ override for created subnet when use_existing_network=false."
  type        = string
  default     = null
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "subnet_cidr" {
  description = "IPv4 CIDR block for public subnet."
  type        = string
  default     = "10.42.1.0/24"
}

variable "instance_type" {
  description = "Default EC2 instance type."
  type        = string
  default     = "t3.large"
}

variable "ami_id" {
  description = "Optional explicit Windows AMI ID. If null, AMI is resolved from ami_name_pattern."
  type        = string
  default     = null
}

variable "ami_name_pattern" {
  description = "AMI lookup pattern when ami_id is null."
  type        = string
  default     = "Windows_Server-2022-English-Full-Base-*"
}

variable "root_volume_size" {
  description = "Default root EBS size in GiB."
  type        = number
  default     = 100
}

variable "key_pair_name" {
  description = "Default existing EC2 key pair name. Required only if you want Windows password retrieval."
  type        = string
  default     = null
}

variable "create_key_pair" {
  description = "Default key pair strategy. If true, Terraform creates and manages a key pair per instance."
  type        = bool
  default     = false
}

variable "access_mode" {
  description = "Default access mode for instances. Allowed values: ssm, rdp, both."
  type        = string
  default     = "ssm"

  validation {
    condition     = contains(["ssm", "rdp", "both"], lower(var.access_mode))
    error_message = "access_mode must be one of: ssm, rdp, both."
  }
}

variable "enable_rdp" {
  description = "Deprecated compatibility flag. If true, instance access mode is forced to 'both'."
  type        = bool
  default     = false
}

variable "rdp_allowed_cidrs" {
  description = "Default IPv4 CIDR ranges allowed to RDP (3389)."
  type        = list(string)
  default     = []
}

variable "rdp_allowed_ipv6_cidrs" {
  description = "Default IPv6 CIDR ranges allowed to RDP (3389)."
  type        = list(string)
  default     = []
}

variable "create_ssm_vpc_endpoints" {
  description = "Create interface VPC endpoints for SSM/SSMMessages/EC2Messages."
  type        = bool
  default     = false
}

variable "create_eip" {
  description = "Default EIP strategy. Allocate new EIP when true."
  type        = bool
  default     = false
}

variable "existing_eip_allocation_id" {
  description = "Default existing EIP allocation ID to associate (e.g., eipalloc-xxxx)."
  type        = string
  default     = null
}

variable "allow_eip_reassociation" {
  description = "If true, allows re-associating an in-use existing EIP. If false, module allocates a new EIP instead."
  type        = bool
  default     = false
}

variable "existing_security_group_ids" {
  description = "Default existing security groups to attach. If empty, module creates managed SG per instance."
  type        = list(string)
  default     = []
}

variable "instances" {
  description = "Map of Windows instances to create. Key becomes logical instance name."
  type = map(object({
    instance_type               = optional(string)
    subnet_id                   = optional(string)
    root_volume_size            = optional(number)
    key_pair_name               = optional(string)
    create_key_pair             = optional(bool)
    access_mode                 = optional(string)
    create_eip                  = optional(bool)
    existing_eip_allocation_id  = optional(string)
    allow_eip_reassociation     = optional(bool)
    assign_ipv6_address_count   = optional(number)
    existing_security_group_ids = optional(list(string))
    enable_rdp                  = optional(bool)
    rdp_allowed_cidrs           = optional(list(string))
    rdp_allowed_ipv6_cidrs      = optional(list(string))
    tags                        = optional(map(string))
  }))
  default = {
    windows01 = {}
  }
}

variable "primary_instance_key" {
  description = "Instance key to expose in single-instance compatibility outputs. If null, first sorted key is used."
  type        = string
  default     = null
}

variable "playwright_version" {
  description = "Playwright npm version. Use 'latest' for latest."
  type        = string
  default     = "latest"
}

variable "install_choco_packages" {
  description = "Install Chocolatey packages listed in choco_packages during bootstrap."
  type        = bool
  default     = true
}

variable "choco_packages" {
  description = "Chocolatey package list to install during bootstrap."
  type        = list(string)
  default = [
    "googlechrome",
    "firefox",
    "nodejs-lts",
    "git",
    "vcredist140",
    "webview2-runtime"
  ]
}

variable "install_playwright_browsers" {
  description = "Install Playwright-managed browser binaries (chromium, firefox)."
  type        = bool
  default     = true
}

variable "playwright_browsers" {
  description = "Playwright browsers to install when install_playwright_browsers=true."
  type        = list(string)
  default     = ["chromium", "firefox"]
}

variable "tags" {
  description = "Additional resource tags."
  type        = map(string)
  default     = {}
}
