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

# Create a symlink in /usr/src/<pkg>-<ver> pointing to the current working tree.
# This avoids copying files for development workflows.
dkms-link() {
    _check_dkms_conf || return 1
    local pkg ver src target
    pkg="$(_get_pkg)" || return 1
    ver="$(_get_ver)" || return 1
    src="$(pwd)"
    target="/usr/src/${pkg}-${ver}"
    printf 'Creating/refreshing symlink %s -> %s\n' "$target" "$src"
    sudo mkdir -p /usr/src
    if ! sudo ln -sfn "$src" "$target"; then
        printf 'ln failed\n' >&2
        return 1
    fi
    printf 'Symlink ready: %s -> %s\n' "$target" "$src"
}

dkms-install() {
    # Install: either create a symlink in /usr/src/<pkg>-<ver> (default),
    # or rsync the current tree into that location depending on
    # DKMS_SOURCE_STRATEGY environment variable.
    _check_dkms_conf || return 1
    local pkg ver mod strategy
    pkg="$(_get_pkg)" || return 1
    ver="$(_get_ver)" || return 1
    mod="$(_get_mod_or_fallback)" || return 1

    strategy="${DKMS_SOURCE_STRATEGY:-link}"
    printf 'Installing %s v%s (module: %s) using strategy: %s\n' "$pkg" "$ver" "$mod" "$strategy"

    if [ "$strategy" = "link" ]; then
        # create or refresh symlink
        if ! dkms-link; then
            printf 'ERROR: dkms-link failed\n' >&2
            return 1
        fi
    else
        # fallback to rsync strategy
        if ! command -v rsync >/dev/null 2>&1; then
            printf 'ERROR: rsync not found. Please install rsync or set DKMS_SOURCE_STRATEGY=link\n' >&2
            return 1
        fi
        printf 'Syncing current directory to /usr/src/%s-%s/ (excluding .git, .agents, build/)...\n' "$pkg" "$ver"
        sudo rsync -a --delete --exclude='.git' --exclude='.agents' --exclude='build/' ./ "/usr/src/${pkg}-${ver}/" || {
            printf 'rsync failed\n' >&2
            return 1
        }
    fi

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
    printf 'Module %s v%s is now installed.\n' "$pkg" "$ver"
    printf 'Run sudo modprobe %s to load the module.\n' "$mod"
}

dkms-update() {
    _check_dkms_conf || return 1
    local pkg ver mod strategy
    pkg="$(_get_pkg)" || return 1
    ver="$(_get_ver)" || return 1
    mod="$(_get_mod_or_fallback)" || return 1
    strategy="${DKMS_SOURCE_STRATEGY:-link}"
    printf 'Rebuilding/installing %s v%s (module: %s) using strategy: %s\n' "$pkg" "$ver" "$mod" "$strategy"

    if [ "$strategy" = "link" ]; then
        # Ensure the symlink exists/points to cwd
        if ! dkms-link; then
            printf 'ERROR: dkms-link failed\n' >&2
            return 1
        fi
    else
        # Ensure rsync is available for syncing current tree into /usr/src
        if ! command -v rsync >/dev/null 2>&1; then
            printf 'ERROR: rsync not found. Please install rsync or set DKMS_SOURCE_STRATEGY=link\n' >&2
            return 1
        fi

        printf 'Syncing current directory to /usr/src/%s-%s/ (excluding .git, .agents, build/)...\n' "$pkg" "$ver"
        sudo rsync -a --delete --exclude='.git' --exclude='.agents' --exclude='build/' ./ "/usr/src/${pkg}-${ver}/" || {
            printf 'rsync failed\n' >&2
            return 1
        }
    fi

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

    # After successful depmod - check for other installed/built versions of this package
    # (exclude the current $ver) and offer to remove them interactively.
    _other_versions="$(dkms status | awk -v pkg="$pkg" -v ver="$ver" '
    {
      if (match($0, /^([^\/]+)\/([^,]+),/, m)) {
        name=m[1]; v=m[2];
        if (name==pkg && v!=ver) print v " -- " $0;
      }
    }')"

    if [ -n "$_other_versions" ]; then
        printf '\nFound other installed/built versions for %s:\n%s\n' "$pkg" "$_other_versions"
        # Prompt on the controlling tty when available.
        if [ -c /dev/tty ]; then
            printf 'Remove these older versions? [y/N]: ' >/dev/tty
            read -r _resp </dev/tty || _resp=""
        else
            _resp=""
        fi

        case "$_resp" in
        [yY] | [yY][eE][sS])
            printf 'Removing older versions for %s...\n' "$pkg"
            # Extract the version token (first field) and remove each.
            printf '%s\n' "$_other_versions" | awk '{print $1}' | while read -r oldver; do
                printf 'Removing %s version %s\n' "$pkg" "$oldver"
                sudo dkms remove -m "$pkg" -v "$oldver" --all || printf 'Warning: failed to remove %s %s\n' "$pkg" "$oldver"
            done
            ;;
        *)
            printf 'Left older versions in place.\n'
            ;;
        esac
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
    printf 'Run sudo modprobe %s to load the module.\n' "$mod"

    # Offer to reload the module now and optionally follow kernel logs filtered by the module name.
    # Read from /dev/tty so this works when the script is invoked from other programs.
    if [ -c /dev/tty ]; then
        printf '\nWould you like to reload the module %s now? [y/N]: ' "$mod" >/dev/tty
        read -r _resp </dev/tty || _resp=""
    else
        _resp=""
    fi

    case "$_resp" in
    [yY] | [yY][eE][sS])
        # Try to remove the module if currently loaded (ignore failures).
        if sudo modprobe -r "$mod" >/dev/null 2>&1; then
            printf 'Unloaded module %s\n' "$mod"
        else
            printf 'Module %s was not loaded or could not be unloaded (continuing)\n' "$mod"
        fi

        # Try to load the module (report failures).
        if sudo modprobe "$mod"; then
            printf 'Loaded module %s\n' "$mod"
        else
            printf 'Failed to load module %s\n' "$mod" >&2
        fi

        # Optionally follow kernel logs filtered by module name.
        if [ -c /dev/tty ]; then
            printf 'Follow kernel logs for \"%s\" now? [y/N]: ' "$mod" >/dev/tty
            read -r _follow </dev/tty || _follow=""
        else
            _follow=""
        fi

        case "$_follow" in
        [yY] | [yY][eE][sS])
            if command -v journalctl >/dev/null 2>&1; then
                printf 'Following kernel journal for \"%s\" (Ctrl-C to stop)...\n' "$mod"
                # Use --grep so the match is literal and not hardcoded.
                sudo journalctl -k -f --grep "$mod"
            else
                printf 'journalctl not available; falling back to tailing dmesg (may not filter reliably).\n'
                # Use dmesg --follow if available; otherwise use tail on /var/log/kern.log where applicable.
                if command -v dmesg >/dev/null 2>&1 && dmesg --help 2>&1 | grep -q -- '--follow'; then
                    dmesg --follow | grep --line-buffered "$mod" || true
                else
                    # Best-effort fallback: continuous dmesg polling (non-ideal).
                    while true; do
                        dmesg | tail -n 200 | grep --line-buffered "$mod" || true
                        sleep 1
                    done
                fi
            fi
            ;;
        *)
            ;;
        esac
        ;;
    *)
        ;;
    esac
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
