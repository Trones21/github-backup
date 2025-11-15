#!/usr/bin/env bash
set -euo pipefail

# Shred AWS credentials file
if [[ -f "$HOME/.aws/credentials" ]]; then
  shred -u "$HOME/.aws/credentials"
  echo "[creds_shred] Shredded ~/.aws/credentials"
else
  echo "[creds_shred] No ~/.aws/credentials to shred"
fi

# Unset GitHub env vars (effective when sourced)
if [[ "${GITHUB_TOKEN-}" != "" ]]; then
  unset GITHUB_TOKEN
  echo "[creds_shred] Unset GITHUB_TOKEN"
fi

# Add any other sensitive env vars you want to clean up here
