
# Deployment Wrappers (& Credential Hardening)

This project uses a **secure wrapper pattern** for deployments:

1. **Decrypt credentials into session** (`creds_get.sh`)
2. **Run deployment or packaging logic**
3. **Securely shred credentials** (`creds_shred.sh`)

This ensures the machine never leaves decrypted AWS credentials or GitHub tokens behind.

---

# 1. Credential Scripts

## `creds_get.sh`

- Decrypts `~/.aws/credentials.gpg` → `~/.aws/credentials` (if present)
- Decrypts `$GITHUB_TOKEN_GPG_PATH` (default `~/.github-token.gpg`) → exports `GITHUB_TOKEN` (if file exists)
- Decrypts `~/.github-env.gpg` → sources additional env vars (if present)

Each step is skipped silently if the corresponding `.gpg` file is missing, so you can adopt the wrapper incrementally.

The GitHub-token step works with any GPG-encrypted file: a symmetric file (`gpg -c`) or an asymmetric one like a `pass` entry. Point `GITHUB_TOKEN_GPG_PATH` at `~/.password-store/<name>.gpg` and `creds_get.sh` will `gpg -d` it directly — no `pass` invocation needed. See [README.md → Storing the PAT](README.md#storing-the-pat) for the three options.

The `~/.github-env.gpg` file is a standard `KEY=value` env file, encrypted with `gpg -c`. Typical contents for on-demand mode:

```
GITHUB_USERNAME=mygithubuser
S3_BUCKET=my-github-backups
S3_PREFIX=github-backups
INCLUDE_FORKS=false
INCLUDE_ARCHIVED=true
AWS_REGION=us-east-1
```

Usage:

```bash
source ./creds_get.sh
````

---

## `creds_shred.sh`

* Shreds `~/.aws/credentials` using `shred -u`
* Unsets sensitive env vars such as `GITHUB_TOKEN`

Usage:

```bash
source ./creds_shred.sh
```

---

# 2. Deployment Pipelines

You can deploy using either:

* **Makefile**
* **Shell script (`deploy.sh`)**

Both use the same workflow:

```
source creds_get.sh
<package + upload + cfn deploy>
source creds_shred.sh
```

---

# 3. Makefile Workflow

## `make deploy`

Does everything:

1. Builds Lambda zip
2. Uploads to artifact bucket
3. Runs CloudFormation deploy
4. Wraps all AWS calls with credential scripts

Example:

```bash
make deploy \
  GITHUB_USERNAME=mygithubuser \
  BACKUP_BUCKET=my-github-backups \
  ARTIFACTS_BUCKET=my-artifacts-bucket \
  GITHUB_TOKEN_SECRET_ARN=arn:aws:secretsmanager:us-east-1:...
```

---

# 4. Shell Script Workflow

Run:

```bash
./deploy.sh
```

Internally:

```
source creds_get.sh
build zip
aws s3 cp zip
aws cloudformation deploy
source creds_shred.sh
```

This is the same as Makefile, just not coupled to GNU Make.

---

# 5. Why This Pattern?

This solves:

* **No decrypted credentials left on disk**
* **No AWS profile files lingering**
* **GitHub secrets never persist**
* Perfect for:

  * Shared dev machines
  * EC2/VM deploy hosts
  * CI runners
  * Personal workstations with encrypted vaults

This is the same pattern used in high-security internal tooling (e.g. air-gapped build machines).

```