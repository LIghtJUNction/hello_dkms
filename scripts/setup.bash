#!/usr/bin/env bash
# Copyright (c) 2026 lightjunction
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# Interactive setup script for hello-dkms project
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"
BACKUP_DIR=""

# ── 颜色：直接使用 ANSI 转义，不依赖 tput ──────────────────────────────
# curl | bash 时 stdin 是管道，tput 无法正确探测终端，直接硬编码 ANSI 最可靠。
# 如果真的不是终端（如重定向到文件），再关闭颜色。
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

# ── prompt：始终通过 /dev/tty 交互，避免 stdin 被管道占用 ──────────────
prompt() {
    local prompt_text="$1"
    local default="$2"
    local out
    local tty="/dev/tty"

    if [ -n "$default" ]; then
        printf '%b' "${BLUE}${prompt_text}${RESET} ${GREY}[${default}]${RESET}: " >"$tty"
    else
        printf '%b' "${BLUE}${prompt_text}${RESET}: " >"$tty"
    fi

    # 必须从 /dev/tty 读取，否则 curl|bash 时 read 会立刻读到 EOF
    if [ -r "$tty" ]; then
        read -r out <"$tty" || out=""
    else
        read -r out || out=""
    fi

    # 空输入则使用默认值
    if [ -z "$out" ] && [ -n "$default" ]; then
        out="$default"
    fi
    printf '%s' "$out"
}

