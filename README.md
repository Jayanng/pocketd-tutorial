# From zero to a signed transaction: Pocket Network with pocketd

A reproducible walkthrough for developers who want to work with Pocket
Network at the chain level. By the end you will have installed the official
`pocketd` binary and verified its checksum, read live chain state including
the exact fee for registering a service, created a key with safe handling
rules, and built and signed a real service registration transaction on your
own machine. Nothing is broadcast and no money is spent.

Every command in this tutorial was executed on 2026-11-19 against the live
mainnet endpoints. Every output block is a copy of what those commands
really returned: one recovery mnemonic is redacted, and blocks are cut
down where their label says abridged or summary. Nothing here is
simulated.

## How the chain side works

The Agentic Portal that serves applications is backed by Pocket Network's
own chain. Services, fees and ownership all live in chain state, and
`pocketd` is the CLI for both sides of it: `query` reads state, `tx`
builds and sends transactions that change it.

```
pocketd (your machine)
  │
  ├── queries ───────────────► mainnet RPC ──► chain state
  │                              (params, services, accounts)
  │
  └── add-service --generate-only ──► tx.json (unsigned, fully reviewable)
          │
          └── tx sign --offline ──► tx-signed.json (signed, still local)
                  │
                  └── tx broadcast ──► the chain executes MsgAddService:
                       (documented here, not run)   the add_service_fee is
                                                    taken and the service is
                                                    registered to your address
```

Three facts shape everything below:

1. Registering a service costs the `add_service_fee`, charged once at
   creation, plus the transaction's gas fee. Both are visible before you
   sign anything.
2. Every transaction is built and signed offline first. The generated JSON
   is the review surface: you approve exactly what will execute.
3. Keys live in a keyring on your machine, and commands are the only
   thing that moves them. How safely you treat them is up to you, and the
   rules are short.

## Prerequisites

- Linux or macOS on x86-64 or arm64. The release ships all four
  archives, and this tutorial uses `pocket_linux_amd64.tar.gz`. For
  another platform, swap the archive name and its checksum line to the
  matching entry in `release_checksum`.
- `curl`, `tar`, and `sha256sum` (or `shasum -a 256` on macOS).
- No wallet, no tokens, no account. This walkthrough creates its own demo
  key and stops before broadcasting.

## Part 1: Install pocketd and verify the checksum

The official binaries ship in the poktroll repository's releases with a
`release_checksum` file. Download both, verify before you trust:

```bash
curl -sL -o pocket_linux_amd64.tar.gz \
  https://github.com/pokt-network/poktroll/releases/download/v0.1.37/pocket_linux_amd64.tar.gz
curl -sL -o release_checksum \
  https://github.com/pokt-network/poktroll/releases/download/v0.1.37/release_checksum
echo 'e0c5d10bbfcc8cff23736a1b02b7e4066e4681f2b1d1a9596345fd8cedaa21be  pocket_linux_amd64.tar.gz' | sha256sum -c -
tar -xzf pocket_linux_amd64.tar.gz
./pocketd version
```

Expected result:

```
pocket_linux_amd64.tar.gz: OK
0.1.37
```

The checksum line is a copy of the published `release_checksum` entry for
this exact file, so the verification is against what the maintainers
released, not against anything this tutorial tells you to trust. On
macOS, use `shasum -a 256` in place of `sha256sum`.

## Part 2: Read live chain state

Queries need a node. Two equivalent ways to point `pocketd` at mainnet:

```bash
# explicit flags
./pocketd query service params \
  --node https://sauron-rpc.infra.pocket.network --chain-id pocket

# or the network moniker, which sets --chain-id, --node and --grpc-addr
# for a named network at once
./pocketd query service params --network main
```

Expected result (both forms):

```yaml
params:
  add_service_fee:
    amount: "1000000000"
    denom: upokt
  target_num_relays: "100000"
```

This is the fee question answered by the chain itself: registering a
service costs `add_service_fee` = 1,000,000,000 upokt = 1,000 POKT,
charged once at creation. It is a governance parameter, so query it again
before you ever register for real. The same value is reachable over the
public REST route, which is how you can cross-check the CLI against an
independent interface:

```bash
curl -s https://sauron-api.infra.pocket.network/pokt-network/poktroll/service/params
```

Expected result: `{"params":{"add_service_fee":{"denom":"upokt","amount":"1000000000"},"target_num_relays":"100000"}}`

