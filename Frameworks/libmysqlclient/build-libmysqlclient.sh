#!/usr/bin/env bash
# shellcheck shell=bash
#
# Builds the bundled MySQL client — libmysqlclient.24.dylib, its public headers
# and the client-side authentication plugins — from the MySQL source tarball as
# universal arm64 + x86_64 binaries pinned to the app's deployment target, and
# copies them into "SPMySQLFramework/MySQL Client Libraries".
#
# Nothing comes from Homebrew. Every dependency is either bundled in the MySQL
# tarball (zlib, zstd, lz4, ICU, protobuf, libfido2, editline, libevent), part
# of the macOS SDK (SASL), or built by this repository's own recipes: the
# OpenSSL pair by build-openssl.sh (which this script runs when its output is
# missing), and CMake as the official Kitware universal binary, downloaded and
# checksummed into the scratch directory. Bison is not needed: the parser is
# server-only and the client build (WITHOUT_SERVER) never runs it.
#
# The x86_64 slice is cross-compiled on Apple silicon with the same toolchain;
# MySQL's build-time helper programs are compiled for the target architecture
# and run under Rosetta, so Rosetta must be installed on an arm64 host.
#
# Usage:  Frameworks/libmysqlclient/build-libmysqlclient.sh
#         (also what the libmysqlclient.xcodeproj target runs)
# Env:    MYSQL_BUILD_DIR     scratch directory (default: <this dir>/build/mysql)
#         OPENSSL_BUILD_DIR   build-openssl.sh's directory (default: <this dir>/build/openssl)
#         MYSQL_INCREMENTAL=1 reuse the per-architecture build directories
#                             instead of configuring from scratch
#
# Bumping MySQL: change MYSQL_VERSION and MYSQL_SHA256 together. Oracle
# publishes an MD5 next to the tarball on dev.mysql.com; MYSQL_MD5 pins it so
# the download can be matched against that page as well.

set -euo pipefail

MYSQL_VERSION="8.4.11"
MYSQL_SHA256="eb3051164d625dd346a8203f76e0d5d5d9aec51dbe9d51788e39ec6b3f1394c2"
MYSQL_MD5="7e36429318298eb05a79054309f18cb2"
CMAKE_VERSION="4.4.3"
CMAKE_SHA256="0c5d65251c14cc884bfa16bdbed3c263ce5bffe2e21c0d0d00962cb0610464fa"
# Keep in sync with MACOSX_DEPLOYMENT_TARGET in the Xcode projects and
# DEPLOYMENT_TARGET in build-openssl.sh.
DEPLOYMENT_TARGET="13.5"
ARCHS=(arm64 x86_64)

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
client_dir="$script_dir/../SPMySQLFramework/MySQL Client Libraries"
work_dir="${MYSQL_BUILD_DIR:-$script_dir/build/mysql}"
openssl_dir="${OPENSSL_BUILD_DIR:-$script_dir/build/openssl}"
mysql_tarball="mysql-$MYSQL_VERSION.tar.gz"
mysql_url="https://cdn.mysql.com/Downloads/MySQL-${MYSQL_VERSION%.*}/$mysql_tarball"
cmake_tarball="cmake-$CMAKE_VERSION-macos-universal.tar.gz"
cmake_url="https://github.com/Kitware/CMake/releases/download/v$CMAKE_VERSION/$cmake_tarball"

if [ ! -d "$client_dir/lib" ]; then
    echo "❌ Client library directory not found: $client_dir/lib"
    exit 1
fi

# Xcode exports these when the script runs as a build phase; none of them may
# leak into the MySQL configure step.
unset CFLAGS CXXFLAGS CPPFLAGS LDFLAGS SDKROOT ARCHS_STANDARD
export CC=/usr/bin/clang
export CXX=/usr/bin/clang++
export MACOSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET"
sysroot="$(xcrun --sdk macosx --show-sdk-path)"
ncpu="$(sysctl -n hw.ncpu)"

verify_sha256() {
    local file="$1" expected="$2" actual
    actual="$(shasum -a 256 "$file" | cut -d' ' -f1)"
    if [ "$actual" != "$expected" ]; then
        echo "❌ $(basename "$file") checksum mismatch: expected $expected, got $actual"
        exit 1
    fi
}

mkdir -p "$work_dir/downloads" "$work_dir/toolchain"
echo "***** MySQL $MYSQL_VERSION -> ${ARCHS[*]}, macOS $DEPLOYMENT_TARGET, work dir $work_dir *****"

