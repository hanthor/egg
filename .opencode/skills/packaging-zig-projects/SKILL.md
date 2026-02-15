---
name: packaging-zig-projects
description: Use when packaging a project that uses the Zig build system, when an element needs zig fetch/build with offline dependency caching, or when adding Zig dependencies to an existing element
---

# Packaging Zig Projects

## Overview

Zig projects require offline dependency caching because BuildStream's bubblewrap sandbox has no network access during build. The pattern: fetch all dependencies as `remote` sources at source-fetch time, then populate Zig's global cache at build time using `zig fetch` (HTTP deps) and a `place_git_dep()` function (git deps).

## When to Use

- Project has a `build.zig` and `build.zig.zon`
- Project uses Zig's package manager for dependencies
- You're adding Zig dependency sources to an existing element

## Prerequisites

A pre-built Zig SDK must exist as a build dependency. In this project: `bluefin/zig.bst` (a `manual` element installing the Zig binary + stdlib from an official tarball).

## Source Structure

A Zig element has three groups of sources:

```yaml
sources:
  # 1. Project source tarball
  - kind: tar
    url: <alias>:<path-to-release-tarball>
    ref: <sha256>

  # 2. HTTP Zig dependencies (one per dep)
  - kind: remote          # NOT 'tar' — these are opaque files for zig fetch
    url: <dep-url>
    ref: <sha256>
    directory: zig-deps   # All HTTP deps go in the same directory

  # 3. Git-based Zig dependencies (one per dep)
  - kind: remote          # Also 'remote', NOT 'git_repo'
    url: <archive-tarball-url>
    ref: <sha256>
    directory: zig-deps-git  # Separate directory from HTTP deps
```

**Critical:** Use `kind: remote` (not `tar`) for dependencies. `remote` downloads the file as-is without extracting. `zig fetch` handles extraction. All HTTP deps share `directory: zig-deps`; all git deps share `directory: zig-deps-git`.

## Build Commands

Three stages in `build-commands`:

### Stage 1: Set up Zig cache

```yaml
- |
  export ZIG_GLOBAL_CACHE_DIR="/tmp/zig-cache"
  export ZIG_LIB_DIR="%{libdir}/zig"
  mkdir -p "$ZIG_GLOBAL_CACHE_DIR/p"
```

### Stage 2: Populate cache from HTTP deps via `zig fetch`

```yaml
- |
  export ZIG_GLOBAL_CACHE_DIR="/tmp/zig-cache"
  export ZIG_LIB_DIR="%{libdir}/zig"
  for dep in zig-deps/*; do
    echo "Fetching: $dep"
    zig fetch --global-cache-dir "$ZIG_GLOBAL_CACHE_DIR" "$dep" || {
      echo "WARNING: zig fetch failed for $dep" >&2
    }
  done
```

### Stage 3: Place git deps manually

GitHub/Codeberg archive tarballs have a top-level directory wrapper that differs from a git clone. `zig fetch` produces wrong content hashes for these. Instead, extract manually and place at the correct Zig hash path:

```yaml
- |
  export ZIG_GLOBAL_CACHE_DIR="/tmp/zig-cache"

  place_git_dep() {
    local tarball="$1"
    local zig_hash="$2"
    local dest="$ZIG_GLOBAL_CACHE_DIR/p/$zig_hash"
    mkdir -p "$dest"
    tar xf "$tarball" --strip-components=1 -C "$dest"
    echo "Placed git dep at $dest"
  }

  # One call per git dep — hash comes from build.zig.zon
  place_git_dep "zig-deps-git/<commit>.tar.gz" "<zig-content-hash>"
```

**Where do the Zig content hashes come from?** Run `zig fetch` on each git dep tarball locally (outside BuildStream) and note the hash it reports, OR read the `.hash` field in `build.zig.zon` for that dependency. The hash format is like `vaxis-0.1.0-BWNV_FUICQAFZnTCL11TUvnUr1Y0_ZdqtXHhd51d76Rn`.

## Install Commands

Use `zig build --system` to point at the pre-populated cache:

```yaml
install-commands:
  - |
    export ZIG_GLOBAL_CACHE_DIR="/tmp/zig-cache"
    export ZIG_LIB_DIR="%{libdir}/zig"
    DESTDIR="%{install-root}" \
    zig build \
      --prefix /usr \
      --system "$ZIG_GLOBAL_CACHE_DIR/p" \
      -Doptimize=ReleaseFast \
      -Dcpu=baseline \
      -Dpie=true \
      -Dversion-string=<version>
```

**Key flags:**

| Flag | Purpose |
|---|---|
| `--system "$ZIG_GLOBAL_CACHE_DIR/p"` | Use pre-populated offline cache (no network fetch) |
| `--prefix /usr` | Install to standard prefix |
| `DESTDIR="%{install-root}"` | Stage into BuildStream's install root |
| `-Doptimize=ReleaseFast` | Maximum performance optimization |
| `-Dcpu=baseline` | Generic CPU target (no host-specific instructions) |
| `-Dpie=true` | Position-independent executable (security hardening) |

