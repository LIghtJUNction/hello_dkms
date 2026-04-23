<!--
  ~ Copyright (c) 2026 lightjunction
  ~
  ~ This program is free software: you can redistribute it and/or modify
  ~ it under the terms of the GNU General Public License as published by
  ~ the Free Software Foundation, either version 3 of the License, or
  ~ (at your option) any later version.
-->

---
name: hello-dkms
description: >
  Install, build, verify, and remove the `hello-dkms` out-of-tree Linux kernel module via DKMS.
  Use this skill whenever a user asks how to prepare sources for DKMS, how to add/build/install a DKMS module,
  how to verify kernel logs after loading the module, or how to remove a DKMS-managed module. Be slightly pushy:
  if the user mentions "DKMS", "kernel module", "modprobe", "Module.symvers", "headers", or "installing modules", consult this skill.
compatibility:
  - requires: dkms, kernel headers for target kernel, sudo access
  - suggested-environment: Arch-like distributions (commands in examples use `pacman`/`paru` style package names), generic Linux principles apply
version: 1.0
---

## Summary / When to trigger

This skill documents a small, deterministic workflow to manage an out-of-tree kernel module called `hello-dkms` using DKMS:

- How to place the sources at `/usr/src/<name>-<version>`.
- How to call `dkms add`, `dkms build`, `dkms install`.
- How to verify via `modprobe`, `dmesg`, or `journalctl -k`.
- How to remove the module from DKMS.

Trigger this skill whenever the user asks any of the following (not exhaustive, but representative):
- "How do I install this kernel module with DKMS?"
- "Where should I put the source for DKMS?"
- "dkms build / dkms install failing — what do I do?"
- "How to check kernel logs after loading module?"
- "How to remove a DKMS module?"
Also trigger when the user describes building kernel modules and mentions a workflow that would benefit from DKMS (automatic rebuilds on kernel upgrades, consistent source placement, use of `/usr/src`).

Do NOT trigger when the user asks about:
- In-tree kernel module development (i.e., modifying the kernel itself).
- Generic C compilation unrelated to kernel modules.
- Non-kernel binary packages installation.

## What this skill provides

- Clear, step-by-step commands and their intent for the `hello-dkms` module.
- Suggested verification steps and common troubleshooting tips.
- Small, reproducible test prompts (for skill evaluation) and expected outputs.
- Safety notes (require sudo, headers must match target kernel, Module.symvers considerations).

## Usage / Workflow

Use the following steps as the canonical DKMS workflow for this module. Replace `hello-dkms` and version `1.0` with the module's real name and version when adapting.

1. Prepare source directory (DKMS expects `/usr/src/<name>-<version>`).
   - Purpose: DKMS locates the source tree by this convention; keep it versioned.
   - Example intent (not run here): clone repo, then move to standard path.

   Example (sequence of actions a user should perform):
   - Clone the module repo somewhere writable.
   - As root, place it at `/usr/src/hello-dkms-1.0`.
   - Ensure `dkms.conf` and the source files are present at that path.

2. Install dependencies (host-specific).
   - Ensure `dkms` and the appropriate kernel headers are installed for the target kernel.
   - Example package names vary by distribution. On Arch-like systems, use the kernel headers package matching your kernel.

3. Add, build, and install the module with DKMS.
   - `dkms add -m hello-dkms -v 1.0`
     - Registers the source tree with DKMS.
   - `dkms build -m hello-dkms -v 1.0`
     - Compiles the module against the currently-active kernel build headers specified by your kernel build tree.
   - `dkms install -m hello-dkms -v 1.0`
     - Installs the compiled module into `/lib/modules/<release>/updates/` (or similar), and runs depmod.

   Notes:
   - On some systems you may combine add/build/install with automation or wrapper scripts. Keep commands separate when debugging.
   - If `modpost` complains about missing symbols, you may need a matching `Module.symvers` from a full kernel build or provide `.symvers` files via `KBUILD_EXTRA_SYMBOLS`.

