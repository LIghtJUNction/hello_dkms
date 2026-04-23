<!--
  ~ Copyright (c) 2026 lightjunction
  ~
  ~ This program is free software: you can redistribute it and/or modify
  ~ it under the terms of the GNU General Public License as published by
  ~ the Free Software Foundation, either version 3 of the License, or
  ~ (at your option) any later version.
-->

# hello-dkms

A minimal DKMS "Hello World" module .

## quick start
```bash
# Quick install (one-liner)
# Install script hosted in the repository — review it before running.
curl -fsSL  https://raw.githubusercontent.com/LIghtJUNction/hello_dkms/main/scripts/setup.bash | bash
```

## 1. Setup Source Directory
DKMS requires the source to be in `/usr/src/<name>-<version>`.
```bash
# paru -S direnv 
# Clone the repo and move to the standard location
git clone https://github.com/LIghtJUNction/hello_dkms.git

```

## 2. Install Dependencies
```bash
# Install DKMS and headers 
sudo pacman -S base-devel dkms linux-headers
```

## 3. Build and Install
```bash
# Add, build and install the module using PACKAGE_VERSION from dkms.conf
# Extract PACKAGE_VERSION into VER and sync current tree into /usr/src
VER=$(sed -n 's/^PACKAGE_VERSION="\([^"]*\)".*/\1/p' dkms.conf)
sudo rsync -a --delete ./ /usr/src/hello-dkms-$VER/
sudo dkms add -m hello-dkms -v $VER
sudo dkms build -m hello-dkms -v $VER
sudo dkms install -m hello-dkms -v $VER
```
- See the project's `.envrc` for recommended environment variables (we recommend using `direnv`). You can also use dotenv or similar tools to load environment variables. Example entries to add to `.envrc`:
```bash
export DKMS_SOURCE_STRATEGY=link
# Or set DKMS_FORCE=0 to disable the default --force behavior
export DKMS_FORCE=1
```
If you use dotenv, install it and load a `.env` file as needed.

- To generate `compile_commands.json` for use with `clangd` or other static analysis tools, use `bear` together with `make`:
```bash
# Requires bear to be installed
bear -- make
```
Or use the repository build wrapper if present:
```bash
./scripts/build.sh bear -- make
```

## 4. Verify
```bash
# Load module and check logs (module name is 'hello' as compiled; alias 'hello_world' also available)
sudo modprobe hello
sudo dmesg | tail -n 1
# or
journalctl -k | tail -n 1
```

## Versioning (authoritative)
- The canonical source of the package/module version is the `PACKAGE_VERSION` field in `dkms.conf`.
- Do not manually edit the generated `version.h`: it is created automatically by the Makefile from `dkms.conf` at build time and will be overwritten.
- To bump the module version:
  1. Edit `dkms.conf` and change `PACKAGE_VERSION="x.y.z"` to the desired version.
  2. Commit the change to your repo.
  3. Run the build/install steps above (or use the helper commands `dki`/`dku` if you have sourced the helper script). The Makefile will generate an updated `version.h` for the build.

Example (bump to 1.1):
```bash
# Edit dkms.conf -> PACKAGE_VERSION="1.1"
git add dkms.conf && git commit -m "chore: bump PACKAGE_VERSION to 1.1"
# Then run the build/install commands in section 3 (they will generate version.h automatically)
VER=$(sed -n 's/^PACKAGE_VERSION="\([^"]*\)".*/\1/p' dkms.conf)
sudo rsync -a --delete ./ /usr/src/hello-dkms-$VER/
sudo dkms build -m hello-dkms -v $VER
sudo dkms install -m hello-dkms -v $VER
```

## Helper scripts (dki / dku / dkrm) and source strategy
This repository includes a helper script at `scripts/dkms-helper.bash` that provides convenient commands for development:

- `dki` (alias for `dkms-install`): register, build and install the module for the version in `dkms.conf`.
- `dku` (alias for `dkms-update`): rebuild and install the currently configured version and show recent kernel logs and dkms status.
- `dkrm` (alias for `dkms-uninstall`): remove the currently configured version from DKMS.

Before using the helpers:
```bash
# Make the script executable (once)
chmod +x scripts/dkms-helper.bash

# Load helpers into your current shell (or add this line to .envrc for direnv)
source ./scripts/dkms-helper.bash
```

Source strategy (link vs rsync)
- The helpers support two strategies for how the DKMS source in `/usr/src/<name>-<version>` is prepared:
  - `link` (default): the helper creates/refreshes a symlink `/usr/src/<name>-<version>` that points to your current working directory. This is fast and avoids copying files, ideal for iterative development.
  - `rsync`: the helper copies (rsync -a --delete) your current working tree into `/usr/src/<name>-<version>` (the previous behavior). This is safer if you want the system copy to be independent of your working tree.

How to choose:
- Default (recommended for development): do nothing — the helpers will use the `link` strategy.
- To force `rsync` for a single invocation:
```bash
# Use rsync for this run only
DKMS_SOURCE_STRATEGY=rsync dki
DKMS_SOURCE_STRATEGY=rsync dku
```
- Or persistently export the variable in your shell or `.envrc`:
```bash
# Persistently use rsync
export DKMS_SOURCE_STRATEGY=rsync
```

Symlink behavior notes
- When using the default `link` strategy the helper will create `/usr/src/hello-dkms-<VER>` as a symlink pointing at your working directory. That means DKMS will build directly from your working tree — fast for iteration, but changes you make are immediately visible to DKMS builds.
- If you prefer isolation between system sources and your working tree (e.g., to prevent accidental edits of system-side files), use `rsync` strategy.

Examples (using helpers)
```bash
# Make helpers available in the current shell (or add to .envrc and run direnv allow)
source ./scripts/dkms-helper.bash

# Install the package (default link strategy)
dki

# Rebuild/update and show logs
dku

# Remove the version currently defined in dkms.conf
dkrm

# Use rsync instead of link for this install
DKMS_SOURCE_STRATEGY=rsync dki
```

## 5. Remove
```bash
# Remove the currently configured PACKAGE_VERSION from DKMS
VER=$(sed -n 's/^PACKAGE_VERSION="\([^"]*\)".*/\1/p' dkms.conf)
sudo dkms remove -m hello-dkms -v $VER --all
```
