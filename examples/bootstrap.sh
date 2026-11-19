#!/usr/bin/env bash
# Downloads and verifies the pocketd release this tutorial uses, into the
# repository root. Read the commands before you run it.
set -eu

VERSION="v0.1.37"
BASE="https://github.com/pokt-network/poktroll/releases/download/${VERSION}"
# The hash the tutorial quotes for pocket_linux_amd64.tar.gz. It anchors the
# checksum file itself: if this line is missing, the file is not the one the
# tutorial verified, and nothing here is trusted.
ANCHOR="e0c5d10bbfcc8cff23736a1b02b7e4066e4681f2b1d1a9596345fd8cedaa21be"

cd "$(dirname "$0")/.."

# the release ships pocket_{linux,darwin}_{amd64,arm64}.tar.gz
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$(uname -m)" in
  x86_64)        ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) echo "FAIL: unsupported machine $(uname -m)"; exit 1 ;;
esac
case "$OS" in
  linux|darwin) ;;
  *) echo "FAIL: unsupported operating system $OS (the release ships Linux and macOS)"; exit 1 ;;
esac
ARCHIVE="pocket_${OS}_${ARCH}.tar.gz"

# sha256sum on Linux, shasum on macOS
if command -v sha256sum >/dev/null 2>&1; then
  SHA="sha256sum"
else
  SHA="shasum -a 256"
fi

if [ -x ./pocketd ]; then
  echo "./pocketd already present: $(./pocketd version)"
  echo "Delete it first if you want a fresh download."
  exit 0
fi

echo "downloading ${ARCHIVE} and the published checksum from ${VERSION}"
curl -sL -o "$ARCHIVE" "${BASE}/${ARCHIVE}"
curl -sL -o release_checksum "${BASE}/release_checksum"

echo "verifying the checksum file against the hash the tutorial quotes"
if ! grep -q "^${ANCHOR}  pocket_linux_amd64.tar.gz$" release_checksum; then
  echo "FAIL: release_checksum does not carry the hash this tutorial published"
  exit 1
fi

EXPECTED=$(grep "  ${ARCHIVE}$" release_checksum | awk '{print $1}')
if [ -z "$EXPECTED" ]; then
  echo "FAIL: the published release_checksum lists no entry for ${ARCHIVE}"
  exit 1
fi
echo "verifying ${ARCHIVE} against the published entry"
echo "${EXPECTED}  ${ARCHIVE}" | $SHA -c -

# the unpacked binary needs roughly 200 MB free; fail clearly, not with a
# half-written binary
NEED_MB=220
FREE_MB=$(df -Pm . | awk 'NR==2 {print $4}')
if [ "${FREE_MB:-0}" -lt "$NEED_MB" ]; then
  echo "FAIL: about ${NEED_MB} MB free is needed to unpack, ${FREE_MB} MB available in $(pwd)"
  echo "      the archive itself verified, so nothing is wrong with the download"
  exit 1
fi

tar -xzf "$ARCHIVE" || {
  echo "FAIL: could not unpack ${ARCHIVE} (partial binary removed)"
  rm -f ./pocketd
  exit 1
}
echo "ready: $(./pocketd version)"
echo "now run: bash examples/verify.sh"
