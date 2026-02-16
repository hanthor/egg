---
name: managing-bst-overrides
description: Use when creating, evaluating, or removing BuildStream junction element overrides - ensures agents follow GNOME OS upstream-first principle and maintain recognizable patterns
---

# Managing BuildStream Junction Overrides

## Overview

Bluefin-egg extends **gnome-build-meta** via junction. By default, all gnome-build-meta elements (and its freedesktop-sdk transitive dependency) are used as-is from upstream. **Overrides** replace specific upstream elements with local versions. Overrides should be **rare** and **justified** - the upstream-first principle means we align with GNOME OS patterns unless there's a compelling Bluefin-specific reason.

**Guiding principle:** A GNOME OS maintainer should recognize this as a standard GNOME-based image. Overrides break that recognition and create maintenance burden.

## Override Mechanism

Overrides are declared in the junction element using `config.overrides`:

```yaml
# elements/gnome-build-meta.bst
kind: junction
sources:
- kind: git_repo
  url: gnome:gnome-build-meta.git
  ref: <pinned-ref>
- kind: patch_queue
  path: patches/gnome-build-meta
config:
  overrides:
    oci/os-release.bst: oci/os-release.bst
    core/meta-gnome-core-apps.bst: core/meta-gnome-core-apps.bst
```

**What this does:**
- When BuildStream sees `gnome-build-meta.bst:oci/os-release.bst`, it loads `elements/oci/os-release.bst` (local) instead of `gnome-build-meta:oci/os-release.bst` (upstream)
- The local element **completely replaces** the upstream element - no merging, no inheritance
- Dependencies, sources, variables - everything comes from the local file

## When to Create an Override

✅ **Valid reasons:**
- **Bluefin branding**: os-release, Plymouth theme, desktop background
- **Significant behavioral changes**: Package selection (meta-gnome-core-apps excludes unwanted GNOME apps)
- **Impossible to patch**: Changing fundamental structure (like dependency lists in a stack element)

❌ **Invalid reasons (use patching instead):**
- **Build flag changes**: Patch the upstream element via patch_queue
- **Version bumps**: Patch the upstream element to update the ref
- **Bug fixes**: Patch upstream, then submit upstream so the patch can eventually be dropped
- **"Just easier"**: Short-term convenience creates long-term divergence and maintenance burden

### Decision Matrix

| Goal | Mechanism | Why |
|---|---|---|
| Change os-release to say "Bluefin" | Override | Bluefin-specific branding |
| Enable a compiler flag on openssh | Patch | Behavioral tweak, stays aligned |
| Remove GNOME Maps from core apps | Override | Significant app selection change |
| Bump bootc to v1.2.0 | Patch | Version bump, aligns with upstream workflow |
| Fix bootc build failure | Patch | Bug fix, upstream can adopt |
| Replace bootc with identical copy | **NEVER** | Pointless divergence, pure maintenance burden |

## Creating an Override

### 1. Create the local element

```bash
# Copy from upstream as starting point (optional but recommended):
just bst source checkout gnome-build-meta.bst --directory /tmp/gbm-checkout
cp /tmp/gbm-checkout/elements/path/to/element.bst elements/path/to/element.bst
```

Edit the local file to make Bluefin-specific changes. Add a comment at the top documenting **why** this is an override:

```yaml
# Override: Bluefin branding - replaces GNOME OS release info with Bluefin identity
kind: manual
```

### 2. Declare the override in the junction

Edit `elements/gnome-build-meta.bst`:

```yaml
config:
  overrides:
    path/to/element.bst: path/to/element.bst
```

The syntax is `upstream-path: local-path` (usually identical).

### 3. Verify the override works

```bash
just bst show oci/bluefin.bst | grep 'path/to/element.bst'
# Should show elements/path/to/element.bst NOT gnome-build-meta.bst:path/to/element.bst
```

### 4. Update tracking (if needed)

If the element tracks upstream sources, add it to `.github/workflows/track-bst-sources.yml`:

```yaml
elements:
  auto-update:
    - path/to/element.bst
```

## Removing an Override

**Checklist** (mandatory - follow every step):

### 1. Verify upstream provides equivalent functionality

```bash
# Check out upstream at current junction ref
just bst source checkout gnome-build-meta.bst --directory /tmp/gbm-checkout
cat /tmp/gbm-checkout/elements/path/to/element.bst
```

**Compare carefully:**
- Do we need any customizations from the local version?
- If yes → convert to a patch via `patching-upstream-junctions` skill
- If no → proceed with removal

