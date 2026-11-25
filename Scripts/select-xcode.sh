# Source from build/test scripts to preserve the selection in their environment.
# Prefer an explicit override; otherwise use xcode-select's full Xcode selection.
# Versioned /Applications paths go stale when hosted runner images are upgraded.
sa_xcode_developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"
# Apple also accepts the Xcode.app bundle itself as DEVELOPER_DIR.
if [[ -d "$sa_xcode_developer_dir/Contents/Developer/Platforms/MacOSX.platform" ]]; then
  sa_xcode_developer_dir="${sa_xcode_developer_dir%/}/Contents/Developer"
fi
if [[ ! -d "$sa_xcode_developer_dir/Platforms/MacOSX.platform" ]]; then
  echo "Select a full Xcode installation with xcode-select or DEVELOPER_DIR: $sa_xcode_developer_dir" >&2
  return 1
fi
export DEVELOPER_DIR="$sa_xcode_developer_dir"
unset sa_xcode_developer_dir
