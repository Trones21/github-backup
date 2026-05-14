import os
import json
import logging
from datetime import datetime, timezone

import boto3
import requests

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")
secrets_client = boto3.client("secretsmanager")

# Environment vars (passed from CloudFormation)
GITHUB_USERNAME = os.environ["GITHUB_USERNAME"]
S3_BUCKET = os.environ["S3_BUCKET"]
S3_PREFIX = os.environ.get("S3_PREFIX", "").strip("/")

INCLUDE_FORKS = os.environ.get("INCLUDE_FORKS", "false").lower() == "true"
INCLUDE_ARCHIVED = os.environ.get("INCLUDE_ARCHIVED", "true").lower() == "true"

GITHUB_TOKEN_ENV = os.environ.get("GITHUB_TOKEN", "")
GITHUB_TOKEN_SECRET_ARN = os.environ.get("GITHUB_TOKEN_SECRET_ARN", "").strip()


# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

def _now_strings():
    now = datetime.now(timezone.utc)
    return now.strftime("%Y-%m-%d"), now.strftime("%Y%m%dT%H%M%SZ")


def _s3_key_for_repo(repo_name, date_str, ts_str):
    parts = []
    if S3_PREFIX:
        parts.append(S3_PREFIX)
    parts.append(repo_name)
    parts.append(date_str)
    prefix = "/".join(parts)
    filename = f"{repo_name}-{ts_str}.tar.gz"
    return f"{prefix}/{filename}"


def _get_github_token():
    # Secrets Manager version
    if GITHUB_TOKEN_SECRET_ARN:
        logger.info(f"Loading GitHub PAT from Secrets Manager ARN: {GITHUB_TOKEN_SECRET_ARN}")
        resp = secrets_client.get_secret_value(SecretId=GITHUB_TOKEN_SECRET_ARN)
        val = resp.get("SecretString", "")

        # If JSON, extract `token`
        try:
            obj = json.loads(val)
            return obj.get("token", val)
        except json.JSONDecodeError:
            return val

    # Env var fallback
    if GITHUB_TOKEN_ENV:
        return GITHUB_TOKEN_ENV

    raise RuntimeError("No GitHub token configured (env var or Secrets Manager).")


def _github_headers():
    token = _get_github_token()
    return {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "User-Agent": "github-backup-lambda",
    }


# ------------------------------------------------------------
# GitHub Operations
# ------------------------------------------------------------

def _list_all_repos_for_user():
    """List all repos owned by the authenticated user."""
    url = "https://api.github.com/user/repos"

    params = {
        "per_page": 100,
        "page": 1,
        "affiliation": "owner",
        "visibility": "all",
        "sort": "full_name",
        "direction": "asc",
    }

    headers = _github_headers()
    repos = []

    while True:
        resp = requests.get(url, headers=headers, params=params, timeout=30)
        if resp.status_code != 200:
            raise RuntimeError(
                f"Failed to list repos: {resp.status_code} {resp.text[:500]}"
            )
        batch = resp.json()
        if not batch:
            break

        repos.extend(batch)

        if len(batch) < 100:
            break
        params["page"] += 1

    # Filter to only repos owned by exactly this username
    owned = [r for r in repos if r.get("owner", {}).get("login") == GITHUB_USERNAME]

    if not INCLUDE_FORKS:
        owned = [r for r in owned if not r.get("fork", False)]

    if not INCLUDE_ARCHIVED:
        owned = [r for r in owned if not r.get("archived", False)]

    logger.info(f"Found {len(owned)} repos owned by {GITHUB_USERNAME}")
    return owned


def _download_repo_archive(owner, repo_name):
    """Stream the .tar.gz archive of the default branch from GitHub.

    Returns (stream, size_bytes_or_None). size_bytes is None if the response
    is chunked and Content-Length isn't provided.
    """
    url = f"https://api.github.com/repos/{owner}/{repo_name}/tarball"
    headers = _github_headers()

    resp = requests.get(url, headers=headers, stream=True, timeout=300)
    if resp.status_code != 200:
        raise RuntimeError(
            f"Failed to download {owner}/{repo_name}: {resp.status_code} {resp.text[:500]}"
        )

    content_length = resp.headers.get("Content-Length")
    size_bytes = int(content_length) if content_length else None
    return resp.raw, size_bytes


# ------------------------------------------------------------
# Backup Orchestration
# ------------------------------------------------------------

def _backup_repo(repo, date_str, ts_str):
    name = repo["name"]
    owner = repo["owner"]["login"]

    s3_key = _s3_key_for_repo(name, date_str, ts_str)
    stream, size_bytes = _download_repo_archive(owner, name)
    size_str = f"{size_bytes / (1024 * 1024):.1f} MB" if size_bytes else "size unknown"
    logger.info(f"Backing up {owner}/{name} ({size_str}) → s3://{S3_BUCKET}/{s3_key}")

    s3.upload_fileobj(stream, S3_BUCKET, s3_key)

    logger.info(f"Completed backup for {owner}/{name}")
    return s3_key


def lambda_handler(event, context):
    logger.info("Starting GitHub user backup run…")

    date_str, ts_str = _now_strings()
    repos = _list_all_repos_for_user()

    successes = []
    failures = []

    for repo in repos:
        full_name = repo.get("full_name", "<unknown>")
        try:
            s3_key = _backup_repo(repo, date_str, ts_str)
            successes.append({"repo": full_name, "s3_key": s3_key})
        except Exception as e:
            logger.exception(f"Backup failed for {full_name}")
            failures.append({"repo": full_name, "error": str(e)})

    logger.info(f"Run complete: {len(successes)} succeeded, {len(failures)} failed")

    return {
        "statusCode": 200,
        "body": {
            "date": date_str,
            "success_count": len(successes),
            "failure_count": len(failures),
            "successes": successes,
            "failures": failures,
        },
    }
