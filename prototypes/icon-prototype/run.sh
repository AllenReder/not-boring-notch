#!/usr/bin/env bash
set -e

BUILD_DIR="${TMPDIR:-/tmp}/not-boring-notch-icon"
mkdir -p "$BUILD_DIR"

echo "Compiling Icon Design Prototype..."
xcrun swiftc -O prototypes/icon-prototype/main.swift -o "$BUILD_DIR/icon_prototype"

echo "Launching Icon Design Prototype..."
exec "$BUILD_DIR/icon_prototype"
