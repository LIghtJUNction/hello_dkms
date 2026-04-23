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

注意（重要）
- 不要使用 `gcc` 编译内核模块，请使用 `clang`。内核可能由 Clang 构建，使用 GCC 可能会因为 Clang 专属的编译选项（例如 `-mstack-alignment`、`-mretpoline-external-thunk` 等）而导致编译失败。构建时可以通过设置环境变量来指定编译器，例如：
```bash
# 在当前 shell 会话中使用 clang
export KBUILD_CC=clang
# 或直接在单次命令前指定
KBUILD_CC=clang make
```
脚本已包含对内核期望编译器的检测并会在需要时把合适的 `KBUILD_CC` 传递给 DKMS，但在手动运行 `make` 或使用其他工具时请显式使用 `clang`。

- 环境变量请查看项目根目录的 `.envrc` 文件（推荐使用 direnv），也可以使用 dotenv 等工具加载环境变量。示例（将此加入 `.envrc`）：
```bash
export KBUILD_CC=clang
export DKMS_SOURCE_STRATEGY=link
# 或者根据偏好设置 DKMS_FORCE=0 来禁用 --force
export DKMS_FORCE=1
```
如果你使用 dotenv，请先安装并按需加载 `.env` 文件以设置上述变量。

- 若需要生成 `compile_commands.json`（供 clangd / 静态分析工具使用），请使用 `bear` 配合 `make`：
```bash
# 生成 compile_commands.json（需要先安装 bear）
bear -- make
```
或者使用项目内的构建 wrapper（如果存在）：
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
