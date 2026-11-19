#!/usr/bin/env bash
# Downloads and verifies the pocketd release this tutorial uses, into the
# repository root. Read the commands before you run it.
set -eu

VERSION="v0.1.37"
ARCHIVE="pocket_linux_amd64.tar.gz"
EXPECTED="e0c5d10bbfcc8cff23736a1b02b7e4066e4681f2b1d1a9596345fd8cedaa21be"
BASE="https://github.com/pokt-network/poktroll/releases/download/${VERSION}"

cd "$(dirname "$0")/.."

if [ -x ./pocketd ]; then
  echo "./pocketd already present: $(./pocketd version)"
  echo "Delete it first if you want a fresh download."
  exit 0
fi

echo "downloading ${ARCHIVE} and the published checksum from ${VERSION}"
curl -sL -o "$ARCHIVE" "${BASE}/${ARCHIVE}"
curl -sL -o release_checksum "${BASE}/release_checksum"

echo "verifying against the published entry"
if ! grep -q "^${EXPECTED}  ${ARCHIVE}$" release_checksum; then
  echo "FAIL: the downloaded release_checksum does not list the expected hash for ${ARCHIVE}"
  exit 1
fi
echo "${EXPECTED}  ${ARCHIVE}" | sha256sum -c -

tar -xzf "$ARCHIVE"
echo "ready: $(./pocketd version)"
echo "now run: bash examples/verify.sh"
