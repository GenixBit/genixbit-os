# Upstream Synchronization Guide

This document defines the procedure for synchronizing **GenixBit OS** with changes from the upstream repository (**[AiursoftWeb/AnduinOS-2](https://github.com/AiursoftWeb/AnduinOS-2)**).

---

## Remote Repository Setup

Verify configured Git remotes:
```bash
git remote -v
```

Expected output:
```text
origin    https://github.com/GenixBit/genixbit-os.git (fetch)
origin    https://github.com/GenixBit/genixbit-os.git (push)
upstream  https://github.com/AiursoftWeb/AnduinOS-2.git (fetch)
upstream  https://github.com/AiursoftWeb/AnduinOS-2.git (push)
```

If `upstream` is missing, add it using:
```bash
git remote add upstream https://github.com/AiursoftWeb/AnduinOS-2.git
```

---

## Recommended Merge Workflow

> [!IMPORTANT]
> **Do NOT Force Push (`git push -f`)**: Always preserve commit history and resolve upstream merges cleanly using standard merge commits.

### Step 1: Fetch Upstream Changes
Fetch all branches and tags from upstream:
```bash
git fetch upstream
```

### Step 2: Checkout Local Main Branch
Ensure you are on the `main` branch:
```bash
git checkout main
```

### Step 3: Merge Upstream Changes
Merge `upstream/master` into your local `main` branch:
```bash
git merge upstream/master
```

### Step 4: Resolve Merge Conflicts
If merge conflicts occur:
1. Inspect conflicted files using `git status`.
2. Ensure GenixBit OS identity variables in `args.sh` (`TARGET_NAME="genixbitos"`, `TARGET_BUSINESS_NAME="GenixBitOS"`, `TARGET_BUILD_VERSION`) are preserved.
3. Ensure upstream licensing notices and attributions in `UPSTREAM.md` and `LICENSE` remain intact.
4. Stage resolved files with `git add <file>`.
5. Complete the merge commit with `git commit`.

### Step 5: Validate Build System Syntax
Verify that shell scripts pass syntax checks after the merge:
```bash
for f in *.sh mods/*.sh mods/*/install.sh; do bash -n "$f"; done
```

### Step 6: Test ISO Generation
Run `make bootstrap` and `make` on a compatible Ubuntu host to confirm the build remains fully functional.
