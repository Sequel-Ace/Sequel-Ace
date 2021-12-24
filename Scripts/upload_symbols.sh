#!/usr/bin/env bash
# shellcheck shell=bash

# MS AppCenter upload-symbols wrapper for Xcode
# By James Stout 25/01/2021

# SEE: https://docs.microsoft.com/en-us/appcenter/diagnostics/iOS-symbolication#app-center-api
# AND: https://github.com/microsoft/appcenter-cli#commands

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$SCRIPT_DIR" || return 1

me=$(basename "$0")

export SCRIPT_DIR

# Common functions
function sa_log () {
    echo "[SA] $1";
}

function sa_fail () {
    sa_log "$1";
    exit 0; #TODO: change to error
}

function sa_usage ()
{
    sa_log "You must invoke the script as follows:"
    echo "    sh $me \"your/appname\""
}

function dir_exists() {
	if [ -d "$1" ]; then
		return 0
	fi
	return 1
}

function file_exists() {
	if [ -e "$1" ]; then
		return 0
	fi
	return 1
}

safe_cd() {
	cd "$@" >/dev/null || sa_fail "Error: failed to cd to $*!"
}

function is_variable
{
    compgen -A variable | grep ^"${1}"$ > /dev/null
}

function var_exists() {
    if is_variable "${1}"
    then
	    if [ -n "$1" ]; then
		    return 0
	    fi
        sa_log "ret here else 1"
        return 1
    else
        sa_log "ret here else 2"
        return 1
    fi
}

# try to add a path that contains appcenter
function set_path() {

    paths_to_add=(
        # Private "bin"
        "$HOME/bin"
        # Homebrew (and various other distributions and local installations)
        /usr/local/{,s}bin
        /opt/homebrew/{,s}bin
        /Users/local/Homebrew
        "$HOME/Homebrew"
        # System
        /{,s}bin
        /usr/{,s}bin
        /usr/local/lib/node_modules
        "$HOME/.npm-packages/bin"
    );

    # Create an array of directories currently in the PATH variable.
    oldIFS="$IFS";
    IFS=:;
    set -- $PATH;
    IFS="$oldIFS";
    unset oldIFS;
    old_paths=("$@");

    # Construct an array of the directories in the new PATH, preferring our paths
    # to the predefined ones.
    new_paths=();
    for path_to_add in "${paths_to_add[@]}"; do
        [ -d "$path_to_add" ] && new_paths+=("$path_to_add");
    done;
    for old_path in "${old_paths[@]}"; do
        [ -d "$old_path" ] || continue;
        for new_path in "${new_paths[@]}"; do
            [ "${old_path%%/}" = "${new_path%%/}" ] && continue 2;
        done;
        new_paths+=("$old_path");
    done;

    # Now implode everything into the new PATH variable.
    printf -v PATH "%s:" "${new_paths[@]}";
    export PATH="${PATH%:}";
    unset {old,new}_path{,s} path{s,}_to_add;

    # remove dupes
    if hash perl 2> /dev/null; then
        PATH=$(perl -e 'print join ":", grep {!$h{$_}++} split ":", $ENV{PATH}')
    fi
    export PATH

    sa_log "PATH = ${PATH}"
}


function check_return_code () {

case "$1" in
    0)
    sa_log "Symbols uploaded succesully."
    ;;
    1)
    sa_fail "Error: Unknown Error"
    ;;
    2)
    sa_fail "Error: Invalid Options"
    ;;
    3)
    sa_fail "Error: App File Not Found"
    ;;
    [4-9])
    sa_fail "Error: Misc errors"
    ;;
    10)
    sa_fail "Error: dSym Not Found Or Not Directory"
    ;;
    11)
    sa_fail "Error: dSym Directory Wrong Extension"
    ;;
    12)
    sa_fail "Error: dSym Contains More than One Dwarf"
    ;;
    13)
    sa_fail "Error: Test Chunking Failed"
    ;;
    14)
    sa_fail "Error: Upload Negotiation Failed"
    ;;
    15)
    sa_fail "Error: Upload Failed"
    ;;
    20)
    sa_fail "Error: Incompatible Versions"
    ;;
    25)
    sa_fail "Error: Cancelled"
    ;;
    *)
    sa_fail "Error: Unknown Error"
    ;;
