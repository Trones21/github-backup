#!/usr/bin/env bash
set -euo pipefail

# ---------- Config defaults ----------
STACK_NAME="${STACK_NAME:-github-backup-stack}"
REGION="${REGION:-us-east-1}"

GITHUB_USERNAME="${GITHUB_USERNAME:-your-github-username}"
BACKUP_BUCKET="${BACKUP_BUCKET:-your-backup-bucket-name}"
ARTIFACTS_BUCKET="${ARTIFACTS_BUCKET:-your-artifacts-bucket}"
LAMBDA_CODE_KEY="${LAMBDA_CODE_KEY:-github-backup/github-backup-lambda.zip}"

# Auth: use EITHER GITHUB_TOKEN or GITHUB_TOKEN_SECRET_ARN
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
GITHUB_TOKEN_SECRET_ARN="${GITHUB_TOKEN_SECRET_ARN:-}"

INCLUDE_FORKS="${INCLUDE_FORKS:-false}"
INCLUDE_ARCHIVED="${INCLUDE_ARCHIVED:-true}"
S3_PREFIX="${S3_PREFIX:-github-backups}"

# Schedule: default 05:00 UTC on the 1st of each month
SCHEDULE_EXPR="${SCHEDULE_EXPR:-cron(0 5 1 * ? *)}"

PACKAGE_DIR="${PACKAGE_DIR:-package}"
ZIP_FILE="${ZIP_FILE:-github-backup-lambda.zip}"

# ---------- Get creds ----------
if [[ -f ./creds_get.sh ]]; then
  # use 'source' so env changes apply in this shell
  source ./creds_get.sh
else
  echo "[deploy] WARNING: creds_get.sh not found; continuing without it."
fi

echo "[deploy] Building Lambda package..."
rm -rf "${PACKAGE_DIR}" "${ZIP_FILE}"
mkdir -p "${PACKAGE_DIR}"
pip install --target "${PACKAGE_DIR}" requests
cp lambda_function.py "${PACKAGE_DIR}/"
(
  cd "${PACKAGE_DIR}"
  zip -r "../${ZIP_FILE}" .
)
echo "[deploy] Built ${ZIP_FILE}"

echo "[deploy] Uploading package to s3://${ARTIFACTS_BUCKET}/${LAMBDA_CODE_KEY}..."
aws s3 cp "${ZIP_FILE}" "s3://${ARTIFACTS_BUCKET}/${LAMBDA_CODE_KEY}"

echo "[deploy] Stack config:"
echo "  Stack name:        ${STACK_NAME}"
echo "  Region:            ${REGION}"
echo "  GitHub user:       ${GITHUB_USERNAME}"
echo "  Backup bucket:     ${BACKUP_BUCKET}"
echo "  Artifacts bucket:  ${ARTIFACTS_BUCKET}"
echo "  Lambda code key:   ${LAMBDA_CODE_KEY}"
echo "  Include forks:     ${INCLUDE_FORKS}"
echo "  Include archived:  ${INCLUDE_ARCHIVED}"
echo "  S3 prefix:         ${S3_PREFIX}"
echo "  Schedule:          ${SCHEDULE_EXPR}"
if [[ -n "${GITHUB_TOKEN_SECRET_ARN}" ]]; then
  echo "  Using Secrets Manager ARN: ${GITHUB_TOKEN_SECRET_ARN}"
elif [[ -n "${GITHUB_TOKEN}" ]]; then
  echo "  Using raw GitHub token from env (not recommended in prod)"
else
  echo "  WARNING: No GitHub token configured (GITHUB_TOKEN or GITHUB_TOKEN_SECRET_ARN)."
fi

echo ">>> Optional: inspect creds now (e.g. 'aws sts get-caller-identity --region ${REGION}')"
echo ">>> Press Enter to continue with CloudFormation deploy, or Ctrl+C to abort."
read -r _

aws cloudformation deploy \
  --region "${REGION}" \
  --stack-name "${STACK_NAME}" \
  --template-file template.yaml \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
    GitHubUsername="${GITHUB_USERNAME}" \
    BackupBucketName="${BACKUP_BUCKET}" \
    S3Prefix="${S3_PREFIX}" \
    IncludeForks="${INCLUDE_FORKS}" \
    IncludeArchived="${INCLUDE_ARCHIVED}" \
    GitHubToken="${GITHUB_TOKEN}" \
    GitHubTokenSecretArn="${GITHUB_TOKEN_SECRET_ARN}" \
    LambdaCodeS3Bucket="${ARTIFACTS_BUCKET}" \
    LambdaCodeS3Key="${LAMBDA_CODE_KEY}" \
    ScheduleExpression="${SCHEDULE_EXPR}"

echo "[deploy] CloudFormation deploy complete for stack ${STACK_NAME}"

# ---------- Shred creds ----------
if [[ -f ./creds_shred.sh ]]; then
  source ./creds_shred.sh
else
  echo "[deploy] WARNING: creds_shred.sh not found; credentials not shredded."
fi
