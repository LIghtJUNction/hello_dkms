<!--
  ~ Copyright (c) 2026 lightjunction
  ~
  ~ This program is free software: you can redistribute it and/or modify
  ~ it under the terms of the GNU General Public License as published by
  ~ the Free Software Foundation, either version 3 of the License, or
  ~ (at your option) any later version.
-->

# hello-dkms

A minimal DKMS “Hello World” module.

## Quick start

```bash
# One‑liner install (review script first)
curl -fsSL https://raw.githubusercontent.com/LIghtJUNction/hello_dkms/main/scripts/setup.bash | bash
```

---

## 1. Setup source directory

DKMS requires source to live in `/usr/src/<name>-<version>`.

```bash
git clone https://github.com/LIghtJUNction/hello_dkms.git
```

---

## 2. Install dependencies

```bash
sudo pacman -S base-devel dkms linux-headers
```

---

## 3. Build and install

```bash
# Extract PACKAGE_VERSION from dkms.conf
VER=$(sed -n 's/^PACKAGE_VERSION="\\([^"]*\\)".*/\\1/p' dkms.conf)

# Sync current tree into DKMS source dir
sudo rsync -a --delete ./ /usr/src/hello-dkms-$VER/

# Add, build and install
sudo dkms add -m hello-dkms -v $VER
sudo dkms build -m hello-dkms -v $VER
sudo dkms install -m hello-dkms -v $VER
```

- The project’s `.envrc` lists recommended environment variables.  
  You can use `direnv`, `dotenv`, or similar tools to load them.

  Example `.envrc` entries:

  ```bash
  export DKMS_SOURCE_STRATEGY=link
  export DKMS_FORCE=1
  ```

- To generate `compile_commands.json` for `clangd` or other tools:

  ```bash
  bear -- make
  ```

  or, if a wrapper script exists:

  ```bash
  ./scripts/build.sh bear -- make
  ```

---

## 4. Verify

```bash
sudo modprobe hello
sudo dmesg | tail -n 1
# or
journalctl -k | tail -n 1
```

The module is built as `hello`, with `hello_world` as an alias.

---

## Versioning (authoritative)

- Canonical version source: `PACKAGE_VERSION` in `dkms.conf`.  
- Generated `version.h` is updated automatically by the Makefile; **do not edit it manually**.  

To bump the version:

1. Edit `dkms.conf`, e.g. `PACKAGE_VERSION="1.1"`.
2. Commit the change:

   ```bash
   git add dkms.conf
   git commit -m "chore: bump PACKAGE_VERSION to 1.1"
   ```

3. Re‑run the build/install steps from Section 3 (or use helper scripts `dki` / `dku` if sourced).  
   The Makefile will regenerate `version.h`.

---

## Helper scripts (`dki` / `dku` / `dkrm`) and source strategy

The repo includes `scripts/dkms-helper.bash`, providing:

- `dki` – register, build and install the module for the version in `dkms.conf`.  
- `dku` – re‑build / update and show recent kernel logs and DKMS status.  
- `dkrm` – uninstall the currently configured version.

```bash
# Make helper executable
chmod +x scripts/dkms-helper.bash

# Load into current shell (or add to .envrc)
source ./scripts/dkms-helper.bash
```

### Source strategy: `link` vs `rsync`

- `link` (default):  
  `/usr/src/<name>-<version>` is a symlink to your working directory (fast, good for development).  
- `rsync`:  
  The working tree is copied to `/usr/src/<name>-<version>` (more isolated, safer in production‑like workflows).

Choose one:

- Default (recommended for dev): do nothing (uses `link`).
- Single‑shot `rsync`:

  ```bash
  DKMS_SOURCE_STRATEGY=rsync dki
  DKMS_SOURCE_STRATEGY=rsync dku
  ```

- Persistent:

  ```bash
  export DKMS_SOURCE_STRATEGY=rsync
  ```

Notes on `link` strategy:

- DKMS builds directly from your working tree; edits take effect immediately.  
- If you prefer isolation, switch to `rsync`.

Examples with helpers:

```bash
source ./scripts/dkms-helper.bash  # or in .envrc

dki                            # install (default link)
dku                            # update and log
dkrm                           # remove current version
DKMS_SOURCE_STRATEGY=rsync dki # install with rsync
```

---

## 5. Remove

```bash
VER=$(sed -n 's/^PACKAGE_VERSION="\\([^"]*\\)".*/\\1/p' dkms.conf)
sudo dkms remove -m hello-dkms -v $VER --all
```
