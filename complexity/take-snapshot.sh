#/bin/bash

# This is a script that dumps the results of `scc` into a files
# These snapshots can yield insight into the evolution of code complexity in Sequel Ace
# You can also run this script with the TO_CONSOLE env var set to display the results in the console

if [ `which scc` == '' ]; then
  echo "SCC not found"
  exit 1
fi

BASE_DIR="complexity"
if [ "$VERSION" == '' ]; then
  BASE_DIR="$BASE_DIR/$(date '+%FT%H:%M')"
else
  BASE_DIR="$BASE_DIR/$VERSION"
fi

if [ ! -d "$BASE_DIR" ]; then
  mkdir -p "$BASE_DIR"
fi

if [ ! -d "$BASE_DIR"/miscellaneous ]; then
  mkdir -p "$BASE_DIR"/miscellaneous
fi

if [ ! -d "$BASE_DIR"/controllers ]; then
  mkdir -p "$BASE_DIR"/controllers
fi

function snapshot() {
  scc -f json -o $BASE_DIR/$2.json $1
  if [ "$TO_CONSOLE" != '' ]; then
    echo $1
    scc -w $1
  fi
}

snapshot "Source" "overall"
snapshot "Frameworks" "frameworks"
snapshot "Source/Model" "models"
snapshot "Source/ThirdParty" "third-party"
snapshot "Source/Views" "views"

snapshot "Source/Controllers" "controllers"
snapshot "Source/Controllers/BundleSupport" "controllers/bundle-support"
snapshot "Source/Controllers/DataControllers" "controllers/data-controllers"
snapshot "Source/Controllers/DataExport" "controllers/data-export"
snapshot "Source/Controllers/DataImport" "controllers/data-import"
snapshot "Source/Controllers/MainViewControllers" "controllers/main-view-controllers"
snapshot "Source/Controllers/Other" "controllers/other"
snapshot "Source/Controllers/Preferences" "controllers/preferences"
snapshot "Source/Controllers/SubviewControllers" "controllers/subview-controllers"
snapshot "Source/Controllers/Window" "controllers/window"


snapshot "Source/Other" "miscellaneous"
snapshot "Source/Other/CategoryAdditions" "miscellaneous/category-additions"
snapshot "Source/Other/Data" "miscellaneous/data"
snapshot "Source/Other/DatabaseActions" "miscellaneous/database-actions"
snapshot "Source/Other/DebuggingSupport" "miscellaneous/debugging-support"
snapshot "Source/Other/Extensions" "miscellaneous/extensions"
snapshot "Source/Other/FileCompression" "miscellaneous/file-compression"
snapshot "Source/Other/Keychain" "miscellaneous/keychain"
snapshot "Source/Other/Parsing" "miscellaneous/parsing"
snapshot "Source/Other/QuickLookPlugin" "miscellaneous/quick-look-plugin"
snapshot "Source/Other/SSHTunnel" "miscellaneous/ssh-tunnel"
snapshot "Source/Other/Utility" "miscellaneous/utility"
