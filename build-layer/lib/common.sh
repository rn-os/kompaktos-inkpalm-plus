# Shared helpers for the build-layer scripts. Sourced, not executed.
# Must stay bash 3.2 compatible: extract-blobs.sh also runs on macOS's /bin/bash.

# shellcheck shell=bash

_ts() { date '+%H:%M:%S'; }
log()  { printf '%s [%s] %s\n' "$(_ts)" "${LOG_TAG:-layer}" "$*" >&2; }
warn() { printf '%s [%s] WARNING: %s\n' "$(_ts)" "${LOG_TAG:-layer}" "$*" >&2; }
die()  { printf '%s [%s] ERROR: %s\n' "$(_ts)" "${LOG_TAG:-layer}" "$*" >&2; exit 1; }
stage() { printf '\n%s [%s] ===== %s =====\n' "$(_ts)" "${LOG_TAG:-layer}" "$*" >&2; }

need() {
    local t
    for t in "$@"; do
        command -v "$t" >/dev/null 2>&1 || die "missing tool: $t (run setup-host.sh on the build server)"
    done
}

# sha256 of a file, hex only (Linux sha256sum or macOS shasum).
sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    else
        shasum -a 256 "$1" | cut -d' ' -f1
    fi
}

# Absolute path of an existing directory.
abs_dir() { (cd "$1" && pwd -P); }

# True if $1 (existing dir) lies inside any git work tree.
in_git_tree() { git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1; }

# Locate debugfs: PATH, then Homebrew e2fsprogs (macOS), then /sbin.
find_debugfs() {
    local c
    for c in "$(command -v debugfs 2>/dev/null || true)" \
             /opt/homebrew/opt/e2fsprogs/sbin/debugfs \
             /usr/local/opt/e2fsprogs/sbin/debugfs \
             /sbin/debugfs /usr/sbin/debugfs; do
        [ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return 0; }
    done
    return 1
}

# The stock libraries the vendor hwcomposer needs (see gsi/vendor-fix/README.md).
# name:location  (system = stock /system/lib64, art = stock ART APEX lib64)
STOCK_LIBS="libskia.so:system libdng_sdk.so:system libft2.so:system libandroidicu.so:art libicuuc.so:art libicui18n.so:art"
