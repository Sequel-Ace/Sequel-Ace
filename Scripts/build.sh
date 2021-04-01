#!/bin/bash
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

set -e

MODE="$1"

dir_exists() {
	if [ -d "$1" ]; then
		return 0
	fi
	return 1
}

#Shouldn't be needed anymore
#OPENSSL_VER=1.1.1h
#OPENSSL_FILE="openssl-$OPENSSL_VER.tar.gz"
#OPENSSL_URL="https://www.openssl.org/source/$OPENSSL_FILE"
#OPENSSL_TARGET_DIR="Frameworks/openssl"
#
#if ! dir_exists "$OPENSSL_TARGET_DIR"; then
#  echo "$OPENSSL_TARGET_DIR doesn't exist"
#  trap - EXIT
#  exit 1
#fi
#
#if ! curl -L "$OPENSSL_URL" -o "$OPENSSL_TARGET_DIR/$OPENSSL_FILE";
#then
#  echo "curl of $OPENSSL_URL failed"
#  trap - EXIT
#  exit 1
#fi

if ! hash xcpretty 2> /dev/null; then
  echo "xcpretty not installed. Try gem install xcpretty"
  trap - EXIT
  exit 1
fi

if [ "$MODE" = "tests" ]; then
  echo "Running Sequel Ace Unit tests"
  set -o pipefail && xcodebuild test -workspace sequel-ace.xcworkspace -scheme "Sequel Ace Local Testing" -destination "platform=macOS,arch=x86_64" test CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO | xcpretty -c
  success="1"
fi

if [ "$success" = "1" ]; then
trap - EXIT
exit 0
fi

echo "Unrecognised mode '$MODE'."
