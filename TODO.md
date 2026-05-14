# TODO

## Incremental backups (skip repos with no new commits)

Right now every run re-downloads and re-uploads every repo regardless of whether anything changed. For monthly runs against a personal GitHub account this is mostly wasted bandwidth + S3 storage — most repos won't have new commits between runs.

**Idea:** before downloading a repo, compare its last-pushed timestamp against a stored "last backed up" timestamp, and skip if nothing's new.

### Sketch

1. **Source of "last commit / last push" for a repo.** `GET /user/repos` (which we already call to list owned repos) returns a `pushed_at` field per repo — that's the timestamp of the most recent push to any branch. No extra API call needed.

2. **Where to persist "last backed up" per repo.** A few options, easiest first:
   - **Manifest object in S3** — a single `s3://<bucket>/<prefix>/_manifest.json` mapping `repo_name → last_pushed_at_backed_up`. One GET at run start, one PUT at run end. No new IAM, no new infra.
   - **S3 object tags** on each backup — tag with the `pushed_at` it represents; on next run, list objects and read tags. More requests, but no central manifest to keep consistent.
   - **DynamoDB table** — overkill for a single-user backup, but the right shape if this ever grew.

   Manifest-in-S3 is the obvious starting point.

3. **Per-repo decision logic.**
   - If `repo.pushed_at > manifest.get(repo.name, epoch)`: download + upload, then update manifest entry.
   - Else: log "no changes since last backup" and skip.
   - First run / new repo / missing manifest entry: treat as "always do the backup".

4. **Failure handling.** Only update the manifest entry after the S3 upload succeeds. If a repo fails, leave its previous timestamp alone so the next run retries.

5. **Manifest write timing.** Either:
   - Write the manifest once at the end of a successful run (simple, but a crash mid-run loses the per-repo progress and the next run redoes everything).
   - Write incrementally after each successful repo (safer, more S3 PUTs — still cheap).

### Related design questions to revisit alongside this

- **Retention / pruning.** Backups currently accumulate forever under date-stamped keys. When we stop creating one snapshot per run, do we want lifecycle rules to delete after N days? Move to Glacier?
- **Detecting deletions.** If a repo is deleted on GitHub between runs, the manifest will still hold a stale entry. Probably fine to ignore but worth noting.
- **Force-full mode.** An env var / flag to bypass the check and back up everything anyway (e.g. for verifying integrity, or after retention policy changes).

### Out of scope for now

- Per-branch / per-tag backups — current model is "snapshot of default branch via tarball", and changing that is a separate question.
- Restore tooling — these are just `.tar.gz` files in S3, restore is `aws s3 cp` + `tar xzf`. If we want guided restore, separate ticket.
