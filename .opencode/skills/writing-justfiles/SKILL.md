---
name: writing-justfiles
description: Use when creating or modifying Justfiles in this repository, when adding new recipes, or when organizing just commands
---

# Writing Justfiles

## Overview

All Justfiles in this repository follow bluefin-lts style patterns for consistency, discoverability, and maintainability.

**Core principle:** Export environment variables, use group decorators, favor composition over complexity.

## Quick Reference

| Element | Pattern | Example |
|---------|---------|---------|
| Variables | `export VAR := env("VAR", "default")` | `export image_name := env("BUILD_IMAGE_NAME", "egg")` |
| Default recipe | `@just --list` | First recipe in file |
| Groups | `[group('category')]` | `[group('build')]` |
| Quiet mode | Prefix with `@` | `@just --list` |
| Shell | `#!/usr/bin/env bash` + `set -euo pipefail` | Standard for all recipes |
| Comments | Brief description above recipe | `# Build the OCI image` |

## Variable Style

**Always use `export` for variables:**

```justfile
# ✅ GOOD: Exported with env() fallback
export image_name := env("BUILD_IMAGE_NAME", "egg")
export image_tag := env("BUILD_IMAGE_TAG", "latest")

# ❌ BAD: Not exported
image_name := "egg"

# ❌ BAD: No default value
export image_tag := env("BUILD_IMAGE_TAG")
```

**Why export:**
- Variables available to shell recipes
- Environment variables match exported names
- Consistent interface for external callers

**Use `env()` with defaults:**
- Prefer `env("VAR", "default")` over bare assignments
- Allows override via environment variables
- Documents expected configuration points

## Recipe Organization

**Use `[group('category')]` decorators on ALL recipes:**

Standard categories:
- `info` - Information commands (`default`, `help`)
- `build` - Build operations (`build`, `export`, `clean`)
- `test` - Testing operations (`generate-bootable-image`, `boot-vm`)
- `dev` - Development tools (`bst`, `bootc`)
- `registry` - Registry operations (if applicable)
- `vm` - VM operations (if applicable)

```justfile
# ✅ GOOD: Grouped and discoverable
[group('build')]
build:
    just bst build oci/bluefin.bst

[group('test')]
boot-vm:
    qemu-system-x86_64 ...

# ❌ BAD: No group decorator
build:
    just bst build oci/bluefin.bst
```

**Order recipes by logical workflow, not alphabetically:**
- Within a group, order by typical execution order
- Build before test, test before deploy
- Common operations before specialized ones

## Default Recipe

**First recipe should be `@just --list`:**

```justfile
# List available commands
[group('info')]
default:
    @just --list
```

**Why:**
- Improves discoverability for new contributors
- `just` with no args shows all available commands
- Grouped output (from decorators) organizes by category

## Recipe Style

**Use quiet mode with `@` prefix:**

```justfile
# ✅ GOOD: Suppresses command echo
[group('build')]
build:
    @echo "Building..."
    @just bst build oci/bluefin.bst

# ❌ BAD: Shows every command
[group('build')]
build:
    echo "Building..."
    just bst build oci/bluefin.bst
```

**Set shell options:**

```justfile
[group('build')]
build:
    #!/usr/bin/env bash
    set -euo pipefail
    
    echo "Building OCI image..."
    just bst build oci/bluefin.bst
```

**Why these options:**
- `-e` - Exit on error (fail fast)
- `-u` - Error on undefined variables
- `-o pipefail` - Catch pipe failures

**Keep recipes focused:**

```justfile
# ✅ GOOD: One task per recipe, compose with dependencies
[group('build')]
build:
    just bst build oci/bluefin.bst
    just export

[group('build')]
export:
    just bst artifact checkout oci/bluefin.bst --directory .build-out

# ❌ BAD: Monolithic recipe doing too much
[group('build')]
build:
    # Build + export + validate + publish all in one
    ...50 lines...
```

**Composition patterns:**
- Use recipe dependencies: `deploy: build test`
- Call other recipes: `just build`
- Break complex operations into focused recipes

## Comments