Now see what is already registered:

```bash
./pocketd query service all-services \
  --node https://sauron-rpc.infra.pocket.network --chain-id pocket
```

Expected result (abridged, 279 services at capture time):

```yaml
pagination:
  next_key: aG9wci8=
  total: "279"
service:
- compute_units_per_relay: "100000"
  id: address-standardization
  name: Address Standardization
  owner_address: pokt15je33utektp7e7t6rm7mxfgf6ysssw8fjna5px
- compute_units_per_relay: "100000"
  id: agent-trust
  name: Agent Trust
  owner_address: pokt16cqt2tjzec6gsxdncl0v6k2aa7awya0wghevlw
- compute_units_per_relay: "50000"
  id: agentsearch-web-extract-v1
  name: AgentSearch Web Extract
  owner_address: pokt10pqk9609p44n5hudwkmzwkt6hnuphlp9p5nhwh
- [... pagination continues ...]
```

Inspect one in full:

```bash
./pocketd query service show-service agentsearch-web-extract-v1 \
  --node https://sauron-rpc.infra.pocket.network --chain-id pocket
```

Expected result (card base64 abridged):

```yaml
service:
  compute_units_per_relay: "50000"
  id: agentsearch-web-extract-v1
  metadata:
    card: <base64 of the service card>
  name: AgentSearch Web Extract
  owner_address: pokt10pqk9609p44n5hudwkmzwkt6hnuphlp9p5nhwh
```

That base64 blob is the service card, and the CLI can decode it:

```bash
./pocketd query service card agentsearch-web-extract-v1 \
  --node https://sauron-rpc.infra.pocket.network --chain-id pocket
```

Expected result (head): a JSON document with `"schema": "pocket-service-card/v1"`,
a description, `rpc_types`, healthcheck probes and an `updated` date. The
card is how a service describes itself to gateways and agents. You will
write your own in Part 4.

One more read worth knowing:

```bash
./pocketd status --node https://sauron-rpc.infra.pocket.network
```

Expected result (summary):

```
network: pocket | comet: 0.38.26 | moniker: pnf-seed-one
latest_block_height: 1015210 | catching_up: False
earliest_block_height: 1
```

The network is live and producing blocks. `catching_up: False` means the
node you are talking to is synced.

## Part 3: Create a key, safely

`pocketd` supports several keyring backends. The official documentation
draws the security line for you, and the CLI's own help text draws the
same one:

| Backend | Behavior | Recommended for |
|---|---|---|
| `os` | OS credential store (Keychain, libsecret), protected by your system login | production |
| `file` | encrypted keystore on disk, password required on each use | production |
| `test` | unencrypted on disk, no password prompt | local development only |
| `memory` | in-memory only, lost when the process exits | ephemeral runs |

The CLI also lists platform-specific backends (`kwallet`, `pass`) where
those tools are installed. Keys use Pocket's coin type (635) and the
standard derivation path `m/44'/635'/0'/0/0`, which matters when you
import the same mnemonic into another wallet later.

This walkthrough uses `--keyring-backend test` so the commands run without
interaction. For real funds, use `os` or `file`. The difference is the
whole security story, so the CLI is blunt about it.

```bash
mkdir -p home
./pocketd keys add tutorial-demo --keyring-backend test --home ./home
./pocketd keys list --keyring-backend test --home ./home
```

Expected result (address output, pubkey abridged):

```yaml
- address: pokt1lyamkkp54fa845slwffn0yke43xlfvhtqsp5qe
  name: tutorial-demo
  pubkey: '{"@type":"/cosmos.crypto.secp256k1.PubKey","key":"..."}'
  type: local
```

The rest of the output is the recovery notice, redacted in this capture:

```
**Important** write this mnemonic phrase in a safe place.
It is the only way to recover your account if you ever forget your password.

[REDACTED: the tool prints a 24-word recovery mnemonic here. Never share it.]
```

Note where the key material goes: the address record is printed to stdout,
while the recovery mnemonic is printed to the error stream with a warning.
That split is deliberate tooling hygiene. When you run this yourself, the
mnemonic appears on your terminal and nowhere else. Never paste it into a
chat, a log file, or a shared screen. It is the only way to recover the
account, which means it is also the only thing an attacker needs to take
it. This walkthrough never needs the mnemonic again.

