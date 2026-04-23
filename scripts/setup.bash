#!/usr/bin/env bash
# Copyright (c) 2026 lightjunction
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# Interactive setup script for hello-dkms project
#
# Purpose:
# - Prompt for LKM package name, version, author name and email.
# - Update dkms.conf (PACKAGE_NAME, PACKAGE_VERSION).
# - Update hello.c (MODULE_AUTHOR, MODULE_DESCRIPTION/MODULE_ALIAS if requested).
# - Rename README file if requested.
# - Optionally create a symlinked or versioned folder name under /usr/src is NOT done here;
#   this script focuses on repository-level renames/edits and optional removal of .git.
#
# Safety: the script creates backups of files it edits and asks for explicit confirmation
# before performing destructive actions (deleting .git, renaming project directory).
#
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"
# Backups are disabled in this mode.
BACKUP_DIR=""

# Detect terminal color support. Provide sensible ANSI defaults so colors appear even when tput
# isn't available (useful for curl | bash). If tput and /dev/tty are available we will override
# these defaults with terminal-specific sequences.
RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
BOLD=$'\033[1m'
GREY=$'\033[2m'
RESET=$'\033[0m'

# Try to refine colors using tput via /dev/tty when possible.
if command -v tput >/dev/null 2>&1 && [ -r /dev/tty ]; then
    ncolors="$(tput colors </dev/tty 2>/dev/null || echo 0)"
    if [ -n "$ncolors" ] && [ "$ncolors" -ge 8 ]; then
        # Prefer tput output but fall back to the ANSI defaults above when tput calls fail.
        RED="$(tput setaf 1 </dev/tty 2>/dev/null || printf '%b' "$RED")"
        GREEN="$(tput setaf 2 </dev/tty 2>/dev/null || printf '%b' "$GREEN")"
        YELLOW="$(tput setaf 3 </dev/tty 2>/dev/null || printf '%b' "$YELLOW")"
        BLUE="$(tput setaf 4 </dev/tty 2>/dev/null || printf '%b' "$BLUE")"
        BOLD="$(tput bold </dev/tty 2>/dev/null || printf '%b' "$BOLD")"
        GREY="$(tput setaf 8 </dev/tty 2>/dev/null || printf '%b' "$GREY")"
        RESET="$(tput sgr0 </dev/tty 2>/dev/null || printf '%b' "$RESET")"
    fi
fi

die() {
    # Highlight errors in bold red for visibility.
    printf '%b\n' "${BOLD}${RED}ERROR:${RESET} $1" >&2
    exit 1
}

prompt() {
    # prompt: prompt text, default: default value (displayed in grey)
    local prompt="$1"
    local default="$2"
    local out
    # Prefer reading from the controlling TTY so this script remains interactive when stdin is piped.
    # Fall back to standard stdin if /dev/tty is not available.
    local tty="/dev/tty"
    local read_src=""
    if [ -r "$tty" ]; then
        read_src="$tty"
    fi

    if [ -n "$default" ]; then
        # Show default in a muted grey so it is visible but not noisy.
        if [ -n "$read_src" ]; then
            # Print prompt with default to the controlling TTY, then read from it.
            # Use "$tty" (which is /dev/tty) explicitly to ensure the prompt appears on the user's terminal.
            printf '%b ' "${prompt} ${GREY}[${default}]${RESET}" >"$tty"
            read -r out <"$tty"
        else
            # No controlling tty available: print to stdout and read from stdin.
            printf '%b ' "${prompt} ${GREY}[${default}]${RESET}"
            read -r out
        fi
        out="${out:-$default}"
    else
        if [ -n "$read_src" ]; then
            printf '%b ' "${prompt}" >"$tty"
            read -r out <"$tty"
        else
            printf '%b ' "${prompt}"
            read -r out
        fi
    fi
    printf '%s' "$out"
}

confirm() {
    # prompt, default No. Green for 'y', red for 'N'
    local msg="$1"
    local default_no="${2:-no}"
    local resp
    local tty="/dev/tty"
    # Construct colored inline indicator: green y, red N
    local prompt_str="${msg} [${GREEN}y${RESET}/${RED}N${RESET}]: "
    if [ -r "$tty" ]; then
        # Print to tty and read from it to avoid interfering with piped stdin
        printf '%b' "$prompt_str" >"$tty"
        read -r resp <"$tty"
    else
        printf '%b' "$prompt_str"
        read -r resp
    fi
    case "$resp" in
    [yY] | [yY][eE][sS])
        printf '%b\n' "${GREEN}yes${RESET}" >&2
        return 0
        ;;
    [nN] | [nN][oO] | '')
        printf '%b\n' "${RED}no${RESET}" >&2
        return 1
        ;;
    *)
        printf '%b\n' "${YELLOW}invalid response${RESET}" >&2
        return 1
        ;;
    esac
}

