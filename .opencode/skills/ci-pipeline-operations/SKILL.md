---
name: ci-pipeline-operations
description: Use when debugging CI failures, understanding the build pipeline, modifying the GitHub Actions workflow, working with artifact caching, or troubleshooting why a build succeeded locally but fails in CI
---

# CI Pipeline Operations

## Overview

The CI pipeline (`.github/workflows/build-egg.yml`) builds the Bluefin OCI image inside the bst2 container on GitHub Actions, validates it with `bootc container lint`, and pushes to GHCR on main. Caching uses a two-tier architecture: GNOME upstream CAS (read-only) + project R2 cache (read-write via `bazel-remote` proxy).

## Quick Reference

| What | Value |
|---|---|
| Workflow file | `.github/workflows/build-egg.yml` |
| Runner | `ubuntu-24.04` |
| Build target | `oci/bluefin.bst` |
| Build timeout | 120 minutes |
| bst2 container | `registry.gitlab.com/.../bst2:<sha>` (pinned in workflow `env.BST2_IMAGE`) |
| GNOME CAS endpoint | `gbm.gnome.org:11003` (gRPC, read-only) |
| R2 cache proxy (gRPC) | `localhost:9092` |
| R2 cache proxy (HTTP status) | `localhost:8080` |
| R2 bucket | `bst-cache` |
| Published image | `ghcr.io/projectbluefin/egg:latest` and `:$SHA` |
| Build logs artifact | `buildstream-logs` (7-day retention) |
| Cache proxy logs artifact | `bazel-remote-logs` (7-day retention) |

## Workflow Steps

| # | Step | What it does | Notes |
|---|---|---|---|
| 1 | Free disk space | Removes pre-installed SDKs | **Critical** -- builds need >50 GB; runner starts with ~30 GB free |
| 2 | Checkout | Clones the repo | Standard |
| 3 | Pull bst2 image | `podman pull` of the pinned bst2 container | Same image as GNOME upstream CI |
| 4 | Cache BST sources | `actions/cache` for `~/.cache/buildstream/sources` | Key: hash of `elements/**/*.bst` + `project.conf` |
| 5 | Disk space before | `df -h /` | Diagnostic |
| 6 | Prepare cache dir | `mkdir -p ~/.cache/buildstream/sources` | Ensures cache restore has a target |
| 7 | Start cache proxy | Downloads + verifies `bazel-remote` v2.6.1, starts as background daemon | Skips if R2 secrets are missing |
| 8 | Generate BST config | Writes `buildstream-ci.conf` with CI-tuned settings | Adds R2 remote only if proxy is running |
| 9 | Seed R2 from upstream | Pulls artifacts from GNOME CAS, pushes to R2 | Non-fatal; accumulates upstream artifacts in R2 over time |
| 10 | Build | `bst build oci/bluefin.bst` inside bst2 container | `--privileged --device /dev/fuse`, `--network=host` only if proxy running |
| 11 | Push artifacts to R2 | `bst artifact push --deps all` | Non-fatal safety net; ensures all artifacts reach R2 |
| 12 | Cache proxy stats | Logs proxy status + last 50 lines of proxy log | Diagnostic |
| 13 | Disk space after | `df -h /` | Diagnostic |
| 14 | Export OCI image | `bst artifact checkout --tar - \| podman load` | Streams directly, no intermediate tar file on disk |
| 15 | Verify image loaded | `podman images` | Diagnostic |
| 16 | bootc lint | `bootc container lint` on exported image | Validates ostree structure, no `/usr/etc`, valid bootc metadata |
| 17 | Upload build logs | `actions/upload-artifact` | Always runs, even on failure |
| 18 | Upload proxy logs | `actions/upload-artifact` | Always runs |
| 19 | Stop cache proxy | Kills `bazel-remote` process | Always runs |
| 20 | Login to GHCR | `podman login` with `GITHUB_TOKEN` | **Main only** |
| 21 | Tag for GHCR | Tags as `:latest` and `:$SHA` | **Main only** |
| 22 | Push to GHCR | `podman push --retry 3` both tags | **Main only** |

## CI BuildStream Config

Generated as `buildstream-ci.conf` at step 8. Values and rationale:

| Setting | Value | Why |
|---|---|---|
| `on-error` | `continue` | Find ALL failures in one run, not just the first |
| `fetchers` | `12` | Parallel downloads from artifact caches |
| `builders` | `1` | GHA has 4 vCPUs; conservative to avoid OOM |
| `network-retries` | `3` | Retry transient network failures |
| `retry-failed` | `True` | Auto-retry flaky builds |
| `error-lines` | `80` | Generous error context in logs |
| `cache-buildtrees` | `never` | Save disk; only final artifacts matter |
| `max-jobs` | `0` | Let BuildStream auto-detect (uses nproc) |

## Caching Architecture

Three layers, checked in order:

```
1. Local CAS (~/.cache/buildstream/)
   |-- miss -->
2. R2 cache (grpc://localhost:9092 -> Cloudflare R2)
   |-- miss -->
3. GNOME upstream CAS (https://gbm.gnome.org:11003)
   |-- miss -->
4. Build from source
```

### Layer Details

| Layer | Configured in | Read | Write | Contains |
|---|---|---|---|---|
| Local CAS | Automatic | Always | Always | Everything built/fetched this run |
| R2 cache | `buildstream-ci.conf` (added dynamically) | When proxy running | When proxy running | Bluefin-specific + seeded upstream artifacts |
| GNOME upstream | `project.conf` `artifacts:` section | Always | Never | freedesktop-sdk + gnome-build-meta artifacts |
| Source cache | `project.conf` `source-caches:` + `actions/cache` | Always | Always (local) | Upstream tarballs, git repos |

### `bazel-remote` Bridge

