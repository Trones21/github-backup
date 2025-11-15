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

# Optional: decrypt GitHub token into env var
# ~/.github-token.gpg holds just the raw GitHub PAT
if [[ -f "$HOME/.github-token.gpg" ]]; then
  export GITHUB_TOKEN="$(gpg -d "$HOME/.github-token.gpg")"
  echo "[creds_get] Exported GITHUB_TOKEN from ~/.github-token.gpg"
fi

# If you prefer a full env file instead:
# if [[ -f "$HOME/.github-env.gpg" ]]; then
#   tmpfile=$(mktemp)
#   gpg -d "$HOME/.github-env.gpg" > "$tmpfile"
#   set -a
#   source "$tmpfile"
#   set +a
#   rm -f "$tmpfile"
#   echo "[creds_get] Loaded GitHub env vars from ~/.github-env.gpg"
# fi