esac

}

APP="${1}";

if ! dir_exists "${SOURCE_ROOT}"; then
    sa_fail "SOURCE_ROOT path ${SOURCE_ROOT} does not exist!"
fi

FASTLANE_DIR="$SOURCE_ROOT/fastlane"
FASTLANE_ENV_FILE="$FASTLANE_DIR/.env"

# Pre-checks
if dir_exists "$FASTLANE_DIR"; then
    sa_log "FASTLANE_DIR exists: $FASTLANE_DIR"
else
    sa_fail "FASTLANE_DIR does NOT exist: $FASTLANE_DIR"
fi

# source the env file, which should export a var containing the token
# var is: MS_APP_CENTER
if file_exists "$FASTLANE_ENV_FILE"; then
    sa_log "FASTLANE_ENV_FILE exists: $FASTLANE_ENV_FILE"
    # shellcheck source=/dev/null
    source "$FASTLANE_ENV_FILE"
fi

# It's okay if the value is instead in an env though
if [[ -n $APPCENTER_ACCESS_TOKEN ]]; then
    sa_log "APPCENTER_ACCESS_TOKEN exists in ENV! Using this value"
    MS_APP_CENTER="$APPCENTER_ACCESS_TOKEN"
fi

if var_exists MS_APP_CENTER; then
    sa_log "MS_APP_CENTER var exists: ******************"
else
    sa_fail "MS_APP_CENTER var does NOT exist: $MS_APP_CENTER. Define the var in $FASTLANE_ENV_FILE"
fi

if [[ -z "$APP" ]]; then
    sa_usage
    sa_fail "App name not specified!"
fi

if [ ! "${DWARF_DSYM_FOLDER_PATH}" ] || [ ! "${DWARF_DSYM_FILE_NAME}" ]; then
    sa_fail "Xcode Environment Variables are missing!: DWARF_DSYM_FOLDER_PATH and/or DWARF_DSYM_FILE_NAME"
fi

DSYM_PATH="${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}";

if ! dir_exists "${DSYM_PATH}"; then
    sa_fail "dSYM path ${DSYM_PATH} does not exist!"
fi

sa_log "APP = ${APP}"
sa_log "DSYM_PATH = ${DSYM_PATH}"

set_path

method=""

if hash appcenter 2> /dev/null; then
	method="cli"
else
	method="curl"
    sa_fail "curl method DOES NOT WORK! Install appcenter: npm install -g appcenter-cli"
fi

sa_log "method = ${method}"

# these are our expected dSYMs
# might need some work...
declare -a dSYMArray=(
    "SequelAceTunnelAssistant.dSYM"
    "Sequel Ace.app.dSYM"
    "Sequel Ace Beta.app.dSYM"
    "SPMySQL.framework.dSYM"
    "xibLocalizationPostprocessor.dSYM"
    "QueryKit.framework.dSYM"
)

sa_log "DWARF_DSYM_FOLDER_PATH = ${DWARF_DSYM_FOLDER_PATH}"

safe_cd "$DWARF_DSYM_FOLDER_PATH"

dSYM_ARCHIVE_NAME="${APP#*\/}_dSYMs.zip"

sa_log "dSYM_ARCHIVE_NAME: ${dSYM_ARCHIVE_NAME}"

if file_exists "${dSYM_ARCHIVE_NAME}"; then
    sa_log "dSYM_ARCHIVE exists, removing"
    rm -f "${dSYM_ARCHIVE_NAME}"
fi

for dSYM in "${dSYMArray[@]}";
do
   if ! dir_exists "${dSYM}"; then
        sa_log "path ${dSYM} does not exist, just skip?"
    else
        sa_log "path ${dSYM} exists, adding to zip archive."
        zip -X -q -r -9 "${dSYM_ARCHIVE_NAME}" "${dSYM}"
    fi
done

