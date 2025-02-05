#!/usr/bin/env bash
# shellcheck shell=bash
#set | grep ARCH

# ARCHS='arm64 x86_64'
unset CFLAGS

echo "TARGET BUILD DIR = $TARGET_BUILD_DIR"
echo "SRCROOT = $SRCROOT"

# set -x

## Determine the appropriate mysql source path to use
## Introduced by michaeltyson, adapted to account for MYSQL_SRC build path

# locate src archive file if present
SRC_ARCHIVE=$(ls mysql*tar.gz 2>/dev/null)

# if there is a mysql.tar.gz in the directory, expand it to mysql and use it
if [ -f "$SRC_ARCHIVE" ]; then
    MYSQL_SRC="$PROJECT_TEMP_DIR/mysql"
    if [ ! -d "$MYSQL_SRC" ]; then
        echo "extracting $SRC_ARCHIVE..."
        mkdir "$MYSQL_SRC"
        tar -C "$MYSQL_SRC" --strip-components=1 -zxf "$SRC_ARCHIVE" || exit 1
        cp -RL "$MYSQL_SRC/include" "$TARGET_BUILD_DIR"
    fi
elif [ ! -f "$SRC_ARCHIVE" ]; then
    echo "***** Download mysql src from https://dev.mysql.com/downloads/mysql/ and place in Frameworks/libmysql *****"
    exit 1;
fi


echo "***** using $MYSQL_SRC for mysql source code  *****"

# check whether libmysqlclient.a already exists - we'll only build if it does not
if [ -f  "$TARGET_BUILD_DIR/libmysqlclient.24.dylib" ]; then
    echo "***** Using previously-built library $TARGET_BUILD_DIR/libmysqlclient.24.dylib - skipping build *****"
    echo "***** To force a rebuild clean project and clean dependencies *****"
    exit 0;
else
    echo "***** No previously-built library present at $TARGET_BUILD_DIR/libmysqlclient.24.dylib - performing build *****"
fi

export CC=/usr/bin/clang
export CXX=/usr/bin/clang++

cd $MYSQL_SRC

mkdir -p $BUILD_DIR/x86_64 $BUILD_DIR/arm64 $BUILD_DIR/universal


# Check that we have HomeBrew installed
which -s /usr/local/bin/brew 
if [[ $? != 0 ]] ; then
    # Install Homebrew if missing
    arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
# Check that we have HomeBrew installed
which -s /opt/homebrew/bin/brew
if [[ $? != 0 ]] ; then
    # Install Homebrew if missing
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

rm -rf $BUILD_DIR/arm64
mkdir -p $BUILD_DIR/arm64
/opt/homebrew/bin/brew install icu4c googletest bison cmake lz4 zlib llvm openssl@3
export MACOSX_DEPLOYMENT_TARGET=11.0
export OPENSSL_ROOT_DIR=$(/opt/homebrew/bin/brew --prefix openssl@3)
export OPENSSL_LIB_DIR=$(/opt/homebrew/bin/brew --prefix openssl@3)"/lib"
export OPENSSL_INCLUDE_DIR=$(/opt/homebrew/bin/brew --prefix openssl@3)"/include"

