# Local End-to-End Testing Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable developers and agents to build the egg OCI image, install it to a bootable disk, and launch it in a QEMU VM with a single `just show-me-the-future` command.

**Architecture:** The Justfile wraps all BuildStream invocations inside the bst2 container (same image CI uses) via podman, eliminating the need for a native BuildStream installation. Three composable recipes (`build`, `generate-bootable-image`, `boot-vm`) are chained by the top-level `show-me-the-future` recipe. A project-local OpenCode skill documents the workflow for agents.

**Tech Stack:** just, podman, BuildStream 2 (via bst2 container), QEMU with OVMF (UEFI), bootc

---

### Task 1: Refactor Justfile

**Files:**
- Modify: `Justfile`

**Changes:**

1. Add `bst2_image` variable pinned to the same SHA CI uses
2. Add `bst` recipe that wraps BuildStream inside the bst2 container
3. Refactor `build` to use `just bst` instead of calling `bst` directly
4. Add `boot-vm` recipe with OVMF auto-detection (Fedora + Debian paths)
5. Add `show-me-the-future` recipe that chains build -> generate-bootable-image -> boot-vm
6. Keep existing `build-containerfile`, `bootc`, `generate-bootable-image` recipes functional

Key decisions:
- `bst` recipe uses `--privileged --device /dev/fuse` like CI
- `bst` recipe mounts `$PWD:/src` and `$HOME/.cache/buildstream:/root/.cache/buildstream`
- `boot-vm` auto-detects OVMF paths, copies OVMF_VARS to `.ovmf-vars.fd` for writability
- `boot-vm` uses KVM, virtio devices, 4GB RAM, 2 CPUs
- `show-me-the-future` is the single command that does everything

### Task 2: Fix .gitignore

**Files:**
- Modify: `.gitignore`

**Changes:**

Replace `.opencode/` ignore with a pattern that excludes agent session state but allows `.opencode/skills/` to be committed:
```
.opencode/*
!.opencode/skills/
```

### Task 3: Create project-local skill

**Files:**
- Create: `.opencode/skills/local-e2e-testing/SKILL.md`

Skill content covers:
- When to use: running local builds, testing changes, verifying the image boots
- Prerequisites: podman, QEMU, OVMF, ~50GB free disk, KVM access
- The three commands and what they do
- Common failure modes and fixes
- Expected timeline (~1-2 hours for first build, minutes for cached rebuilds)

### Task 4: Update AGENTS.md

**Files:**
- Modify: `AGENTS.md`

Add a "Local End-to-End Testing" section to the Quick Reference table and the Building Locally section. Reference the skill and the `show-me-the-future` command.

### Task 5: Verify

Run `just --list` to confirm Justfile parses correctly and all recipes are visible.
