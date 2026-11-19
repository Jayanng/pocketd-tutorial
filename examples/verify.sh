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
HAVE_BINARY=1
if ! command -v "$POCKETD" >/dev/null 2>&1; then
  HAVE_BINARY=0
  echo "NOTE  pocketd not found (set POCKETD=/path/to/pocketd to verify the CLI claims)."
  echo "      Checks that need the binary will report SKIP. The REST checks still run."
  echo
fi

if [ "$HAVE_BINARY" = 1 ]; then
  check "pocketd runs" "$POCKETD" version
else
  echo "SKIP  pocketd runs (binary not present)"
fi

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

if [ "$HAVE_BINARY" = 1 ]; then
  check "service params reachable" bash -c \
  "$POCKETD query service params --node $NODE --chain-id $CHAIN | grep -q add_service_fee"
else
  echo "SKIP  params reachable (needs the pocketd binary)"
fi

if [ "$HAVE_BINARY" = 1 ]; then
  check "add_service_fee is 1000000000 upokt" bash -c \
  "$POCKETD query service params --node $NODE --chain-id $CHAIN | grep -A1 add_service_fee | grep -q 'amount: \"1000000000\"'"
else
  echo "SKIP  fee value (needs the pocketd binary)"
fi

check "REST cross-check agrees" bash -c \
  "curl -s --max-time 30 https://sauron-api.infra.pocket.network/pokt-network/poktroll/service/params | grep -q '\"amount\":\"1000000000\"'"

if [ "$HAVE_BINARY" = 1 ]; then
  check "service registry lists services" bash -c \
  "$POCKETD query service all-services --node $NODE --chain-id $CHAIN | grep -q 'total:'"
else
  echo "SKIP  registry (needs the pocketd binary)"
fi

if [ "$HAVE_BINARY" = 1 ]; then
  check "show-service returns a known service" bash -c \
  "$POCKETD query service show-service agentsearch-web-extract-v1 --node $NODE --chain-id $CHAIN | grep -q 'id: agentsearch-web-extract-v1'"
else
  echo "SKIP  show-service (needs the pocketd binary)"
fi

if [ "$HAVE_BINARY" = 1 ]; then
  check "service card decodes to pocket-service-card/v1" bash -c \
  "$POCKETD query service card agentsearch-web-extract-v1 --node $NODE --chain-id $CHAIN | grep -q 'pocket-service-card/v1'"
else
  echo "SKIP  card decode (needs the pocketd binary)"
fi

if [ "$HAVE_BINARY" = 1 ]; then
  check "example card validates" "$POCKETD" tx service validate-card card.json
else
  echo "SKIP  validate-card (needs the pocketd binary)"
fi

if [ "$HAVE_BINARY" = 1 ]; then
  check "node is on mainnet and synced" bash -c \
  "$POCKETD status --node $NODE | grep -q '\"network\":\"pocket\"'"
else
  echo "SKIP  network (needs the pocketd binary)"
fi

if [ "$HAVE_BINARY" = 1 ]; then
  check "node is not catching up" bash -c \
  "$POCKETD status --node $NODE | grep -q '\"catching_up\":false'"
else
  echo "SKIP  catching up (needs the pocketd binary)"
fi

# the offline claims: build and sign must work with no reachable node
offline_build() {
  "$POCKETD" tx service add-service verify-offline-v1 "Verify Offline" 10 \
    --card-file card.json --from verify-demo --keyring-backend test --home "$TMPHOME" \
    --chain-id pocket --node http://127.0.0.1:1 --gas 200000 --fees 30000upokt \
    --generate-only 2>/dev/null
}

offline_sign() {
  offline_build | "$POCKETD" tx sign /dev/stdin --from verify-demo \
    --keyring-backend test --home "$TMPHOME" --chain-id pocket \
    --node http://127.0.0.1:1 --offline --account-number 0 --sequence 0 2>/dev/null
}

if [ "$HAVE_BINARY" = 1 ]; then
  TMPHOME=$(mktemp -d)
  if "$POCKETD" keys add verify-demo --keyring-backend test --home "$TMPHOME" >/dev/null 2>&1; then
    check "generate-only works with an unreachable node" bash -c \
      "$(declare -f offline_build); POCKETD='$POCKETD' TMPHOME='$TMPHOME' offline_build | grep -q MsgAddService"
    check "sign --offline works with an unreachable node" bash -c \
      "$(declare -f offline_build offline_sign); POCKETD='$POCKETD' TMPHOME='$TMPHOME' offline_sign | grep -q signatures"
  else
    echo "SKIP  offline build and sign (could not create a temporary key)"
  fi
  rm -rf "$TMPHOME"
else
  echo "SKIP  offline build and sign (needs the pocketd binary)"
fi

echo
echo "== summary: $PASS passed, $FAIL failed =="
exit "$FAIL"
