#!/usr/bin/env bash
# Copyright (c) 2026 lightjunction
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# Safe DKMS helper functions — avoid set -e at top-level so sourcing cannot abort the shell.
# Usage: source ./scripts/dkms-helpers-fixed.sh

# Helper: ensure we are in project dir with dkms.conf
_check_dkms_conf() {
    if [ ! -f "dkms.conf" ]; then
        printf 'ERROR: dkms.conf not found in current directory (%s)\n' "$(pwd)" >&2
        return 1
    fi
    return 0
}

# Parse values from dkms.conf (returns via stdout)
_get_pkg() {
    _check_dkms_conf || return 1
    sed -n 's/^PACKAGE_NAME="\([^"]*\)".*/\1/p' dkms.conf
}
_get_ver() {
    _check_dkms_conf || return 1
    sed -n 's/^PACKAGE_VERSION="\([^"]*\)".*/\1/p' dkms.conf
}
_get_mod() {
    _check_dkms_conf || return 1
    sed -n 's/^BUILT_MODULE_NAME\[[0-9]*\]="\([^"]*\)".*/\1/p' dkms.conf || true
}
_get_mod_or_fallback() {
    local m pkg
    m="$(_get_mod)" || true
    if [ -z "$m" ]; then
        pkg="$(_get_pkg)" || return 1
        printf '%s' "${pkg%-dkms}"
    else
        printf '%s' "$m"
    fi
}

dkms-install() {
    # Install: sync to /usr/src/<pkg>-<ver>, add, build, install, depmod
    _check_dkms_conf || return 1
    local pkg ver mod
    pkg="$(_get_pkg)" || return 1
    ver="$(_get_ver)" || return 1
    mod="$(_get_mod_or_fallback)" || return 1

    printf 'Installing %s v%s (module: %s)\n' "$pkg" "$ver" "$mod"
    # sync (fail early with message if rsync not present)
    if ! command -v rsync >/dev/null 2>&1; then
        printf 'ERROR: rsync not found. Please install rsync.\n' >&2
        return 1
    fi

    sudo rsync -a --delete ./ "/usr/src/${pkg}-${ver}/" || {
        printf 'rsync failed\n' >&2
        return 1
    }
    sudo dkms add -m "$pkg" -v "$ver" || {
        printf 'dkms add failed\n' >&2
        return 1
    }
    sudo dkms build -m "$pkg" -v "$ver" || {
        printf 'dkms build failed\n' >&2
        return 1
    }
    sudo dkms install -m "$pkg" -v "$ver" || {
        printf 'dkms install failed\n' >&2
        return 1
    }
    sudo depmod -a || {
        printf 'depmod failed\n' >&2
        return 1
    }
    printf 'Install complete.\n'
}

dkms-update() {
    _check_dkms_conf || return 1
    local pkg ver mod
    pkg="$(_get_pkg)" || return 1
    ver="$(_get_ver)" || return 1
    mod="$(_get_mod_or_fallback)" || return 1
    printf 'Rebuilding/installing %s v%s (module: %s)\n' "$pkg" "$ver" "$mod"

    # Ensure rsync is available for syncing current tree into /usr/src
    if ! command -v rsync >/dev/null 2>&1; then
        printf 'ERROR: rsync not found. Please install rsync or run dkms-install which will sync sources.\n' >&2
        return 1
    fi

    printf 'Syncing current directory to /usr/src/%s-%s/ (excluding .git, .agents, build/)...\n' "$pkg" "$ver"
    sudo rsync -a --delete --exclude='.git' --exclude='.agents' --exclude='build/' ./ "/usr/src/${pkg}-${ver}/" || {
        printf 'rsync failed\n' >&2
        return 1
    }

    printf 'Starting dkms build (this may take a while)...\n'
    if ! sudo dkms build -m "$pkg" -v "$ver"; then
        printf 'dkms build failed\n' >&2
        return 1
    fi

    printf 'Installing module via dkms...\n'
    if ! sudo dkms install -m "$pkg" -v "$ver"; then
        printf 'dkms install failed\n' >&2
        return 1
    fi

    if ! sudo depmod -a; then
        printf 'depmod failed\n' >&2
        return 1
    fi

    printf 'Update complete. Showing recent kernel logs and dkms status:\n\n'

    # Show kernel logs: prefer journalctl if available, otherwise dmesg
    if command -v journalctl >/dev/null 2>&1; then
        printf '---- kernel journal (last 50 lines) ----\n'
        sudo journalctl -k -n 50 --no-pager || true
    else
        printf 'journalctl not available; showing dmesg last 50 lines instead\n'
        dmesg | tail -n 50 || true
    fi

    printf '\n---- dkms status ----\n'
    dkms status || true

    printf '\n---- modinfo %s ----\n' "$mod"
    modinfo "$mod" || true

    printf '\nFinished.\n'
}

dkms-uninstall() {
    _check_dkms_conf || return 1
    local pkg ver
    pkg="$(_get_pkg)" || return 1
    ver="$(_get_ver)" || return 1
    printf 'Removing %s v%s from DKMS\n' "$pkg" "$ver"
    sudo dkms remove -m "$pkg" -v "$ver" --all || {
        printf 'dkms remove failed\n' >&2
        return 1
    }
    printf 'Uninstall complete.\n'
}

# Short aliases (optional)
dki() { dkms-install "$@"; }
dku() { dkms-update "$@"; }
dkrm() { dkms-uninstall "$@"; }