/opt/homebrew/bin/cmake -S . -B $BUILD_DIR/arm64 \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_SYSTEM_PROCESSOR=arm64 \
    -DCMAKE_OSX_SYSROOT=$(xcrun --sdk macosx --show-sdk-path) \
    -DCMAKE_CXX_FLAGS="-stdlib=libc++ -nostdinc++ -I/opt/homebrew/opt/llvm/include/c++/v1 -mmacosx-version-min=11.0" \
    -DCMAKE_INSTALL_PREFIX=$BUILD_DIR/arm64/install \
    -DCMAKE_PREFIX_PATH="/opt/homebrew/opt/gtest;/opt/homebrew/opt/icu4c;/opt/homebrew/opt/openssl" \
    -DBISON_EXECUTABLE=/opt/homebrew/opt/bison/bin/bison \
    -DWITH_SSL=/opt/homebrew/opt/openssl@3 \
    -DOPENSSL_ROOT_DIR=/opt/homebrew/opt/openssl@3 \
    -DOPENSSL_LIBRARIES=/opt/homebrew/opt/openssl@3/lib \
    -DOPENSSL_INCLUDE_DIR=/opt/homebrew/opt/openssl@3/include \
    -DDOWNLOAD_BOOST=1 -DWITH_BOOST=boost_directory -DBUILD_CONFIG=mysql_release -DENABLED_LOCAL_INFILE=1  -DWITH_MYSQLD_LDFLAGS="-all-static --disable-shared" -DWITHOUT_SERVER=1 -DWITH_ZLIB=system -DWITH_UNIT_TESTS=0 \
    -DDISABLE_SHARED=1 \
    -DWITH_AUTHENTICATION_CLIENT_PLUGINS=yes \
    -DWITH_AUTHENTICATION_PLUGIN=ALL \
    -DWITH_INSECURE_AUTH=ON \
    -DWITH_OLD_PASSWORD=ON \
    -DENABLED_LOCAL_INFILE=ON \
    -DWITH_COMPRESSION=ON \
    -DWITH_ZLIB=bundled \
    -DWITH_INNODB_MEMCACHED=ON \
    -DWITH_PARTITION_STORAGE_ENGINE=ON \
    -DWITH_INNODB_STORAGE_ENGINE=ON \
    -DWITH_ARCHIVE_STORAGE_ENGINE=ON \
    -DWITH_BLACKHOLE_STORAGE_ENGINE=ON \
    -DWITH_FEDERATED_STORAGE_ENGINE=ON \
    -DWITH_PERFSCHEMA_STORAGE_ENGINE=ON \
    -DWITH_TOKUDB_STORAGE_ENGINE=ON \
    -DWITH_EXTRA_CHARSETS=all
# Check if CMake succeeded
if [ $? -ne 0 ]; then
    echo "❌ CMake failed! Aborting build process."
    exit 1
fi

/opt/homebrew/bin/cmake --build $BUILD_DIR/arm64 --target install --parallel $(sysctl -n hw.ncpu)
# Check if CMake succeeded
if [ $? -ne 0 ]; then
    echo "❌ CMake failed! Aborting build process."
    exit 1
fi

rm -rf $BUILD_DIR/x86_64
mkdir -p $BUILD_DIR/x86_64
arch -x86_64 /usr/local/bin/brew install icu4c googletest bison cmake lz4 zlib llvm openssl@3
mkdir -p /usr/local/mysql/lib/private
export MACOSX_DEPLOYMENT_TARGET=10.13
export OPENSSL_ROOT_DIR=$(/usr/local/bin/brew --prefix openssl@3)
export OPENSSL_LIB_DIR=$(/usr/local/bin/brew --prefix openssl@3)"/lib"
export OPENSSL_INCLUDE_DIR=$(/usr/local/bin/brew --prefix openssl@3)"/include"

