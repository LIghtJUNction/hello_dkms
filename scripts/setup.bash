#!/usr/bin/env bash
# Copyright (c) 2026 lightjunction
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────────────
if [ -t 2 ] || [ -r /dev/tty ]; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[0;33m'
    BLUE=$'\033[0;34m'
    BOLD=$'\033[1m'
    GREY=$'\033[2m'
    RESET=$'\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' BOLD='' GREY='' RESET=''
fi

die() {
    printf '%b\n' "${BOLD}${RED}ERROR:${RESET} $1" >&2
    exit 1
}

prompt() {
    local prompt_text="$1"
    local default="$2"
    local out=""
    local tty="/dev/tty"

    if [ -n "$default" ]; then
        printf '%b' "${BLUE}${prompt_text}${RESET} ${GREY}[${default}]${RESET}: " >"$tty"
    else
        printf '%b' "${BLUE}${prompt_text}${RESET}: " >"$tty"
    fi

    if [ -r "$tty" ]; then
        read -r out <"$tty" || out=""
    else
        read -r out || out=""
    fi

    [ -z "$out" ] && out="$default"
    printf '%s' "$out"
}

confirm() {
    local msg="$1"
    local resp=""
    local tty="/dev/tty"

    printf '%b' "${BOLD}${msg}${RESET} [${GREEN}y${RESET}/${RED}N${RESET}]: " >"$tty"

    if [ -r "$tty" ]; then
        read -r resp <"$tty" || resp=""
    else
        read -r resp || resp=""
    fi

    case "$resp" in
    [yY] | [yY][eE][sS]) return 0 ;;
    *) return 1 ;;
    esac
}

ORIG_DIR="$(pwd)"
WORK_DIR="$ORIG_DIR"
NEED_SYNC_BACK=0

current_pkg=""
current_ver=""
current_author=""
current_email=""

