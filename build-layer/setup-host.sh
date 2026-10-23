#!/usr/bin/env bash
# Prepare a fresh Ubuntu 24.04 x86-64 server for building InkPalm KompaktOS.
#
#     bash build-layer/setup-host.sh
#
# Installs the LineageOS build dependencies plus what this layer uses (debugfs, simg2img,
# Pillow, openssl), the `repo` launcher, a git identity (needed by repo and git am) and ccache.
# Safe to re-run. Uses sudo for apt only; everything else goes into $HOME.
#
# Env: GIT_NAME / GIT_EMAIL (identity for build commits, only set if none is configured),
#      CCACHE_SIZE (default 50G), CCACHE_DIR (default ~/.ccache).
set -euo pipefail
LOG_TAG=setup
# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

[ "$(uname -m)" = x86_64 ] || die "the Android build needs an x86-64 Linux host (this is $(uname -m))"
[ "$(id -u)" -ne 0 ] || die "run as a normal user with sudo rights, not as root (AOSP refuses root builds)"
if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    [ "${VERSION_ID:-}" = 24.04 ] || warn "tested target is Ubuntu 24.04, this is ${PRETTY_NAME:-unknown}"
fi

stage "apt packages"
# LineageOS build deps (wiki list for Ubuntu >= 23.10, where libncurses5 is gone), plus:
#   e2fsprogs (debugfs, post-build checks), android-sdk-libsparse-utils (simg2img),
#   python3-pil (boot animation rescale), openssl (gen-keys.sh), xxd/file/unzip (checks), tmux.
# UNVERIFIED: package availability checked against the wiki list, not installed on a 24.04 box.
PKGS="bc bison build-essential ccache curl flex g++-multilib gcc-multilib git git-lfs gnupg gperf
imagemagick protobuf-compiler python3-protobuf lib32readline-dev lib32z1-dev libdw-dev libelf-dev
lz4 libsdl1.2-dev libssl-dev libxml2 libxml2-utils lzop pngcrush rsync schedtool squashfs-tools
xsltproc zip zlib1g-dev lib32ncurses-dev libncurses-dev python3 python-is-python3
e2fsprogs android-sdk-libsparse-utils python3-pil openssl xxd file unzip tmux"
sudo apt-get update
# shellcheck disable=SC2086
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y $PKGS

stage "repo launcher"
mkdir -p "$HOME/.local/bin"
if [ ! -x "$HOME/.local/bin/repo" ]; then
    curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o "$HOME/.local/bin/repo"
    chmod 0755 "$HOME/.local/bin/repo"
fi
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) grep -q 'HOME/.local/bin' "$HOME/.profile" 2>/dev/null ||
           printf '\n# repo launcher (build-layer/setup-host.sh)\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.profile"
       export PATH="$HOME/.local/bin:$PATH" ;;
esac
log "repo: $(command -v repo)"

stage "git"
git config --global user.email >/dev/null 2>&1 ||
    git config --global user.email "${GIT_EMAIL:-inkpalm-build@localhost}"
git config --global user.name >/dev/null 2>&1 ||
    git config --global user.name "${GIT_NAME:-InkPalm build}"
git config --global color.ui auto      # stops repo init from asking
git lfs install --skip-repo >/dev/null
log "git identity: $(git config --global user.name) <$(git config --global user.email)>"

stage "ccache"
CCACHE_DIR=${CCACHE_DIR:-$HOME/.ccache}
mkdir -p "$CCACHE_DIR"
CCACHE_DIR=$CCACHE_DIR ccache -M "${CCACHE_SIZE:-50G}" >/dev/null
if ! grep -q 'USE_CCACHE' "$HOME/.profile" 2>/dev/null; then
    cat >> "$HOME/.profile" <<EOF

# ccache for the Android build (build-layer/setup-host.sh)
export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache
export CCACHE_DIR=$CCACHE_DIR
EOF
fi
log "ccache: $CCACHE_DIR, max ${CCACHE_SIZE:-50G}"

stage "checks"
df -h "$HOME" | tail -1 | awk '{print "free disk on $HOME: " $4}' >&2
awk '/MemTotal/ {printf "RAM: %.0f GB\n", $2/1048576}' /proc/meminfo >&2
log "cores: $(nproc)"
log "done. Log out and back in (or: . ~/.profile), then run build-layer/gen-keys.sh"
