# Team Runbook: Windows EC2 Automation Stack

## Purpose

Standardize how the team provisions and accesses Windows EC2 automation hosts with:
- SSM/RDP access modes
- Dynamic SG allowlist by user IP
- Optional managed key pairs
- User-configurable package installs

## File Layout

- `templates/team-base.tfvars.example`:
  Common baseline for account/region/network/package defaults.
- `templates/user-override.tfvars.example`:
  User-specific override (mostly access mode + RDP CIDR).
- `README.md`:
  Full module reference.

## Team Workflow

1. Copy base and user templates:
```bash
cd terraform/windows-ec2-single
mkdir -p tfvars
cp templates/team-base.tfvars.example tfvars/team-base.tfvars
cp templates/user-override.tfvars.example tfvars/<your-name>.tfvars
```

2. Update your IP in `tfvars/<your-name>.tfvars`:
- `rdp_allowed_cidrs = ["<YOUR_IP>/32"]`

3. Deploy with both var files:
```bash
./deploy.sh \
  --account-id 886427957493 \
  --region ca-central-1 \
  --profile strln \
  --tfvars tfvars/team-base.tfvars

terraform plan \
  -var-file=tfvars/team-base.tfvars \
  -var-file=tfvars/<your-name>.tfvars

terraform apply \
  -var-file=tfvars/team-base.tfvars \
  -var-file=tfvars/<your-name>.tfvars
```

Note:
- For map variables like `instances`, later var files replace the entire map value.
- Keep all required instance entries in your user override if you override `instances`.

## Access Notes

- `access_mode = "ssm"`: SSM only
- `access_mode = "rdp"`: RDP only
- `access_mode = "both"`: SSM + RDP
- Keep `prevent_instance_destroy = true` in team/base vars to block accidental EC2 deletion or replacement.

RDP:
- Username: `Administrator`
- Password: retrieve via EC2 password-data decryption command from Terraform outputs.

PEM:
- PEM is used to decrypt the Windows password.
- PEM is not entered into RDP client directly.

## Package Controls

Use these variables in tfvars:
- `install_choco_packages`
- `choco_packages`
- `install_playwright_browsers`
- `playwright_browsers`
- `playwright_version`

## Git Hygiene

Do not commit:
- `*.tfstate*`
- `.terraform/`
- `*.pem`
- non-example `*.tfvars`

Commit:
- `.tf` source files
- `README.md` / `TEAM_README.md`
- `templates/*.tfvars.example`
