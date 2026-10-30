#!/usr/bin/env bash
# Fails if the app grows a shell, a network client, an event tap, or a purchase flow.
# Uses grep so CI does not depend on ripgrep.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

fail() {
  echo "security-scan: $1" >&2
  exit 1
}

scan() {
  local pattern="$1"
  local message="$2"
  if grep -rnE --include='*.swift' "$pattern" App Sources; then
    fail "$message"
  fi
}

scan 'URLSession' 'network client is not allowed'
scan 'import Network' 'network client is not allowed'
scan 'StoreKit' 'purchases are not allowed'
scan 'SKPayment' 'purchases are not allowed'
scan 'CGEvent\.tapCreate|CGEventTap' 'event taps are not allowed; post events only'
scan '/bin/zsh|bin/bash|"/bin/sh"' 'shell execution is not allowed'
scan 'NSAppleScript' 'arbitrary AppleScript is not allowed'

if grep -rnE 'Process\(' App Sources | grep -v 'App/SystemServices.swift'; then
  fail 'Process is only allowed in SystemServices.swift'
fi

if ! grep -q '"/usr/bin/shortcuts"' App/SystemServices.swift; then
  fail 'shortcuts must be launched by absolute path'
fi

echo "security-scan: ok"
