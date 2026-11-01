#!/bin/bash
# Run only against a private, throwaway MySQL instance: tests change global settings.
set -euo pipefail

cd "$(dirname "$0")/.."
results_root="$PWD/build/spmysql-ci"
mkdir -p "$results_root"
results="$(mktemp -d "$results_root/run.XXXXXX")"
source Scripts/select-xcode.sh
xcodebuild -version | tee "$results/xcode-version.log"
# Fail early if the selected toolchain lacks the result API used by the verifier.
xcrun xcresulttool get test-results tests --help >/dev/null

mysql_prefix="$(brew --prefix "${SPMYSQL_TEST_MYSQL_FORMULA:-mysql@8.4}")"
server_dir="$(mktemp -d /tmp/sa-mysql.XXXXXX)"
socket="$server_dir/mysql.sock"
server_pid=""

cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$server_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

"$mysql_prefix/bin/mysqld" --no-defaults --initialize-insecure \
  --basedir="$mysql_prefix" --datadir="$server_dir/data" \
  >"$results/mysql-init.log" 2>&1
"$mysql_prefix/bin/mysqld" --no-defaults \
  --basedir="$mysql_prefix" --datadir="$server_dir/data" \
  --socket="$socket" --pid-file="$server_dir/mysql.pid" \
  --bind-address=127.0.0.1 --port=13306 --mysqlx=OFF \
  --log-error="$results/mysql.log" >"$results/mysql-console.log" 2>&1 &
server_pid=$!

ready=0
for ((attempt = 0; attempt < 60; attempt++)); do
  kill -0 "$server_pid" 2>/dev/null || break
  if "$mysql_prefix/bin/mysqladmin" --no-defaults --socket="$socket" --user=root ping >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done
if [[ "$ready" != 1 ]]; then
  cat "$results/mysql.log" "$results/mysql-console.log" >&2
  exit 1
fi

# The tunnel stand-in regression also connects over TCP. This root account exists
# only inside the disposable server, bound to loopback, with no external secrets.
"$mysql_prefix/bin/mysql" --no-defaults --socket="$socket" --user=root <<'SQL'
CREATE USER 'root'@'127.0.0.1' IDENTIFIED BY '';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;
SQL
"$mysql_prefix/bin/mysql" --no-defaults --host=127.0.0.1 --port=13306 --user=root --execute='SELECT VERSION()'

# xcodebuild forwards TEST_RUNNER_ variables to XCTest with the prefix removed.
# Leave HOST unset so ordinary tests use the private socket; the TCP regression
# uses 127.0.0.1 and the explicit port. The disposable socket opts into global changes.
unset TEST_RUNNER_SPMYSQL_TEST_HOST
export TEST_RUNNER_SPMYSQL_TEST_SOCKET="$socket"
export TEST_RUNNER_SPMYSQL_TEST_DISPOSABLE_SOCKET="$socket"
export TEST_RUNNER_SPMYSQL_TEST_PORT=13306
export TEST_RUNNER_SPMYSQL_TEST_USER=root
export TEST_RUNNER_SPMYSQL_TEST_PASSWORD=''

xcodebuild test \
  -project Frameworks/SPMySQLFramework/SPMySQLFramework.xcodeproj \
  -scheme SPMySQL.framework \
  -destination "platform=macOS,arch=${TEST_ARCH:-$(uname -m)}" \
  -parallel-testing-enabled NO \
  -resultBundlePath "$results/FrameworkTests.xcresult" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  2>&1 | tee "$results/xcodebuild.log"

xcrun xcresulttool get test-results tests --path "$results/FrameworkTests.xcresult" \
  >"$results/tests.json"
# Discover live suite declarations throughout the framework, independent of filenames.
xcrun swift Scripts/verify-spmysql-results.swift "$results/tests.json" Frameworks/SPMySQLFramework