BuildStream speaks gRPC CAS. Cloudflare R2 speaks S3. `bazel-remote` v2.6.1 bridges them.

| Setting | Value |
|---|---|
| Binary | Downloaded from GitHub releases, SHA256-verified |
| gRPC port | `9092` (env: `CACHE_GRPC_PORT`) |
| HTTP port | `8080` (env: `CACHE_HTTP_PORT`) |
| Local disk cache | `/tmp/bazel-remote-cache` (5 GB max) |
| S3 prefix | `cas` |
| Health check | `curl http://localhost:8080/status` (30s timeout) |

### The `type: storage` Trap

The R2 remote in `buildstream-ci.conf` MUST include `type: storage`:

```yaml
artifacts:
  servers:
    - url: "grpc://localhost:9092"
      type: storage
      push: true
```

**Without `type: storage`, BuildStream silently ignores the remote entirely.** `bazel-remote` only implements CAS (Content Addressable Storage), not the Remote Asset API. The `type: storage` flag tells BuildStream to use pure CAS protocol.

## PR vs Main Differences

| Behavior | PR | Main push |
|---|---|---|
| Build runs? | Yes | Yes |
| bootc lint? | Yes | Yes |
| R2 cache read | Yes (if secrets available) | Yes |
| R2 cache write | Yes (if secrets available) | Yes |
| Fork PR gets R2 secrets? | **No** -- GitHub doesn't expose secrets to forks | N/A |
| Push to GHCR? | **No** | Yes |
| Concurrency | Grouped by branch; new pushes cancel stale runs | Grouped by SHA; every push runs |

## Secrets and Permissions

| Secret | Required? | Purpose |
|---|---|---|
| `R2_ACCESS_KEY` | Optional | Cloudflare R2 access key ID |
| `R2_SECRET_KEY` | Optional | Cloudflare R2 secret access key |
| `R2_ENDPOINT` | Optional | R2 S3-compatible endpoint (`https://<ACCOUNT_ID>.r2.cloudflarestorage.com`) |
| `GITHUB_TOKEN` | Auto-provided | GHCR login (main branch push only) |

**All R2 secrets are optional.** If missing, the cache proxy is skipped and the build proceeds using only GNOME upstream CAS + local CAS. The build works without R2 -- it just takes longer.

Job permissions: `contents: read`, `packages: write`.

## bst2 Container Configuration

The bst2 container runs via `podman run` (NOT as a GitHub Actions `container:`), because the disk-space-reclamation step needs host filesystem access.

| Flag | Why |
|---|---|
| `--privileged` | Required for bubblewrap sandboxing inside BuildStream |
| `--device /dev/fuse` | Required for `buildbox-fuse` (ext4 on GHA lacks reflinks) |
| `--network=host` | Only when cache proxy is running; lets container reach `localhost:9092` |
| `-v workspace:/src:rw` | Mount repo into container |
| `-v ~/.cache/buildstream:...:rw` | Persist CAS across steps |
| `ulimit -n 1048576` | `buildbox-casd` needs many file descriptors |
| `--no-interactive` | Prevents blocking on prompts in CI |

## Debugging CI Failures

### Where to Find Logs

| Log | Location | Contents |
|---|---|---|
| Build log | `buildstream-logs` artifact -> `logs/build.log` | Full BuildStream build output |
| Cache proxy log | `bazel-remote-logs` artifact -> `bazel-remote.log` | R2 cache hits/misses, S3 errors |
| Workflow log | GitHub Actions UI -> step output | Each step's stdout/stderr |
| Disk usage | "Disk space before/after build" steps | `df -h /` snapshots |

### Common Failures

| Symptom | Likely cause | Fix |
|---|---|---|
| Build OOM or hangs | Too many parallel builders | `builders` is already 1; check if element's own build is too memory-heavy |
| "No space left on device" | BuildStream CAS fills disk | Verify disk reclamation step ran; check `cache-buildtrees: never` is set |
| Cache proxy failed to start | R2 secrets misconfigured or endpoint unreachable | Check `bazel-remote-logs`; verify secrets in repo settings |
| `bootc container lint` fails | Image has `/usr/etc`, missing ostree refs, or invalid metadata | Check `oci/bluefin.bst` assembly script; ensure `/usr/etc` merge runs |
| Build succeeds locally, fails in CI | Different element versions cached, or network-dependent sources | Compare `bst show` output locally vs CI; check if GNOME CAS has stale artifacts |
| Remote silently ignored | Missing `type: storage` on R2 remote | Ensure `buildstream-ci.conf` includes `type: storage` |
| GHCR push fails | Token permissions or rate limiting | Check `packages: write` permission; `--retry 3` handles transient failures |
| Source fetch timeout | GNOME CAS or upstream source unreachable | `network-retries: 3` handles transient issues; check GNOME infra status |
| Seed step fails | Normal -- non-fatal by design | `continue-on-error: true`; check proxy logs if persistent |

### Debugging Workflow

1. **Download artifacts**: Get `buildstream-logs` and `bazel-remote-logs` from the failed run
2. **Check disk space**: Look at before/after disk space steps -- OOM and disk full are the most common issues
3. **Search build log**: Look for `[FAILURE]` lines in `logs/build.log`; `on-error: continue` means all failures are collected
4. **Check cache hits**: In `bazel-remote.log`, look for cache hit ratio; low hits mean long builds
5. **Reproduce locally**: `just bst build oci/bluefin.bst` uses the same bst2 container

## Cross-References

| Skill | When |
|---|---|
| `local-e2e-testing` | Reproducing CI issues locally |
| `oci-layer-composition` | Understanding what the build produces |
| `debugging-bst-build-failures` | Diagnosing individual element build failures |
| `buildstream-element-reference` | Writing or modifying `.bst` elements |
