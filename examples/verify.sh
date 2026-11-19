#!/usr/bin/env bash
# Re-checks every read-only claim in the tutorial. Creates no keys,
# sends nothing, spends nothing.
set -u

NODE="https://sauron-rpc.infra.pocket.network"
CHAIN="pocket"
PASS=0
FAIL=0

check() {
  local name="$1"; shift
  if "$@" > /tmp/verify_out.txt 2>&1; then
    echo "PASS  $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL  $name"
    sed 's/^/      /' /tmp/verify_out.txt | head -5
    FAIL=$((FAIL + 1))
  fi
}

cd "$(dirname "$0")/.."

echo "== pocketd tutorial verification =="
echo "node: $NODE | chain-id: $CHAIN"
echo

POCKETD="${POCKETD:-./pocketd}"
command -v "$POCKETD" >/dev/null 2>&1 || { echo "FAIL  pocketd binary missing (see Part 1, or set POCKETD=/path/to/pocketd)"; exit 1; }

check "pocketd runs" "$POCKETD" version

# the tutorial's checksum line must match what the maintainers published
check "published checksum matches" bash -c \
  "curl -sL --max-time 60 https://github.com/pokt-network/poktroll/releases/download/v0.1.37/release_checksum | grep -q '^e0c5d10bbfcc8cff23736a1b02b7e4066e4681f2b1d1a9596345fd8cedaa21be  pocket_linux_amd64.tar.gz$'"

# if the downloaded archive is present, it must hash correctly
if [ -f pocket_linux_amd64.tar.gz ]; then
  check "downloaded archive matches checksum" bash -c \
    "echo 'e0c5d10bbfcc8cff23736a1b02b7e4066e4681f2b1d1a9596345fd8cedaa21be  pocket_linux_amd64.tar.gz' | sha256sum -c -"
else
  echo "SKIP  downloaded archive matches checksum (pocket_linux_amd64.tar.gz not present here)"
fi

check "service params reachable" bash -c \
  "$POCKETD query service params --node $NODE --chain-id $CHAIN | grep -q add_service_fee"

check "add_service_fee is 1000000000 upokt" bash -c \
  "$POCKETD query service params --node $NODE --chain-id $CHAIN | grep -A1 add_service_fee | grep -q 'amount: \"1000000000\"'"

check "REST cross-check agrees" bash -c \
  "curl -s --max-time 30 https://sauron-api.infra.pocket.network/pokt-network/poktroll/service/params | grep -q '\"amount\":\"1000000000\"'"

check "service registry lists services" bash -c \
  "$POCKETD query service all-services --node $NODE --chain-id $CHAIN | grep -q 'total:'"

check "show-service returns a known service" bash -c \
  "$POCKETD query service show-service agentsearch-web-extract-v1 --node $NODE --chain-id $CHAIN | grep -q 'id: agentsearch-web-extract-v1'"

check "service card decodes to pocket-service-card/v1" bash -c \
  "$POCKETD query service card agentsearch-web-extract-v1 --node $NODE --chain-id $CHAIN | grep -q 'pocket-service-card/v1'"

check "example card validates" "$POCKETD" tx service validate-card card.json

check "node is on mainnet and synced" bash -c \
  "$POCKETD status --node $NODE | grep -q '\"network\":\"pocket\"'"

check "node is not catching up" bash -c \
  "$POCKETD status --node $NODE | grep -q '\"catching_up\":false'"

echo
echo "== summary: $PASS passed, $FAIL failed =="
exit "$FAIL"
