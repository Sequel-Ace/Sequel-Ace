# SPMySQL.framework

The SPMySQL Framework is intended to provide a stable MySQL connection framework, with the ability to run text-based queries and rapidly retrieve result sets with conversion from MySQL data types to Cocoa objects.

SPMySQL.framework has an interface loosely based around that provided by MCPKit by Serge Cohen and Bertrand Mansion ([http://mysql-cocoa.sourceforge.net/](http://mysql-cocoa.sourceforge.net/)), and in particular the heavily modified Sequel Pro version ([https://sequelpro.com/](https://sequelpro.com/)). It is a full rewrite of the original framework, although it includes code from patches implementing the following Sequel Pro functionality, largely contributed by Hans-Jörg Bibiko, Stuart Connolly, Jakob Egger and Rowan Beentje:

* Connection locking (Jakob et al.)
* Ping & keepalive (Rowan et al.)
* Query cancellation (Rowan et al.)
* Delegate setup (Stuart et al.)
* SSL support (Rowan et al.)
* Connection checking (Rowan et al.)
* Version state (Stuart et al.)
* Maximum packet size control (Hans et al.)
* Result multithreading and streaming (Rowan et al.)
* Improved encoding support & switching (Rowan et al.)
* Database structure; moved to inside the app (Hans et al.)
* Query reattempts and error-handling approach (Rowan et al.)
* Geometry result class (Hans et al.)
* Connection proxy (Stuart et al.)

## Integration

SPMySQL.framework can be added to your project as a standard Cocoa framework, or the entire project
can be added as a subproject in Xcode.

To add as a subproject in Xcode:

1. Add the SPMySQL framework's `.xcodeproj` to your current project
2. Choose an existing target, Get Info, and under direct dependenies add a new dependency. Choose the SPMySQL.framework target from the sub-project.
3. Expand the subproject to see its child target - SPMySQL.framework. Drag this to the "Link Binary With Libraries" build phase of any targets using the framework.
4. If you don't have a Copy Frameworks phase, add one; drag the SPMySQL.framework child target to this phase.
5. In your build settings, add a User Header Search Path; make it a recursive path to the SPMySQL project folder location (for example `${PROJECT_DIR}/Frameworks/SPMySQLFramework`). This should allow you to `#include "SPMySQL.h"` and have everything function.

As a last resort jump onto IRC and join #sequel-pro on irc.freenode.net and any of the
developers will be more than happy to help you out.

## Framework tests in CI

The PR Tests workflow runs the framework's own `SPMySQL.framework` scheme in a
separate GitHub-hosted macOS job; the app's `Unit Tests` scheme does not include
these tests. To run the same job locally on a Mac with full Xcode and Homebrew:

```sh
brew install mysql@8.4
bash Scripts/test-spmysql-framework.sh # from the repository root
```

The job uses `macos-latest` and its selected full Xcode, rather than a versioned
developer-directory path or a fixed processor architecture. Both app and framework
test scripts share `Scripts/select-xcode.sh`. It honors a
`DEVELOPER_DIR` override, rejects Command Line Tools-only installations, logs the
actual Xcode version and checks for the xcresult API it needs before starting a
database. MySQL stays on the **8.4 LTS series**, accepting Homebrew's patch updates
without floating onto an incompatible Innovation/major release. GitHub Actions
remain pinned by commit for supply-chain integrity.

The script initializes a private MySQL 8.4 data directory under `/tmp`, binds TCP
to loopback port 13306, and passes its private socket and port to XCTest using
`TEST_RUNNER_SPMYSQL_TEST_*`. It never starts a Homebrew service or uses an existing
database. Its passwordless root accounts exist only in this throwaway instance,
which is stopped and removed on exit. Do not point this job at a shared server:
the integration tests create users/databases and temporarily change global
settings. Tests run serially so those settings cannot race between suites.

Each invocation gets a fresh results directory under `build/spmysql-ci/`, so local
reruns do not collide with an existing xcresult bundle. Logs are uploaded by CI, including
on failure. The result verifier requires the escaping and database-assertion live
suites to have test cases and rejects every non-passing live test except the
explicit Sphinx-only skip (this job does not provision Sphinx).

This CI change is independent of #2775. Its session-identity tests are not copied
here; the verifier discovers every `*IntegrationTests: XCTestCase` declaration
throughout the framework sources, so moving or renaming its test file cannot
omit the session-identity suite from the required coverage. The full framework scheme already
includes its cancellation, gate and statement-byte tests once #2775 is merged.
The verifier's synthetic positive/negative checks run before the native tests:
`xcrun swift Scripts/verify-spmysql-results.swift --self-test`.

## License

Copyright (c) 2018 Rowan Beentje (rowan.beent.je) & the Sequel Pro team. All rights reserved.

SPMySQLFramework is free and open source software, licensed under [MIT](https://opensource.org/licenses/MIT). See [LICENSE](https://github.com/sequelpro/sequelpro/blob/master/Frameworks/SPMySQLFramework/LICENSE) for full details.