# --- OpenSSL: the pair built by build-openssl.sh --------------------------
for arch in "${ARCHS[@]}"; do
    if [ ! -x "$openssl_dir/sdk-$arch/bin/openssl" ]; then
        echo "***** OpenSSL tree for $arch missing, running build-openssl.sh *****"
        OPENSSL_BUILD_DIR="$openssl_dir" "$script_dir/build-openssl.sh"
        break
    fi
done
for arch in "${ARCHS[@]}"; do
    for f in bin/openssl lib/libssl.3.dylib lib/libcrypto.3.dylib include/openssl/ssl.h; do
        if [ ! -e "$openssl_dir/sdk-$arch/$f" ]; then
            echo "❌ $openssl_dir/sdk-$arch/$f is missing; run build-openssl.sh"
            exit 1
        fi
    done
done

# --- CMake: the official universal binary ---------------------------------
cmake_bin="${CMAKE:-$work_dir/toolchain/cmake-$CMAKE_VERSION-macos-universal/CMake.app/Contents/bin/cmake}"
if [ ! -x "$cmake_bin" ]; then
    if [ ! -f "$work_dir/downloads/$cmake_tarball" ]; then
        echo "***** downloading $cmake_url *****"
        curl -fsSL -o "$work_dir/downloads/$cmake_tarball" "$cmake_url"
    fi
    verify_sha256 "$work_dir/downloads/$cmake_tarball" "$CMAKE_SHA256"
    tar -C "$work_dir/toolchain" -zxf "$work_dir/downloads/$cmake_tarball"
fi
echo "***** using $("$cmake_bin" --version | head -1) *****"

# --- MySQL source ----------------------------------------------------------
if [ ! -f "$work_dir/downloads/$mysql_tarball" ]; then
    echo "***** downloading $mysql_url *****"
    curl -fsSL -o "$work_dir/downloads/$mysql_tarball" "$mysql_url"
fi
verify_sha256 "$work_dir/downloads/$mysql_tarball" "$MYSQL_SHA256"
actual_md5="$(md5 -q "$work_dir/downloads/$mysql_tarball")"
if [ "$actual_md5" != "$MYSQL_MD5" ]; then
    echo "❌ $mysql_tarball MD5 mismatch against dev.mysql.com: expected $MYSQL_MD5, got $actual_md5"
    exit 1
fi
echo "***** checksums verified *****"
src="$work_dir/src-$MYSQL_VERSION"
if [ ! -f "$src/CMakeLists.txt" ]; then
    rm -rf "$src"
    mkdir -p "$src"
    tar -C "$src" --strip-components=1 -zxf "$work_dir/downloads/$mysql_tarball"
fi

# --- Per-architecture configure, build, install ---------------------------
for arch in "${ARCHS[@]}"; do
    build="$work_dir/build-$arch"
    install="$work_dir/install-$arch"
    if [ "${MYSQL_INCREMENTAL:-0}" != "1" ]; then
        rm -rf "$build"
    fi
    rm -rf "$install"
    mkdir -p "$build"

    # CMake derives CMAKE_SYSTEM_PROCESSOR from the host, so MySQL's own
    # APPLE_ARM flag stays on while cross-compiling x86_64 and the bundled
    # zstd then omits its x86_64 assembly yet still references it from C.
    # Disabling zstd's assembly for that slice keeps the C fallback path
    # (only InnoDB, which is server-only, reads APPLE_ARM otherwise).
    extra_c_flags=""
    if [ "$arch" = "x86_64" ] && [ "$(uname -m)" = "arm64" ]; then
        extra_c_flags="-DZSTD_DISABLE_ASM"
    fi

    echo "***** configuring $arch *****"
    # CMAKE_IGNORE_PREFIX_PATH keeps find_* away from Homebrew even though
    # /opt/homebrew/bin is usually on PATH; every WITH_* is bundled or points at
    # a tree this repository built. BUILD_CONFIG=mysql_release is Oracle's own
    # release configuration (RelWithDebInfo). Kerberos is off because the
    # bundle never shipped that plugin; the LDAP SASL plugin builds against the
    # SDK's libsasl2 without it.
    "$cmake_bin" -S "$src" -B "$build" -G "Unix Makefiles" \
        -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
        -DCMAKE_C_FLAGS="$extra_c_flags" \
        -DCMAKE_OSX_ARCHITECTURES="$arch" -DCMAKE_SYSTEM_PROCESSOR="$arch" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" -DCMAKE_OSX_SYSROOT="$sysroot" \
        -DCMAKE_INSTALL_PREFIX="$install" -DINSTALL_LAYOUT=STANDALONE \
        -DCMAKE_IGNORE_PREFIX_PATH="/opt/homebrew;/usr/local" \
        -DBUILD_CONFIG=mysql_release -DWITHOUT_SERVER=ON -DWITH_UNIT_TESTS=OFF \
        -DWITH_SSL="$openssl_dir/sdk-$arch" \
        -DWITH_ZLIB=bundled -DWITH_ZSTD=bundled -DWITH_LZ4=bundled -DWITH_ICU=bundled \
        -DWITH_PROTOBUF=bundled -DWITH_FIDO=bundled -DWITH_EDITLINE=bundled \
        -DWITH_LIBEVENT=bundled -DWITH_KERBEROS=none \
        -DWITH_AUTHENTICATION_CLIENT_PLUGINS=ON -DWITH_AUTHENTICATION_LDAP=ON \
        -DWITH_AUTHENTICATION_WEBAUTHN=ON \
        -DENABLED_LOCAL_INFILE=ON -DWITH_EXTRA_CHARSETS=all \
        > "$work_dir/configure-$arch.log" 2>&1
    echo "***** building $arch (log: $work_dir/build-$arch.log) *****"
    "$cmake_bin" --build "$build" --target install --parallel "$ncpu" > "$work_dir/build-$arch.log" 2>&1

    for f in lib/libmysqlclient.24.dylib include/mysql.h include/mysql_version.h; do
        if [ ! -f "$install/$f" ]; then
            echo "❌ $arch build did not produce $f (see $work_dir/build-$arch.log)"
            exit 1
        fi
    done
    if ! ls "$install/lib/plugin/"*.so >/dev/null 2>&1; then
        echo "❌ $arch build produced no client plugins in $install/lib/plugin"
        exit 1
    fi
    if [ ! -f "$install/lib/libfido2.1.dylib" ]; then
        echo "❌ $arch build did not produce the bundled libfido2.1.dylib"
        exit 1
    fi
