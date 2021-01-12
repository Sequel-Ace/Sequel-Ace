#!/bin/bash

# Crowdin Translation fetch script
# By Jakub Kaspar 12/04/2020

# Crowdin Keys
PROJECT_IDENTIFIER="sequel-ace"

# Load project key from .env file
PROJECT_KEY=$(grep CROWDIN_PROJECT_KEY "../fastlane/.env" | cut -d '=' -f2)
echo $PROJECT_KEY

# Local Vars
OUTPUT_DIR=""
MODE_FILENAME="macOS_app.strings"

################  Handle Flags ###############
while getopts 'mbsho:' opt; do
  case "${opt}" in
    o) OUTPUT_DIR="$OPTARG";;
  esac
done

# Validate that output directory is actually a directory
if [[ -d $OUTPUT_DIR ]]; then
  echo "Output directory to update strings is $OUTPUT_DIR"
else
  echo "ERROR: $OUTPUT_DIR is not a valid directory!"
  exit 1
fi

STRINGFILE="${OUTPUT_DIR}en.lproj/Localizable.strings"

echo "Uploading file update to Crowdin"
curl -F "files[/macOS_app.strings]=@${STRINGFILE}" "https://api.crowdin.com/api/project/${PROJECT_IDENTIFIER}/update-file?key=${PROJECT_KEY}"

echo "Fetching strings..."

################ Begin Download ###############

# First, generate latest translations if necessary
echo "Generating latest strings"
curl -ss https://api.crowdin.com/api/project/"$PROJECT_IDENTIFIER"/export?key="$PROJECT_KEY" > temp.txt
rm temp.txt
echo "Generation successful"

# Then download latest strings
mkdir _data
cd _data
echo "Downloading Latest Strings..."
curl https://api.crowdin.com/api/project/"$PROJECT_IDENTIFIER"/download/all.zip?key="$PROJECT_KEY" > strings.zip
echo "Download complete, unzipping"
tar -xf strings.zip
rm strings.zip
echo "Unzip complete, parsing"

################ Begin Parsing ################

# Delete all the files we don't care about
find . -not -name "$MODE_FILENAME" -delete

# Delete all the directories we don't have translations for
find . -type d -empty -delete

# Rename all the files
for f in */"$MODE_FILENAME"; do mv "$f" "$(dirname "$f")/Localizable.strings"; done

# Rename all the directories
for f in */; do mv "$f" "${f%/}.lproj"; done

echo "Parsing complete, copying over to folder $OUTPUT_DIR"

for CURRENT_DIR in */ ; do

  # This will hold the name that we want the language to be
  TARGET_DIR=$CURRENT_DIR
  
  if [ "$TARGET_DIR" = "es-ES.lproj/" ]; then
    echo "Converting Crowdin Spain spanish into Xcode compatible universal spanish code"
    TARGET_DIR="es.lproj/"
    DIRECTORY="${OUTPUT_DIR}${TARGET_DIR}"
    cp -f "${CURRENT_DIR}Localizable.strings" "${DIRECTORY}Localizable.strings"
  fi

  # This will hold the name that we want the language to be
  TARGET_DIR=$CURRENT_DIR

  DIRECTORY="${OUTPUT_DIR}${TARGET_DIR}"

  if [ -d "$DIRECTORY" ]; then
    echo "Updating language for code: $TARGET_DIR"
    cp -f "${CURRENT_DIR}Localizable.strings" "${DIRECTORY}Localizable.strings"
  else
    echo "error: New language detected for code: $TARGET_DIR MAKE SURE TO UPDATE BUILD SETTINGS"
    cp -rf "${TARGET_DIR}" "${DIRECTORY%/}"
  fi

done

echo "Update complete!"

cd ..
rm -rf _data
