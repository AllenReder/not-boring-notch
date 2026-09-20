#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🎨 Compiling and executing Liquid Glass App Icon Generator..."
xcrun swiftc -O "$SCRIPT_DIR/generate_app_icon.swift" -o /tmp/gen_icon_bin

/tmp/gen_icon_bin "$PROJECT_ROOT"
rm -f /tmp/gen_icon_bin
echo "✅ Icon generation complete!"
