# Bundled MySQL client build recipes

`SPMySQLFramework/MySQL Client Libraries` ships prebuilt, universal
(arm64 + x86_64) binaries pinned to the app's deployment target:

| File | Built by | From |
|---|---|---|
| `lib/libssl.3.dylib`, `lib/libcrypto.3.dylib` | `build-openssl.sh` | the OpenSSL release tarball |
| `lib/libmysqlclient.24.dylib`, `include/`, `lib/mysqlplugins/` (auth plugins + the bundled libfido2 the WebAuthn plugin loads) | `build-libmysqlclient.sh` | the MySQL source tarball |

One of those plugins is not Oracle's to give. MySQL compiles
`plugin/auth/dialog.cc` only as a `TEST_ONLY` module and names it after its
plugin directory entry (`auth`), while the client loader opens
`<plugin name>.so` — so a community build ships no loadable `dialog` plugin
even though every server asking for PAM authentication wants one. The recipe
compiles that same source client-only under the name the loader looks for,
with the flags `MYSQL_ADD_PLUGIN`'s `SERVER_AND_CLIENT` path uses. The plugin
asks its questions through `mysql_authentication_dialog_ask`, which it finds
with `dlsym(RTLD_DEFAULT, …)`; `SADialogAuthPrompt.swift` exports that symbol
from the app, so the questions become an alert instead of the `fgets(stdin)`
the plugin falls back to.

It is the one source file here that is **not** shipped as Oracle wrote it.
`dialog-plaintext-consent.patch` redirects the plugin's two unasked replies — the
`mysql_change_user` packet and a password question with an empty prompt, both
of which answer straight from `mysql->passwd` — through the client callback.
Every dialog answer now requires user interaction, including over TLS:
`mysql_get_ssl_cipher()` establishes encryption but does not verify the server's
identity. The app warns on plaintext connections and on TLS connections without
`SSL_MODE_VERIFY_IDENTITY`, and still lets the user proceed so no-TLS PAM remains
usable. Cancelling sends no answer. The build applies the patch to a copy and
fails if it does not apply. `test-dialog-plugin.swift` then exercises both slices
of the actual binary through the plugin ABI: empty and nonempty questions,
change-user packets, cancellation, accepted answers, and long multibyte answers
under both simulated transport states. This replaces the earlier symbol check,
which could not prove that the saved-password bypass was closed.

This is a dialog-specific consent policy. The app's existing `PREFERRED` and
`REQUIRED` TLS modes do not verify peer identity, and MySQL's built-in SHA-256
authentication plugins can still send a saved password on such a connection.
The dialog change does not fix that separate, pre-existing client-wide policy.

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
tree it links against is missing or stale (a stamp records the OpenSSL
version and floor it was built with, and the libraries' minimum OS is
checked), so the second command alone rebuilds everything. On Apple
silicon it also requires Rosetta 2 (`softwareupdate --install-rosetta`)
and says so up front. Both write to `build/` next to the scripts (git-ignored) unless
`OPENSSL_BUILD_DIR` / `MYSQL_BUILD_DIR` say otherwise, and both copy their
output into `SPMySQLFramework/MySQL Client Libraries` only after every check
passes. The `libmysqlclient.xcodeproj` target is a wrapper that runs the
same script.

Versions and checksums are pinned at the top of each script; bump the
version and the checksum together. The OpenSSL build sets
`SOURCE_DATE_EPOCH`, so re-running it on the same toolchain reproduces the
committed bytes exactly.

## The compile-time prefix

`CMAKE_INSTALL_PREFIX` is baked into the client as its plugin, share, etc and
data directories, so it is fixed at MySQL's conventional `/usr/local/mysql`
and `DESTDIR` redirects the install into the work directory. `__FILE__` from
`assert`/`DBUG` macros is mapped with `-ffile-prefix-map` for the same reason.
Without both, whatever directory the recipe happened to run in ships inside
the dylib and is what a user reads out of a plugin-loading error — which is
how a build scratch directory came to be quoted in #2773. The verification
step fails the build if either leaks back in, so a rebuild anywhere
reproduces the same strings.

## Layout inside the framework

`SPMySQL.framework/Versions/A` holds `SPMySQL` next to the three dylibs, all
referring to each other as `@loader_path/<name>`. `SPMySQLConnection` sets
`MYSQL_PLUGIN_DIR` to the framework's `PlugIns` directory, one level below,
which is why the plugins reference the OpenSSL pair as
`@loader_path/../lib*.dylib`. The framework target copies them there from
`lib/mysqlplugins/` ("Copy MySQL Client Plugins", code-signed on copy) and
then links `PlugIns` at the bundle's top level: `NSBundle` resolves
`builtInPlugInsPath` to `<bundle>/PlugIns`, never to
`Versions/Current/PlugIns`, so a versioned framework needs that symlink the
same way it needs one for `Resources`, or the plugins are invisible at
runtime.

## While a bundled `.dylib` is modified in the working tree

`SPMySQL.framework`'s post-build script re-copies the dylibs from the built
framework back into `MySQL Client Libraries/lib` on every build as long as
`git diff` reports one of them modified. Every publisher (that script and
both recipes) stages through a unique temporary file and renames it into
place, so a concurrent reader always sees a complete file. What remains is
last-writer-wins: two builds publishing at once leave whichever finished
last, so still run `xcodebuild` invocations one at a time in that state if
it matters which build's copy ends up in the tree.
