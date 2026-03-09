# Windows EC2 + EIP + IPv6 + SSM + Playwright (Scalable)

This Terraform stack now supports provisioning **multiple Windows EC2 instances in one run** using an `instances` map.

It also supports runtime account/region selection and preserves single-instance compatibility outputs.

## Safety Defaults

- `prevent_instance_destroy = true` (default) blocks accidental EC2 destroy/replace operations.
- If Terraform needs replacement, apply fails instead of deleting the running instance.
- Set `prevent_instance_destroy = false` only for planned replacement/decommission windows.

## Team Templates

- Team baseline template: `templates/team-base.tfvars.example`
- Per-user override template: `templates/user-override.tfvars.example`
- Team operating README: `TEAM_README.md`
- Confluence-ready content: `docs/CONFLUENCE_PAGE_TEMPLATE.md`

## What Is Automated

### Terraform-managed

- Single shared network (new or existing VPC/subnet)
- Security groups (managed per instance unless existing SGs are supplied)
- Multiple Windows instances (`for_each` over `instances`)
- Per-instance EIP strategy (reuse existing EIP or create new EIP)
- Safe EIP fallback: if requested existing EIP is already associated, a new EIP is created by default (no reassociation)
- IPv6 assignment on each instance (`assign_ipv6_address_count`)
- IAM role/profile for SSM (`AmazonSSMManagedInstanceCore`) when any instance access mode includes SSM
- Optional Terraform-managed key pairs for RDP password retrieval
- Optional SSM VPC interface endpoints (`ssm`, `ssmmessages`, `ec2messages`)

### First boot via user-data PowerShell

- Starts SSM agent
- Installs Chocolatey
- Installs user-configurable Chocolatey packages (`choco_packages`)
- Installs Playwright + user-configurable browser binaries (`playwright_browsers`)
- Writes bootstrap artifact at `C:\bootstrap\tooling_versions.json`

## Team Usage Model

Use one shared pattern across the team:

1. Keep a base `terraform.tfvars` committed for common settings (VPC/subnet, defaults).
2. Keep per-user override files (for example `tfvars/krishna.tfvars`) containing:
   - RDP allowlist CIDRs
   - access mode (`ssm`, `rdp`, `both`)
   - optional package overrides
3. Run with `deploy.sh --tfvars <user-file>` so each teammate can safely use their own IP allowlist.

This avoids editing shared files every time VPN IP changes.

## Inputs for Account and Region

You can pass account/region dynamically in two ways:

1. `deploy.sh` flags (`--account-id`, `--region`, `--profile`)
2. Terraform variables (`target_account_id`, `aws_region`, `aws_profile`)

`target_account_id` is an account guardrail. Plan/apply fails if credentials point to a different account.

## Quick Start

```bash
cd terraform/windows-ec2-single
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars

./deploy.sh \
  --account-id 886427957493 \
  --region ca-central-1 \
  --profile strln \
  --role-name owner \
  --tfvars terraform.tfvars
```

## Terraform-only Run

```bash
sl login
sl aws session generate --role-name owner --account-id 886427957493

export AWS_PROFILE=strln
export AWS_REGION=ca-central-1

terraform init
terraform plan \
  -var="target_account_id=886427957493" \
  -var="aws_region=ca-central-1" \
  -var="aws_profile=strln" \
  -var-file="terraform.tfvars"

terraform apply \
  -var="target_account_id=886427957493" \
  -var="aws_region=ca-central-1" \
  -var="aws_profile=strln" \
  -var-file="terraform.tfvars"
```

## Multi-Instance Example

```hcl
aws_region        = "ca-central-1"
aws_profile       = "strln"
target_account_id = "886427957493"

use_existing_network = true
existing_vpc_id      = "vpc-01556f973e3030fc2"
existing_subnet_id   = "subnet-0a6102871d429e3ad"

instances = {
  windows01 = {
    access_mode                = "both"
    existing_eip_allocation_id = "eipalloc-05f2119d3b04f089a"
    # If that EIP is already in use, module creates a new EIP by default.
    # allow_eip_reassociation = true  # set true only if you explicitly want reassociation
    rdp_allowed_cidrs          = ["203.0.113.10/32"]
    create_key_pair            = true
    # key_pair_name            = "IntegrationVM_KP" # optional custom name; auto-generated if omitted
    tags = {
      Service = "landers"
    }
  }
  windows02 = {
    create_eip   = true
    access_mode  = "ssm"
    tags = {
      Service = "iproxy"
    }
  }
}

primary_instance_key = "windows01"
```