# ── confirm：返回 0=yes 1=no，不向 stderr 打印多余内容 ─────────────────
confirm() {
    local msg="$1"
    local resp
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

backup_file() {
    # Backups disabled: no-op
    return 0
}

# ── perl_replace：用 Perl 做替换，正确转义变量中的特殊字符 ──────────────
# 使用 -e 传入变量而非插值到代码字符串，避免 / @ 等字符破坏 perl 表达式
perl_replace_file() {
    local file="$1"
    local pattern="$2"
    local replacement="$3"
    [ -f "$file" ] || {
        echo "warning: $file not found; skipping"
        return 0
    }
    local tmp
    tmp="$(mktemp "${file}.tmp.XXXX")"
    # 通过环境变量传递替换值，在 perl 代码中用 $ENV{} 引用，彻底避免转义问题
    PERL_REPL="$replacement" perl -0777 -pe \
        "s/\Q${pattern}\E/\$ENV{PERL_REPL}/g" \
        "$file" >"$tmp" || {
        rm -f "$tmp"
        die "perl replace failed on $file"
    }
    mv "$tmp" "$file"
}

# ── 用 perl 做正则替换（pattern 是正则，repl 是字面量） ──────────────────
perl_regex_replace_file() {
    local file="$1"
    local pattern="$2"     # perl 正则
    local replacement="$3" # 字面替换值（通过环境变量传入，无需转义）
    [ -f "$file" ] || {
        echo "warning: $file not found; skipping"
        return 0
    }
    local tmp
    tmp="$(mktemp "${file}.tmp.XXXX")"
    PERL_REPL="$replacement" perl -0777 -pe \
        "s/${pattern}/\$ENV{PERL_REPL}/gm" \
        "$file" >"$tmp" || {
        rm -f "$tmp"
        die "perl regex replace failed on $file"
    }
    mv "$tmp" "$file"
}

# ════════════════════════════════════════════════════════════════════════
# 读取当前值
# ════════════════════════════════════════════════════════════════════════
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

# git config 兜底
git_name="$(git config --global user.name 2>/dev/null || true)"
git_email="$(git config --global user.email 2>/dev/null || true)"
[ -z "$current_author" ] && [ -n "$git_name" ] && current_author="$git_name"
[ -z "$current_email" ] && [ -n "$git_email" ] && current_email="$git_email"

printf '\n%bCurrent values detected:%b\n' "$BOLD" "$RESET"
printf '  %bPACKAGE_NAME%b:    %s\n' "$BOLD" "$RESET" "${current_pkg:-<none>}"
printf '  %bPACKAGE_VERSION%b: %s\n' "$BOLD" "$RESET" "${current_ver:-<none>}"
printf '  %bMODULE_AUTHOR%b:   %s\n' "$BOLD" "$RESET" "${current_author:-<none>}"
[ -n "$current_email" ] && printf '  %bMODULE_AUTHOR email%b: %s\n' "$BOLD" "$RESET" "$current_email"
printf '\n'

# ════════════════════════════════════════════════════════════════════════
# 若缺少项目文件，自动克隆仓库
# ════════════════════════════════════════════════════════════════════════
if [ ! -f "dkms.conf" ] || [ ! -f "hello.c" ]; then
    printf '%bWarning:%b one or more project files (dkms.conf, hello.c) are missing.\n' "$YELLOW" "$RESET"
    tmpdir="$(mktemp -d -t hello-dkms-XXXX)"
    printf 'Cloning repository into %s...\n' "$tmpdir"
    git clone --depth=1 https://github.com/LIghtJUNction/hello_dkms.git "$tmpdir" ||
        die "git clone failed; aborting"
    echo "Switching to $tmpdir"
    cd "$tmpdir" || die "failed to cd to $tmpdir"
    BACKUP_DIR=""
    printf 'Now operating in: %b%s%b\n' "$GREEN" "$(pwd)" "$RESET"
    printf 'Backups are disabled.\n\n'

    # 克隆后重新读取真实值（模板里可能有占位符，清空让用户填写）
    current_pkg="$(sed -n 's/^PACKAGE_NAME="\([^"]*\)".*/\1/p' dkms.conf 2>/dev/null || true)"
    current_ver="$(sed -n 's/^PACKAGE_VERSION="\([^"]*\)".*/\1/p' dkms.conf 2>/dev/null || true)"
    # 如果读到的是空字符串或占位符，清空让用户输入
    [[ "$current_pkg" =~ ^(hello-dkms|your-module|)$ ]] && current_pkg=""
    [[ "$current_ver" =~ ^(1\.0|0\.1|)$ ]] && current_ver=""
fi

# ════════════════════════════════════════════════════════════════════════
# 交互式输入
# ════════════════════════════════════════════════════════════════════════
printf '%bEnter new values%b (leave blank to keep current):\n' "$BOLD" "$RESET"

pkg="$(prompt 'LKM package name   (e.g. hello-dkms)' "$current_pkg")"
ver="$(prompt 'LKM package version (e.g. 1.1)' "$current_ver")"
author_name="$(prompt 'Author full name' "$current_author")"
author_email="$(prompt 'Author email' "$current_email")"

# built_module 默认值：去掉 -dkms 后缀的包名，而非临时目录名
if [ -n "${pkg:-}" ]; then
    built_module_default="${pkg%-dkms}"
else
    built_module_default="hello"
fi
built_module="$(prompt "Built module name (.ko name)" "$built_module_default")"

# ════════════════════════════════════════════════════════════════════════
# 确认摘要
# ════════════════════════════════════════════════════════════════════════
printf '\n%bSummary of changes to be applied:%b\n' "$BOLD" "$RESET"
printf '  PACKAGE_NAME:       %b%s%b -> %b%s%b\n' "$GREY" "$current_pkg" "$RESET" "$GREEN" "$pkg" "$RESET"
printf '  PACKAGE_VERSION:    %b%s%b -> %b%s%b\n' "$GREY" "$current_ver" "$RESET" "$GREEN" "$ver" "$RESET"
printf '  MODULE_AUTHOR:      %b%s <%s>%b\n' "$GREEN" "$author_name" "$author_email" "$RESET"
printf '  BUILT_MODULE_NAME:  %b%s%b\n' "$GREEN" "$built_module" "$RESET"
printf '\n'

if ! confirm "Proceed with the above changes?"; then
    printf '%bAborted by user.%b\n' "$YELLOW" "$RESET"
    exit 0
fi

# ════════════════════════════════════════════════════════════════════════
# 更新 dkms.conf
# ════════════════════════════════════════════════════════════════════════
printf '\n%bUpdating dkms.conf...%b\n' "$BLUE" "$RESET"
[ -f "dkms.conf" ] || die "dkms.conf not found in current directory"

# 通过环境变量传递所有替换值，perl 代码中用 $ENV{} 引用，完全规避转义问题
PERL_PKG="$pkg" PERL_VER="$ver" PERL_MOD="$built_module" \
    perl -0777 -i -pe '
  s/^(PACKAGE_NAME=")[^"]*(")/($1 . $ENV{PERL_PKG} . $2)/gem;
  s/^(PACKAGE_VERSION=")[^"]*(")/($1 . $ENV{PERL_VER} . $2)/gem;
  if (/BUILT_MODULE_NAME/) {
    s/^(BUILT_MODULE_NAME\[\d+\]=")[^"]*(")/($1 . $ENV{PERL_MOD} . $2)/gem;
  } else {
    s/\z/\nBUILT_MODULE_NAME[0]="$ENV{PERL_MOD}"\n/;
  }
' dkms.conf || die "failed to update dkms.conf"

printf '%bOK%b dkms.conf updated.\n' "$GREEN" "$RESET"

# ════════════════════════════════════════════════════════════════════════
# 更新 hello.c
# ════════════════════════════════════════════════════════════════════════
printf '%bUpdating hello.c author...%b\n' "$BLUE" "$RESET"
if [ -f "hello.c" ]; then
    author_entry="${author_name}"
    [ -n "$author_email" ] && author_entry="${author_entry} <${author_email}>"

    PERL_AUTHOR="$author_entry" \
        perl -0777 -i -pe \
        's/MODULE_AUTHOR\([^;]*\);/"MODULE_AUTHOR(\"" . $ENV{PERL_AUTHOR} . "\");"/ge' \
        hello.c || die "failed to update hello.c"

    printf '%bOK%b hello.c updated.\n' "$GREEN" "$RESET"
else
    printf '%bwarning:%b hello.c not found; skipping\n' "$YELLOW" "$RESET"
fi

# 可选：更新 MODULE_DESCRIPTION 和 MODULE_ALIAS
if confirm "Update MODULE_DESCRIPTION and MODULE_ALIAS in hello.c?"; then
    current_desc="$(sed -n -E 's/^MODULE_DESCRIPTION\("(.*)"\);.*/\1/p' hello.c 2>/dev/null || true)"
    current_alias="$(sed -n -E 's/^MODULE_ALIAS\("(.*)"\);.*/\1/p' hello.c 2>/dev/null || true)"
    default_desc="${current_desc:-${pkg} DKMS module}"
    default_alias="${current_alias:-${built_module}}"
    new_desc="$(prompt 'Module description' "$default_desc")"
    new_alias="$(prompt 'Module alias' "$default_alias")"

    PERL_DESC="$new_desc" PERL_ALIAS="$new_alias" \
        perl -0777 -i -pe '
    if (s/MODULE_DESCRIPTION\([^;]*\);/"MODULE_DESCRIPTION(\"" . $ENV{PERL_DESC} . "\");"/ge) {}
    else { s/(MODULE_AUTHOR\("[^"]*"\);)/$1\nMODULE_DESCRIPTION("$ENV{PERL_DESC}");/m }
    if (s/MODULE_ALIAS\([^;]*\);/"MODULE_ALIAS(\"" . $ENV{PERL_ALIAS} . "\");"/ge) {}
    else { s/(MODULE_LICENSE\("[^"]*"\);)/$1\nMODULE_ALIAS("$ENV{PERL_ALIAS}");/m }
  ' hello.c || die "failed to update description/alias"
    printf '%bOK%b description/alias updated.\n' "$GREEN" "$RESET"
fi

# ════════════════════════════════════════════════════════════════════════
# README 重命名
# ════════════════════════════════════════════════════════════════════════
readme_file=""
[ -f "README.md" ] && readme_file="README.md"
[ -f "REAMDE.md" ] && readme_file="REAMDE.md" # 常见拼写错误

if [ -n "$readme_file" ]; then
    printf 'Found README file: %b%s%b\n' "$BOLD" "$readme_file" "$RESET"
    if [ -n "$pkg" ] && confirm "Rename README to README-${pkg}.md?"; then
        new_readme="README-${pkg}.md"
        mv "$readme_file" "$new_readme"
        printf '%bRenamed%b %s -> %s\n' "$GREEN" "$RESET" "$readme_file" "$new_readme"
        printf 'This repository was initialized by setup script.\nPrimary documentation moved to %s\n' \
            "$new_readme" >README.md
        printf 'Created lightweight README.md pointing to %s\n' "$new_readme"
    fi
else
    printf 'No README found; skipping rename.\n'
fi

# ════════════════════════════════════════════════════════════════════════
# 可选：删除 .git
# ════════════════════════════════════════════════════════════════════════
if [ -d ".git" ]; then
    printf '%b.git directory detected.%b\n' "$YELLOW" "$RESET"
    if confirm "REMOVE .git directory? (irreversible)"; then
        rm -rf .git || die "failed to remove .git"
        printf '%b.git removed.%b\n' "$GREEN" "$RESET"
    else
        printf 'Skipping .git removal.\n'
    fi
fi

# ════════════════════════════════════════════════════════════════════════
# 可选：重命名项目目录
# ════════════════════════════════════════════════════════════════════════
if [ -n "$pkg" ] && [ -n "$ver" ] &&
    confirm "Rename project directory to ${pkg}-${ver}?"; then
    curdir="$(pwd)"
    parent="$(dirname "$curdir")"
    base="$(basename "$curdir")"
    target_name="${pkg}-${ver}"
    printf 'About to move: %s -> %s/%s\n' "$curdir" "$parent" "$target_name"
    if confirm "Confirm move?"; then
        cd "$parent"
        if mv "$base" "$target_name"; then
            printf '%bDirectory moved to %s/%s%b\n' "$GREEN" "$parent" "$target_name" "$RESET"
            printf 'NOTE: run: %bcd %s/%s%b\n' "$BOLD" "$parent" "$target_name" "$RESET"
        else
            printf '%bFailed to move directory.%b\n' "$RED" "$RESET"
            cd "$curdir"
        fi
    else
        printf 'Move cancelled.\n'
    fi
fi

# ════════════════════════════════════════════════════════════════════════
printf '\n%bAll operations complete.%b\n' "$GREEN" "$RESET"
printf 'Next steps:\n'
printf '  - Inspect changes, run %bmake%b or use helper scripts:\n' "$BOLD" "$RESET"
printf '    %bsource ./scripts/dkms-helper.bash%b\n' "$BOLD" "$RESET"
printf '  - If you removed .git, reinitialize with:\n'
printf '    %bgit init && git add -A && git commit -m "init"%b\n' "$BOLD" "$RESET"
printf '\n'
