#!/usr/bin/env bash
# Copyright (c) 2026 lightjunction
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# Safe DKMS helper functions — avoid set -e at top-level so sourcing cannot abort the shell.
# Usage: source ./scripts/dkms-helpers-fixed.sh
#
# DKMS_FORCE behavior:
# By default this script will pass --force to `dkms build` and `dkms install` so
# installs override existing builds. Set DKMS_FORCE=0 (or false/no) to disable.
case "${DKMS_FORCE:-1}" in
0 | false | FALSE | False | no | NO | No) DKMS_FORCE_FLAG="" ;;
*) DKMS_FORCE_FLAG="--force" ;;
esac

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

# Detect which compiler the kernel build expects and return a suitable KBUILD_CC value.
# Heuristics:
#  - If the kernel build .config declares CONFIG_CC_IS_CLANG=y, prefer clang.
#  - If the kernel Makefile mentions 'clang' prefer clang.
#  - Fall back to empty (no KBUILD_CC) if detection fails.
_detect_kbuild_cc() {
    local kbuild_dir="/lib/modules/$(uname -r)/build"
    local cc=""

    if [ -f "$kbuild_dir/.config" ] && grep -q '^CONFIG_CC_IS_CLANG=y' "$kbuild_dir/.config" 2>/dev/null; then
        cc="clang"
    elif [ -f "$kbuild_dir/Makefile" ] && grep -q 'clang' "$kbuild_dir/Makefile" 2>/dev/null; then
        cc="clang"
    elif [ -f /proc/version ] && grep -q 'clang' /proc/version 2>/dev/null; then
        cc="clang"
    fi

    printf '%s' "$cc"
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

    # Detect kernel build compiler and, if present, pass it to dkms via sudo env so the
    # module is built with the correct compiler (avoids clang/gcc mismatch flags).
    _kcc="$(_detect_kbuild_cc)" || true
    if [ -n "$_kcc" ]; then
        if ! sudo env KBUILD_CC="$_kcc" dkms build -m "$pkg" -v "$ver" $DKMS_FORCE_FLAG; then
            printf 'dkms build failed\n' >&2
            return 1
        fi
        if ! sudo env KBUILD_CC="$_kcc" dkms install -m "$pkg" -v "$ver" $DKMS_FORCE_FLAG; then
            printf 'dkms install failed\n' >&2
            return 1
        fi
    else
        sudo dkms build -m "$pkg" -v "$ver" $DKMS_FORCE_FLAG || {
            printf 'dkms build failed\n' >&2
            return 1
        }
        sudo dkms install -m "$pkg" -v "$ver" $DKMS_FORCE_FLAG || {
            printf 'dkms install failed\n' >&2
            return 1
        }
    fi

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
    # Detect kernel compiler and pass via sudo env when detected.
    _kcc="$(_detect_kbuild_cc)" || true
    if [ -n "$_kcc" ]; then
        if ! sudo env KBUILD_CC="$_kcc" dkms build -m "$pkg" -v "$ver" $DKMS_FORCE_FLAG; then
            printf 'dkms build failed\n' >&2
            return 1
        fi
    else
        if ! sudo dkms build -m "$pkg" -v "$ver" $DKMS_FORCE_FLAG; then
            printf 'dkms build failed\n' >&2
            return 1
        fi
    fi

    printf 'Installing module via dkms...\n'
    if [ -n "$_kcc" ]; then
        if ! sudo env KBUILD_CC="$_kcc" dkms install -m "$pkg" -v "$ver" $DKMS_FORCE_FLAG; then
            printf 'dkms install failed\n' >&2
            return 1
        fi
    else
        if ! sudo dkms install -m "$pkg" -v "$ver" $DKMS_FORCE_FLAG; then
            printf 'dkms install failed\n' >&2
            return 1
        fi
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
    local pkg ver mod src_link varlib modfiles reply target
    pkg="$(_get_pkg)" || return 1
    ver="$(_get_ver)" || return 1
    mod="$(_get_mod_or_fallback)" || true

    printf 'Removing %s v%s from DKMS\n' "$pkg" "$ver"

    # Try the normal DKMS remove first; continue even if it reports failure so we can offer cleanup.
    if ! sudo dkms remove -m "$pkg" -v "$ver" --all; then
        printf 'dkms remove reported failure for %s %s — offering cleanup options\n' "$pkg" "$ver" >&2
    else
        printf 'dkms remove completed (or nothing to remove) for %s %s\n' "$pkg" "$ver"
    fi

    # 1) /usr/src cleanup: check for symlink or directory for this package/version.
    src_link="/usr/src/${pkg}-${ver}"
    if [ -L "$src_link" ] || [ -d "$src_link" ]; then
        target="$(readlink -f "$src_link" 2>/dev/null || true)"
        if [ -L "$src_link" ] && [ ! -e "$target" ]; then
            printf 'Detected broken symlink: %s -> %s\n' "$src_link" "$target"
            if [ -c /dev/tty ]; then
                printf 'Remove broken /usr/src link %s? [y/N]: ' "$src_link" >/dev/tty
                read -r reply </dev/tty || reply=""
            else
                reply=""
            fi
            case "$reply" in
            [yY] | [yY][eE][sS])
                sudo rm -rf "$src_link" && printf 'Removed %s\n' "$src_link"
                ;;
            *)
                printf 'Left %s in place\n' "$src_link"
                ;;
            esac
        elif [ -d "$src_link" ]; then
            # Directory exists; offer to remove if empty or with confirmation if non-empty.
            if [ -z "$(ls -A "$src_link" 2>/dev/null)" ]; then
                if [ -c /dev/tty ]; then
                    printf 'Remove empty /usr/src dir %s? [y/N]: ' "$src_link" >/dev/tty
                    read -r reply </dev/tty || reply=""
                else
                    reply=""
                fi
                case "$reply" in
                [yY] | [yY][eE][sS])
                    sudo rm -rf "$src_link" && printf 'Removed %s\n' "$src_link"
                    ;;
                *)
                    printf 'Left %s in place\n' "$src_link"
                    ;;
                esac
            else
                if [ -c /dev/tty ]; then
                    printf '/usr/src/%s exists and is not empty. Remove it (recursively)? [y/N]: ' "$pkg-$ver" >/dev/tty
                    read -r reply </dev/tty || reply=""
                else
                    reply=""
                fi
                case "$reply" in
                [yY] | [yY][eE][sS])
                    sudo rm -rf "$src_link" && printf 'Removed %s\n' "$src_link"
                    ;;
                *)
                    printf 'Left %s in place\n' "$src_link"
                    ;;
                esac
            fi
        fi
    fi

    # 2) /var/lib/dkms cleanup: offer to remove DKMS state if present.
    varlib="/var/lib/dkms/$pkg/$ver"
    if [ -d "$varlib" ]; then
        printf 'Found DKMS state at %s\n' "$varlib"
        if [ -c /dev/tty ]; then
            printf 'Remove /var/lib/dkms entry %s? [y/N]: ' "$varlib" >/dev/tty
            read -r reply </dev/tty || reply=""
        else
            reply=""
        fi
        case "$reply" in
        [yY] | [yY][eE][sS])
            # Remove only the specific version directory
            sudo rm -rf "$varlib" && printf 'Removed %s\n' "$varlib"
            ;;
        *)
            printf 'Left %s in place\n' "$varlib"
            ;;
        esac
    fi

    # 3) Installed module files cleanup under /lib/modules/*/updates/dkms/
    if [ -n "$mod" ]; then
        # Find files that look like the module for any kernel's updates/dkms directory.
        modfiles="$(find /lib/modules -path '*/updates/dkms/*' -type f -name "${mod}.*" 2>/dev/null || true)"
        if [ -n "$modfiles" ]; then
            printf 'Found installed module files for %s:\n%s\n' "$mod" "$modfiles"
            if [ -c /dev/tty ]; then
                printf 'Remove these module files? [y/N]: ' >/dev/tty
                read -r reply </dev/tty || reply=""
            else
                reply=""
            fi
            case "$reply" in
            [yY] | [yY][eE][sS])
                # Remove listed files and refresh module dependencies.
                printf '%s\n' "$modfiles" | xargs -r sudo rm -f
                sudo depmod -a || printf 'depmod failed (you may need to run it manually)\n' >&2
                printf 'Removed module files and ran depmod\n'
                ;;
            *)
                printf 'Left module files in place\n'
                ;;
            esac
        fi
    fi

    printf 'Uninstall complete.\n'
}

# Short aliases (optional)
dki() { dkms-install "$@"; }
dku() { dkms-update "$@"; }
dkrm() { dkms-uninstall "$@"; }
