# GitHub → S3 Backup

Back up **all GitHub repositories owned by a user** to S3 as zipballs.

This project supports two modes against the same backup logic ([lambda_function.py](../lambda_function.py)):

### On-demand mode (run from your laptop)

Run the backup right now, from your shell, against a bucket you own. No AWS infrastructure to deploy — just credentials and a bucket.

```bash
./local_run.sh
```

Good for: first-time tryout, ad-hoc backups, debugging, or if you don't want a scheduled Lambda at all.

### Scheduled mode (deployed AWS Lambda + EventBridge)

Deploy the same code as a Lambda that runs on a cron schedule (default: 05:00 UTC on the 1st of each month).

```bash
make deploy ...
```

Good for: hands-off recurring backups. Requires a small CloudFormation stack.

Most people start with on-demand to validate the flow, then graduate to scheduled.

Backups land at:

```
s3://<BackupBucket>/<S3Prefix>/<repo-name>/<YYYY-MM-DD>/<repo-name>-<timestamp>.tar.gz
```

Source archives are pulled from the GitHub [tarball endpoint](https://docs.github.com/en/rest/repos/contents#download-a-repository-archive-tar) (already gzipped by GitHub) and streamed directly to S3.

---

## Features

- Backs up **all repos owned** by a GitHub username (public + private; optional forks + archived).
- Streamed `.tar.gz` downloads → S3 (no disk usage).
- Minimal IAM permissions.
- Deployment options: `make deploy` or `./deploy.sh`.
- Local run via `make test-local` or `./local_run.sh`.
- Encrypted credential workflow (GPG) — nothing decrypted is left on disk.

---

## Project Structure

```
.
├── lambda_function.py       # core backup logic (used by both modes)
├── local_run.py             # imports lambda_handler and invokes it locally
├── local_run.sh             # on-demand wrapper (creds → run → shred)
├── deploy.sh                # scheduled-mode deploy wrapper
├── Makefile                 # make targets for deploy / test-local / etc.
├── template.yaml            # CloudFormation stack (Lambda + EventBridge + IAM)
├── creds_get.sh             # decrypt GPG creds into shell session
├── creds_shred.sh           # wipe creds after run
├── requirements-local.txt   # Python deps for on-demand mode
└── docs/
    ├── README.md
    ├── LOCAL_RUNS.md        # on-demand mode setup + run
    └── DEPLOYMENT_WRAPPERS.md # scheduled mode + credential pattern
```

---

## Prerequisites

### Common (both modes)

- **AWS CLI v2** — [install instructions](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html), then configure with `aws configure` or by placing credentials at `~/.aws/credentials`.
- **An AWS account** and an IAM user/role with permission to write to your backup bucket.
- **A GitHub Personal Access Token (PAT)** — see [Creating a GitHub PAT](#creating-a-github-pat) below.
- **An S3 bucket for backups** — see [Creating the backup bucket](#creating-the-backup-bucket) below. **CloudFormation does not create this for you.**
- **GPG** (for the encrypted credentials workflow). Optional if you skip the wrappers.

### On-demand mode only

- **Python 3.11+** on your machine.
- **`boto3` and `requests`** Python packages: `pip install -r requirements-local.txt` (a venv is recommended).

### Scheduled mode only

- **A second S3 bucket for Lambda artifacts** (the deploy uploads the function ZIP here). Can be the same bucket as backups, but a separate one is cleaner.
- Permission to create CloudFormation stacks, IAM roles, Lambda functions, and EventBridge rules.

---

## Creating the backup bucket

This project **does not** create the S3 bucket — you make it yourself, then pass its name into the run/deploy.

```bash
# us-east-1 (note: us-east-1 does NOT take a LocationConstraint)
aws s3api create-bucket \
  --bucket my-github-backups \
  --region us-east-1

# any other region
aws s3api create-bucket \
  --bucket my-github-backups \
  --region us-west-2 \
  --create-bucket-configuration LocationConstraint=us-west-2

# (recommended) block all public access
aws s3api put-public-access-block \
  --bucket my-github-backups \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# (recommended) enable versioning so old backups aren't lost on accidental overwrite
aws s3api put-bucket-versioning \
  --bucket my-github-backups \
  --versioning-configuration Status=Enabled
```

Bucket names are globally unique — pick something namespaced (e.g. `<your-handle>-github-backups`).

For **scheduled mode**, repeat for an artifacts bucket (or reuse the backup bucket with a distinct prefix).

## Creating a GitHub PAT

The backup uses two GitHub API calls: `GET /user/repos` (list owned repos) and `GET /repos/{owner}/{repo}/zipball` (download the source archive). Both can be authorized with a classic PAT.

Open https://github.com/settings/tokens/new and:

1. **Note** — give it a recognizable name, e.g. `github-backup-lambda`.
2. **Expiration** — your call; 90 days is the default, "No expiration" works if you'll rotate it yourself.
3. **Select scopes** — check **one** of:
   - ☑ **`repo`** (full control of private repositories) — required if you want to back up your **private** repos. This is the right pick for most users.
   - ☑ **`public_repo`** (under the `repo` group) — sufficient if you only need to back up **public** repos.

   You do **not** need `workflow`, `admin:*`, `delete_repo`, `gist`, `notifications`, or any of the `user:*` / `write:*` scopes. Keep the surface area small.
4. Click **Generate token** and copy the `ghp_…` value — GitHub only shows it once.

> **Fine-grained PATs** (https://github.com/settings/personal-access-tokens/new) also work. Grant access to the repos you want backed up, with **Repository permissions → Contents: Read-only** and **Metadata: Read-only**. Classic is simpler for this use case.

### Storing the PAT

[creds_get.sh](../creds_get.sh) decrypts the token at runtime and exports `GITHUB_TOKEN`. It reads from `$GITHUB_TOKEN_GPG_PATH` (default `~/.github-token.gpg`) and works with any GPG-encrypted file — symmetric (`gpg -c`) or asymmetric (e.g. `pass`). Pick **one** of the options below.

**Option A — symmetric encryption with `gpg -c`** (simplest; passphrase-based, no GPG key required)

```bash
# Prompts for a passphrase. The passphrase will be needed every decrypt
# (or cached by gpg-agent for a while).
printf '%s' 'ghp_yourtoken' | gpg -c -o ~/.github-token.gpg
```

The default path `~/.github-token.gpg` is what `creds_get.sh` looks at by default — no env var needed.

**Option B — `pass`** (if you already have a `pass` setup — see https://www.passwordstore.org/)

```bash
# One-time, if you haven't initialized pass yet:
pass init <your-gpg-id>       # e.g. your GPG key's email

# Insert the token. `-m` lets you paste multi-line, but a single line is fine too.
pass insert github/backup-pat
# (paste ghp_yourtoken, press Enter, Ctrl+D)

# Tell creds_get.sh where to find it:
export GITHUB_TOKEN_GPG_PATH="$HOME/.password-store/github/backup-pat.gpg"
```

You can put that `export` in your `~/.bashrc`/`~/.zshrc`, or in `~/.github-env.gpg` (see [LOCAL_RUNS.md §1e](LOCAL_RUNS.md#1e-set-the-other-env-vars)).

Note: `pass` encrypts asymmetrically against your GPG key. `creds_get.sh` invokes `gpg -d` directly on the file — it does **not** call `pass show` — so your private key just needs to be available via `gpg-agent`. Both storage methods produce `.gpg` files and both work transparently with `gpg -d`.

**Option C — plain env var** (quick local testing; the token sits in your shell history/process env)

```bash
export GITHUB_TOKEN=ghp_yourtoken
```

`creds_get.sh` skips the decrypt step if the file at `$GITHUB_TOKEN_GPG_PATH` doesn't exist and just uses whatever you've exported.

---

### Sanity check your AWS setup

Before running anything, confirm the CLI is wired up to the account you expect:

```bash
aws sts get-caller-identity
```

You should see your account ID and IAM user/role ARN. If this fails, fix it before continuing — every subsequent step depends on it.

---

## Quick Start — On-demand

See [LOCAL_RUNS.md](LOCAL_RUNS.md) for the full walkthrough. Short version:

```bash
# one-time setup (venv is required on modern Debian/Ubuntu due to PEP 668)
python3 -m venv .venv
.venv/bin/pip install -r requirements-local.txt

# every run
export GITHUB_USERNAME=mygithubuser              # GitHub user whose repos to back up
export S3_BUCKET=my-github-backups               # bucket you created above
export GITHUB_TOKEN=ghp_...                      # or set up ~/.github-token.gpg
./local_run.sh                                   # auto-activates ./.venv
```

---

## Quick Start — Scheduled (CloudFormation)

### Using Makefile

```bash
make deploy \
  GITHUB_USERNAME=mygithubuser \
  BACKUP_BUCKET=my-github-backups \
  ARTIFACTS_BUCKET=my-artifacts-bucket \
  LAMBDA_CODE_KEY=github-backup/github-backup-lambda.zip \
  GITHUB_TOKEN_SECRET_ARN=arn:aws:secretsmanager:us-east-1:1234:secret:github/pat-AbCd
```

### Using shell script

```bash
export GITHUB_USERNAME=mygithubuser
export BACKUP_BUCKET=my-github-backups
export ARTIFACTS_BUCKET=my-artifacts-bucket
export LAMBDA_CODE_KEY=github-backup/github-backup-lambda.zip
export GITHUB_TOKEN_SECRET_ARN=arn:aws:secretsmanager:us-east-1:...

./deploy.sh
```

See [DEPLOYMENT_WRAPPERS.md](DEPLOYMENT_WRAPPERS.md) for full details and the credential wrapper pattern.

---

## Additional Documentation

- **[LOCAL_RUNS.md](LOCAL_RUNS.md)** — on-demand setup (Python deps, GPG files, env vars, region) and the run loop.
- **[DEPLOYMENT_WRAPPERS.md](DEPLOYMENT_WRAPPERS.md)** — how `creds_get.sh`/`creds_shred.sh` work, plus the Makefile and `deploy.sh` for scheduled mode.