Two more rules worth internalizing while you are here:

- `pocketd keys export` writes a key out of the keyring. Its default is an
  ASCII-armored encrypted format. The raw formats (`--unarmored-hex
  --unsafe`) exist for advanced migration use and the tool's own help
  warns that anyone using them must be fully aware of the risks.
- A dedicated key per purpose (one for experiments, one for services, one
  for treasury) limits what any single leak can cost.

## Part 4: Write and validate the service card

A service card is a small self-describing JSON document (256 KiB limit)
that tells gateways and agents what a service does. This repository ships
[`card.json`](card.json), a minimal card for a demo price lookup API. Read
it before you use it, then validate it the same way the chain will:

```bash
./pocketd tx service validate-card card.json
```

Expected result:

```
✅ valid service card: pocket-service-card/v1, 1080 bytes (onchain max 262144)
```

Validation is offline. A card that passes here will not be rejected for
shape at registration time.

## Part 5: Build the transaction offline

The registration command is `add-service`. Its signature says exactly what
the chain expects:

```bash
./pocketd tx service add-service <service_id> <service_name> \
  [compute_units_per_relay: default=1] [flags]
```

The service ID must be unique in the network, and only the owner can update
a service after creation. Build the transaction with `--generate-only`,
which writes the unsigned transaction to stdout and touches nothing else:

```bash
./pocketd tx service add-service \
  'tutorial-price-lookup-v1' 'Tutorial Price Lookup' 10 \
  --card-file card.json \
  --from tutorial-demo --keyring-backend test --home ./home \
  --chain-id pocket --node https://sauron-rpc.infra.pocket.network \
  --gas 200000 --fees 30000upokt \
  --generate-only > tx.json
```

Expected result: `tx.json` contains one `MsgAddService` (abridged):

```json
{
  "body": {
    "messages": [{
      "@type": "/pocket.service.MsgAddService",
      "owner_address": "pokt1lyamkkp54fa845slwffn0yke43xlfvhtqsp5qe",
      "service": {
        "id": "tutorial-price-lookup-v1",
        "name": "Tutorial Price Lookup",
        "compute_units_per_relay": "10",
        "owner_address": "pokt1lyamkkp54fa845slwffn0yke43xlfvhtqsp5qe",
        "metadata": { "card": "<base64 of card.json>" }
      }
    }]
  },
  "auth_info": {
    "signer_infos": [],
    "fee": { "amount": [{ "denom": "upokt", "amount": "30000" }],
             "gas_limit": "200000" }
  },
  "signatures": []
}
```

Read this file before signing. It is the review surface: the owner address,
the service identity, the compute units, the card, and the fee are all
visible and immutable from here on.

Costs come in two separate places, and it is worth being precise:

1. The `gas fee` (`--fees 30000upokt` above) pays validators for
   processing. That value is this example's choice. Gas pricing is
   validator policy, so check current conditions before a real broadcast.
2. The `add_service_fee` (1,000 POKT, verified in Part 2) is charged
   inside the transaction at execution, once, at creation. The official
   docs put the balance rule bluntly: your owner account must hold more
   than the fee plus gas. Updates to an existing service cost gas only.

## Part 6: Sign offline

Signing reads the generated file and attaches a signature. It never
touches the network in `--offline` mode:

```bash
./pocketd tx sign tx.json \
  --from tutorial-demo --keyring-backend test --home ./home \
  --chain-id pocket --offline --account-number 0 --sequence 0 \
  > tx-signed.json
```

Expected result (summary of `tx-signed.json`):

```
signatures: 1 | base64 sig length: 88
signer_infos: [{"public_key": {...}, "mode_info": {"single": {"mode": "SIGN_MODE_DIRECT"}}, "sequence": "0"}]
fee: {"amount": [{"denom": "upokt", "amount": "30000"}], "gas_limit": "200000"}
```

About the two numeric flags. `--account-number` and `--sequence` are part
of what gets signed, and wrong values make the transaction fail at
broadcast. In offline mode you must provide them yourself, so the zeros
above are placeholders that prove the mechanics. Before a real broadcast,
get the real values from chain state:

```bash
./pocketd query auth account pokt1lyamkkp54fa845slwffn0yke43xlfvhtqsp5qe \
  --node https://sauron-rpc.infra.pocket.network --chain-id pocket
```