**Add brief description above each recipe:**

```justfile
# Build the OCI image and load it into podman
[group('build')]
build:
    ...

# Boot the raw disk image in QEMU with UEFI (OVMF)
# Requires: qemu-system-x86_64, OVMF firmware, KVM access
[group('test')]
boot-vm:
    ...
```

**Explain non-obvious environment variables:**

```justfile
# VM settings
export vm_ram := env("VM_RAM", "8192")
export vm_cpus := env("VM_CPUS", "4")

# OCI metadata (dynamic labels)
export OCI_IMAGE_CREATED := env("OCI_IMAGE_CREATED", "")
export OCI_IMAGE_REVISION := env("OCI_IMAGE_REVISION", "")
```

**Document prerequisites for complex recipes:**

```justfile
# Boot the raw disk image in QEMU with UEFI (OVMF)
# Requires: qemu-system-x86_64, OVMF firmware, KVM access
[group('test')]
boot-vm:
    ...
```

## Common Patterns

**Conditional execution:**

```justfile
[group('build')]
export:
    #!/usr/bin/env bash
    set -euo pipefail
    
    # Use sudo unless already root (CI runners are root)
    SUDO_CMD=""
    if [ "$(id -u)" -ne 0 ]; then
        SUDO_CMD="sudo"
    fi
    
    $SUDO_CMD podman images
```

**File existence checks:**

```justfile
[group('test')]
generate-bootable-image:
    #!/usr/bin/env bash
    set -euo pipefail
    
    if ! sudo podman image exists "{{image_name}}:{{image_tag}}"; then
        echo "ERROR: Image not found. Run 'just build' first." >&2
        exit 1
    fi
```

**Path detection loops:**

```justfile
[group('test')]
boot-vm:
    #!/usr/bin/env bash
    set -euo pipefail
    
    OVMF_CODE=""
    for candidate in \
        /usr/share/edk2/ovmf/OVMF_CODE.fd \
        /usr/share/OVMF/OVMF_CODE.fd; do
        if [ -f "$candidate" ]; then
            OVMF_CODE="$candidate"
            break
        fi
    done
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Bare variable assignment | Use `export VAR := env("VAR", "default")` |
| No group decorators | Add `[group('category')]` to all recipes |
| Alphabetical ordering | Order by logical workflow |
| Echo command output | Prefix with `@` for quiet mode |
| No shell options | Add `set -euo pipefail` |
| Monolithic recipes | Break into focused, composable recipes |
| Missing comments | Add brief description above each recipe |
| No default recipe | First recipe should be `@just --list` |

## Integration with BuildStream

**Wrapper pattern for bst commands:**

```justfile
# Runs any bst command inside the bst2 container via podman
[group('dev')]
bst *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "${HOME}/.cache/buildstream"
    podman run --rm \
        --privileged \
        --device /dev/fuse \
        -v "{{justfile_directory()}}:/src:rw" \
        -v "${HOME}/.cache/buildstream:/root/.cache/buildstream:rw" \
        -w /src \
        "{{bst2_image}}" \
        bash -c 'bst --colors "$@"' -- ${BST_FLAGS:-} {{ARGS}}
```

**Why this pattern:**
- Encapsulates container complexity
- Consistent with CI environment
- Allows flag injection via `BST_FLAGS` env var
- All bst commands go through same wrapper

## Real-World Example

From this repository's Justfile:

```justfile
# List available commands
[group('info')]
default:
    @just --list

export image_name := env("BUILD_IMAGE_NAME", "egg")
export image_tag := env("BUILD_IMAGE_TAG", "latest")

# Build the OCI image and load it into podman
[group('build')]
build:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Building OCI image..."
    just bst build oci/bluefin.bst
    just export

# Remove generated artifacts
[group('build')]
clean:
    rm -f bootable.raw .ovmf-vars.fd
    rm -rf .build-out
```

This demonstrates:
- Default recipe for discoverability
- Exported variables with env() defaults
- Group decorators for organization
- Quiet mode with `@`
- Shell options for safety
- Brief, informative comments
- Recipe composition (`build` calls `export`)
