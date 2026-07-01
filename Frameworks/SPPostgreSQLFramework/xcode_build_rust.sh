#!/bin/bash
#
#  xcode_build_rust.sh
#  Xcode build phase script for SPPostgreSQLFramework
#  Runs only when Rust source files are newer than the library.
#

set -e

log() { echo "[Rust Build] $1"; }

log "Starting Rust build for PostgreSQL framework..."

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Locate Rust
if ! command -v rustc &> /dev/null; then
    log "Rust not in PATH, trying common install locations..."
    if [ -f "$HOME/.cargo/env" ]; then
        source "$HOME/.cargo/env"
    elif [ -d "$HOME/.cargo/bin" ]; then
        export PATH="$HOME/.cargo/bin:$PATH"
    fi
    if ! command -v rustc &> /dev/null; then
        log "ERROR: Rust not found. Install from https://rustup.rs/"
        exit 1
    fi
fi

log "Rust: $(rustc --version)"

RUST_SRC_DIR="$SCRIPT_DIR/rust_src"
LIB_OUTPUT="$SCRIPT_DIR/libsppostgresql.a"

# Skip rebuild if library is up to date
if [ -f "$LIB_OUTPUT" ]; then
    NEEDS_REBUILD=0
    if [ -d "$RUST_SRC_DIR/src" ]; then
        while IFS= read -r -d '' file; do
            if [ "$file" -nt "$LIB_OUTPUT" ]; then
                NEEDS_REBUILD=1
                log "Source changed: $file"
                break
            fi
        done < <(find "$RUST_SRC_DIR/src" -name "*.rs" -print0)
    fi
    if [ "$NEEDS_REBUILD" -eq 0 ]; then
        log "Library is up to date, skipping build."
        exit 0
    fi
fi

log "Building Rust library..."
bash "$SCRIPT_DIR/build_rust.sh"

if [ ! -f "$LIB_OUTPUT" ]; then
    log "ERROR: Expected library not found at $LIB_OUTPUT"
    exit 1
fi

log "Build complete."
exit 0