4. Verify the module
   - Load:
     - `sudo modprobe hello_dkms` (module name depends on the module's `MODULE_NAME` in the source; confirm the produced `.ko` filename)
   - Check kernel output:
     - `dmesg | tail -n 10`
     - or `journalctl -k | tail -n 10`
   - Expected: a message from the module init (the sample `hello.c` typically prints something like "Hello, world" or the module name/version).
   - If the module fails to load, check:
     - `dkms status` to confirm installed builds
     - `sudo modinfo hello_dkms` for module metadata
     - `dmesg` for errors such as "Unknown symbol" or "version magic" mismatches

5. Remove the module
   - `sudo dkms remove -m hello-dkms -v 1.0 --all`
     - The `--all` flag removes all installed instances for all kernels. Omit it if you intend to remove only for a specific kernel version.

## Troubleshooting tips (common issues and what to check)

- Kernel header mismatch / version magic:
  - Ensure headers correspond to the running kernel: `uname -r` vs installed headers package.
  - If you built against a different kernel, rebuild against the correct headers.

- Missing `Module.symvers` or exported symbol CRC failures:
  - For strict modversions setups, get `Module.symvers` from a full kernel build or provide dependent module `.symvers` via `KBUILD_EXTRA_SYMBOLS`.

- Undefined symbol errors at load time:
  - Examine `dmesg` to see which symbol is missing and ensure the provider module is loaded or exported correctly.

- Permission issues moving files into `/usr/src`:
  - Use `sudo` or root to move files; preserve ownership/permissions so DKMS and package scripts can read them.

## Files referenced in this repository

(These paths are repository-local references the skill consults or expects.)
- `dkms.conf` — DKMS control file that should be present in the module source tree.
- `hello.c` — example module source used for the sample `hello-dkms` module.
- `Makefile` / `Kbuild` — module build metadata used by kbuild/kbuild wrapper.

Refer to these files when you need to adapt the example to a different module name or add more sources.

## Testing this skill (evals and test prompts)

Suggested test prompts (save to `evals/evals.json` under the skill workspace when you run evaluations). These are realistic user queries that should cause the skill to trigger.

- Should-trigger (deploy/install flow)
  - Prompt: "I cloned a repo that builds an out-of-tree kernel module. It has a `dkms.conf` and `hello.c`. Where should I put it so DKMS can manage it, and how do I add/build/install it so it rebuilds on kernel updates?"
  - Expected output: Step-by-step instructions matching the "Usage / Workflow" section: place under `/usr/src/hello-dkms-1.0`, run `dkms add`, `dkms build`, `dkms install`, then `modprobe` and `dmesg` verification steps.

- Should-not-trigger (unrelated or in-tree requests)
  - Prompt: "How do I modify the Linux kernel's memory allocator in-tree and rebuild the kernel?"
  - Expected behavior: Do not trigger this skill; instead recommend in-tree kernel development resources (kernel source tree, `make` targets, configuring and building the whole kernel). Explain why DKMS is not the right tool.

When running verification/evaluations:
- Use two runs per test: with-skill (this skill consulted) and baseline (no skill).
- Save qualitative outputs and a short checklist verifying the presence of key steps: `/usr/src` placement, `dkms add`/`build`/`install` commands, `modprobe` and `dmesg` verification.

## Packaging and distribution notes

- Keep `SKILL.md` and small eval JSON under the skill directory.
- If bundling scripts (e.g., small wrappers to run `dkms` commands), put them in `scripts/` inside the skill directory and reference them in `SKILL.md`.
- The skill intentionally avoids executing commands; it provides deterministic instructions. Always require the user to run commands themselves.

## Security and safety

- The instructions require `sudo` and write access to system directories. Emphasize that the user must review and understand commands before executing.
- Do not embed or suggest insecure practices like disabling module signature checks globally. If kernel module signing or secure boot is present, note that additional signing steps are required and defer to distribution documentation.

## Maintenance and improvement ideas

- Add platform-specific examples (Debian/Ubuntu apt package names, Fedora dnf names).
- Provide a helper script that validates the header-package vs `uname -r` and warns of mismatches.
- Expand evals to include failing scenarios (symbol mismatch, missing headers) so grading can ensure the skill explains how to diagnose those failures.

## Short checklist (what the model should output when the skill triggers)

- Remind user to put source at `/usr/src/<name>-<version>`.
- Show `dkms add`, `dkms build`, `dkms install` commands.
- Show verification commands: `modprobe`, `dmesg` / `journalctl -k`.
- Mention `dkms remove -m <name> -v <version> --all` for removal.
- Note kernel headers must match the running kernel and mention `Module.symvers` if modversion checks are likely.


End of skill.