### 2. Remove override declaration

Edit `elements/gnome-build-meta.bst`, delete the line from `config.overrides:`:

```yaml
config:
  overrides:
    path/to/element.bst: path/to/element.bst  # DELETE THIS LINE
```

### 3. Update references to use junction path

Find all references to the override:

```bash
rg --type=bst 'path/to/element.bst'
```

For each **non-junction reference** (`path/to/element.bst` instead of `gnome-build-meta.bst:path/to/element.bst`), update to the junction path:

```yaml
# Before:
build-depends:
- core/bootc.bst

# After:
build-depends:
- gnome-build-meta.bst:gnomeos-deps/bootc.bst
```

**Exception:** If the reference is FROM a local override element, you may need to keep the local path (but re-evaluate whether that override should exist).

### 4. Remove tracking entries

Search `.github/workflows/track-bst-sources.yml` for the element name and remove it from tracking groups (auto-update, manual-merge, etc.).

### 5. Update documentation

Skills reference overrides as examples. Update:
- `.opencode/skills/patching-upstream-junctions/SKILL.md`
- `.opencode/skills/oci-layer-composition/SKILL.md`
- `.opencode/skills/packaging-*/SKILL.md` (for package-type-specific examples)
- `.opencode/skills/updating-upstream-refs/SKILL.md` (tracking groups)

Search for the element filename across all skill files:

```bash
rg 'element-name' .opencode/skills/
```

### 6. Delete the local element file

```bash
rm elements/path/to/element.bst
```

### 7. Verify the build

```bash
# Verify dependency graph resolves:
just bst show oci/bluefin.bst

# Verify build succeeds (or fails for unrelated reasons):
just build
```

**Critical:** The junction path (e.g., `gnome-build-meta.bst:path/to/element.bst`) must appear in `bst show` output. If it says "element not found" or "reference not found", you broke something in steps 2-3.

## Override Hygiene Audit

Periodically (quarterly or when bumping upstream refs), audit existing overrides:

### 1. List all current overrides

```bash
yq '.config.overrides' elements/gnome-build-meta.bst
```

### 2. For each override, check if it's still justified

```bash
# Check out current upstream:
just bst source checkout gnome-build-meta.bst --directory /tmp/gbm-checkout

# Compare local vs upstream:
diff -u /tmp/gbm-checkout/elements/path/to/element.bst elements/path/to/element.bst
```

**Ask:**
- Is the diff Bluefin-specific branding/customization? → Keep override
- Is the diff a version bump or bug fix? → Convert to patch, remove override
- Is the diff empty or trivial? → **Remove override immediately** (identical overrides are bugs)

### 3. Document findings

Create a plan in `docs/plans/YYYY-MM-DD-override-audit.md` listing:
- Overrides that should be removed
- Overrides that should be converted to patches
- Overrides that are justified and should remain

## Current Overrides (2026-02-16)

| Override | Justification | Status |
|---|---|---|
| `oci/os-release.bst` | Bluefin branding (NAME, ID, PRETTY_NAME, etc.) | ✅ Justified |
| `core/meta-gnome-core-apps.bst` | Custom GNOME app selection (removes unwanted apps) | ✅ Justified |
| `bluefin/plymouth-bluefin-theme.bst` | Replaces `gnomeos-deps/plymouth-gnome-theme.bst` | ✅ Justified (branding) |

**Removed overrides:**
- ~~`core/bootc.bst`~~ (2026-02-16): Identical to upstream - removed
- ~~`oci/gnomeos.bst`~~ (2026-02-16): Defensive /usr/etc merge was redundant - removed

## Red Flags

These patterns indicate override misuse:

🚩 **Identical override**: Local element is byte-for-byte identical to upstream
- **Why bad:** Pure maintenance burden, no value, breaks caching
- **Fix:** Remove immediately

🚩 **Version-only override**: Only difference is `ref:` field pointing to newer version
- **Why bad:** Upstream will catch up; patch is better
- **Fix:** Convert to patch, remove override

🚩 **Override without comment**: No explanation of why it exists
- **Why bad:** Future maintainers don't know if it's safe to remove
- **Fix:** Add comment documenting Bluefin-specific need

🚩 **Override of freedesktop-sdk element**: Overriding FDO SDK elements is almost never justified
- **Why bad:** Even more fundamental than GNOME - extremely high maintenance burden
- **Fix:** Patch instead, or reconsider whether the change is needed