done

# The headers are architecture-independent by construction; prove it rather
# than assume it before shipping one copy.
if ! diff -r "$work_dir/install-arm64/include" "$work_dir/install-x86_64/include" > "$work_dir/include-diff.log"; then
    echo "❌ arm64 and x86_64 headers differ (see $work_dir/include-diff.log)"
    exit 1
fi

# --- Universal binaries ----------------------------------------------------
universal="$work_dir/universal"
rm -rf "$universal"
mkdir -p "$universal/plugin"
cd "$universal"

echo "***** creating universal libraries *****"
slices=()
for arch in "${ARCHS[@]}"; do slices+=("$work_dir/install-$arch/lib/libmysqlclient.24.dylib"); done
lipo -create -output libmysqlclient.24.dylib "${slices[@]}"
for plugin_path in "$work_dir/install-arm64/lib/plugin/"*.so; do
    plugin="$(basename "$plugin_path")"
    slices=()
    for arch in "${ARCHS[@]}"; do
        if [ ! -f "$work_dir/install-$arch/lib/plugin/$plugin" ]; then
            echo "❌ $plugin was built for arm64 but not for $arch"
            exit 1
        fi
        slices+=("$work_dir/install-$arch/lib/plugin/$plugin")
    done
    lipo -create -output "plugin/$plugin" "${slices[@]}"
done
# The WebAuthn plugin loads the bundled libfido2 as @loader_path/libfido2.1.dylib,
# so the library ships next to the plugins. (lib/libfido2.1.dylib is the real
# file; the other libfido2 names in lib/ are symlinks to it.)
slices=()
for arch in "${ARCHS[@]}"; do slices+=("$work_dir/install-$arch/lib/libfido2.1.dylib"); done
lipo -create -output plugin/libfido2.1.dylib "${slices[@]}"

# Rewrites every reference to the OpenSSL pair in $1 to $2/<lib>, whatever
# absolute or relative path the link step recorded.
retarget_openssl() {
    local file="$1" prefix="$2" lib old
    for lib in libssl.3.dylib libcrypto.3.dylib; do
        while IFS= read -r old; do
            [ -z "$old" ] && continue
            [ "$old" = "$prefix/$lib" ] && continue
            install_name_tool -change "$old" "$prefix/$lib" "$file" 2>&1 | grep -v "invalidate the code signature" || true
        done < <(otool -L "$file" | grep '^	' | awk -v lib="$lib" 'index($1, lib) { print $1 }' | sort -u)
    done
}

