#!/usr/bin/env bash
set -euo pipefail

# Auto-activate ./.venv if present (so users don't have to remember to `source` it).
if [[ -f ./.venv/bin/activate ]]; then
  # shellcheck disable=SC1091
  source ./.venv/bin/activate
  echo "[local_run] Activated venv: $(python3 -c 'import sys; print(sys.executable)')"
fi

# Get creds (AWS + GitHub token)
if [[ -f ./creds_get.sh ]]; then
  source ./creds_get.sh
else
  echo "[local_run] WARNING: creds_get.sh not found; continuing without it."
fi

echo "[local_run] Running lambda_function.lambda_handler locally..."
python3 local_run.py

# Shred creds afterward
if [[ -f ./creds_shred.sh ]]; then
  source ./creds_shred.sh
else
  echo "[local_run] WARNING: creds_shred.sh not found; credentials not shredded."
fi
