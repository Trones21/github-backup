# Local Lambda Testing (With Secure Credential Wrappers)

You can run the Lambda function **locally**, using real GitHub + AWS API calls, without deploying anything.

This uses:

- `local_run.py` — direct Python execution  
- `local_run.sh` — wrapper with `creds_get` + `creds_shred`  
- `make test-local`

---

# 1. Local Test Flow

The local test wrapper works like:

````

source creds_get.sh
python local_run.py
source creds_shred.sh

````

This ensures:

- AWS CLI calls work
- GitHub PAT is loaded
- No credentials remain afterward

---

# 2. Running Locally

## Option A: Use make

```bash
make test-local
````

## Option B: Use script directly

```bash
./local_run.sh
```

## Option C: Pure Python

(Useful for debugging)

```bash
source creds_get.sh
python local_run.py
source creds_shred.sh
```

---

# 3. Environment Variables Required

Before running local tests, set:

```
export GITHUB_USERNAME=mygithubuser
export S3_BUCKET=my-github-backups
export S3_PREFIX=github-backups
export INCLUDE_FORKS=false
export INCLUDE_ARCHIVED=true
```

If you’re not using Secrets Manager locally:

```
export GITHUB_TOKEN=ghp_...
```

If using the encrypted token:

```
~/.github-token.gpg → decrypted and exported automatically via creds_get.sh
```

---

# 4. What Happens During Local Run?

`local_run.py` loads `lambda_function.lambda_handler` and runs it with:

```
event = {}
context = None
```

It performs:

* GitHub API calls to list repos
* GitHub API downloads of repo ZIPs
* S3 uploads of the backups

Everything is real.

---

# 5. Local Testing Safety

* Credentials decrypted only for the duration of the test
* Automatically shredded afterward
* No `.aws/credentials` file left behind
* No GitHub token left in the environment

This matches your deployment security model.

---

# 6. Local Debug Tips

### Fast failure on authentication:

```bash
aws sts get-caller-identity
```

### Inspect the downloaded S3 keys:

```bash
aws s3 ls s3://my-github-backups/github-backups/
```

### Run handler with debug prints:

```bash
python -m pdb local_run.py
```
