#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

for architecture in aarch64 x86_64; do
  (
    uname() { printf '%s\n' "$architecture"; }
    omarchy-hw-surface() { return 0; }
    omarchy-pkg-add() { printf '%s\n' "$*" >> "$scratch/packages-$architecture"; }
    lsmod() { touch "$scratch/keyboard-$architecture"; }
    source "$ROOT/install/hardware/surface.sh"
    source "$ROOT/install/hardware/fix-surface-keyboard.sh" > /dev/null
  )
done
[[ ! -e $scratch/packages-aarch64 && ! -e $scratch/keyboard-aarch64 ]] || fail "ARM skips Intel Surface setup"
[[ $(cat "$scratch/packages-x86_64") == linux-firmware-marvell && -e $scratch/keyboard-x86_64 ]] || fail "Intel Surface setup remains active"
pass "Surface setup selects architecture before requesting Intel-only components"

for architecture in aarch64 x86_64; do
  (
    case $architecture in aarch64) node_arch=arm64 ;; *) node_arch=x64 ;; esac
    mkdir -p "$scratch/tree/node-v26.8.2-linux-$node_arch/bin"
    printf '%s\n' "$node_arch" > "$scratch/tree/node-v26.8.2-linux-$node_arch/bin/node-fixture"
    tar -czf "$scratch/node-v26.8.2-linux-$node_arch.tar.gz" -C "$scratch/tree" "node-v26.8.2-linux-$node_arch"
    # HOME is scoped to this test subprocess, never the invoking session.
    export HOME="$scratch/home-$architecture" OMARCHY_SETUP_CONTEXT=iso-chroot
    uname() { printf '%s\n' "$architecture"; }
    mise() { printf '%s\n' "$*" >> "$scratch/mise-$architecture"; }
    find() {
      [[ $3 == "node-v*-linux-$node_arch.tar.gz" ]] || return 1
      printf '%s\n' "$scratch/node-v26.8.2-linux-$node_arch.tar.gz"
    }
    source "$ROOT/install/user/mise-work.sh"
    [[ $(cat "$HOME/.local/share/mise/installs/node/26.8.2/bin/node-fixture") == "$node_arch" ]] || fail "correct Node archive extracted"
    grep -Fx 'use -g node@26.8.2' "$scratch/mise-$architecture" > /dev/null || fail "correct Node version selected"
  )
done
pass "Offline Node setup selects ARM64 and x64 archives and parses their version"
