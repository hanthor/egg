---
name: oci-layer-composition
description: Use when understanding how packages flow into the final OCI image, when modifying layer assembly, or when debugging why files appear or are missing from the built image
---

# OCI Layer Composition

## Overview

The Bluefin OCI image is assembled through a chain of BuildStream elements in `elements/oci/` and `elements/oci/layers/`. Each element kind has a specific role: **stack** elements aggregate dependencies, **compose** elements filter artifacts by split domain, **collect_initial_scripts** collects first-boot scripts, and **script** elements perform final OCI assembly. Understanding this chain is essential for knowing why a file ends up (or doesn't end up) in the final image.

## When to Use

- You need to understand how a new package gets included in the OCI image
- You're debugging why a file is present or missing from the built image
- You're adding a new filesystem layer or modifying layer composition
- You need to understand split domains (devel, debug, extra) and what gets excluded
- You're modifying OCI metadata (labels, annotations, os-release)
- You need to understand the parent layer relationship (Bluefin on GNOME OS on freedesktop-sdk)

## The Layer Chain

Every package follows this path from element to OCI image:

```
bluefin/my-package.bst
        |
        v
bluefin/deps.bst                    (kind: stack -- aggregates ALL bluefin packages)
        |
        v
oci/layers/bluefin-stack.bst         (kind: stack -- merges bluefin + gnomeos dependencies)
        |
        v
oci/layers/bluefin-runtime.bst       (kind: compose -- EXCLUDES devel, debug, static-blocklist)
        |
        v
oci/layers/bluefin.bst              (kind: compose -- FURTHER EXCLUDES extra, debug, static-blocklist)
        |
        v
oci/bluefin.bst                     (kind: script -- OCI assembly with build-oci heredoc)
```

### Element Kinds in the Chain

| Element | Kind | Purpose |
|---|---|---|
| `bluefin/deps.bst` | `stack` | Master package list. Add your package here as a dependency. |
| `oci/layers/bluefin-stack.bst` | `stack` | Merges `bluefin/deps.bst` with `gnome-build-meta.bst:oci/layers/gnomeos-stack.bst` |
| `oci/layers/bluefin-runtime.bst` | `compose` | Filters out `devel`, `debug`, `static-blocklist` split domains |
| `oci/layers/bluefin.bst` | `compose` | Filters out `extra`, `debug`, `static-blocklist` (final layer content) |
| `oci/layers/bluefin-init-scripts.bst` | `collect_initial_scripts` | Collects first-boot scripts at `/initial_scripts` |
| `oci/bluefin.bst` | `script` | Final OCI assembly: `prepare-image.sh`, `glib-compile-schemas`, `build-oci` |

### Two-Stage Compose Filtering

Compose elements filter artifacts by **split domains** (defined in `project.conf` or inherited from junctions). The two-stage compose ensures:

1. **`bluefin-runtime.bst`**: Excludes `devel` (headers, pkg-config, static libs) + `debug` + `static-blocklist`. This removes build-time-only artifacts.
2. **`bluefin.bst`**: Further excludes `extra` + `debug` + `static-blocklist`. This removes documentation, large optional data, etc.

If your package installs files that land in an excluded split domain, they will NOT appear in the final image. Common splits:
- **devel**: `/usr/include/`, `/usr/lib/pkgconfig/`, `*.a` static libraries
- **debug**: `/usr/lib/debug/` debug symbols
- **extra**: `/usr/share/doc/`, `/usr/share/man/`, large optional files

### `gcc.bst` in the Final Compose

`oci/layers/bluefin.bst` has an unusual build-dep on `freedesktop-sdk.bst:components/gcc.bst`. This pulls GCC's runtime libraries (libstdc++, libgcc_s) into the final image -- NOT the compiler itself. The `compose` filter excludes devel artifacts, so only the shared libraries survive.

## Parent Layer Hierarchy

The Bluefin image is layered on top of GNOME OS:

```
freedesktop-sdk: oci/platform.bst              (base freedesktop runtime)
        |
        v
gnome-build-meta: oci/platform.bst             (GNOME platform)
        |
        v
gnome-build-meta: oci/gnomeos.bst              (GNOME OS layer -- kind: script, upstream)
        |
        v
oci/bluefin.bst                                (Bluefin layer -- kind: script)
```

Both `gnome-build-meta:oci/gnomeos.bst` (upstream) and `oci/bluefin.bst` (local) are `kind: script` elements that use the same assembly pattern:
- Mount parent image at `/parent` and layer at `/layer`
- Run `prepare-image.sh` on the layer with `--initscripts` and `--seed`
- Run `systemd-sysusers --root /layer`
- Merge `/usr/etc` into `/etc` (bootc requirement -- no `/usr/etc` in images)
- Run `build-oci` heredoc to produce the final OCI artifact

### Junction Overrides

Several elements in `elements/oci/` are **local overrides** of upstream gnome-build-meta elements. The `elements/gnome-build-meta.bst` junction declares these overrides in `config.overrides`:

```yaml
config:
  overrides:
    oci/os-release.bst: oci/os-release.bst      # Bluefin's os-release replaces GNOME's
    core/meta-gnome-core-apps.bst: core/meta-gnome-core-apps.bst  # Custom GNOME app selection
    gnomeos-deps/plymouth-gnome-theme.bst: bluefin/plymouth-bluefin-theme.bst  # Bluefin theme
```

This means `oci/os-release.bst` is a local file that **replaces** its upstream counterpart. When you modify this file, you're changing what gnome-build-meta sees when it resolves that element path.

## OCI Assembly Script (oci/bluefin.bst)

The final `kind: script` element does this:

```yaml
kind: script

build-depends:
  - gnome-build-meta.bst:freedesktop-sdk.bst:components/fakecap.bst
  - gnome-build-meta.bst:freedesktop-sdk.bst:components/oci-builder.bst
  - freedesktop-sdk.bst:components/glib.bst
  - gnome-build-meta.bst:freedesktop-sdk.bst:vm/prepare-image.bst
  - oci/layers/bluefin-init-scripts.bst
  - filename: gnome-build-meta.bst:oci/gnomeos.bst  # Parent image (upstream GNOME OS)
    config:
      location: /parent
  - filename: oci/layers/bluefin.bst  # Layer content mounted at /layer
    config:
      location: /layer

environment:
  LD_PRELOAD: /usr/libexec/fakecap/fakecap.so
  FAKECAP_DB: /fakecap
```

Key details:
- **`fakecap`**: LD_PRELOAD library that emulates filesystem capabilities (setcap/getcap) inside BuildStream's bubblewrap sandbox, which lacks real capability support.
- **`prepare-image.sh`**: Sets up ostree/bootc-compatible sysroot structure from the layer.
- **`glib-compile-schemas`**: Compiles ALL GSettings schemas at OCI assembly time. Individual package elements do NOT need to run this -- it happens once here on the full merged `/layer/usr/share/glib-2.0/schemas`.
- **`/usr/etc` merge**: bootc images must not have both `/etc` and `/usr/etc`. The script merges `/usr/etc` into `/etc` and removes the former.
- **`build-oci` heredoc**: Produces the OCI image with labels and annotations.

## OCI Labels and Metadata

```yaml
config:
  Labels:
    'com.github.containers.toolbox': 'true'      # Toolbox compatibility
    'containers.bootc': '1'                        # bootc-compatible image
    'org.opencontainers.image.source': 'https://github.com/projectbluefin/egg/'
    'org.opencontainers.image.url': 'https://github.com/projectbluefin/egg/'
index-annotations:
  'org.opencontainers.image.ref.name': 'ghcr.io/projectbluefin/egg:latest'
```

Architecture is set via `%{go-arch}` variable (resolves to `amd64`, `arm64`, etc.).

## First-Boot Scripts (collect_initial_scripts)

Elements can declare first-boot scripts via `public.initial-script`:

```yaml
# In a package element:
public:
  initial-script:
    script: |
      #!/bin/bash
      sysroot="${1}"
      chmod 4755 "${sysroot}/usr/bin/something"
```

The `collect_initial_scripts` element (`oci/layers/bluefin-init-scripts.bst`) walks the dependency tree of `bluefin-stack.bst` and collects all `public.initial-script` declarations into `/initial_scripts/`. These scripts are then executed by `prepare-image.sh --initscripts /initial_scripts` during OCI assembly.

Use cases: setting capabilities, creating system users, adjusting file permissions -- things that can't be done at build time in the sandbox.

## os-release Element

`oci/os-release.bst` (`kind: manual`) generates `/usr/lib/os-release` and `/usr/share/ublue-os/image-info.json` from environment variables. It enters the image via a **junction override** in `elements/gnome-build-meta.bst` (`oci/os-release.bst: oci/os-release.bst`), which replaces gnome-build-meta's upstream os-release with Bluefin's version. It flows through the GNOME OS dependency chain, NOT through `bluefin/deps.bst`. Key environment variables:

| Variable | Value |
|---|---|
| `IMAGE_NAME` | `egg` |
| `IMAGE_VENDOR` | `projectbluefin` |
| `IMAGE_PRETTY_NAME` | `Bluefin` |
| `ID` | `bluefin-dakota` |
| `CODE_NAME` | `Dakotaraptor` |

## Adding a Package to the Image

The only file you need to modify to add a package is **`elements/bluefin/deps.bst`**:

```yaml
# In elements/bluefin/deps.bst:
depends:
  - bluefin/my-new-package.bst    # Add your element here
```

The rest of the chain (stack → compose → script) picks it up automatically. You do NOT need to modify any `oci/layers/` files or `oci/bluefin.bst`.

### When You DO Need to Modify the OCI Layer

Rare cases where you'd touch `elements/oci/`:
- **Changing OCI labels/annotations**: Edit `oci/bluefin.bst`
- **Changing os-release metadata**: Edit `oci/os-release.bst` environment variables
- **Adding a new split domain exclusion**: Edit the `compose` elements' `config.exclude` lists
- **Changing the parent image**: Edit `oci/bluefin.bst` build-depends to point to a different upstream or custom parent

## Common Mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Adding package to a compose/script element instead of deps.bst | Package not included or breaks layer chain | Add to `bluefin/deps.bst` -- it flows through automatically |
| Running `glib-compile-schemas` in a package element | Schemas compiled against incomplete set | Don't -- it runs once in `oci/bluefin.bst` on the full merged layer |
| Expecting `/usr/etc` in the final image | Files missing from `/etc` | Image merges `/usr/etc` into `/etc` at assembly time |
| Forgetting overlap-whitelist when replacing upstream files | Build fails with file overlap error | Add `public.bst.overlap-whitelist` in your package element |
| Installing files into devel/debug split domains | Files excluded by compose filters | Install to runtime paths (`/usr/bin`, `/usr/lib`, `/usr/share`) |
| Modifying compose exclude lists unnecessarily | Bloated image with debug/devel artifacts | Only modify if you have a specific reason to include excluded artifacts |
| Not understanding fakecap | Capability operations fail in sandbox | `LD_PRELOAD` with fakecap is set automatically in OCI script elements |

## Real Files

| File | Kind | Purpose |
|---|---|---|
| `elements/bluefin/deps.bst` | stack | Master package list -- add packages here |
| `elements/oci/layers/bluefin-stack.bst` | stack | Merges bluefin + gnomeos stacks |
| `elements/oci/layers/bluefin-runtime.bst` | compose | First filter (excludes devel) |
| `elements/oci/layers/bluefin.bst` | compose | Second filter (excludes extra) |
| `elements/oci/layers/bluefin-init-scripts.bst` | collect_initial_scripts | First-boot scripts |
| `elements/oci/bluefin.bst` | script | Final OCI assembly |
| `elements/oci/os-release.bst` | manual | OS release metadata |