🚩 **Override that could be a patch**: Element diff only changes build flags, configure options, or sources
- **Why bad:** Patch keeps us aligned with upstream structure
- **Fix:** Convert to patch via `patching-upstream-junctions` skill

## Integration with Other Skills

- **Before creating override:** Read `patching-upstream-junctions` to see if a patch suffices
- **When removing package:** Check `removing-packages` for dependency cleanup
- **After override changes:** Run `verification-before-completion` with local build evidence
- **When updating upstream refs:** Read `updating-upstream-refs` for junction ref bumps
- **When building locally:** Use `local-e2e-testing` for full verification workflow

## Examples

### Example: Removing an Identical Override (bootc)

This is the exact process used to remove `core/bootc.bst` on 2026-02-16:

**Discovery:**
```bash
# Check upstream version
just bst source checkout gnome-build-meta.bst --directory /tmp/gbm
diff -u /tmp/gbm/elements/gnomeos-deps/bootc.bst elements/core/bootc.bst
# Output: Files are identical (1358 lines, both v1.12.1, same cargo deps)
```

**Removal:**
```bash
# 1. Remove override declaration
# Edit elements/gnome-build-meta.bst, delete line 20 from config.overrides

# 2. Update reference in oci/bluefin.bst
# Change build-depends from 'core/bootc.bst' to 'gnome-build-meta.bst:gnomeos-deps/bootc.bst'

# 3. Remove tracking
# Edit .github/workflows/track-bst-sources.yml, remove 'core/bootc.bst' from manual-merge group

# 4. Update skills (5 files)
rg 'core/bootc' .opencode/skills/
# Update references in packaging-rust-cargo-projects, updating-upstream-refs, etc.

# 5. Delete local file
rm elements/core/bootc.bst

# 6. Verify
just bst show oci/bluefin.bst | grep bootc
# Output: gnome-build-meta.bst:gnomeos-deps/bootc.bst (SUCCESS - using upstream)
```

**Result:** 1358 lines of dead weight removed, BuildStream now pulls cached artifacts from GNOME's CAS, zero functional change.

### Example: Keeping a Justified Override (os-release)

```bash
# Check diff
diff -u /tmp/gbm/elements/oci/os-release.bst elements/oci/os-release.bst
```

**Output shows Bluefin-specific branding:**
```diff
-  NAME: "GNOME OS"
-  ID: gnomeos
+  NAME: "Bluefin"
+  ID: bluefin
-  PRETTY_NAME: "GNOME OS (46.0)"
+  PRETTY_NAME: "Bluefin Egg ($(rpm --eval '%{os_version}'))"
```

**Conclusion:** Override is justified - this is fundamental Bluefin branding. Keep it, add comment documenting it.

## Upstream-First Principle

The goal is **not** to avoid overrides entirely - it's to use them **only when necessary** for Bluefin-specific needs. Every override creates divergence from GNOME OS:

- ✅ Divergence for branding: Acceptable (that's what makes it Bluefin)
- ✅ Divergence for user experience: Acceptable (curated app selection)
- ❌ Divergence for convenience: Not acceptable (patch instead)
- ❌ Divergence with no reason: Not acceptable (remove immediately)

**Litmus test:** If a GNOME OS maintainer looked at our element tree, would they say "this is clearly GNOME-based with Bluefin branding" or "what is this custom mess?" Overrides push us toward the latter.

## Troubleshooting

### "Element not found" after removing override

**Cause:** Forgot to update references to use junction path.

**Fix:**
```bash
rg 'old/element/path.bst' elements/
# For each match, change to gnome-build-meta.bst:old/element/path.bst
```

### Build fails after removing override

**Likely causes:**
1. We relied on a local customization (should've converted to patch)
2. Upstream element has a bug (submit upstream fix, patch in meantime)
3. Dependency graph changed (upstream refactored element structure)

**Debug:**
```bash
# Compare local (before removal) vs upstream:
git show HEAD~1:elements/path/to/element.bst > /tmp/local.bst
just bst source checkout gnome-build-meta.bst --directory /tmp/gbm
diff -u /tmp/local.bst /tmp/gbm/elements/path/to/element.bst
```

### Override shows as "cached" but I just changed it

**Cause:** BuildStream caches by strong cache key (hash of element content + dependencies). If you changed only comments or whitespace, the cache key is unchanged.

**Fix:** Make a functional change (add/remove a dependency, change a variable) or bust the cache:
```bash
just bst artifact delete path/to/element.bst
```
