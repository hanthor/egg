---
name: local-e2e-testing
description: Use when building the egg OCI image locally, testing changes end-to-end, verifying the image boots, or running any BuildStream commands against the project
---

# Local End-to-End Testing

## Overview

**This is the default development workflow.** All build verification happens locally before pushing to the remote. CI is a safety net, not the primary build environment.

Build Bluefin from source and boot it in a VM using three composable `just` recipes. All BuildStream commands run inside the bst2 container via podman -- no native BuildStream installation required.

**Hard gate:** No code may be committed or pushed without a local build log showing affected elements build successfully. See `verification-before-completion` skill for the full gate function.

## Prerequisites

| Requirement | Install (Fedora) | Install (Ubuntu) |
|---|---|---|
| podman | Pre-installed | `sudo apt install podman` |
| QEMU + KVM | `sudo dnf install qemu-system-x86-core` | `sudo apt install qemu-system-x86` |
| OVMF (UEFI firmware) | `sudo dnf install edk2-ovmf` | `sudo apt install ovmf` |
| KVM access | `sudo usermod -aG kvm $USER` | `sudo usermod -aG kvm $USER` |
| Free disk space | ~50 GB for BuildStream CAS + build artifacts | Same |

Verify KVM: `ls -la /dev/kvm` -- if missing, enable virtualization in BIOS.

## Commands

### One command to rule them all

```bash
just show-me-the-future
```

Builds the OCI image, installs it to a 30GB bootable disk, and launches QEMU. First run takes 1-2 hours (downloading/building ~2000 elements). Subsequent runs with warm cache take minutes.

### Individual steps

| Command | What it does |
|---|---|
| `just build` | Build OCI image inside bst2 container, load into podman |
| `just generate-bootable-image` | Install image to `bootable.raw` via `bootc install to-disk` |
| `just boot-vm` | Boot `bootable.raw` in QEMU with UEFI + KVM |
| `just bst <args>` | Run any BuildStream command inside the bst2 container |

### Ad-hoc BuildStream commands

```bash
just bst show oci/bluefin.bst          # Show element details
just bst build bluefin/brew.bst        # Build a single element
just bst shell bluefin/brew.bst        # Interactive shell in build sandbox
just bst artifact log oci/bluefin.bst  # View build logs
just bst artifact delete <element.bst> # Delete cached artifact to reclaim disk
```

## Cache Behavior

BuildStream uses a local Content Addressable Storage (CAS) cache. The first build downloads and builds ~2000 elements (~1-2 hours depending on network). Once cached, only changed elements rebuild — subsequent builds with a warm cache typically take minutes. The cache lives in `~/.cache/buildstream/` (inside the bst2 container, mapped to the host). If disk runs low, use `just bst artifact delete <element>` to selectively reclaim space or remove the entire cache directory.

## Environment Variables

| Variable | Default | Purpose |
|---|---|---|
| `BST2_IMAGE` | (pinned SHA in Justfile) | Override bst2 container image |
| `BUILD_IMAGE_NAME` | `egg` | Name for the loaded OCI image |
| `BUILD_IMAGE_TAG` | `latest` | Tag for the loaded OCI image |
| `BUILD_BASE_DIR` | `.` | Directory for `bootable.raw` |
| `BUILD_FILESYSTEM` | `btrfs` | Root filesystem type |
| `VM_RAM` | `4096` | VM memory in MB |
| `VM_CPUS` | `2` | VM CPU count |

## Common Failures

| Symptom | Cause | Fix |
|---|---|---|
| `permission denied` on `/dev/fuse` | Missing FUSE device | `sudo modprobe fuse` |
| `bst` hangs pulling sources | Network/firewall blocking GNOME CAS | Check connectivity to `gbm.gnome.org:11003` |
| `bootc install` fails with device error | SELinux or missing privileges | Ensure `--privileged` and `--security-opt label=type:unconfined_t` (already in Justfile) |
| QEMU: `Could not access KVM kernel module` | KVM not available | Enable virtualization in BIOS, `sudo modprobe kvm_intel` or `kvm_amd` |
| QEMU: `OVMF firmware not found` | Missing OVMF package | Install `edk2-ovmf` (Fedora) or `ovmf` (Ubuntu) |
| Build runs out of disk space | BuildStream CAS fills disk | Need ~50 GB free; `bst artifact delete` to reclaim |
| `podman load` fails with permission error | Rootless podman can't load large images | The Justfile uses `sudo podman load` |

## What the Build Produces

1. **OCI image** (`egg:latest` in podman) -- a bootc-compatible container image containing a full GNOME desktop OS with Bluefin customizations
2. **Disk image** (`bootable.raw`) -- a 30GB GPT-partitioned disk with systemd-boot, btrfs root, and the deployed OS tree
3. **Running VM** -- QEMU window showing the Bluefin desktop booting with Plymouth splash

## Serial Debug Shell

The disk image includes `systemd.debug_shell=ttyS1` as a kernel argument. In the QEMU console (stdio), you get access to this debug shell for troubleshooting boot issues without needing a graphical login.

## Local OTA Updates via Registry

The local dev workflow extends beyond booting a VM -- you can push updates to a running VM via a local `zot` OCI registry. This enables a full build-publish-upgrade loop without leaving the network.

**Plan:** `docs/plans/2026-02-15-local-ota-registry.md` has the full design and implementation tasks.

### Quick Reference

| Command | What it does |
|---|---|
| `just registry-start` | Start local zot registry on port 5000 |
| `just registry-stop` | Stop the registry (data preserved in volume) |
| `just registry-status` | Show registry status and image catalog |
| `just publish` | Push `egg:latest` from podman to the local registry |
| `just vm-switch-local` | Print the `bootc switch` command to run inside the VM |

### The OTA Dev Loop

```
1. just build                              # Build the image
2. just publish                            # Push to local registry
3. just generate-bootable-image && just boot-vm  # Boot VM (first time only)
4. [In VM] sudo bootc switch --transport registry 10.0.2.2:5000/egg:latest  # One-time
5. [In VM] sudo bootc upgrade              # Pull update from local registry
```

After step 4, the VM permanently tracks the local registry. The iterative loop is just: edit -> `just build` -> `just publish` -> `bootc upgrade` in VM.

### How It Works

- **zot** runs as a podman container on the host, listening on port 5000
- **`10.0.2.2`** is QEMU's default gateway to the host -- the VM reaches the registry there
- **`bootc switch`** rewrites the VM's tracked image ref (one-time, persists across reboots)
- **`registries.conf.d` drop-in** in the image marks `10.0.2.2:5000` as insecure (HTTP, no TLS)
- **`policy.json.d` drop-in** allows unsigned pulls from `10.0.2.2:5000`

These configs only affect `10.0.2.2:5000` -- an IP that only exists inside QEMU VMs. Zero effect on production.

## Related Skills

- **`debugging-bst-build-failures`** -- When a build fails during local testing, use this skill for systematic diagnosis of BuildStream element failures
- **`ci-pipeline-operations`** -- Understanding how the full CI pipeline works, including remote artifact caching and image publishing to GHCR. Note: the local registry is dev-only; CI continues to use GHCR
- **`oci-layer-composition`** -- The `bluefin/local-dev-registry.bst` element adds container registry config files to the Bluefin layer
