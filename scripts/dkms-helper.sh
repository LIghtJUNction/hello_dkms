#!/usr/bin/env bash
# dkms helpers for this repo - safe function names to avoid clashing with system commands.
# Usage: source ./scripts/dkms-helpers.sh
set -eu

# Parse values from dkms.conf in current directory
_get_pkg()  { sed -n 's/^PACKAGE_NAME="\([^"]*\)".*/\1/p' dkms.conf; }
_get_ver()  { sed -n 's/^PACKAGE_VERSION="\([^"]*\)".*/\1/p' dkms.conf; }
_get_mod()  { sed -n 's/^BUILT_MODULE_NAME\[[0-9]*\]="\([^"]*\)".*/\1/p' dkms.conf || true; }
_get_mod_or_fallback() {
  local m
  m="$(_get_mod)"
  if [ -z "$m" ]; then
    local p
    p="$(_get_pkg)"
    printf '%s' "${p%-dkms}"
  else
    printf '%s' "$m"
  fi
}

dkms-install() {
  local pkg ver mod
  pkg="$(_get_pkg)"
  ver="$(_get_ver)"
  mod="$(_get_mod_or_fallback)"
  echo "Installing $pkg v$ver (module: $mod)..."
  sudo rsync -a --delete ./ "/usr/src/${pkg}-${ver}/" \
    && sudo dkms add -m "$pkg" -v "$ver" \
    && sudo dkms build -m "$pkg" -v "$ver" \
    && sudo dkms install -m "$pkg" -v "$ver" \
    && sudo depmod -a
}

dkms-update() {
  local pkg ver
  pkg="$(_get_pkg)"
  ver="$(_get_ver)"
  echo "Rebuilding/installing $pkg v$ver..."
  sudo dkms build -m "$pkg" -v "$ver" \
    && sudo dkms install -m "$pkg" -v "$ver" \
    && sudo depmod -a
}

dkms-uninstall() {
  local pkg ver
  pkg="$(_get_pkg)"
  ver="$(_get_ver)"
  echo "Removing $pkg v$ver from DKMS..."
  sudo dkms remove -m "$pkg" -v "$ver" --all
}

# Convenience short names (optional)
dki() { dkms-install "$@"; }
dku() { dkms-update "$@"; }
dkrm() { dkms-uninstall "$@"; }
