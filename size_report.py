#!/usr/bin/env python3
"""
Report on GitHub repo sizes for the authenticated user.

Useful for spotting repos where node_modules / build output / large binaries
were accidentally committed before kicking off a real backup.

Usage:
    python3 size_report.py                          # top 20 repos by size
    python3 size_report.py --top 50                 # show 50 instead
    python3 size_report.py --top 10 --files         # also list largest files
                                                     #   in each top-10 repo
    python3 size_report.py --include-forks          # include forks
    python3 size_report.py --exclude-archived       # drop archived repos

Requires: GITHUB_TOKEN env var. Works with the same creds_get.sh flow as
local_run.sh.
"""
import argparse
import logging
import os
import sys

import requests

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger(__name__)


def _headers():
    token = os.environ.get("GITHUB_TOKEN")
    if not token:
        sys.exit("GITHUB_TOKEN not set. Source creds_get.sh or export it manually.")
    return {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "User-Agent": "github-backup-size-report",
    }


def list_owned_repos(include_forks: bool, include_archived: bool):
    url = "https://api.github.com/user/repos"
    params = {
        "per_page": 100,
        "page": 1,
        "affiliation": "owner",
        "visibility": "all",
        "sort": "full_name",
    }
    headers = _headers()
    repos = []
    while True:
        resp = requests.get(url, headers=headers, params=params, timeout=30)
        resp.raise_for_status()
        batch = resp.json()
        if not batch:
            break
        repos.extend(batch)
        if len(batch) < params["per_page"]:
            break
        params["page"] += 1

    if not include_forks:
        repos = [r for r in repos if not r.get("fork", False)]
    if not include_archived:
        repos = [r for r in repos if not r.get("archived", False)]
    return repos


def top_files_in_repo(full_name: str, default_branch: str, top: int):
    """Use the recursive tree API to find the largest blobs in the default branch.

    Returns (blobs, truncated) where blobs is a list of (path, size_bytes)
    sorted desc, and `truncated` indicates GitHub clipped the response.
    """
    url = f"https://api.github.com/repos/{full_name}/git/trees/{default_branch}?recursive=1"
    resp = requests.get(url, headers=_headers(), timeout=30)
    if resp.status_code != 200:
        log.warning(f"{full_name}: tree fetch failed ({resp.status_code})")
        return [], False
    data = resp.json()
    truncated = bool(data.get("truncated", False))
    blobs = [
        (entry["path"], entry.get("size", 0))
        for entry in data.get("tree", [])
        if entry.get("type") == "blob"
    ]
    blobs.sort(key=lambda x: x[1], reverse=True)
    return blobs[:top], truncated


def fmt_bytes(b):
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if b < 1024:
            return f"{b:.1f} {unit}"
        b /= 1024
    return f"{b:.1f} PB"


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--top", type=int, default=20, help="show top N repos by size (default: 20)")
    p.add_argument("--files", action="store_true",
                   help="also list the largest files in each of the top-N repos (uses default-branch tree)")
    p.add_argument("--files-top", type=int, default=10,
                   help="how many files to show per repo when --files is set (default: 10)")
    p.add_argument("--include-forks", action="store_true")
    archived_grp = p.add_mutually_exclusive_group()
    archived_grp.add_argument("--include-archived", dest="include_archived", action="store_true", default=True)
    archived_grp.add_argument("--exclude-archived", dest="include_archived", action="store_false")
    args = p.parse_args()

    log.info("Listing repos…")
    repos = list_owned_repos(args.include_forks, args.include_archived)
    log.info(f"Got {len(repos)} repos")

    repos.sort(key=lambda r: r["size"], reverse=True)
    shown = repos[: args.top]

    print()
    print(f"{'Size':>10}  {'Pushed':<19}  Repo")
    print(f"{'-' * 10}  {'-' * 19}  {'-' * 40}")
    for r in shown:
        size_str = fmt_bytes(r["size"] * 1024)
        pushed = (r.get("pushed_at") or "")[:19]
        print(f"{size_str:>10}  {pushed:<19}  {r['full_name']}")

    if args.files:
        print()
        print("=" * 80)
        print(f"Largest files in top {len(shown)} repos (default branch only)")
        print("=" * 80)
        for r in shown:
            full_name = r["full_name"]
            branch = r.get("default_branch") or "main"
            log.info(f"Fetching tree for {full_name}@{branch}…")
            blobs, truncated = top_files_in_repo(full_name, branch, args.files_top)
            print()
            print(f"## {full_name} ({fmt_bytes(r['size'] * 1024)} total)")
            if truncated:
                print("   (GitHub truncated the tree — partial results only)")
            if not blobs:
                print("   (no blobs returned)")
                continue
            for path, size in blobs:
                print(f"   {fmt_bytes(size):>10}  {path}")


if __name__ == "__main__":
    main()
