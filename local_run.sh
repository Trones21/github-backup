#!/usr/bin/env bash
set -euo pipefail

# Get creds (AWS + GitHub token)
if [[ -x ./creds_get.sh ]]; then
  source ./creds_get.sh
else
  echo "[local_run] WARNING: creds_get.sh not found or not executable; continuing without it."
fi

echo "[local_run] Running lambda_function.lambda_handler locally..."
python local_run.py

# Shred creds afterward
if [[ -x ./creds_shred.sh ]]; then
  source ./creds_shred.sh
else
  echo "[local_run] WARNING: creds_shred.sh not found or not executable; credentials not shredded."
fi