Expected result for the demo address (first line):

```
rpc error: code = NotFound desc = 
```

This is the correct and honest answer: an address that has never received
funds has no on-chain account yet. The account is created when it first
holds tokens, and at that point this query returns its account number and
the next sequence to sign with. This tutorial's companion, the
[Agentic Portal walkthrough](https://github.com/Jayanng/pocket-agentic-portal-tutorial),
showed the same discipline on the payment side: quote first, fund second.
Here it reads: check the account, then sign, then broadcast.

## Part 7: Broadcast (documented, not run)

The final step is one command, and this is where the tutorial deliberately
stops:

```bash
./pocketd tx broadcast tx-signed.json \
  --node https://sauron-rpc.infra.pocket.network --chain-id pocket
```

Broadcasting executes the transaction for real: the gas fee and the
1,000 POKT `add_service_fee` are deducted and the service is registered
under your address. Both `broadcast` and `simulate` need a funded
on-chain account, so neither can be exercised with the unfunded demo key
this tutorial creates. Before you ever broadcast for real, this checklist
is worth the thirty seconds:

1. `query service params` again and confirm the `add_service_fee` is what
   you expect. It is governance-controlled and can change.
2. Confirm the owner account holds more than the fee plus gas.
3. Re-read `tx.json` and confirm the service ID, name and card are yours.
4. Rebuild the signature with the real account number and sequence.
5. To test before spending, run `tx simulate` on the unsigned `tx.json`
   with your funded key. The node reports the gas the call consumes or
   the error it would fail with.

Security rules, in order of importance:

- A key that can sign is a key that can spend. Keep signing keys in `os`
  or `file` backends, never `test`, and never reuse a tutorial key for
  real funds.
- The recovery mnemonic is the account. It lives offline, in a safe, and
  never in a terminal scrollback you plan to share.
- Review the generated transaction, not the command. `--generate-only`
  turns your intent into a file you can read. The file
  is what gets signed.
- Nothing in this tutorial broadcasts. That boundary is deliberate, and
  crossing it should be a decision, not a habit.

## Run the verification

[`examples/verify.sh`](examples/verify.sh) re-checks every read-only claim
this tutorial makes: checksum, version, live params, the service registry,
a service card decode, card validation, node status, and the offline
claims themselves (build and sign with an unreachable node). It creates
only a throwaway key in a temporary directory, and it never sends
anything to the network.

If you have not installed `pocketd` yet, [`examples/bootstrap.sh`](examples/bootstrap.sh)
does Part 1 for you: it downloads the release, checks the published
checksum, and unpacks the binary into the repository root.

```bash
bash examples/bootstrap.sh   # downloads and verifies pocketd
bash examples/verify.sh      # checks the tutorial's claims
```

Without the binary, `verify.sh` still runs the checks that need no local
CLI and reports the rest as `SKIP`.

Expected result: a line per check ending in `PASS`, and a summary with
zero failures (13 checks after the bootstrap). The archive check reports
`SKIP` when `pocket_linux_amd64.tar.gz` is not in the repository root,
since it verifies bytes this repository does not ship.

## Test evidence

Everything above was run live on 2026-11-19. Raw sanitized captures are in
[`evidence/`](evidence/):

| Capture | File | Verified |
|---|---|---|
| Checksum verification and version | `01-install-and-checksum.txt` | live |
| Service params via CLI, REST cross-check and `--network main` | `02-service-params.txt` | live |
| Service registry listing | `03-all-services.txt` | live |
| Service detail and decoded card | `04-show-service-and-card.txt` | live |
| Node status and relay mining difficulty | `05-status-and-relay-mining.txt` | live |
| Key creation and listing (mnemonic redacted) | `06-keyring.txt` | live |
| Card validation | `07-validate-card.txt` | live |
| Offline transaction build | `08-generate-only.txt` | live |
| Offline signature and the absent-account answer | `09-sign-offline.txt` | live |
| Verification script run | `10-verify-run.txt` | live |

## Sources

- https://docs.pocket.network/pocketd/
- https://docs.pocket.network/pocketd/accounts-keys/
- https://docs.pocket.network/pocketd/querying/
- https://docs.pocket.network/pocketd/transactions/
- https://docs.pocket.network/services/register/
- https://github.com/pokt-network/poktroll/releases/tag/v0.1.37
- https://agent.pocket.network/services