arch -x86_64 /usr/local/bin/cmake -S . -B $BUILD_DIR/x86_64 \
    -DCMAKE_OSX_ARCHITECTURES=x86_64 \
    -DCMAKE_SYSTEM_PROCESSOR=x86_64 \
    -DCMAKE_OSX_SYSROOT=$(xcrun --sdk macosx --show-sdk-path) \
    -DCMAKE_CXX_FLAGS="-stdlib=libc++ -nostdinc++ -I/usr/local/opt/llvm/include/c++/v1 -mmacosx-version-min=10.13" \
    -DCMAKE_INSTALL_PREFIX=$BUILD_DIR/x86_64/install \
    -DCMAKE_PREFIX_PATH="/usr/local/gtest_x86_64;/usr/local/icu_x86_64" \
    -DBISON_EXECUTABLE=/usr/local/opt/bison/bin/bison \
    -DWITH_SSL=/usr/local/opt/openssl@3 \
    -DOPENSSL_ROOT_DIR=/usr/local/opt/openssl@3 \
    -DOPENSSL_LIBRARIES=/usr/local/opt/openssl@3/lib \
    -DOPENSSL_INCLUDE_DIR=/usr/local/opt/openssl@3/include \
    -DDOWNLOAD_BOOST=1 -DWITH_BOOST=boost_directory -DBUILD_CONFIG=mysql_release -DENABLED_LOCAL_INFILE=1  -DWITH_MYSQLD_LDFLAGS="-all-static --disable-shared" -DWITHOUT_SERVER=1 -DWITH_ZLIB=system -DWITH_UNIT_TESTS=0 \
    -DDISABLE_SHARED=1 \
    -DWITH_AUTHENTICATION_CLIENT_PLUGINS=yes \
    -DWITH_AUTHENTICATION_PLUGIN=ALL \
    -DWITH_INSECURE_AUTH=ON \
    -DWITH_OLD_PASSWORD=ON \
    -DENABLED_LOCAL_INFILE=ON \
    -DWITH_COMPRESSION=ON \
    -DWITH_ZLIB=bundled \
    -DWITH_INNODB_MEMCACHED=ON \
    -DWITH_PARTITION_STORAGE_ENGINE=ON \
    -DWITH_INNODB_STORAGE_ENGINE=ON \
    -DWITH_ARCHIVE_STORAGE_ENGINE=ON \
    -DWITH_BLACKHOLE_STORAGE_ENGINE=ON \
    -DWITH_FEDERATED_STORAGE_ENGINE=ON \
    -DWITH_PERFSCHEMA_STORAGE_ENGINE=ON \
    -DWITH_TOKUDB_STORAGE_ENGINE=ON \
    -DWITH_EXTRA_CHARSETS=all
# Check if CMake succeeded
if [ $? -ne 0 ]; then
    echo "❌ CMake failed! Aborting build process."
    exit 1
fi

arch -x86_64 /usr/local/bin/cmake --build $BUILD_DIR/x86_64 --target install --parallel $(sysctl -n hw.ncpu)
# Check if CMake succeeded
if [ $? -ne 0 ]; then
    echo "❌ CMake failed! Aborting build process."
    exit 1
fi

echo "***** creating universallibraries in $TARGET_BUILD_DIR *****"
lipo -create -output $TARGET_BUILD_DIR/libmysqlclient.24.dylib \
    $BUILD_DIR/x86_64/install/lib/libmysqlclient.24.dylib \
    $BUILD_DIR/arm64/install/lib/libmysqlclient.24.dylib

lipo -create -output $TARGET_BUILD_DIR/libcrypto.3.dylib \
    $BUILD_DIR/x86_64/install/lib/libcrypto.3.dylib \
    $BUILD_DIR/arm64/install/lib/libcrypto.3.dylib

lipo -create -output $TARGET_BUILD_DIR/libssl.3.dylib \
    $BUILD_DIR/x86_64/install/lib/libssl.3.dylib \
    $BUILD_DIR/arm64/install/lib/libssl.3.dylib

# lipo -create -output $TARGET_BUILD_DIR/libprotobuf-lite.24.4.0.dylib \
#     $BUILD_DIR/x86_64/install/lib/libprotobuf-lite.24.4.0.dylib \
#     $BUILD_DIR/arm64/install/lib/libprotobuf-lite.24.4.0.dylib

# lipo -create -output $TARGET_BUILD_DIR/libprotobuf.24.4.0.dylib \
#     $BUILD_DIR/x86_64/install/lib/libprotobuf.24.4.0.dylib \
#     $BUILD_DIR/arm64/install/lib/libprotobuf.24.4.0.dylib

# lipo -create -output $TARGET_BUILD_DIR/libfido2.1.15.0.dylib \
#     $BUILD_DIR/x86_64/install/lib/libfido2.1.15.0.dylib \
#     $BUILD_DIR/arm64/install/lib/libfido2.1.15.0.dylib

echo "***** Fixing DYLIB Paths *****"
cd "$TARGET_BUILD_DIR"
install_name_tool -id "libmysqlclient.24.dylib" libmysqlclient.24.dylib
install_name_tool -id "libcrypto.3.dylib" libcrypto.3.dylib
install_name_tool -id "libssl.3.dylib" libssl.3.dylib
# install_name_tool -id "libprotobuf-lite.24.4.0.dylib" libprotobuf-lite.24.4.0.dylib
# install_name_tool -id "libprotobuf.24.4.0.dylib" libprotobuf.24.4.0.dylib
# install_name_tool -id "libfido2.1.15.0.dylib" libfido2.1.15.0.dylib

