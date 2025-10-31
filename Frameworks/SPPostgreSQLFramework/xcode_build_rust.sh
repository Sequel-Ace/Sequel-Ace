#!/bin/bash

# Xcode-specific build script for Rust PostgreSQL framework
# This script is designed to run within Xcode's build environment

set -e  # Exit on error

# Log function for better debugging
log() {
    echo "[Rust Build] $1"
}

log "Starting Rust build for PostgreSQL framework..."

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
log "Script directory: $SCRIPT_DIR"

# Change to the script directory
cd "$SCRIPT_DIR"

# Check if Rust is installed and in PATH
if ! command -v rustc &> /dev/null; then
    log "ERROR: Rust not found in PATH"
    log "Adding common Rust installation paths..."
    
    # Try common Rust installation locations
    if [ -f "$HOME/.cargo/env" ]; then
        source "$HOME/.cargo/env"
        log "Sourced Rust environment from ~/.cargo/env"
    elif [ -d "$HOME/.cargo/bin" ]; then
        export PATH="$HOME/.cargo/bin:$PATH"
        log "Added ~/.cargo/bin to PATH"
    fi
    
    # Check again
    if ! command -v rustc &> /dev/null; then
        log "ERROR: Still can't find Rust. Please ensure Rust is installed."
        log "Install with: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
        exit 1
    fi
fi

log "Rust version: $(rustc --version)"

# Check if the library is already up to date
RUST_SRC_DIR="$SCRIPT_DIR/rust_src"
LIB_OUTPUT="$SCRIPT_DIR/libsppostgresql.a"

if [ -f "$LIB_OUTPUT" ]; then
    # Check if any Rust source files are newer than the library
    NEEDS_REBUILD=0
    
    if [ -d "$RUST_SRC_DIR/src" ]; then
        while IFS= read -r -d '' file; do
            if [ "$file" -nt "$LIB_OUTPUT" ]; then
                NEEDS_REBUILD=1
                log "Source file changed: $file"
                break
            fi
        done < <(find "$RUST_SRC_DIR/src" -name "*.rs" -print0)
    fi
    
    if [ "$NEEDS_REBUILD" -eq 0 ]; then
        log "Library is up to date, skipping build"
        exit 0
    fi
fi

log "Building Rust library..."

# Run the build script
if [ -f "$SCRIPT_DIR/build_rust.sh" ]; then
    bash "$SCRIPT_DIR/build_rust.sh"
    BUILD_EXIT_CODE=$?
    
    if [ $BUILD_EXIT_CODE -ne 0 ]; then
        log "ERROR: Build script failed with exit code $BUILD_EXIT_CODE"
        exit $BUILD_EXIT_CODE
    fi
    
    log "Build completed successfully"
else
    log "ERROR: build_rust.sh not found in $SCRIPT_DIR"
    exit 1
fi

# Verify the output exists
if [ ! -f "$LIB_OUTPUT" ]; then
    log "ERROR: Expected library file not found at $LIB_OUTPUT"
    exit 1
fi

log "Rust PostgreSQL framework build complete"
exit 0