if [ -f "dkms.conf" ]; then
    current_pkg="$(sed -n 's/^PACKAGE_NAME="\([^"]*\)".*/\1/p' dkms.conf 2>/dev/null || true)"
    current_ver="$(sed -n 's/^PACKAGE_VERSION="\([^"]*\)".*/\1/p' dkms.conf 2>/dev/null || true)"
fi

if [ -f "hello.c" ]; then
    current_author="$(sed -n -E 's/^MODULE_AUTHOR\("(.*)"\);.*/\1/p' hello.c 2>/dev/null || true)"
fi

if [[ "$current_author" =~ \<([^>]+)\> ]]; then
    current_email="${BASH_REMATCH[1]}"
    current_author="$(echo "$current_author" | sed 's/ *<.*>//')"
fi

git_name="$(git config --global user.name 2>/dev/null || true)"
git_email="$(git config --global user.email 2>/dev/null || true)"
[ -z "$current_author" ] && [ -n "$git_name" ] && current_author="$git_name"
[ -z "$current_email" ] && [ -n "$git_email" ] && current_email="$git_email"

printf '\n%bCurrent values detected:%b\n' "$BOLD" "$RESET"
printf '  %bPACKAGE_NAME%b: %s\n' "$BOLD" "$RESET" "${current_pkg:-<none>}"
printf '  %bPACKAGE_VERSION%b: %s\n' "$BOLD" "$RESET" "${current_ver:-<none>}"
printf '  %bMODULE_AUTHOR%b: %s\n' "$BOLD" "$RESET" "${current_author:-<none>}"
[ -n "$current_email" ] && printf '  %bMODULE_AUTHOR email%b: %s\n' "$BOLD" "$RESET" "$current_email"
printf '\n'

if [ ! -f "dkms.conf" ] || [ ! -f "hello.c" ]; then
    printf '%bWarning:%b project files missing in current directory; cloning template...\n' "$YELLOW" "$RESET"
    tmpdir="$(mktemp -d -t hello-dkms-XXXX)"
    git clone --depth=1 https://github.com/LIghtJUNction/hello_dkms.git "$tmpdir" || die "git clone failed"
    cd "$tmpdir" || die "failed to cd to tmpdir"
    WORK_DIR="$tmpdir"
    NEED_SYNC_BACK=1
    printf 'Working in temporary directory: %s\n\n' "$WORK_DIR"

    current_pkg="$(sed -n 's/^PACKAGE_NAME="\([^"]*\)".*/\1/p' dkms.conf 2>/dev/null || true)"
    current_ver="$(sed -n 's/^PACKAGE_VERSION="\([^"]*\)".*/\1/p' dkms.conf 2>/dev/null || true)"
    [[ "$current_pkg" =~ ^(hello-dkms|your-module|)$ ]] && current_pkg=""
    [[ "$current_ver" =~ ^(1\.0|0\.1|)$ ]] && current_ver=""
fi

printf '%bEnter new values%b (leave blank to keep current):\n' "$BOLD" "$RESET"

pkg="$(prompt 'LKM package name (e.g. hello-dkms)' "$current_pkg")"
ver="$(prompt 'LKM package version (e.g. 1.1)' "$current_ver")"
author_name="$(prompt 'Author full name' "$current_author")"
author_email="$(prompt 'Author email' "$current_email")"

if [ -n "${pkg:-}" ]; then
    built_module_default="${pkg%-dkms}"
else
    built_module_default="hello"
fi
built_module="$(prompt 'Built module name (.ko name)' "$built_module_default")"

printf '\n%bSummary of changes to be applied:%b\n' "$BOLD" "$RESET"
printf '  PACKAGE_NAME: %b%s%b -> %b%s%b\n' "$GREY" "$current_pkg" "$RESET" "$GREEN" "$pkg" "$RESET"
printf '  PACKAGE_VERSION: %b%s%b -> %b%s%b\n' "$GREY" "$current_ver" "$RESET" "$GREEN" "$ver" "$RESET"
printf '  MODULE_AUTHOR: %b%s <%s>%b\n' "$GREEN" "$author_name" "$author_email" "$RESET"
printf '  BUILT_MODULE_NAME[0]: %b%s%b\n' "$GREEN" "$built_module" "$RESET"
printf '\n'

if ! confirm "Proceed with the above changes?"; then
    printf '%bAborted by user.%b\n' "$YELLOW" "$RESET"
    exit 0
fi

PERL_PKG="$pkg" PERL_VER="$ver" PERL_MOD="$built_module" \
    perl -0777 -i -pe '
  s/^(PACKAGE_NAME=")[^"]*(")/$1 . $ENV{PERL_PKG} . $2/gem;
  s/^(PACKAGE_VERSION=")[^"]*(")/$1 . $ENV{PERL_VER} . $2/gem;
  if (/^BUILT_MODULE_NAME\[\d+\]=/m) {
    s/^(BUILT_MODULE_NAME\[\d+\]=")[^"]*(")/$1 . $ENV{PERL_MOD} . $2/gem;
  } else {
    s/\z/\nBUILT_MODULE_NAME[0]="$ENV{PERL_MOD}"\n/;
  }
' dkms.conf || die "failed to update dkms.conf"

if [ -f "hello.c" ]; then
    author_entry="$author_name"
    [ -n "$author_email" ] && author_entry="$author_entry <$author_email>"

    PERL_AUTHOR="$author_entry" \
        perl -0777 -i -pe '
    s/MODULE_AUTHOR\([^;]*\);/MODULE_AUTHOR("$ENV{PERL_AUTHOR}");/g;
  ' hello.c || die "failed to update hello.c"
else
    die "hello.c not found"
fi

if confirm "Update MODULE_DESCRIPTION and MODULE_ALIAS in hello.c?"; then
    default_desc="${pkg} DKMS module"
    default_alias="${built_module}"

    new_desc="$(prompt 'Module description' "$default_desc")"
    new_alias="$(prompt 'Module alias' "$default_alias")"

    PERL_DESC="$new_desc" PERL_ALIAS="$new_alias" \
        perl -0777 -i -pe '
    if (s/MODULE_DESCRIPTION\([^;]*\);/MODULE_DESCRIPTION("$ENV{PERL_DESC}");/g) {
    } else {
      s/(MODULE_AUTHOR\("[^"]*"\);)/$1\nMODULE_DESCRIPTION("$ENV{PERL_DESC}");/m;
    }

    if (s/MODULE_ALIAS\([^;]*\);/MODULE_ALIAS("$ENV{PERL_ALIAS}");/g) {
    } else {
      s/(MODULE_LICENSE\("[^"]*"\);)/$1\nMODULE_ALIAS("$ENV{PERL_ALIAS}");/m;
    }
  ' hello.c || die "failed to update description/alias"
fi

if [ "$NEED_SYNC_BACK" -eq 1 ]; then
    printf '\n%bSyncing generated project back to original directory...%b\n' "$BLUE" "$RESET"
    rsync -a --delete "$WORK_DIR"/ "$ORIG_DIR"/ || die "failed to sync project back to original directory"
    printf '%bSync complete.%b\n' "$GREEN" "$RESET"
fi

printf '\n%bAll operations complete.%b\n' "$GREEN" "$RESET"
printf 'Next steps:\n'
printf '  - Files are now in: %s\n' "$ORIG_DIR"
printf '  - Run make or your DKMS helper scripts.\n'
printf '\n'
