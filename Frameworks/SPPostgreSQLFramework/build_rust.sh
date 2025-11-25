#!/bin/bash
#
#  build_rust.sh
#  Build script for Rust PostgreSQL framework
#
#  Created by Sequel Ace on 2024.
#  Copyright (c) 2024 Sequel Ace. All rights reserved.
#

set -e  # Exit on error

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
RUST_SRC_DIR="$SCRIPT_DIR/rust_src"
BUILD_DIR="$SCRIPT_DIR/build"
OUTPUT_DIR="$SCRIPT_DIR"

echo "🦀 Building Rust PostgreSQL Framework..."

# Check if Rust is installed
if ! command -v cargo &> /dev/null; then
    echo "❌ Error: Rust is not installed. Please install Rust from https://rustup.rs/"
    exit 1
fi

echo "✓ Rust is installed: $(rustc --version)"

# Create build directory
mkdir -p "$BUILD_DIR"

cd "$RUST_SRC_DIR"

# Build for both architectures in release mode
echo "📦 Building for arm64 (Apple Silicon)..."
cargo build --release --target aarch64-apple-darwin

echo "📦 Building for x86_64 (Intel)..."
cargo build --release --target x86_64-apple-darwin

# Create universal binary
echo "🔨 Creating universal binary..."
ARM64_LIB="target/aarch64-apple-darwin/release/libsppostgresql.a"
X86_64_LIB="target/x86_64-apple-darwin/release/libsppostgresql.a"
UNIVERSAL_LIB="$BUILD_DIR/libsppostgresql.a"

if [ -f "$ARM64_LIB" ] && [ -f "$X86_64_LIB" ]; then
    lipo -create "$ARM64_LIB" "$X86_64_LIB" -output "$UNIVERSAL_LIB"
    echo "✓ Created universal binary: $UNIVERSAL_LIB"
elif [ -f "$ARM64_LIB" ]; then
    cp "$ARM64_LIB" "$UNIVERSAL_LIB"
    echo "✓ Created arm64 binary: $UNIVERSAL_LIB"
elif [ -f "$X86_64_LIB" ]; then
    cp "$X86_64_LIB" "$UNIVERSAL_LIB"
    echo "✓ Created x86_64 binary: $UNIVERSAL_LIB"
else
    echo "❌ Error: No build artifacts found"
    exit 1
fi

# Verify the binary
echo "📋 Binary information:"
file "$UNIVERSAL_LIB"
lipo -info "$UNIVERSAL_LIB" || true

# Copy to output directory
cp "$UNIVERSAL_LIB" "$OUTPUT_DIR/"
echo "✓ Copied library to $OUTPUT_DIR/"

echo "✅ Build complete!"
echo ""
echo "Next steps:"
echo "1. Add libsppostgresql.a to your Xcode project"
echo "2. Add the Headers directory to your header search paths"
echo "3. Link against the library in your target"

