#!/usr/bin/env bash
# shellcheck shell=bash
#set | grep ARCH

# ARCHS='arm64 x86_64'
unset CFLAGS
# set -x

## Determine the appropriate openssl source path to use
## Introduced by michaeltyson, adapted to account for OPENSSL_SRC build path

# locate src archive file if present
SRC_ARCHIVE=$(ls openssl*tar.gz 2>/dev/null)
mkdir -p "$TARGET_BUILD_DIR"

# if there is an openssl directory immediately under the openssl.xcode source
# folder then build there
if [ -d "$SRCROOT/openssl" ]; then
    OPENSSL_SRC="$SRCROOT/openssl"
# else, if there is a openssl.tar.gz in the directory, expand it to openssl
# and use it
elif [ -f "$SRC_ARCHIVE" ]; then
    OPENSSL_SRC="$PROJECT_TEMP_DIR/openssl"
    if [ ! -d "$OPENSSL_SRC" ]; then
        echo "extracting $SRC_ARCHIVE..."
        mkdir "$OPENSSL_SRC"
        tar -C "$OPENSSL_SRC" --strip-components=1 -zxf "$SRC_ARCHIVE" || exit 1
        cp -RL "$OPENSSL_SRC/include" "$TARGET_BUILD_DIR"
    fi
elif [ ! -f "$SRC_ARCHIVE" ]; then
    echo "***** Download openssl src from https://www.openssl.org/source and place in Frameworks/openssl *****"
    exit 1;
fi
echo "About to CP"
echo "$SRCROOT"
echo "$OPENSSL_SRC"

mkdir -p "$OPENSSL_SRC"/Configurations/
cp -f "$SRCROOT"/10-main.conf "$OPENSSL_SRC"/Configurations/ || exit 1

echo "***** using $OPENSSL_SRC for openssl source code  *****"

# check whether libcrypto.1.1.dylib already exists - we'll only build if it does not
if [ -f  "$TARGET_BUILD_DIR/libcrypto.1.1.dylib" ]; then
    echo "***** Using previously-built libary $TARGET_BUILD_DIR/libcrypto.1.1.dylib - skipping build *****"
    echo "***** To force a rebuild clean project and clean dependencies *****"
    exit 0;
else
    echo "***** No previously-built libary present at $TARGET_BUILD_DIR/libcrypto.1.1.dylib - performing build *****"
fi

BUILDARCHS="darwin64-x86_64-cc"

# sw_vers -productVersion can return
# 11.0.0 or 10.16 depending on version of
# big sur or setting of SYSTEM_VERSION_COMPAT
# so we'll check for both
# c.f. https://eclecticlight.co/2020/08/13/macos-version-numbering-isnt-so-simple/

IS_12=$(sw_vers -productVersion | grep -o '12.[0-9]*')
IS_11=$(sw_vers -productVersion | grep -o '11.[0-9]*')
IS_16=$(sw_vers -productVersion | grep -o '10.16.[0-9]*')

IS_AT_LEAST_BIG_SUR=0
if  [ -n "$IS_12" ] || [ -n "$IS_11" ] || [ -n "$IS_16" ]; then
    IS_AT_LEAST_BIG_SUR=1
fi

if [[ $IS_AT_LEAST_BIG_SUR -gt 0 ]]; then
    echo "is at least big sur"
    BUILDARCHS="darwin64-arm64-cc darwin64-x86_64-cc"
fi

echo "***** creating universal binary for architectures: $BUILDARCHS *****"

if [ "$SDKROOT" != "" ]; then
    ISYSROOT="-isysroot $SDKROOT"
fi

echo "***** using ISYSROOT $ISYSROOT *****"

OPENSSL_OPTIONS=""

echo "***** using OPENSSL_OPTIONS $OPENSSL_OPTIONS *****"

echo "$OPENSSL_SRC"
echo "$BUILD_DIR"

cd "$OPENSSL_SRC" || exit 1;

if [[ $IS_AT_LEAST_BIG_SUR -gt 0 ]]; then
    echo "***** BUILDING UNIVERSAL ARCH darwin64-arm64-cc ******"
    
    ./Configure darwin64-arm64-cc no-asm -openssldir="$OPENSSL_SRC" --prefix="$BUILD_DIR"
    
    make -j "$(sysctl -n hw.ncpu)" CFLAG="-D_DARWIN_C_SOURCE $ASM_DEF -arch arm64 $ISYSROOT -Wno-unused-value -Wno-parentheses" SHARED_LDFLAGS="-arch arm64 -dynamiclib"
    
    echo "***** copying intermediate libraries to $CONFIGURATION_TEMP_DIR/arm64-*.a *****"
    cp libcrypto.a "$CONFIGURATION_TEMP_DIR"/arm64-libcrypto.a
    cp libssl.a "$CONFIGURATION_TEMP_DIR"/arm64-libssl.a
    
    cp libcrypto.1.1.dylib "$CONFIGURATION_TEMP_DIR"/arm64-libcrypto.1.1.dylib
    cp libssl.1.1.dylib "$CONFIGURATION_TEMP_DIR"/arm64-libssl.1.1.dylib
fi

echo "***** BUILDING UNIVERSAL ARCH darwin64-x86_64-cc ******"
make clean

./Configure darwin64-x86_64-cc -openssldir="$OPENSSL_SRC" --prefix="$BUILD_DIR"

make -j "$(sysctl -n hw.ncpu)" CFLAG="-D_DARWIN_C_SOURCE $ASM_DEF -arch x86_64 $ISYSROOT" SHARED_LDFLAGS="-arch x86_64 -dynamiclib"

echo "***** copying intermediate libraries to $CONFIGURATION_TEMP_DIR/x86_64-*.a *****"
cp libcrypto.a "$CONFIGURATION_TEMP_DIR"/x86_64-libcrypto.a
cp libssl.a "$CONFIGURATION_TEMP_DIR"/x86_64-libssl.a
cp libcrypto.1.1.dylib "$CONFIGURATION_TEMP_DIR"/x86_64-libcrypto.1.1.dylib
cp libssl.1.1.dylib "$CONFIGURATION_TEMP_DIR"/x86_64-libssl.1.1.dylib

mkdir -p "$TARGET_BUILD_DIR"

if [[ $IS_AT_LEAST_BIG_SUR -gt 0 ]]; then
    echo "***** creating universallibraries in $TARGET_BUILD_DIR *****"
    lipo -create "$CONFIGURATION_TEMP_DIR/"*-libcrypto.1.1.dylib -output "$TARGET_BUILD_DIR/libcrypto.1.1.dylib"
    lipo -create "$CONFIGURATION_TEMP_DIR/"*-libssl.1.1.dylib -output "$TARGET_BUILD_DIR/libssl.1.1.dylib"
else
    echo "***** copying libraries to $TARGET_BUILD_DIR *****"
    cp "$CONFIGURATION_TEMP_DIR"/x86_64-libcrypto.1.1.dylib "$TARGET_BUILD_DIR/libcrypto.1.1.dylib"
    cp "$CONFIGURATION_TEMP_DIR"/x86_64-libssl.1.1.dylib "$TARGET_BUILD_DIR/libssl.1.1.dylib"
fi

echo "***** removing temporary files from $CONFIGURATION_TEMP_DIR *****"
rm -f "$CONFIGURATION_TEMP_DIR/"*-libcrypto.*
rm -f "$CONFIGURATION_TEMP_DIR/"*-libssl.*
