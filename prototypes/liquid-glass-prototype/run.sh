#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${TMPDIR:-/tmp}/boring-notch-liquid-glass"
mkdir -p "$BUILD_DIR"

echo "==> Compiling Liquid Glass Interactive Prototype..."
xcrun swiftc -O "$DIR/main.swift" -o "$BUILD_DIR/prototype"

echo "==> Launching prototype..."
pkill -f "boring-notch-liquid-glass/prototype" 2>/dev/null || true
exec "$BUILD_DIR/prototype"
