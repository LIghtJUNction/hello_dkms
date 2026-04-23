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
BACKUP_DIR="./.setup-backups-${TIMESTAMP}"
mkdir -p "$BACKUP_DIR"

die() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

prompt() {
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
        if [ -n "$read_src" ]; then
            read -r -p "$prompt [$default]: " out <"$read_src"
        else
            read -r -p "$prompt [$default]: " out
        fi
        out="${out:-$default}"
    else
        if [ -n "$read_src" ]; then
            read -r -p "$prompt: " out <"$read_src"
        else
            read -r -p "$prompt: " out
        fi
    fi
    printf '%s' "$out"
}

confirm() {
    # prompt, default No
    local msg="$1"
    local default_no="${2:-no}"
    local resp
    # Prefer the controlling TTY for confirmation prompts when available.
    local tty="/dev/tty"
    if [ -r "$tty" ]; then
        read -r -p "$msg [y/N]: " resp <"$tty"
    else
        read -r -p "$msg [y/N]: " resp
    fi
    case "$resp" in
    [yY] | [yY][eE][sS]) return 0 ;;
    *) return 1 ;;
    esac
}

backup_file() {
    local f="$1"
    if [ -e "$f" ]; then
        mkdir -p "$BACKUP_DIR/$(dirname "$f")"
        cp -a "$f" "$BACKUP_DIR/$f" || die "failed to backup $f"
    fi
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
current_pkg="$(sed -n 's/^PACKAGE_NAME="\([^"]*\)".*/\1/p' dkms.conf || true)"
current_ver="$(sed -n 's/^PACKAGE_VERSION="\([^"]*\)".*/\1/p' dkms.conf || true)"
current_author="$(sed -n -E 's/^MODULE_AUTHOR\(\"(.*)\"\);.*/\1/p' hello.c || true)"
current_email=""
# Try to split author into name and email if possible
if [[ "$current_author" =~ \<([^>]+)\> ]]; then
    current_email="${BASH_REMATCH[1]}"
    # remove email portion from author for display
    current_author="$(echo "$current_author" | sed 's/ *<.*>//')"
fi

printf 'Current values detected:\n'
printf '  PACKAGE_NAME: %s\n' "${current_pkg:-<none>}"
printf '  PACKAGE_VERSION: %s\n' "${current_ver:-<none>}"
printf '  MODULE_AUTHOR: %s\n' "${current_author:-<none>}"
[ -n "$current_email" ] && printf '  MODULE_AUTHOR email: %s\n' "$current_email"

echo
# If key project files are missing, auto-clone in non-interactive mode; otherwise offer to clone.
# This makes the script safe to run as an online script (curl | bash) by automatically
# performing a shallow git clone when stdin is not a TTY.
if [ ! -f "dkms.conf" ] || [ ! -f "hello.c" ]; then
    echo "Warning: one or more project files (dkms.conf, hello.c) are missing in the current directory."
    # Non-interactive (piped) runs commonly have stdin not a TTY. In that case auto-clone.
    if ! [ -t 0 ]; then
        tmpdir="$(mktemp -d -t hello-dkms-XXXX)"
        echo "Non-interactive run detected; cloning repository into $tmpdir..."
        if git clone --depth=1 https://github.com/LIghtJUNction/hello_dkms.git "$tmpdir"; then
            echo "Switching to $tmpdir"
            cd "$tmpdir" || die "failed to cd to $tmpdir"
            BACKUP_DIR="./.setup-backups-${TIMESTAMP}"
            mkdir -p "$BACKUP_DIR"
            echo "Now operating in: $(pwd)"
            echo "Backups will be created under: $BACKUP_DIR"
        else
            die "git clone failed; aborting"
        fi
    else
        # Interactive: ask the user as before
        if confirm "Would you like to git-clone the repository into a temporary directory and continue there?"; then
            tmpdir="$(mktemp -d -t hello-dkms-XXXX)"
            echo "Cloning repository into $tmpdir..."
            if git clone --depth=1 https://github.com/LIghtJUNction/hello_dkms.git "$tmpdir"; then
                echo "Switching to $tmpdir"
                cd "$tmpdir" || die "failed to cd to $tmpdir"
                BACKUP_DIR="./.setup-backups-${TIMESTAMP}"
                mkdir -p "$BACKUP_DIR"
                echo "Now operating in: $(pwd)"
                echo "Backups will be created under: $BACKUP_DIR"
            else
                die "git clone failed; aborting"
            fi
        else
            echo "Continuing in current directory; operations may fail if required files are missing."
        fi
    fi
fi

printf 'Enter new values (leave blank to keep current):\n'
pkg="$(prompt 'LKM package name (e.g. hello-dkms)' "$current_pkg")"
ver="$(prompt 'LKM package version (e.g. 1.1)' "$current_ver")"
author_name="$(prompt 'Author full name' "$current_author")"
author_email="$(prompt 'Author email' "$current_email")"

# Derived values
# built module name: prefer user input or fallback to package name with -dkms stripped
built_module_default="${pkg%-dkms}"
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
echo "dkms.conf updated and backed up to $BACKUP_DIR/dkms.conf (original)."

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
    new_desc="$(prompt 'Module description' "${current_desc:-Standard Hello World DKMS module}")"
    new_alias="$(prompt 'Module alias' "${current_alias:-${built_module}}")"
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
    perl -0777 -pe "s/\Q${current_pkg}\E/${pkg}/g; s/\Q${current_ver}\E/${ver}/g" "$BACKUP_DIR/$readme_file" 2>/dev/null || true
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
        echo "Backing up .git to $BACKUP_DIR/git-backup.tar.gz"
        tar -czf "$BACKUP_DIR/git-backup.tar.gz" .git || echo "warning: failed to archive .git"
        rm -rf .git || die "failed to remove .git"
        echo ".git removed (backup stored in $BACKUP_DIR/git-backup.tar.gz)"
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
echo "All operations complete. Backups of modified files are stored under: $BACKUP_DIR"
echo "Next steps:"
echo "  - Inspect changes, run 'make' or use helper scripts (source ./scripts/dkms-helper.bash) to build and install."
echo "  - If you removed .git and want to reinitialize a repo, run 'git init' and create an initial commit."
echo
