#!/bin/bash
#
#  build_rust.sh
#  Build script for Rust PostgreSQL framework
#

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
RUST_SRC_DIR="$SCRIPT_DIR/rust_src"
BUILD_DIR="$SCRIPT_DIR/build"
OUTPUT_DIR="$SCRIPT_DIR"

echo "Building Rust PostgreSQL Framework..."

if ! command -v cargo &> /dev/null; then
    echo "Error: Rust is not installed. Please install Rust from https://rustup.rs/"
    exit 1
fi

echo "Rust: $(rustc --version)"
mkdir -p "$BUILD_DIR"
cd "$RUST_SRC_DIR"

echo "Building for arm64 (Apple Silicon)..."
cargo build --release --target aarch64-apple-darwin

echo "Building for x86_64 (Intel)..."
cargo build --release --target x86_64-apple-darwin

ARM64_LIB="target/aarch64-apple-darwin/release/libsppostgresql.a"
X86_64_LIB="target/x86_64-apple-darwin/release/libsppostgresql.a"
UNIVERSAL_LIB="$BUILD_DIR/libsppostgresql.a"

if [ -f "$ARM64_LIB" ] && [ -f "$X86_64_LIB" ]; then
    lipo -create "$ARM64_LIB" "$X86_64_LIB" -output "$UNIVERSAL_LIB"
    echo "Created universal binary: $UNIVERSAL_LIB"
elif [ -f "$ARM64_LIB" ]; then
    cp "$ARM64_LIB" "$UNIVERSAL_LIB"
    echo "Created arm64 binary: $UNIVERSAL_LIB"
elif [ -f "$X86_64_LIB" ]; then
    cp "$X86_64_LIB" "$UNIVERSAL_LIB"
    echo "Created x86_64 binary: $UNIVERSAL_LIB"
else
    echo "Error: No build artifacts found"
    exit 1
fi

file "$UNIVERSAL_LIB"
lipo -info "$UNIVERSAL_LIB" || true
cp "$UNIVERSAL_LIB" "$OUTPUT_DIR/"
echo "Build complete. Library at $OUTPUT_DIR/libsppostgresql.a"
echo ""
echo "Next steps:"
echo "1. Add libsppostgresql.a to your Xcode project"
echo "2. Add the Headers directory to your header search paths"
echo "3. Link against -lresolv -lc++ in Other Linker Flags"