backup_file() {
    # Backups disabled: no-op
    return 0
}

replace_in_file() {
    # replace a regex-based line using awk - writes to temp and moves it back
    # args: file, sed_expr (basic sed replacement expression, e.g. s/^FOO=.*/FOO="bar"/)
    local file="$1"
    local sed_expr="$2"
    if [ ! -f "$file" ]; then
        echo "warning: $file not found; skipping"
        return 0
    fi
    backup_file "$file"
    local tmp
    tmp="$(mktemp "${file}.tmp.XXXX")"
    # Use awk to perform a sed-like substitution safely
    awk -v expr="$sed_expr" '
    BEGIN {
        # parse expr like s/regex/repl/flags
        sub(/^s\//, "", expr)
        split(expr, parts, "/")
        regex = parts[1]
        repl = parts[2]
        flags = parts[3]
    }
    {
        if ($0 ~ regex) {
            # Use gensub to respect backreferences (GNU awk)
            $0 = gensub(regex, repl, "g", $0)
        }
        print $0
    }' "$file" >"$tmp" || {
        rm -f "$tmp"
        die "failed to run replacement on $file"
    }
    mv "$tmp" "$file"
}

# Convenience sed replacement (POSIX-friendly fallback)
sed_replace_line() {
    # args: file, pattern (regex), replacement (literal)
    local file="$1" pattern="$2" replacement="$3"
    if [ ! -f "$file" ]; then
        echo "warning: $file not found; skipping"
        return 0
    fi
    backup_file "$file"
    # Use perl for robust in-place replace with backup
    perl -0777 -pe "s/$pattern/$replacement/gs" "$file" >"${file}.new" || die "perl replace failed"
    mv "${file}.new" "$file"
}