if [ "$method" == "cli" ]
then
    appcenter crashes upload-symbols --app "${APP}" --symbol "${dSYM_ARCHIVE_NAME}" --token "${MS_APP_CENTER}"
    # should error check here: https://docs.microsoft.com/en-us/appcenter/test-cloud/troubleshooting/cli-exit-codes
    rc="$?"
    check_return_code "${rc}"
else
    if ! hash jq &>/dev/null; then
	    sa_log "You need to install jq for this to work - jq is like sed for JSON data"
	    sa_log "Run: brew install jq"
	    sa_fail "Or build from source: https://github.com/stedolan/jq"
    fi

    # per: https://docs.microsoft.com/en-us/appcenter/diagnostics/iOS-symbolication#app-center-api

    #construct filename
    file_name="${APP#*\/}"
    file_name="${file_name}-"$(date -u +"%Y-%m-%dT%H-%M-%SZ")
    sa_log "file_name = ${file_name}"

    #construct url
    # This call allocates space on our backend for your file and returns a symbol_upload_id and an upload_url property.
    URL="https://api.appcenter.ms/v0.1/apps/${APP}/symbol_uploads"

    response="$(curl -s -X POST "${URL}" -H  "accept: application/json" \
        -H  "X-API-Token: ${TOKEN}" \
        -H  "Content-Type: application/json" \
        -d "{  \"symbol_type\": \"Apple\", \"file_name\": \"${file_name}\"}")"

    sa_log "response = ${response}"

    # check for errors
    error_msg=$(echo "$response" | jq -r '.message')

    if [[ "$error_msg" != "null" ]]; then
        sa_fail "Request failed. error_msg = ${error_msg}"
    fi

    symbol_upload_id=$(echo "$response" | jq -r '.symbol_upload_id')
    upload_url=$(echo "$response" | jq -r '.upload_url')

    if [[ "$symbol_upload_id" == "null" ]]; then
        sa_fail "Request failed. symbol_upload_id = ${symbol_upload_id}"
    fi
    if [[ "$upload_url" == "null" ]]; then
        sa_fail "Request failed. upload_url = ${upload_url}"
    fi

    sa_log "symbol_upload_id = ${symbol_upload_id}"
    sa_log "upload_url = ${upload_url}"

    # Using the upload_url property returned from the first step, make a PUT request with the header: "x-ms-blob-type: BlockBlob" and supply the location of your file on disk.
    # This call uploads the file to our backend storage accounts
    # -----------
    #   HOWEVER
    # -----------
    # this doesn't work. Reported to MS
    # Transfer-Encoding: chunked is set by the call to curl
    #
    # https://docs.microsoft.com/en-us/rest/api/storageservices/put-blob#request-headers-all-blob-types says:
    # "For a page blob or an append blob, the value of this header must be set to zero"
    #
    # but this is the response:
    #<?xml version="1.0" encoding="utf-8"?><Error><Code>InvalidHeaderValue</Code><Message>The value for one of the HTTP headers is not in the correct format.
    # RequestId:1485bd45-701e-0025-284b-9eb210000000
    # Time:2020-10-09T14:47:04.2689302Z</Message><HeaderName>Content-Length</HeaderName><HeaderValue>-1</HeaderValue></Error>
    curl -X PUT "${upload_url}" -H 'Content-Length: 0' -H 'x-ms-blob-type: BlockBlob' --upload-file "${DSYM_PATH}"

    # this works, but nothing is committed
    # Make a PATCH request to the symbol_uploads API using the symbol_upload_id property returned from the first step.
    # In the body of the request, specify whether you want to set the status of the upload to committed (successfully completed) the upload process,
    # or aborted (unsuccessfully completed).

    #construct url
    URL="https://api.appcenter.ms/v0.1/apps/${APP}/symbol_uploads/${symbol_upload_id}"

    curl -X PATCH "${URL}" \
    -H 'accept: application/json' \
    -H  "X-API-Token: ${TOKEN}" \
    -H 'Content-Type: application/json' \
    -d '{ "status": "committed" }'

fi

exit 0;
