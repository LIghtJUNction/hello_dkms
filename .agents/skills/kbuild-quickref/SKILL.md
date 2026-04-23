---
name: kbuild-quickref
description: >
  Compact, machine-friendly decision rules and copy-paste recipes for building
  out-of-tree Linux kernel modules with kbuild. Provide deterministic choices:
  when to use `modules_prepare` vs a full kernel build, when to prefer top-level
  kbuild vs `KBUILD_EXTRA_SYMBOLS`, and quick fixes for common errors.
version: 1.0
---

# kbuild-quickref — Compact decision rules, recipes, and error mappings

Summary / When to trigger
- Trigger when the user asks about building external (out-of-tree) kernel modules,
  kbuild Makefiles/Kbuild, module installation, symbol/version issues, or DKMS
  preparation that depends on kbuild behavior.
- Do NOT trigger for in-tree kernel development or generic C compilation tasks.

Decision rules (if / when)
- Use `make modules_prepare`.
  When: you only need kernel headers and do NOT rely on exported-symbol CRCs
  (i.e., `CONFIG_MODVERSIONS` is not required AND your module does not import
  exported symbols from other modules).
- Require a full kernel build that provides `Module.symvers`.
  When: `CONFIG_MODVERSIONS = y` OR your external module imports exported
  symbols from other modules and CRC checks are enforced by `modpost`.
- Prefer top-level kbuild (single build for multiple modules).
  When: multiple external modules depend on each other and you can build them
  together. This lets `modpost` see exports from producers during the same build.
- Use `KBUILD_EXTRA_SYMBOLS`.
  When: modules are built separately but must share symbols; pass producer
  `.symvers` files to consumers via `KBUILD_EXTRA_SYMBOLS="/path/a.symvers /path/b.symvers"`.

Quick recipes (copy-paste)
- Build a simple external module (out-of-tree).
```hello-1.0/examples.sh#L1-3
make -C /lib/modules/$(uname -r)/build M=$PWD
```

- Build against a specific kernel build tree.
```hello-1.0/examples.sh#L1-3
make -C <KDIR> M=$PWD
```

- Linux 6.13+ alternative (avoid changing workdir).
```hello-1.0/examples.sh#L1-3
make -f /lib/modules/$(uname -r)/build/Makefile M=$PWD
```

- Build with separate module output dir.
```hello-1.0/examples.sh#L1-3
make -C <KDIR> M=$PWD MO=$BUILD_DIR
```

- Install modules into kernel modules tree.
```hello-1.0/examples.sh#L1-3
make -C /lib/modules/$(uname -r)/build M=$PWD modules_install
```

- Provide `Module.symvers` to a consumer build.
```hello-1.0/examples.sh#L1-3
make -C <KDIR> M=$PWD KBUILD_EXTRA_SYMBOLS="/path/to/producer/Module.symvers"
```

Minimal Kbuild / Makefile examples
- Single-file `Kbuild`.
```hello-1.0/Kbuild#L1-3
obj-m := hello.o
```

- Typical out-of-tree Makefile wrapper.
```hello-1.0/Makefile#L1-12
ifneq ($(KERNELRELEASE),)
obj-m := mymod.o
mymod-y := part1.o part2.o
else
KDIR ?= /lib/modules/$(shell uname -r)/build
default:
	$(MAKE) -C $(KDIR) M=$$PWD
endif
```

Error → solution (quick map)
- "Unknown symbol" or undefined symbol warnings during `modprobe`.
  Likely causes:
    - Consumer built without seeing producer exports.
    - Missing or incompatible `Module.symvers`.
  Fixes (in order):
    1. Build producers & consumers together (top-level kbuild).
    2. Or pass producer `.symvers` files via `KBUILD_EXTRA_SYMBOLS`.
    3. Ensure correct `KDIR` and kernel version (`uname -r` vs the kernel tree).
- "Invalid module format" when loading (.ko).
  Cause: vermagic/kernel mismatch.
  Fix:
    - Build against the kernel source/output directory that matches target kernel.
    - After install, run `depmod -a`.
- Build succeeds but module load fails.
  Steps:
    - Inspect `dmesg` / `journalctl -k` for specific errors.
    - Check `modinfo` for vermagic and symbol dependencies.
    - Confirm `Module.symvers` compatibility if CONFIG_MODVERSIONS is set.

Pre-flight checklist (run before building)
- Is `KDIR` pointing to a kernel build tree that matches `uname -r`?
- Do you require symbol CRC checks? Is `CONFIG_MODVERSIONS` enabled?
- If you have multiple interdependent modules, can you build them together (top-level)?
- If you use local headers, set:
```hello-1.0/Kbuild#L1-3
ccflags-y := -I$(src)/include
```
- For per-object flags:
```hello-1.0/Kbuild#L1-3
CFLAGS_file.o := -D...
```

Short guidance for LLM / agent integration
- When answering, present first the single best recipe (copy-paste command) and then 1–2 alternative fixes in order of simplicity (prefer top-level build; else `KBUILD_EXTRA_SYMBOLS`).
- If the user mentions DKMS, delegate DKMS-specific steps to the `hello-dkms` skill (do not duplicate DKMS content here).
- Keep responses concise: include the core command, one-line rationale, and the one follow-up diagnostic to run (e.g., `dmesg | tail -n 20` or `modinfo <module>`).

Trigger checklist (what the model should output when this skill triggers)
- One-line decision: modules_prepare vs full build vs top-level vs KBUILD_EXTRA_SYMBOLS.
- Copy-paste recipe (single command block).
- One common diagnostic command to run if something breaks.
- Reference to `Module.symvers` if modversions may apply.

Notes and constraints
- `make modules_prepare` prepares headers only and does NOT produce `Module.symvers`. For reproducible modversion checks you must build a full kernel (which generates `Module.symvers`).
- Avoid recommending editing kernel source tree; prefer using a kernel build/output tree or `MO=` for CI isolation.
- Be explicit about permissions: module install and DKMS operations require elevated privileges (user consent to run commands).

End of skill.