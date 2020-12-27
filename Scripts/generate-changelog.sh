#!/bin/bash

TEMP_FILE=/tmp/CHANGELOG_DIFF.md
CHANGELOG_FILE=../CHANGELOG.md
CURRENT_VERSION=$1
LAST_MAJOR_VERSION=$(git describe --match "production/*" --tags --abbrev=0)

################  Write Recent Change to Tempfile ###############

echo "## [$CURRENT_VERSION]" > $TEMP_FILE

changelog_changes=""

changelog_changes+="\n### Added"
changelog_changes+="$(git log --merges $LAST_MAJOR_VERSION..HEAD --pretty=format:'%h, %b' | grep '#added' | sed 's/#added//g')\n"

changelog_changes+="\n### Fixed"
changelog_changes+="$(git log --merges $LAST_MAJOR_VERSION..HEAD --pretty=format:'%h, %b' | grep '#fixed' | sed 's/#fixed//g')\n"

changelog_changes+="\n### Changed"
changelog_changes+="$(git log --merges $LAST_MAJOR_VERSION..HEAD --pretty=format:'%h, %b' | grep '#changed' | sed 's/#changed//g')\n"

changelog_changes+="\n### Removed"
changelog_changes+="$(git log --merges $LAST_MAJOR_VERSION..HEAD --pretty=format:'%h, %b' | grep '#removed' | sed 's/#removed//g')\n"

changelog_changes+="\n### Infra"
changelog_changes+="$(git log --merges $LAST_MAJOR_VERSION..HEAD --pretty=format:'%h, %b' | grep '#infra' | sed 's/#infra//g')\n"

changelog_changes+="\n"

printf "$changelog_changes" >> $TEMP_FILE

################  Prepend Tempfile to CHANGELOG ###############

cat $CHANGELOG_FILE >> $TEMP_FILE
cp $TEMP_FILE $CHANGELOG_FILE

printf "$changelog_changes"
