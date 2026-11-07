#!/bin/bash
# Compiles the pure-logic sources together with Tests/main.swift and runs them.
set -euo pipefail
cd "$(dirname "$0")"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
swiftc -O Click2Minimize/GestureMath.swift Tests/main.swift -o "$OUT/logic_tests"
"$OUT/logic_tests"
