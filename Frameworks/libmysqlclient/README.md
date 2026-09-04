# Bundled MySQL client build recipes

`SPMySQLFramework/MySQL Client Libraries` ships prebuilt, universal
(arm64 + x86_64) binaries pinned to the app's deployment target:

| File | Built by | From |
|---|---|---|
| `lib/libssl.3.dylib`, `lib/libcrypto.3.dylib` | `build-openssl.sh` | the OpenSSL release tarball |
| `lib/libmysqlclient.24.dylib`, `include/`, `lib/mysqlplugins/` (auth plugins + the bundled libfido2 the WebAuthn plugin loads) | `build-libmysqlclient.sh` | the MySQL source tarball |

Both scripts are self-contained and **use nothing from Homebrew**. Every
dependency is either bundled in the MySQL tarball (zlib, zstd, lz4, ICU,
protobuf, libfido2, editline, libevent), part of the macOS SDK (SASL), or
fetched and checksummed by the scripts themselves (the MySQL and OpenSSL
tarballs, and CMake as Kitware's official universal binary). Bison is not
needed for a client-only MySQL build. The x86_64 slice is cross-compiled on
Apple silicon with the same Xcode toolchain; MySQL's build-time helper
programs run under Rosetta, which must therefore be installed on an arm64
host.

Why not Homebrew: its bottles are compiled for the host macOS release, so a
dylib taken from one carries the host's minimum OS version (the 3.4.1 pair
that used to ship was arm64 minos 15.0 / x86_64 minos 14.0 against a 13.5
target), and its libraries reference each other by absolute `/opt/homebrew`
or `/usr/local` paths that do not exist on users' machines. The scripts
verify that no produced binary links anything outside `@loader_path`,
`/usr/lib` or `/System/Library`.

## Running

```sh
Frameworks/libmysqlclient/build-openssl.sh        # the OpenSSL pair
Frameworks/libmysqlclient/build-libmysqlclient.sh # the client, headers, plugins
```

`build-libmysqlclient.sh` runs `build-openssl.sh` itself when the OpenSSL
tree it links against is missing, so the second command alone rebuilds
everything. Both write to `build/` next to the scripts (git-ignored) unless
`OPENSSL_BUILD_DIR` / `MYSQL_BUILD_DIR` say otherwise, and both copy their
output into `SPMySQLFramework/MySQL Client Libraries` only after every check
passes. The `libmysqlclient.xcodeproj` target is a wrapper that runs the
same script.

Versions and checksums are pinned at the top of each script; bump the
version and the checksum together. The OpenSSL build sets
`SOURCE_DATE_EPOCH`, so re-running it on the same toolchain reproduces the
committed bytes exactly.

## Layout inside the framework

`SPMySQL.framework/Versions/A` holds `SPMySQL` next to the three dylibs, all
referring to each other as `@loader_path/<name>`. `SPMySQLConnection` sets
`MYSQL_PLUGIN_DIR` to the framework's `PlugIns` directory, one level below,
which is why the plugins reference the OpenSSL pair as
`@loader_path/../lib*.dylib`. Packaging the plugins into that directory is
not wired up yet (see #2590); the built plugins are kept in
`lib/mysqlplugins/` ready for it.

## While a bundled `.dylib` is modified in the working tree

`SPMySQL.framework`'s post-build script re-copies the dylibs from the built
framework back into `MySQL Client Libraries/lib` on every build as long as
`git diff` reports one of them modified. Run `xcodebuild` invocations one at
a time in that state: two builds copying at once have corrupted
`libmysqlclient.24.dylib` mid-write.
