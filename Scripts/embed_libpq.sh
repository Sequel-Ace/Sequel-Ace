#!/bin/bash
#
# embed_libpq.sh - Embeds libpq into the application bundle
#
# This script copies libpq.dylib into the application's Frameworks directory
# and updates the install names to use @rpath for proper embedding.
#

set -e

echo "=== Embedding libpq into application bundle ==="

# Configuration
FRAMEWORK_NAME="PostgreSQL"
DYLIB_NAME="libpq.5.dylib"

# Paths
APP_FRAMEWORKS_DIR="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"
POSTGRES_FRAMEWORK_DIR="${APP_FRAMEWORKS_DIR}/${FRAMEWORK_NAME}.framework"

# Find libpq - try multiple locations
LIBPQ_SEARCH_PATHS=(
    "/opt/homebrew/opt/libpq/lib"
    "/opt/homebrew/lib/postgresql@16"
    "/opt/homebrew/lib/postgresql@15"
    "/opt/homebrew/lib/postgresql@14"
    "/usr/local/opt/libpq/lib"
    "/usr/local/lib/postgresql@16"
    "/usr/local/lib/postgresql@15"
    "/usr/local/lib/postgresql@14"
    "/usr/local/lib"
)

LIBPQ_SOURCE=""
for search_path in "${LIBPQ_SEARCH_PATHS[@]}"; do
    if [ -f "${search_path}/${DYLIB_NAME}" ]; then
        LIBPQ_SOURCE="${search_path}/${DYLIB_NAME}"
        echo "Found libpq at: ${LIBPQ_SOURCE}"
        break
    fi
    # Also check for libpq.dylib symlink
    if [ -f "${search_path}/libpq.dylib" ]; then
        LIBPQ_SOURCE="${search_path}/libpq.dylib"
        echo "Found libpq at: ${LIBPQ_SOURCE}"
        break
    fi
done

if [ -z "${LIBPQ_SOURCE}" ]; then
    echo "Error: Could not find libpq.dylib"
    echo "Please install PostgreSQL via Homebrew: brew install libpq"
    exit 1
fi

# Create framework directory structure
mkdir -p "${POSTGRES_FRAMEWORK_DIR}/Versions/A"

# Copy libpq
cp -f "${LIBPQ_SOURCE}" "${POSTGRES_FRAMEWORK_DIR}/Versions/A/${FRAMEWORK_NAME}"
chmod +x "${POSTGRES_FRAMEWORK_DIR}/Versions/A/${FRAMEWORK_NAME}"

# Create symlinks
cd "${POSTGRES_FRAMEWORK_DIR}/Versions"
ln -sf A Current
cd "${POSTGRES_FRAMEWORK_DIR}"
ln -sf Versions/Current/${FRAMEWORK_NAME} ${FRAMEWORK_NAME}

# Update install name
DYLIB_PATH="${POSTGRES_FRAMEWORK_DIR}/Versions/A/${FRAMEWORK_NAME}"
install_name_tool -id "@rpath/${FRAMEWORK_NAME}.framework/Versions/A/${FRAMEWORK_NAME}" "${DYLIB_PATH}"

# Copy dependent libraries (OpenSSL if needed)
echo "Checking dependencies..."
otool -L "${DYLIB_PATH}" | grep -E "(libssl|libcrypto)" | while read line; do
    DEP_PATH=$(echo "$line" | awk '{print $1}')
    if [ -f "$DEP_PATH" ]; then
        DEP_NAME=$(basename "$DEP_PATH")
        echo "Copying dependency: ${DEP_NAME}"
        cp -f "$DEP_PATH" "${POSTGRES_FRAMEWORK_DIR}/Versions/A/"
        chmod +x "${POSTGRES_FRAMEWORK_DIR}/Versions/A/${DEP_NAME}"

        # Update references
        install_name_tool -change "$DEP_PATH" "@rpath/${FRAMEWORK_NAME}.framework/Versions/A/${DEP_NAME}" "${DYLIB_PATH}"
        install_name_tool -id "@rpath/${FRAMEWORK_NAME}.framework/Versions/A/${DEP_NAME}" "${POSTGRES_FRAMEWORK_DIR}/Versions/A/${DEP_NAME}"
    fi
done

# Copy Info.plist if available
SOURCE_PLIST="${SRCROOT}/Frameworks/${FRAMEWORK_NAME}.framework/Versions/A/Resources/Info.plist"
if [ -f "${SOURCE_PLIST}" ]; then
    mkdir -p "${POSTGRES_FRAMEWORK_DIR}/Versions/A/Resources"
    cp -f "${SOURCE_PLIST}" "${POSTGRES_FRAMEWORK_DIR}/Versions/A/Resources/"
    cd "${POSTGRES_FRAMEWORK_DIR}"
    ln -sf Versions/Current/Resources Resources
fi

# Sign the framework (for development)
if [ -n "${CODE_SIGN_IDENTITY}" ] && [ "${CODE_SIGN_IDENTITY}" != "-" ]; then
    echo "Signing framework..."
    codesign --force --sign "${CODE_SIGN_IDENTITY}" "${DYLIB_PATH}"
fi

echo "=== libpq embedding complete ==="
