# Local (On-demand) Lambda Runs

Run the backup logic **right now**, from your laptop, against real GitHub + real S3. No CloudFormation, no Lambda — just the same code in [lambda_function.py](../lambda_function.py) invoked directly.

Entry points:

- [local_run.py](../local_run.py) — imports `lambda_handler` and calls it with an empty event
- [local_run.sh](../local_run.sh) — wrapper: `creds_get` → run → `creds_shred`
- `make test-local` — equivalent to `./local_run.sh`

---

## 1. One-time setup

You need three things before your first run: Python deps, AWS credentials, and a GitHub token. Skip steps you've already done.

### 1a. Install Python deps in a venv

The Lambda runtime ships `boto3` automatically; locally you have to install it. On modern Debian/Ubuntu and most package-managed Python installs, a plain `pip install` will fail with `error: externally-managed-environment` (PEP 668) — so we use a venv. It's a one-time setup.

From the repo root:

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements-local.txt
```

That's it — you don't need to `source .venv/bin/activate` yourself. [local_run.sh](../local_run.sh) auto-activates `./.venv` if it exists, so subsequent runs just work.

> If `python3 -m venv` fails with a `python3-venv` error on Debian/Ubuntu, install it first: `sudo apt install python3-venv` (or `python3-full`).

### 1b. Get AWS credentials onto your machine

If you haven't already configured the AWS CLI:

```bash
aws configure
# enter Access Key ID, Secret, default region, default output
```

Sanity-check:

```bash
aws sts get-caller-identity
```

You should see your account/user. If not, stop and fix this first.

### 1c. Encrypt your AWS credentials (optional, recommended)

The scripts in this repo follow a "decrypt on use, shred after" pattern so plaintext AWS creds aren't left at rest. To opt in, encrypt your `~/.aws/credentials`:

```bash
gpg -c ~/.aws/credentials                # creates ~/.aws/credentials.gpg
shred -u ~/.aws/credentials              # delete the plaintext
```

`creds_get.sh` will decrypt it before each run; `creds_shred.sh` will wipe the decrypted copy afterward.

If you'd rather just use plaintext `~/.aws/credentials`, you can — the scripts will just print a warning and continue. The on-demand flow still works.

### 1d. Get a GitHub PAT

Create a classic PAT at https://github.com/settings/tokens/new.

**Scope to check:**

- ☑ **`repo`** (full control of private repositories) — needed if you want **private** repos backed up.
- ☑ **`public_repo`** (under the `repo` group) — sufficient if you only need **public** repos.

No other scopes are needed.

Store it one of three ways (full walkthrough in [README.md → Storing the PAT](README.md#storing-the-pat)):

```bash
# A) symmetric gpg encryption (default location creds_get.sh looks at)
printf '%s' 'ghp_yourtoken' | gpg -c -o ~/.github-token.gpg

# B) pass (your existing password store) — point creds_get.sh at the file
pass insert github/backup-pat
export GITHUB_TOKEN_GPG_PATH="$HOME/.password-store/github/backup-pat.gpg"

# C) plain env var (no encryption at rest)
export GITHUB_TOKEN=ghp_yourtoken
```

`creds_get.sh` reads `$GITHUB_TOKEN_GPG_PATH` (default `~/.github-token.gpg`) and runs `gpg -d` on it — works for both `gpg -c` files and `pass` entries since both are standard GPG-encrypted files.

### 1e. Set the other env vars

The backup code needs to know which user and which bucket. You have two options:

**Option 1 — encrypted env file (recommended; auto-loaded by `creds_get.sh`):**

```bash
cat > /tmp/github-env <<'EOF'
GITHUB_USERNAME=mygithubuser
S3_BUCKET=my-github-backups
S3_PREFIX=github-backups
INCLUDE_FORKS=false
INCLUDE_ARCHIVED=true
AWS_REGION=us-east-1
EOF

gpg -c -o ~/.github-env.gpg /tmp/github-env
shred -u /tmp/github-env
```

**Option 2 — export them yourself before each run:**

```bash
export GITHUB_USERNAME=mygithubuser
export S3_BUCKET=my-github-backups
export S3_PREFIX=github-backups        # optional, defaults to ""
export INCLUDE_FORKS=false             # optional, defaults to false
export INCLUDE_ARCHIVED=true           # optional, defaults to true
export AWS_REGION=us-east-1            # if your bucket isn't in your CLI default
```

**Note on region:** boto3 picks up the region from (in order) `AWS_REGION`, `AWS_DEFAULT_REGION`, `~/.aws/credentials`, or `~/.aws/config`. If your backup bucket is in a different region than your CLI default, set `AWS_REGION` explicitly.

---

## 2. Run it

### Option A: `make test-local`

```bash
make test-local
```

### Option B: `./local_run.sh`

```bash
./local_run.sh
```

### Option C: manually (for debugging)

```bash
source creds_get.sh
python3 local_run.py
source creds_shred.sh
```

---

## 3. What actually happens

`local_run.py` imports `lambda_handler` from `lambda_function.py` and calls it with `event={}, context=None`. The handler:

1. Lists all repos owned by `GITHUB_USERNAME` via the GitHub API.
2. For each repo, streams its `.tar.gz` archive download from GitHub → uploads to `s3://$S3_BUCKET/<prefix>/<repo>/<date>/<repo>-<ts>.tar.gz`.
3. Returns a JSON summary of successes and failures, which `local_run.py` pretty-prints to stdout.

These are **real** API calls and **real** S3 uploads. They cost real money (negligible for personal use) and create real objects in your bucket.

---

## 4. Verifying it worked

```bash
aws s3 ls s3://my-github-backups/github-backups/ --recursive --human-readable --summarize
```

You should see one zip per repo under `<prefix>/<repo>/<date>/`.

---

## 5. Safety model

When using the encrypted-creds flow:

- `~/.aws/credentials` is decrypted only for the duration of the run.
- `GITHUB_TOKEN` is exported into the shell environment, then `unset` by `creds_shred.sh`.
- `~/.aws/credentials` (plaintext) is `shred -u`'d after the run.
- No decrypted artifacts remain on disk.

Matches the deployment security model in [DEPLOYMENT_WRAPPERS.md](DEPLOYMENT_WRAPPERS.md).

---

## 6. Debug tips

**Auth failing fast:**

```bash
aws sts get-caller-identity                    # AWS side
curl -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://api.github.com/user                  # GitHub side
```

**Inspect uploaded objects:**

```bash
aws s3 ls s3://$S3_BUCKET/$S3_PREFIX/ --recursive
```

**Run under pdb:**

```bash
python3 -m pdb local_run.py
```

**`error: externally-managed-environment` from pip:** you ran `pip install` against system Python. Modern Debian/Ubuntu (PEP 668) blocks that. Use a venv — see [§1a](#1a-install-python-deps-in-a-venv).

**Missing module errors when running:** the venv isn't being picked up. Confirm `./.venv/bin/activate` exists; `local_run.sh` auto-sources it. If you're running `python3 local_run.py` directly, `source .venv/bin/activate` first.

**`KeyError: 'GITHUB_USERNAME'` or `'S3_BUCKET'`:** env vars not loaded. Either set up `~/.github-env.gpg` (step 1e Option 1) or `export` them in your shell (Option 2).
