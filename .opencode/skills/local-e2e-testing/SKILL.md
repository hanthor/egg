---
name: local-e2e-testing
description: Use when building the egg OCI image locally, testing changes end-to-end, verifying the image boots, or running any BuildStream commands against the project
---

# Local End-to-End Testing

## Overview

Build Bluefin from source and boot it in a VM using three composable `just` recipes. All BuildStream commands run inside the bst2 container via podman -- no native BuildStream installation required.

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
```

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