## RDP / UI Access Decision

Access is now user-selectable per instance using `access_mode`:

- `ssm`: SSM shell/session access only
- `rdp`: RDP/UI access only
- `both`: both SSM and RDP

Default is `access_mode = "ssm"`.

If access mode includes RDP (`rdp` or `both`):

1. Set at least one CIDR in `rdp_allowed_cidrs` and/or `rdp_allowed_ipv6_cidrs`.
2. Use either `key_pair_name` (existing key) or `create_key_pair = true` (managed key creation) for password retrieval.

Per-instance access mode example:

```hcl
instances = {
  windows01 = {
    access_mode       = "both"
    rdp_allowed_cidrs = ["203.0.113.10/32"]
    key_pair_name     = "IntegrationVM_KP"
  }
  windows02 = {
    access_mode = "ssm"
  }
}
```

Compatibility note: legacy `enable_rdp = true` is still supported and forces `access_mode = "both"` for that scope.

### SG Allowlist Is User-Configurable

Yes. `rdp_allowed_cidrs` and `rdp_allowed_ipv6_cidrs` are fully user-configurable globally or per instance.

Example:

```hcl
instances = {
  windows01 = {
    access_mode       = "both"
    rdp_allowed_cidrs = ["64.103.240.121/32"]
  }
}
```

### PEM and RDP

The PEM file is **not** used directly by the RDP client.

- RDP login uses: `Administrator` + decrypted Windows password
- PEM is used only to decrypt password data returned by EC2 API

You can use the same PEM for multiple instances only if they were launched with the same key pair.

## EIP Behavior (No Takeover by Default)

If you specify `existing_eip_allocation_id` and that EIP is already associated to another resource:

- Default behavior: a **new EIP is created** for the instance (no disruption to existing workloads).
- To explicitly re-associate in-use EIP, set `allow_eip_reassociation = true`.

If you use `existing_security_group_ids`, ensure those SGs already allow required RDP ingress.

## Package/Application Install Is User-Configurable

The bootstrap install set is now configurable from tfvars:

```hcl
install_choco_packages = true
choco_packages = [
  "googlechrome",
  "firefox",
  "nodejs-lts",
  "git",
  "vcredist140",
  "webview2-runtime"
]

playwright_version          = "latest"
install_playwright_browsers = true
playwright_browsers         = ["chromium", "firefox"]
```

To skip package install on a hardened prebuilt image:

```hcl
install_choco_packages      = false
install_playwright_browsers = false
```

## Outputs

### Map outputs (multi-instance)

- `instance_ids`
- `public_ipv4_by_instance`
- `public_dns_by_instance`
- `ipv6_addresses_by_instance`
- `eip_allocation_ids_by_instance`
- `rdp_endpoints_by_instance`
- `access_modes_by_instance`
- `ssm_targets`
- `password_retrieval_commands_by_instance`
- `managed_key_pair_names_by_instance`
- `managed_private_keys_pem_by_instance` (sensitive)
- `windows_password_data_encrypted_by_instance` (sensitive)

### Backward-compatible primary outputs

- `instance_id`
- `public_ipv4`
- `public_dns`
- `ipv6_addresses`
- `rdp_endpoint`
- `eip_allocation_id_effective`
- `ssm_target`
- `password_retrieval_command`
- `windows_password_data_encrypted` (sensitive)
- `managed_private_key_pem` (sensitive, when primary instance uses `create_key_pair=true`)

`primary_instance_key` controls which instance powers these single-value outputs.

## Notes

- For restricted org accounts, keep `use_existing_network = true`.
- If EIP quota is limited, use per-instance `existing_eip_allocation_id`.
- Terraform profile switching does not generate credentials; keep using `sl login` + `sl aws session generate`.

## State Migration (Existing Single-Instance Users)

Legacy `moved` blocks are included for the common single-instance to `windows01` migration path.

If your historical state uses different addresses, move state once before apply to avoid recreation:

```bash
terraform state mv 'aws_instance.windows' 'aws_instance.windows["windows01"]'
terraform state mv 'aws_security_group.instance[0]' 'aws_security_group.instance["windows01"]'
terraform state mv 'aws_eip_association.windows[0]' 'aws_eip_association.windows["windows01"]' # if it exists
terraform state mv 'aws_eip.windows[0]' 'aws_eip.windows["windows01"]'                         # if it exists
```
