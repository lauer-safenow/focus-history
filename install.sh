#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BINARY="$SCRIPT_DIR/focus-history"
SOURCE="$SCRIPT_DIR/focus-history.swift"

echo "Compiling focus-history..."
swiftc -o "$BINARY" "$SOURCE" -framework Cocoa

echo "Installing daemon..."
"$BINARY" --install

echo ""
echo "Done! Try: $BINARY --history"
