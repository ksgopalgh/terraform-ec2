#!/usr/bin/env bash
set -euo pipefail

ACCOUNT_ID="${ACCOUNT_ID:-886427957493}"
ROLE_NAME="${ROLE_NAME:-owner}"
AWS_PROFILE_NAME="${AWS_PROFILE_NAME:-strln}"
AWS_REGION="${AWS_REGION:-ca-central-1}"
TFVARS_FILE="${TFVARS_FILE:-terraform.tfvars}"

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --account-id <id>     AWS account ID for session generation (default: ${ACCOUNT_ID})
  --role-name <name>    Role name for sl aws session generate (default: ${ROLE_NAME})
  --profile <name>      AWS profile name used by Terraform (default: ${AWS_PROFILE_NAME})
  --region <region>     AWS region for deployment (default: ${AWS_REGION})
  --tfvars <path>       Terraform tfvars file path (default: ${TFVARS_FILE})
  -h, --help            Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --account-id)
      ACCOUNT_ID="$2"
      shift 2
      ;;
    --role-name)
      ROLE_NAME="$2"
      shift 2
      ;;
    --profile)
      AWS_PROFILE_NAME="$2"
      shift 2
      ;;
    --region)
      AWS_REGION="$2"
      shift 2
      ;;
    --tfvars)
      TFVARS_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

sl login
sl aws session generate --role-name "${ROLE_NAME}" --account-id "${ACCOUNT_ID}"

export AWS_PROFILE="${AWS_PROFILE_NAME}"
export AWS_REGION

TF_VAR_ARGS=(
  "-var=aws_region=${AWS_REGION}"
  "-var=aws_profile=${AWS_PROFILE_NAME}"
  "-var=target_account_id=${ACCOUNT_ID}"
)

if [[ -f "${TFVARS_FILE}" ]]; then
  TF_VAR_ARGS+=("-var-file=${TFVARS_FILE}")
fi

terraform init
terraform plan "${TF_VAR_ARGS[@]}"
terraform apply "${TF_VAR_ARGS[@]}"
