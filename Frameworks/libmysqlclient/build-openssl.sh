#!/usr/bin/env bash
# shellcheck shell=bash
#
# Rebuilds the bundled OpenSSL (libssl.3.dylib + libcrypto.3.dylib) from source
# as universal arm64 + x86_64 dylibs pinned to the app's deployment target, and
# copies them into "SPMySQLFramework/MySQL Client Libraries/lib".
#
# Why a source build: build-libmysqlclient.sh takes OpenSSL from Homebrew, and
# Homebrew bottles are compiled for the *host* macOS release (the 3.4.1 pair
# that shipped before this script was arm64 minos 15.0 / x86_64 minos 14.0).
# That is what produced the "building for macOS-13.5, but linking with dylib
# 'libssl.3.dylib' which was built for newer version 15.0" linker warnings.
# Only a source build can set the minimum to 13.5.
#
# Configure flags mirror Homebrew's openssl@3 formula (no-ssl3, no-ssl3-method,
# no-zlib, --libdir=lib) and its per-architecture --prefix / --openssldir, so
# the only intended differences from the previous binaries are the OpenSSL
# version and the deployment target. The install names are set to
# @loader_path/<lib> directly: SPMySQL re-exports both dylibs, and ld warns
# when a re-exported library's own install name differs from the one recorded
# in its parent, which is what happened with the bare "libssl.3.dylib" id.
#
# Usage:  Frameworks/libmysqlclient/build-openssl.sh
# Env:    OPENSSL_BUILD_DIR   scratch directory (default: <this dir>/build/openssl)
#
# Bumping OpenSSL: change OPENSSL_VERSION *and* OPENSSL_SHA256 together. The
# checksum is the one published next to the tarball at
# https://github.com/openssl/openssl/releases/tag/openssl-<version>.

set -euo pipefail

OPENSSL_VERSION="3.5.8"
OPENSSL_SHA256="a8f84a39918ec6415ce765d9b429d313ba97b8143169c172e734b9514464f5b2"
# Keep in sync with MACOSX_DEPLOYMENT_TARGET in the Xcode projects and the
# -mmacosx-version-min in build-libmysqlclient.sh.
DEPLOYMENT_TARGET="13.5"
ARCHS=(arm64 x86_64)

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lib_dir="$script_dir/../SPMySQLFramework/MySQL Client Libraries/lib"
work_dir="${OPENSSL_BUILD_DIR:-$script_dir/build/openssl}"
tarball="openssl-$OPENSSL_VERSION.tar.gz"
tarball_url="https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/$tarball"

if [ ! -d "$lib_dir" ]; then
    echo "❌ Library directory not found: $lib_dir"
    exit 1
fi

# Homebrew's prefix / openssldir per architecture. OPENSSLDIR is baked into
# libcrypto (default cert and config lookup) and MODULESDIR derives from the
# prefix; both are kept identical to the previous binaries on purpose.
brew_prefix_for() {
    case "$1" in
        arm64)  echo "/opt/homebrew/opt/openssl@3" ;;
        x86_64) echo "/usr/local/opt/openssl@3" ;;
        *) echo "❌ Unsupported architecture: $1" >&2; exit 1 ;;
    esac
}
openssldir_for() {
    case "$1" in
        arm64)  echo "/opt/homebrew/etc/openssl@3" ;;
        x86_64) echo "/usr/local/etc/openssl@3" ;;
        *) echo "❌ Unsupported architecture: $1" >&2; exit 1 ;;
    esac
}

export CC=/usr/bin/clang
export MACOSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET"
ncpu="$(sysctl -n hw.ncpu)"

mkdir -p "$work_dir"
cd "$work_dir"

echo "***** OpenSSL $OPENSSL_VERSION -> ${ARCHS[*]}, macOS $DEPLOYMENT_TARGET, work dir $work_dir *****"

if [ ! -f "$tarball" ]; then
    echo "***** downloading $tarball_url *****"
    curl -fsSL -o "$tarball" "$tarball_url"
fi
actual_sha="$(shasum -a 256 "$tarball" | cut -d' ' -f1)"
if [ "$actual_sha" != "$OPENSSL_SHA256" ]; then
    echo "❌ $tarball checksum mismatch: expected $OPENSSL_SHA256, got $actual_sha"
    exit 1
fi
echo "***** checksum verified *****"

