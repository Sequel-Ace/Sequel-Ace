#!/bin/bash

TEMP_FILE=/tmp/CHANGELOG_DIFF.md
CHANGELOG_FILE=../CHANGELOG.md
CURRENT_VERSION=$1
LAST_MAJOR_VERSION=$(git describe --match "production/*" --tags --abbrev=0)

################  Write Recent Change to Tempfile ###############

echo "## [$CURRENT_VERSION]" > $TEMP_FILE

echo -e "\n### Added" >> $TEMP_FILE
printf "$(git log --merges $LAST_MAJOR_VERSION..HEAD --pretty=format:'%h, %b' | grep '#added' | sed 's/#added//g')\n" >> $TEMP_FILE

echo -e "\n### Fixed" >> $TEMP_FILE
printf "$(git log --merges $LAST_MAJOR_VERSION..HEAD --pretty=format:'%h, %b' | grep '#fixed' | sed 's/#fixed//g')\n" >> $TEMP_FILE

echo -e "\n### Changed" >> $TEMP_FILE
printf "$(git log --merges $LAST_MAJOR_VERSION..HEAD --pretty=format:'%h, %b' | grep '#changed' | sed 's/#changed//g')\n" >> $TEMP_FILE

echo -e "\n### Removed" >> $TEMP_FILE
printf "$(git log --merges $LAST_MAJOR_VERSION..HEAD --pretty=format:'%h, %b' | grep '#removed' | sed 's/#removed//g')\n" >> $TEMP_FILE

echo -e "\n### Infra" >> $TEMP_FILE
printf "$(git log --merges $LAST_MAJOR_VERSION..HEAD --pretty=format:'%h, %b' | grep '#infra' | sed 's/#infra//g')\n" >> $TEMP_FILE

echo -e "\n" >> $TEMP_FILE

################  Prepend Tempfile to CHANGELOG ###############

cat $CHANGELOG_FILE >> $TEMP_FILE
cp $TEMP_FILE $CHANGELOG_FILE

echo "Updated $CHANGELOG_FILE with all changes since $LAST_MAJOR_VERSION!"