Add project-specific flags as needed (e.g., `-Dgtk-x11=true` for GTK/X11 support).

## Element Template

```yaml
kind: manual

build-depends:
  - bluefin/zig.bst

depends:
  - freedesktop-sdk.bst:public-stacks/runtime-minimal.bst
  # Add library deps as needed (gtk, libadwaita, etc.)

sources:
  - kind: tar
    url: <release-tarball-url>
    ref: <sha256>

  # HTTP Zig deps (repeat for each)
  - kind: remote
    url: <dep-url>
    ref: <sha256>
    directory: zig-deps

  # Git Zig deps (repeat for each)
  - kind: remote
    url: <archive-tarball-url>
    ref: <sha256>
    directory: zig-deps-git

config:
  build-commands:
    - |
      export ZIG_GLOBAL_CACHE_DIR="/tmp/zig-cache"
      export ZIG_LIB_DIR="%{libdir}/zig"
      mkdir -p "$ZIG_GLOBAL_CACHE_DIR/p"
    - |
      export ZIG_GLOBAL_CACHE_DIR="/tmp/zig-cache"
      export ZIG_LIB_DIR="%{libdir}/zig"
      for dep in zig-deps/*; do
        zig fetch --global-cache-dir "$ZIG_GLOBAL_CACHE_DIR" "$dep" || true
      done
    - |
      export ZIG_GLOBAL_CACHE_DIR="/tmp/zig-cache"
      place_git_dep() {
        local tarball="$1"; local zig_hash="$2"
        local dest="$ZIG_GLOBAL_CACHE_DIR/p/$zig_hash"
        mkdir -p "$dest"
        tar xf "$tarball" --strip-components=1 -C "$dest"
      }
      # place_git_dep "zig-deps-git/<file>" "<zig-hash>"

  install-commands:
    - |
      export ZIG_GLOBAL_CACHE_DIR="/tmp/zig-cache"
      export ZIG_LIB_DIR="%{libdir}/zig"
      DESTDIR="%{install-root}" \
      zig build \
        --prefix /usr \
        --system "$ZIG_GLOBAL_CACHE_DIR/p" \
        -Doptimize=ReleaseFast \
        -Dcpu=baseline \
        -Dpie=true
```

## Finding Dependency URLs

1. Read `build.zig.zon` for the list of dependencies and their URLs
2. HTTP deps: URL is directly in `.url` field — download and get SHA256
3. Git deps: identified by `git+https://` prefix in `.url` field — convert to archive tarball URL:
   - GitHub: `https://github.com/<org>/<repo>/archive/<commit>.tar.gz`
   - Codeberg: `https://codeberg.org/<org>/<repo>/archive/<commit>.tar.gz`
4. Use BuildStream source aliases (`github_files:`, `codeberg_files:`, or add new ones to `include/aliases.yml`)

## Dependency Tracking

Zig elements (Ghostty, Zig SDK) are **NOT tracked by any automation**. Updates are manual:
1. Bump version in source URL and update `ref:` (SHA256)
2. Update all dependency source entries (URLs and refs change with each release)
3. Update git dep hashes in `place_git_dep()` calls
4. Test build: `just bst build bluefin/<element>.bst`

This is a known gap — future Renovate custom managers may automate parts of this.

## Common Mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Using `kind: tar` for deps | Dependencies extracted prematurely, `zig fetch` fails | Use `kind: remote` — files must be opaque for `zig fetch` |
| Using `kind: git_repo` for git deps | Wrong content hash from archive vs clone | Use `kind: remote` with archive tarball + `place_git_dep()` |
| Missing `--system` flag on `zig build` | Build tries to fetch from network, fails in sandbox | Add `--system "$ZIG_GLOBAL_CACHE_DIR/p"` |
| Wrong Zig content hash for git dep | Build fails with "package not found" | Re-derive hash locally or check `build.zig.zon` |
| Mixing HTTP and git deps in same directory | `zig fetch` loop processes git deps incorrectly | HTTP deps → `zig-deps/`, git deps → `zig-deps-git/` |
| Missing `ZIG_LIB_DIR` export | Zig can't find its standard library | Set `export ZIG_LIB_DIR="%{libdir}/zig"` |
| Missing `bluefin/zig.bst` build-dep | `zig` command not found in sandbox | Add `bluefin/zig.bst` to `build-depends` |
| Adding `strip-binaries: ""` | Unnecessary — Zig produces standard ELF binaries | Don't set this unless the element also installs non-ELF files |

## Real Example

See `elements/bluefin/ghostty.bst` (285 lines) — packages Ghostty 1.2.3 with 32 HTTP deps and 3 git deps. The Zig SDK element is `elements/bluefin/zig.bst` (19 lines).
