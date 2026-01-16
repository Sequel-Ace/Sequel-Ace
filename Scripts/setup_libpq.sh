#!/bin/bash
#
# setup_libpq.sh - Downloads and sets up libpq for Sequel PAce
#
# This script automatically detects your system architecture and
# copies the appropriate libpq library into the PostgreSQL framework.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FRAMEWORK_DIR="${PROJECT_ROOT}/Frameworks/PostgreSQL.framework"
DYLIB_DEST="${FRAMEWORK_DIR}/Versions/A/PostgreSQL"

echo "=== Sequel PAce libpq Setup Script ==="
echo ""

# Detect architecture
ARCH=$(uname -m)
echo "Detected architecture: ${ARCH}"

# Find libpq
LIBPQ_PATH=""

if [ "$ARCH" = "arm64" ]; then
    # Apple Silicon paths
    SEARCH_PATHS=(
        "/opt/homebrew/opt/libpq/lib/libpq.5.dylib"
        "/opt/homebrew/opt/libpq/lib/libpq.dylib"
        "/opt/homebrew/lib/postgresql@16/libpq.5.dylib"
        "/opt/homebrew/lib/postgresql@15/libpq.5.dylib"
        "/opt/homebrew/lib/postgresql@14/libpq.5.dylib"
    )
else
    # Intel Mac paths
    SEARCH_PATHS=(
        "/usr/local/opt/libpq/lib/libpq.5.dylib"
        "/usr/local/opt/libpq/lib/libpq.dylib"
        "/usr/local/lib/postgresql@16/libpq.5.dylib"
        "/usr/local/lib/postgresql@15/libpq.5.dylib"
        "/usr/local/lib/postgresql@14/libpq.5.dylib"
    )
fi

for path in "${SEARCH_PATHS[@]}"; do
    if [ -f "$path" ]; then
        LIBPQ_PATH="$path"
        break
    fi
done

if [ -z "$LIBPQ_PATH" ]; then
    echo ""
    echo "ERROR: libpq not found!"
    echo ""
    echo "Please install PostgreSQL client libraries via Homebrew:"
    echo ""
    echo "    brew install libpq"
    echo ""
    echo "Then run this script again."
    exit 1
fi

echo "Found libpq at: ${LIBPQ_PATH}"
echo ""

# Create framework directory structure
echo "Creating framework structure..."
mkdir -p "${FRAMEWORK_DIR}/Versions/A/Headers"
mkdir -p "${FRAMEWORK_DIR}/Versions/A/Resources"

# Copy libpq
echo "Copying libpq..."
cp -f "$LIBPQ_PATH" "$DYLIB_DEST"
chmod +x "$DYLIB_DEST"

# Update install name for embedding
echo "Updating install names..."
install_name_tool -id "@rpath/PostgreSQL.framework/Versions/A/PostgreSQL" "$DYLIB_DEST"

# Handle dependencies (OpenSSL)
echo "Checking dependencies..."
DEPS=$(otool -L "$DYLIB_DEST" | grep -E "libssl|libcrypto" | awk '{print $1}' || true)

for dep in $DEPS; do
    if [ -f "$dep" ]; then
        DEP_NAME=$(basename "$dep")
        echo "  Copying dependency: ${DEP_NAME}"
        cp -f "$dep" "${FRAMEWORK_DIR}/Versions/A/${DEP_NAME}"
        chmod +x "${FRAMEWORK_DIR}/Versions/A/${DEP_NAME}"

        # Update reference in libpq
        install_name_tool -change "$dep" "@rpath/PostgreSQL.framework/Versions/A/${DEP_NAME}" "$DYLIB_DEST"

        # Update install name of dependency
        install_name_tool -id "@rpath/PostgreSQL.framework/Versions/A/${DEP_NAME}" "${FRAMEWORK_DIR}/Versions/A/${DEP_NAME}"
    fi
done

# Create/update symlinks
echo "Creating symlinks..."
cd "${FRAMEWORK_DIR}/Versions"
rm -f Current
ln -sf A Current

cd "${FRAMEWORK_DIR}"
rm -f PostgreSQL Headers Resources
ln -sf Versions/Current/PostgreSQL PostgreSQL
ln -sf Versions/Current/Headers Headers
ln -sf Versions/Current/Resources Resources

# Verify
echo ""
echo "=== Setup Complete ==="
echo ""
echo "Framework location: ${FRAMEWORK_DIR}"
echo ""
echo "Installed library info:"
otool -L "$DYLIB_DEST" | head -5
echo ""
echo "You can now build Sequel PAce in Xcode."
