# GitHub → S3 Monthly Backup (AWS Lambda + CloudFormation)

This project automatically backs up **all GitHub repositories owned by a user** into S3 on a **monthly schedule**.  
It uses:

- AWS Lambda (Python)
- CloudFormation
- EventBridge (cron schedule)
- S3 for storage
- Optional Secrets Manager for the GitHub PAT
- A credential-hardening pattern using:
  - `creds_get.sh` (decrypt + load)
  - `creds_shred.sh` (securely wipe)

Backups are stored in:

```

s3://<BackupBucketName>/<S3Prefix>/<repo-name>/<YYYY-MM-DD>/<repo-name>-<timestamp>.zip

```

---

## Features

- Backs up **all repos owned** by a GitHub username  
  (public + private; optional forks + archived).
- Streamed ZIP downloads → S3, no disk usage.
- Minimal IAM permissions.
- Deployment flow supports:
  - **Makefile** (`make deploy`)
  - **Shell script** (`./deploy.sh`)
- Local test execution (`make test-local` or `./local_run.sh`).
- Encrypted credential workflow (GPG).

---

## Project Structure

```
.
├── lambda_function.py
├── template.yaml
├── Makefile
├── deploy.sh
├── local_run.py
├── local_run.sh
├── creds_get.sh
├── creds_shred.sh
├── docs/
│   ├── README.md
│   ├── DEPLOYMENT_WRAPPERS.md
│   └── LOCAL_RUNS.md
```

---

## Prerequisites

- AWS CLI v2
- Python 3.11+
- An S3 bucket for backups
- An S3 bucket for Lambda artifacts
- (Recommended) A GitHub PAT stored in:
  - `~/.github-token.gpg` **OR**
  - AWS Secrets Manager

---

## Quick Start

### Deploy using Makefile

```bash
make deploy \
  GITHUB_USERNAME=mygithubuser \
  BACKUP_BUCKET=my-github-backups \
  ARTIFACTS_BUCKET=my-artifacts-bucket \
  LAMBDA_CODE_KEY=github-backup/github-backup-lambda.zip \
  GITHUB_TOKEN_SECRET_ARN=arn:aws:secretsmanager:us-east-1:1234:secret:github/pat-AbCd
````

### Deploy using shell script

```bash
export GITHUB_USERNAME=mygithubuser
export BACKUP_BUCKET=my-github-backups
export ARTIFACTS_BUCKET=my-artifacts-bucket
export LAMBDA_CODE_KEY=github-backup/github-backup-lambda.zip
export GITHUB_TOKEN_SECRET_ARN=arn:aws:secretsmanager:us-east-1:...

./deploy.sh
```

---

## Local Testing

You can run the Lambda code locally, with real AWS + GitHub interactions:

```
make test-local
```

or:

```
./local_run.sh
```

(See **LOCAL_RUNS.md** for full details.)

---

## Additional Documentation

* **DEPLOYMENT_WRAPPERS.md** — How `creds_get.sh`/`creds_shred.sh` work + Makefile and deploy script
* **LOCAL_RUNS.md** — How to test the Lambda locally safely