# Read current values
# Initialize to empty; populate only if files exist to avoid noisy sed errors.
current_pkg=""
current_ver=""
current_author=""
current_email=""
# Try to read current values from files if present, suppressing sed stderr so missing files do not print errors.
if [ -f "dkms.conf" ]; then
    current_pkg="$(sed -n 's/^PACKAGE_NAME="\([^"]*\)".*/\1/p' dkms.conf 2>/dev/null || true)"
    current_ver="$(sed -n 's/^PACKAGE_VERSION="\([^"]*\)".*/\1/p' dkms.conf 2>/dev/null || true)"
fi
if [ -f "hello.c" ]; then
    current_author="$(sed -n -E 's/^MODULE_AUTHOR\(\"(.*)\"\);.*/\1/p' hello.c 2>/dev/null || true)"
fi
# Try to split author into name and email if possible
if [[ "$current_author" =~ \<([^>]+)\> ]]; then
    current_email="${BASH_REMATCH[1]}"
    # remove email portion from author for display
    current_author="$(echo "$current_author" | sed 's/ *<.*>//')"
fi

# Print detected current values. If absent, try git config for sensible defaults.
printf 'Current values detected:\n'
# prefer local file values; fall back to global git config for author info if available
git_name="$(git config --global user.name 2>/dev/null || true)"
git_email="$(git config --global user.email 2>/dev/null || true)"
if [ -z "$current_author" ] && [ -n "$git_name" ]; then
    current_author="$git_name"
fi
if [ -z "$current_email" ] && [ -n "$git_email" ]; then
    current_email="$git_email"
fi
printf '  %b: %s\n' "${BOLD}PACKAGE_NAME${RESET}" "${current_pkg:-<none>}"
printf '  %b: %s\n' "${BOLD}PACKAGE_VERSION${RESET}" "${current_ver:-<none>}"
printf '  %b: %s\n' "${BOLD}MODULE_AUTHOR${RESET}" "${current_author:-<none>}"
[ -n "$current_email" ] && printf '  %b: %s\n' "${BOLD}MODULE_AUTHOR email${RESET}" "$current_email"

echo

# visual separation: blank line to make output easier to read
echo
# If key project files are missing, clone the repository into a temporary directory and continue there.
# This is unconditional (no interactive prompt) so the script is safe for `curl | bash` from an empty dir.
if [ ! -f "dkms.conf" ] || [ ! -f "hello.c" ]; then
    echo "Warning: one or more project files (dkms.conf, hello.c) are missing in the current directory."
    tmpdir="$(mktemp -d -t hello-dkms-XXXX)"
    echo "Cloning repository into $tmpdir..."
    if git clone --depth=1 https://github.com/LIghtJUNction/hello_dkms.git "$tmpdir"; then
        echo "Switching to $tmpdir"
        cd "$tmpdir" || die "failed to cd to $tmpdir"
        # Backups disabled; no backup directory will be created.
        BACKUP_DIR=""
        echo "Now operating in: $(pwd)"
        echo "Backups are disabled."

        # visual separation: blank line after clone messages
        echo

    else
        die "git clone failed; aborting"
    fi
fi

echo
printf 'Enter new values (leave blank to keep current):\n'
pkg="$(prompt 'LKM package name (e.g. hello-dkms)' "$current_pkg")"
ver="$(prompt 'LKM package version (e.g. 1.1)' "$current_ver")"
author_name="$(prompt 'Author full name' "$current_author")"
author_email="$(prompt 'Author email' "$current_email")"

# Derived values
# built module name: prefer user input or fallback to package name, otherwise use current directory basename.
if [ -n "${pkg:-}" ]; then
    built_module_default="${pkg%-dkms}"
else
    built_module_default="$(basename "$(pwd)")"
    built_module_default="${built_module_default%-dkms}"
fi
built_module="$(prompt "Built module name (module .ko name, default: ${built_module_default})" "$built_module_default")"

echo
printf 'Summary of changes to be applied:\n'
printf '  PACKAGE_NAME: %s -> %s\n' "$current_pkg" "$pkg"
printf '  PACKAGE_VERSION: %s -> %s\n' "$current_ver" "$ver"
printf '  MODULE_AUTHOR: %s <%s>\n' "$author_name" "$author_email"
printf '  BUILT_MODULE_NAME[0]: %s\n' "$built_module"
echo

if ! confirm "Proceed with the above changes?"; then
    echo "Aborted by user."
    exit 0
fi

# --- Update dkms.conf ---
echo "Updating dkms.conf..."
if [ -f "dkms.conf" ]; then
    backup_file "dkms.conf"
    # replace PACKAGE_NAME and PACKAGE_VERSION and BUILT_MODULE_NAME[0]
    # Use perl for robust replacement
    perl -0777 -pe "
    s/^(PACKAGE_NAME=\")[^\"]*(\".*\n)/\${1}${pkg}\${2}/m;
    s/^(PACKAGE_VERSION=\")[^\"]*(\".*\n)/\${1}${ver}\${2}/m;
    if (/BUILT_MODULE_NAME/) {
        s/^(BUILT_MODULE_NAME\[[0-9]*\]=\")[^\"]*(\".*\n)/\${1}${built_module}\${2}/m;
    } else {
        # append BUILT_MODULE_NAME[0]
        s/(\$)/\nBUILT_MODULE_NAME[0]=\"${built_module}\"\n/;
    }
    " dkms.conf >dkms.conf.new || die "failed to write new dkms.conf"
    mv dkms.conf.new dkms.conf
else
    die "dkms.conf not found in current directory"
fi
echo "dkms.conf updated."

# --- Update hello.c author and alias/description if present ---
echo "Updating hello.c author and alias..."
if [ -f "hello.c" ]; then
    backup_file "hello.c"
    # Format MODULE_AUTHOR("Name <email>");
    author_entry="${author_name}"
    if [ -n "$author_email" ]; then
        author_entry="${author_entry} <${author_email}>"
    fi
    # Replace MODULE_AUTHOR(...) line
    # Use perl to replace a line that starts with MODULE_AUTHOR(
    perl -0777 -pe "
    if (s/MODULE_AUTHOR\([^;]*\);/MODULE_AUTHOR(\"${author_entry}\");/m) { }
    " hello.c >hello.c.new || die "failed to update hello.c"
    mv hello.c.new hello.c
else
    echo "warning: hello.c not found; skipping"
fi

# Optionally update MODULE_DESCRIPTION and MODULE_ALIAS
if confirm "Would you like to update MODULE_DESCRIPTION and MODULE_ALIAS in hello.c now?"; then
    current_desc="$(sed -n -E 's/^MODULE_DESCRIPTION\(\"(.*)\"\);.*/\1/p' hello.c || true)"
    current_alias="$(sed -n -E 's/^MODULE_ALIAS\(\"(.*)\"\);.*/\1/p' hello.c || true)"
    # Construct smarter defaults based on prior inputs: prefer existing values, otherwise use package/module info.
    default_desc="${current_desc:-${pkg} DKMS module}"
    default_alias="${current_alias:-${built_module}}"
    new_desc="$(prompt 'Module description' "$default_desc")"
    new_alias="$(prompt 'Module alias' "$default_alias")"
    backup_file "hello.c" # additional backup
    perl -0777 -pe "
    if (s/MODULE_DESCRIPTION\([^;]*\);/MODULE_DESCRIPTION(\"${new_desc}\");/m) { } else { s/(MODULE_AUTHOR\(\".*\"\);)/\1\nMODULE_DESCRIPTION(\"${new_desc}\");/m }
    if (s/MODULE_ALIAS\([^;]*\);/MODULE_ALIAS(\"${new_alias}\");/m) { } else { s/(MODULE_LICENSE\(\".*\"\);)/MODULE_LICENSE(\"GPL\");\nMODULE_ALIAS(\"${new_alias}\");/m }
    " hello.c >hello.c.new || die "failed to update description/alias"
    mv hello.c.new hello.c
fi

# Update README file rename (ask)
readme_file=""
if [ -f "README.md" ]; then
    readme_file="README.md"
elif [ -f "REAMDE.md" ]; then
    # common typo in project
    readme_file="REAMDE.md"
fi

if [ -n "$readme_file" ]; then
    echo "Found README file: $readme_file"
    if confirm "Would you like to rename README to README-${pkg}.md?"; then
        backup_file "$readme_file"
        new_readme="README-${pkg}.md"
        mv "$readme_file" "$new_readme"
        echo "Renamed $readme_file -> $new_readme"
        # Create a small NOTICE README.md pointing to new file
        cat >README.md <<EOF
This repository was initialized by setup script.
Primary documentation moved to ${new_readme}
EOF
        echo "Created lightweight README.md pointing to ${new_readme}"
    fi
else
    echo "No README found (README.md or REAMDE.md). Skipping README rename."
fi

# Update other occurrences: replace old pkg/version occurrences in files (README, dkms.conf already handled)
echo "Updating textual occurrences of old package/version in README(s) and docs..."
# Only attempt if readme_file existed before; otherwise skip
if [ -n "$readme_file" ]; then
    # backups disabled; skipping attempt to update backup README content
    :
    # Also attempt to update current README.md (if it contains the old values)
    if [ -f "README.md" ]; then
        # skip (we already created minimal README)
        :
    fi
fi

# Optionally remove .git
if [ -d ".git" ]; then
    echo ".git directory detected."
    if confirm "Do you want to REMOVE the .git directory (this is irreversible)?"; then
        # backup .git as a tarball in backups dir before removing
        # Backups disabled; remove .git without creating an archive
        rm -rf .git || die "failed to remove .git"
        echo ".git removed."
    else
        echo "Skipping .git removal."
    fi
fi

# Optionally rename the project folder (move current directory)
if confirm "Would you like to rename the project directory to ${pkg}-${ver}? (This will move the directory)"; then
    curdir="$(pwd)"
    parent="$(dirname "$curdir")"
    base="$(basename "$curdir")"
    target_name="${pkg}-${ver}"
    echo "About to move $curdir -> $parent/$target_name"
    if confirm "Confirm moving directory now?"; then
        # Move: cd to parent then mv
        cd "$parent"
        if mv "$base" "$target_name"; then
            echo "Directory moved to $parent/$target_name"
            echo "NOTE: your shell may still have a working directory pointing to the old path."
            echo "If you ran this script from inside the directory, you may need to 'cd' into the new path manually."
        else
            echo "Failed to move directory. Restoring working dir."
            cd "$curdir"
        fi
    else
        echo "Move cancelled."
    fi
fi

echo
echo "All operations complete."
echo "Next steps:"
echo "  - Inspect changes, run 'make' or use helper scripts (source ./scripts/dkms-helper.bash) to build and install."
echo "  - If you removed .git and want to reinitialize a repo, run 'git init' and create an initial commit."
echo
