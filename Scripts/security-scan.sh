#!/usr/bin/env bash
# Fails if the app grows a shell, a network client, an event tap, or a purchase flow.
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
  if rg -n --glob '!Scripts/security-scan.sh' --glob '!**/README.md' "$pattern" App Sources >/dev/null; then
    rg -n --glob '!Scripts/security-scan.sh' --glob '!**/README.md' "$pattern" App Sources >&2 || true
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

if rg -n 'Process\(' App Sources | rg -v 'App/SystemServices.swift' >/dev/null; then
  rg -n 'Process\(' App Sources >&2 || true
  fail 'Process is only allowed in SystemServices.swift'
fi

if ! rg -n '"/usr/bin/shortcuts"' App/SystemServices.swift >/dev/null; then
  fail 'shortcuts must be launched by absolute path'
fi

echo "security-scan: ok"
