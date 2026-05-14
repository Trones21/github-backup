#!/usr/bin/env bash
set -euo pipefail

# Decrypt AWS credentials
if [[ -f "$HOME/.aws/credentials.gpg" ]]; then
  mkdir -p "$HOME/.aws"
  gpg -d "$HOME/.aws/credentials.gpg" > "$HOME/.aws/credentials"
  echo "[creds_get] Decrypted AWS credentials to ~/.aws/credentials"
else
  echo "[creds_get] WARNING: ~/.aws/credentials.gpg not found"
fi

# Decrypt GitHub PAT into GITHUB_TOKEN.
# Set GITHUB_TOKEN_GPG_PATH to point at any GPG-encrypted file:
#   - a symmetric file you made with `gpg -c` (default location below)
#   - a `pass` entry under ~/.password-store/<name>.gpg
#   - any other GPG-encrypted file
# Both symmetric and asymmetric (pass) files work — gpg -d auto-detects.
GITHUB_TOKEN_GPG_PATH="${GITHUB_TOKEN_GPG_PATH:-$HOME/.github-token.gpg}"

if [[ -f "$GITHUB_TOKEN_GPG_PATH" ]]; then
  # First line only — `pass` keeps the password on line 1, metadata after.
  __decrypted="$(gpg -d "$GITHUB_TOKEN_GPG_PATH")"
  export GITHUB_TOKEN="${__decrypted%%$'\n'*}"
  unset __decrypted
  echo "[creds_get] Exported GITHUB_TOKEN from $GITHUB_TOKEN_GPG_PATH"
else
  echo "[creds_get] $GITHUB_TOKEN_GPG_PATH not found; export GITHUB_TOKEN manually or set GITHUB_TOKEN_GPG_PATH"
fi

# Optional encrypted env file with GITHUB_USERNAME / S3_BUCKET / AWS_REGION / etc.
# Plaintext format: standard KEY=value lines, one per line.
if [[ -f "$HOME/.github-env.gpg" ]]; then
  tmpfile=$(mktemp)
  gpg -d "$HOME/.github-env.gpg" > "$tmpfile"
  set -a
  source "$tmpfile"
  set +a
  rm -f "$tmpfile"
  echo "[creds_get] Loaded env vars from ~/.github-env.gpg"
fi