echo "***** fixing install names *****"
# The client library sits next to the OpenSSL pair inside SPMySQL.framework's
# Versions/A; the plugins load from Versions/A/PlugIns (MYSQL_PLUGIN_DIR is set
# to builtInPlugInsPath), one level below the dylibs.
install_name_tool -id "@loader_path/libmysqlclient.24.dylib" libmysqlclient.24.dylib 2>&1 | grep -v "invalidate the code signature" || true
retarget_openssl libmysqlclient.24.dylib "@loader_path"
install_name_tool -id "@loader_path/libfido2.1.dylib" plugin/libfido2.1.dylib 2>&1 | grep -v "invalidate the code signature" || true
retarget_openssl plugin/libfido2.1.dylib "@loader_path/.."
for plugin_path in plugin/*.so; do
    retarget_openssl "$plugin_path" "@loader_path/.."
done
# dyld refuses an unsigned arm64 image, and install_name_tool has invalidated
# the linker's ad-hoc signatures; Xcode re-signs on copy when signing is on.
codesign --force --sign - libmysqlclient.24.dylib plugin/*.so plugin/libfido2.1.dylib

# --- Verification ----------------------------------------------------------
echo "***** verifying *****"
status=0
check_binary() {
    local file="$1" archs minos arch
    archs="$(lipo -archs "$file")"
    for arch in "${ARCHS[@]}"; do
        case " $archs " in *" $arch "*) ;; *) echo "❌ $file is missing the $arch slice ($archs)"; status=1 ;; esac
        minos="$(otool -arch "$arch" -l "$file" | awk '/LC_BUILD_VERSION/ { in_cmd = 1 } in_cmd && /minos/ { print $2; exit }')"
        if [ "$minos" != "$DEPLOYMENT_TARGET" ]; then
            echo "❌ $file ($arch): minimum macOS is '$minos', expected $DEPLOYMENT_TARGET"
            status=1
        fi
    done
    # Anything outside the bundle, the SDK or the loader-relative names would
    # break on a machine without this build tree or without Homebrew.
    # Dependency lines are tab-indented; the others are the per-architecture
    # headers otool prints for a fat file.
    if otool -L "$file" | grep '^	' | awk '{ print $1 }' | grep -vE '^(@loader_path/|/usr/lib/|/System/Library/)' | grep -q .; then
        echo "❌ $file links something outside the bundle and the OS:"
        otool -L "$file" | grep '^	' | awk '{ print "     " $1 }' | grep -vE '^ +(@loader_path/|/usr/lib/|/System/Library/)'
        status=1
    fi
    if ! codesign --verify "$file" 2>/dev/null; then
        echo "❌ $file: code signature missing or invalid"
        status=1
    fi
}
check_binary libmysqlclient.24.dylib
check_binary plugin/libfido2.1.dylib
for plugin_path in plugin/*.so; do check_binary "$plugin_path"; done
fido_id="$(otool -D plugin/libfido2.1.dylib | sed -n '2p')"
if [ "$fido_id" != "@loader_path/libfido2.1.dylib" ]; then
    echo "❌ libfido2.1.dylib: install name is '$fido_id'"
    status=1
fi
id="$(otool -D libmysqlclient.24.dylib | sed -n '2p')"
if [ "$id" != "@loader_path/libmysqlclient.24.dylib" ]; then
    echo "❌ libmysqlclient.24.dylib: install name is '$id'"
    status=1
fi
version_hits="$(strings -a libmysqlclient.24.dylib | grep -c "^$MYSQL_VERSION$" || true)"
if [ "$version_hits" -eq 0 ]; then
    echo "❌ libmysqlclient.24.dylib does not carry the $MYSQL_VERSION version string"
    status=1
fi
if ! grep -q "\"$MYSQL_VERSION\"" "$work_dir/install-arm64/include/mysql_version.h"; then
    echo "❌ mysql_version.h does not declare $MYSQL_VERSION"
    status=1
fi
if [ "$status" -ne 0 ]; then
    echo "❌ verification failed; nothing copied"
    exit 1
fi
otool -L libmysqlclient.24.dylib plugin/*.so plugin/libfido2.1.dylib

# --- Copy into the framework ----------------------------------------------
echo "***** copying to $client_dir *****"
cp libmysqlclient.24.dylib "$client_dir/lib/"
rsync -a --delete "$work_dir/install-arm64/include/" "$client_dir/include/"
rm -rf "$client_dir/lib/mysqlplugins"
mkdir -p "$client_dir/lib/mysqlplugins"
cp plugin/*.so plugin/libfido2.1.dylib "$client_dir/lib/mysqlplugins/"
echo "***** done: libmysqlclient $MYSQL_VERSION, $(ls plugin/*.so | wc -l | tr -d ' ') plugins + libfido2 *****"
