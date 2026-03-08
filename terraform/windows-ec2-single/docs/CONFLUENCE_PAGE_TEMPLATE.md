# Windows EC2 Terraform Automation - Team Operating Guide

## 1. Objective

Provide a standardized approach to provision and manage Windows EC2 automation hosts with:
- dual access mode support (SSM/RDP/Both),
- dynamic SG allowlist handling,
- predictable key management,
- configurable package bootstrap.

## 2. Scope

- AWS account/region-driven provisioning
- Multi-instance support using `instances` map
- Safe Elastic IP behavior to avoid service disruption
- Team template-based execution model

## 3. Architecture Summary

| Area | Capability |
|---|---|
| Provisioning | Multiple instances in single `terraform apply` |
| Access | `access_mode = ssm / rdp / both` per instance |
| Security | RDP allowlist via `rdp_allowed_cidrs` |
| EIP | Existing EIP reuse with safe fallback to new EIP if already in-use |
| Key Management | Existing key pair or Terraform-managed key pair |
| Bootstrap | User-configurable Chocolatey + Playwright installation |

## 4. Team Operating Model

| File | Owner | Purpose |
|---|---|---|
| `templates/team-base.tfvars.example` | Platform/Infra owner | Shared defaults |
| `templates/user-override.tfvars.example` | Individual engineer | IP + access mode overrides |
| `TEAM_README.md` | Platform/Infra owner | Team run instructions |

### 4.1 Execution Pattern

1. Copy team base template to `tfvars/team-base.tfvars`.
2. Copy user override template to `tfvars/<user>.tfvars`.
3. Update user IP CIDR and access preferences.
4. Run plan/apply with both var files.

## 5. Access Model

| Mode | Behavior |
|---|---|
| `ssm` | SSM only (no RDP ingress) |
| `rdp` | RDP only |
| `both` | SSM + RDP |

RDP authentication flow:
1. Use PEM key to decrypt EC2 Windows password data.
2. Login via RDP as `Administrator` using decrypted password.

## 6. Security Group Allowlist Process

When VPN/public IP changes:
1. Update `rdp_allowed_cidrs` in user override file.
2. Re-run `terraform apply`.

Recommended:
- Use `/32` CIDR for individual client IPs.
- Avoid broad ranges.

## 7. Package Installation Controls

| Variable | Description |
|---|---|
| `install_choco_packages` | Enable/disable Chocolatey package install |
| `choco_packages` | Package list to install |
| `playwright_version` | Playwright npm version |
| `install_playwright_browsers` | Install Playwright browsers or not |
| `playwright_browsers` | Playwright browser list |

## 8. Safe EIP Behavior

If `existing_eip_allocation_id` is already associated:
- default behavior: create new EIP (no takeover),
- optional override: `allow_eip_reassociation = true`.

## 9. Git Commit Policy

Commit:
- Terraform source (`*.tf`)
- Module docs (`README.md`, `TEAM_README.md`)
- Example templates (`templates/*.tfvars.example`)

Do not commit:
- `.terraform/`
- `*.tfstate*`
- `*.pem`
- non-example `*.tfvars`