for arch in "${ARCHS[@]}"; do
    src="$work_dir/src-$arch"
    dest="$work_dir/dest-$arch"
    prefix="$(brew_prefix_for "$arch")"
    openssldir="$(openssldir_for "$arch")"

    rm -rf "$src" "$dest"
    mkdir -p "$src"
    tar -C "$src" --strip-components=1 -zxf "$tarball"

    echo "***** configuring $arch (prefix $prefix) *****"
    (
        cd "$src"
        perl ./Configure "darwin64-$arch-cc" \
            --prefix="$prefix" \
            --openssldir="$openssldir" \
            --libdir=lib \
            shared no-ssl3 no-ssl3-method no-zlib no-tests \
            "-mmacosx-version-min=$DEPLOYMENT_TARGET" > "$work_dir/configure-$arch.log" 2>&1
        echo "***** building $arch *****"
        make -j "$ncpu" build_libs > "$work_dir/build-$arch.log" 2>&1
        # install_dev = headers + libraries only (no apps, no docs, no engines
        # or providers, which the bundle does not ship). DESTDIR keeps the
        # Homebrew-shaped prefix out of the real filesystem.
        make install_dev DESTDIR="$dest" > "$work_dir/install-$arch.log" 2>&1
    )
    for lib in libssl.3.dylib libcrypto.3.dylib; do
        if [ ! -f "$dest$prefix/lib/$lib" ]; then
            echo "❌ $arch build did not produce $lib (see $work_dir/*-$arch.log)"
            exit 1
        fi
    done
done

universal="$work_dir/universal"
rm -rf "$universal"
mkdir -p "$universal"
cd "$universal"

echo "***** creating universal libraries *****"
for lib in libcrypto.3.dylib libssl.3.dylib; do
    slices=()
    for arch in "${ARCHS[@]}"; do
        slices+=("$work_dir/dest-$arch$(brew_prefix_for "$arch")/lib/$lib")
    done
    lipo -create -output "$lib" "${slices[@]}"
done

echo "***** fixing install names *****"
# install_name_tool invalidates the linker's ad-hoc signature on the arm64
# slice, so both libraries are ad-hoc signed again afterwards: dyld refuses an
# unsigned arm64 dylib ("missing code signature"), which matters for builds
# that run with CODE_SIGNING_ALLOWED=NO such as the unit-test schemes. Xcode
# re-signs on copy when signing is on.
install_name_tool -id "@loader_path/libcrypto.3.dylib" libcrypto.3.dylib 2>&1 | grep -v "invalidate the code signature" || true
install_name_tool -id "@loader_path/libssl.3.dylib" libssl.3.dylib 2>&1 | grep -v "invalidate the code signature" || true
while IFS= read -r old; do
    [ -z "$old" ] && continue
    echo "libssl.3.dylib: $old -> @loader_path/libcrypto.3.dylib"
    install_name_tool -change "$old" "@loader_path/libcrypto.3.dylib" libssl.3.dylib 2>&1 | grep -v "invalidate the code signature" || true
done < <(otool -L libssl.3.dylib | awk '/libcrypto\.3\.dylib/ && !/@loader_path/ { print $1 }' | sort -u)
codesign --force --sign - libcrypto.3.dylib libssl.3.dylib

echo "***** verifying *****"
status=0
for lib in libcrypto.3.dylib libssl.3.dylib; do
    archs="$(lipo -archs "$lib")"
    for arch in "${ARCHS[@]}"; do
        case " $archs " in *" $arch "*) ;; *) echo "❌ $lib is missing the $arch slice ($archs)"; status=1 ;; esac
        minos="$(otool -arch "$arch" -l "$lib" | awk '/LC_BUILD_VERSION/ { in_cmd = 1 } in_cmd && /minos/ { print $2; exit }')"
        if [ "$minos" != "$DEPLOYMENT_TARGET" ]; then
            echo "❌ $lib ($arch): minimum macOS is '$minos', expected $DEPLOYMENT_TARGET"
            status=1
        fi
    done
    id="$(otool -D "$lib" | sed -n '2p')"
    if [ "$id" != "@loader_path/$lib" ]; then
        echo "❌ $lib: install name is '$id', expected @loader_path/$lib"
        status=1
    fi
done
# Only libcrypto embeds the version banner. Counted rather than grep -q: under
# pipefail an early grep exit would fail the pipeline and invert the test.
version_hits="$(strings -a libcrypto.3.dylib | grep -c "^OpenSSL $OPENSSL_VERSION " || true)"
if [ "$version_hits" -eq 0 ]; then
    echo "❌ libcrypto.3.dylib: does not carry the OpenSSL $OPENSSL_VERSION version string"
    status=1
fi
stray_crypto="$(otool -L libssl.3.dylib | awk '/libcrypto\.3\.dylib/ && !/@loader_path/' | grep -c . || true)"
if [ "$stray_crypto" -ne 0 ]; then
    echo "❌ libssl.3.dylib still references libcrypto by an absolute path"
    status=1
fi
for lib in libcrypto.3.dylib libssl.3.dylib; do
    if ! codesign --verify "$lib" 2>/dev/null; then
        echo "❌ $lib: code signature missing or invalid"
        status=1
    fi
done
if [ "$status" -ne 0 ]; then
    echo "❌ verification failed; nothing copied"
    exit 1
fi
otool -L libssl.3.dylib libcrypto.3.dylib

echo "***** copying to $lib_dir *****"
# Copy to a temporary name and rename, so a build reading the directory at
# the same time never sees a half-written dylib.
for lib in libcrypto.3.dylib libssl.3.dylib; do
    cp "$lib" "$lib_dir/.$lib.tmp"
    mv -f "$lib_dir/.$lib.tmp" "$lib_dir/$lib"
done
echo "***** done *****"