while true; do
    CRYPTO=$(otool -L libssl.3.dylib | grep -v "@loader_path" | grep libcrypto.3.dylib | cut -d' ' -f1 | head -1)
    CRYPTO="${CRYPTO#"${CRYPTO%%[![:space:]]*}"}"  
    CRYPTO="${CRYPTO%"${CRYPTO##*[![:space:]]}"}"     

    # Exit the loop if CRYPTO is empty
    if [[ -z "$CRYPTO" ]]; then
        break
    fi

    echo "CRYPTO: $CRYPTO"
    echo "Setting @loader_path/libcrypto.3.dylib in libssl.3.dylib (replacing $CRYPTO)"
    install_name_tool -change "$CRYPTO" @loader_path/libcrypto.3.dylib libssl.3.dylib
done;

while true; do
    SSL=$(otool -L libmysqlclient.24.dylib | grep -v "@loader_path" | grep libssl.3.dylib | cut -d' ' -f1 | head -1)
    SSL="${SSL#"${SSL%%[![:space:]]*}"}"  
    SSL="${SSL%"${SSL##*[![:space:]]}"}"   

    # Exit the loop if CRYPTO is empty
    if [[ -z "$SSL" ]]; then
        break
    fi

    echo "Setting @loader_path/libssl.3.dylib in libmysqlclient.24.dylib (replacing $SSL)"
    install_name_tool -change "$SSL" @loader_path/libssl.3.dylib libmysqlclient.24.dylib
done;

while true; do
    CRYPTO=$(otool -L libmysqlclient.24.dylib | grep -v "@loader_path" | grep libcrypto.3.dylib | cut -d' ' -f1 | head -1)
    CRYPTO="${CRYPTO#"${CRYPTO%%[![:space:]]*}"}"  
    CRYPTO="${CRYPTO%"${CRYPTO##*[![:space:]]}"}" 

    # Exit the loop if CRYPTO is empty
    if [[ -z "$CRYPTO" ]]; then
        break
    fi

    echo "Setting @loader_path/libcrypto.3.dylib in libmysqlclient.24.dylib (replacing $CRYPTO)"
    install_name_tool -change "$CRYPTO" @loader_path/libcrypto.3.dylib libmysqlclient.24.dylib  
done

echo "***** copying libraries to $SRCROOT/../SPMySQLFramework/MySQL Client Libraries/lib" || exit 1;
mkdir -p "$SRCROOT/../SPMySQLFramework/MySQL Client Libraries/lib/mysqlplugins/arm64" || exit 1;
mkdir -p "$SRCROOT/../SPMySQLFramework/MySQL Client Libraries/lib/mysqlplugins/x86_64" || exit 1;
mkdir -p "$SRCROOT/../SPMySQLFramework/MySQL Client Libraries/include" || exit 1;
rm -rf "$SRCROOT/../SPMySQLFramework/MySQL Client Libraries/lib/mysqlplugins/arm64/*" || exit 1;
rm -rf "$SRCROOT/../SPMySQLFramework/MySQL Client Libraries/lib/mysqlplugins/x86_64/*" || exit 1;
rm -rf "$SRCROOT/../SPMySQLFramework/MySQL Client Libraries/include/*" || exit 1;
cp "$TARGET_BUILD_DIR/"*.dylib "$SRCROOT/../SPMySQLFramework/MySQL Client Libraries/lib" || exit 1;
rsync -Hav "$BUILD_DIR/arm64/install/include/" "$SRCROOT/../SPMySQLFramework/MySQL Client Libraries/include" || exit 1;
cp "$TARGET_BUILD_DIR/../arm64/install/lib/plugin/"*.so "$SRCROOT/../SPMySQLFramework/MySQL Client Libraries/lib/mysqlplugins/arm64" || exit 1;
cp "$TARGET_BUILD_DIR/../x86_64/install/lib/plugin/"*.so "$SRCROOT/../SPMySQLFramework/MySQL Client Libraries/lib/mysqlplugins/x86_64" || exit 1;