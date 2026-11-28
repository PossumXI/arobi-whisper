# Arobi Whisper

**End-to-end encrypted DeFi messenger built on Gno.land — client-sealed `X25519 + XChaCha20-Poly1305` chat paired with GNOT tipping, HTLC/expiry DeFi escrows, programmable anti-spam inbox rules, and RFC 6962 cryptographic evidence proofs. Deployed to the Gno.land Onyx testnet (`onyx-1`).**

Built by [Arobi Technology Alliance, Inc.](https://aura-genesis.org) (live web app at [aura-genesis.org/whisper](https://aura-genesis.org/whisper)) for the **Gnome Tavern hackathon**. Tested with `gno test` on current master.

- **1080p Demo Video (2m 11s):** [Watch / Download MP4](https://github.com/PossumXI/arobi-whisper/releases/download/v1.0.0-gnome-tavern/Arobi_Whisper_Demo_1080p.mp4)
- **Live Adena Browser Playground (100/100/100 PageSpeed):** [possumxi.github.io/arobi-whisper/web/](https://possumxi.github.io/arobi-whisper/web/)
- **Public Benchmarks on Hugging Face Hub:** [Dataset (JSONL)](https://huggingface.co/datasets/TruLumecreator/immaculate-agent-gno-benchmarks) · [Interactive Space](https://huggingface.co/spaces/TruLumecreator/immaculate-agent-gno-benchmarks)

---

## Run it locally in 5 minutes

Same steps as the [quick start](https://docs.gno.land/builders/quickstart): install the toolchain, run the tests, boot `gnodev`, open the realm.

```sh
# 1. Install gno, gnokey, and gnodev from github.com/gnolang/gno master.
#    Needs Go 1.25+, git, and make. The quick start installer without
#    --from-source installs the latest release instead of master.
curl -fsSL https://raw.githubusercontent.com/gnolang/gno/master/misc/install.sh | sh -s -- --from-source
export PATH="$HOME/.gno/bin:$PATH"

# 2. Clone this repo and the signals/assurance dependency as siblings.
mkdir -p "$HOME/src" && cd "$HOME/src"
git clone https://github.com/PossumXI/arobi-whisper.git
git clone https://github.com/PossumXI/immaculate-sdk-agent-builder.git

# 3. Unify both repos in one workspace. `immaculate-sdk-agent-builder` ships
#    its own root `gnowork.toml` so it works standalone, and current `gno`'s
#    workspace walker skips child directories that hold a nested `gnowork.toml`.
#    Removing the nested file lets the parent `gnowork.toml` resolve both repos
#    together for `gno test` and `gnodev .` (or run `bash scripts/run-gno-tests.sh`
#    from `arobi-whisper` to use an automatic temporary workspace without editing
#    either checkout).
rm -f immaculate-sdk-agent-builder/gnowork.toml
touch gnowork.toml

# 4. Test the package and the realm (or run `bash scripts/run-gno-tests.sh`).
cd arobi-whisper
gno test ./gno.land/p/arobi/whisper ./gno.land/r/arobi/whisper

# 5. Boot a local chain from the realm directory. The parent gnowork.toml
#    loads this realm together with gno.land/p/arobi/whisper, signals, and assurance.
cd gno.land/r/arobi/whisper
gnodev .
# Open http://localhost:8888  (redirects to /r/arobi/whisper)

# 6. Key for a testnet deploy. Fund the g1 address at the faucet.
#    Do not commit the mnemonic gnokey prints.
gnokey list
gnokey add dev
```

Deploy commands are in [Deploying to Gno.land Onyx Testnet (`onyx-1`)](#deploying-to-gnoland-onyx-testnet-onyx-1) below.

---

## Why Arobi Whisper?

Arobi Whisper is an agent chat realm built on Gno.land and submitted on-chain to the Gno.land Onyx testnet (`onyx-1`), where it awaits activation (see the deployment section below).

- **Zero Centralized Server / Zero TOFU:** Your X25519 encryption public key and claim-once `@handle` bind directly to your native `g1...` address via `cur.Previous().Address()`.
- **True End-to-End Encryption:** Every message is sealed client-side with an ephemeral X25519 key + `HKDF-SHA256` (`arobi-whisper-x25519-xchacha-v1`) + `XChaCha20-Poly1305` (24-byte nonce). Only ciphertext, ephemeral public key, nonce, and `SHA-256` commitment ever touch Gno.land state.
- **Tiered GNOT Subscriptions & Service Fees (mirroring live `aura-genesis.org/whisper`):**
  - **Free Tier:** `110` credits, `4 KiB` max ciphertext, standard E2EE messaging.
  - **Pro Subscription (`Subscribe` in GNOT — default `25 GNOT` / 30 days):** `2,500` credits per 30-day period, `16 KiB` encrypted envelopes, and DeFi HTLC escrow creation.
  - **Pay-Per-Message Overage & Escrow Settlement Fees in GNOT:** Optional `0.01 GNOT` overage fee when credits reach `0` (enforced on both `SendMessage` and `SendEscrowMessage`), plus a protocol settlement fee locked in `EscrowRecord.FeeBps` at creation time (default `1%` / `100 bps`, capped at `5%` / `500 bps`) on claimed DeFi escrows (`0%` fee on expired refunds; `100%` of direct user tips forward straight to recipients). The deploying account becomes `operator` atomically inside `init()` (no post-deploy claim race). `Render` and events do not print operator or settlement addresses; note that on a public chain, realm state, bank transfers, sender/recipient addresses, timestamps, and tip/escrow amounts are publicly inspectable metadata (E2EE protects message plaintext only).
- **Built-In Arobi Assurance Evidence:** Directly imports `gno.land/p/arobi/assurance` so every delivered ciphertext envelope and DeFi escrow state transition is appended to an on-chain **RFC 6962 / RFC 9162 Merkle Accumulator** with independently verifiable inclusion proofs (`ProofForLeaf` / `VerifyLeafProof`).
- **Cross-Shell / Cross-Environment / Cross-Harness Encrypted Agent Bus (`agentbus.gno` + `bridge/whisper-agent-bus.mjs`):** Whisper is a standalone E2EE DeFi messenger, and also ships a dedicated **Agent Bus utility** so autonomous agents running across different shells (`bash`, `pwsh`), environments (containers, WSL, cloud runners), and harnesses (**`Ullumii`**, **`gnosh.ai`**, realms) can exchange X25519 + ChaCha20-Poly1305 encrypted handoffs, delegated warrants, and RFC 6962 evidence digests directly over Whisper without sharing local pipes or centralized message brokers.

---

## Repository Layout

| Path | Description |
| --- | --- |
| `gno.land/p/arobi/whisper` | Pure package: wire-compatible envelope & escrow types, `AgentBusRoute` + `BindAgentEnvelopeCommitment` (`agentbus.gno`), strict X25519/nonce/canonical-Base64/handle validators, RFC 6962 leaf hashing (imports `gno.land/p/arobi/assurance`). |
| `gno.land/r/arobi/whisper` | Stateful realm: on-chain key directory, claim-once `@handles`, key rotation, Free/Pro GNOT subscriptions (`Subscribe`), GNOT overage & 1% escrow settlement fees with private opaque operator settlement, anti-spam inbox policies, direct GNOT tip messaging, HTLC/expiry DeFi escrows, RFC 6962 proofs, and `gnoweb` `Render(path)` UI. |
| `bridge/whisper-agent-bus.mjs` | Zero-dependency Node.js CLI & SDK (`keygen`, `seal`, `open`, `buildAgentWhisperTx`) for cross-shell / cross-environment / cross-harness (`Ullumii`, `gnosh.ai`, Docker, WSL) encrypted agent communication over Whisper. |
| `bridge/gnosh-peer-relay.mjs` | Encrypted `gnosh.ai` `gnomem/v2` peer-plan relay (`peer_claim`, `peer_handoff`, `peer_done`, `peer_halt`) with fail-closed `planDigestHex` verification and SHA-256 HTLC escrow/claim builders. |
| `bridge/whisper-mcp-server.mjs` | Zero-dependency JSON-RPC 2.0 MCP stdio server (`whisper_keygen`, `whisper_create_hashlock`, `whisper_seal_peer_handoff`, `whisper_open_peer_handoff`, `whisper_build_relay_tx`) + `--print-gnosh-mcp` one-liner for `gnosh.ai`, `Ullumii`, and `HUE`. |
| `web/adena-whisper.mjs` | Adena Wallet (`window.adena.DoContract`) transaction builders (`RegisterIdentity`, `Subscribe`, `SetInboxPolicy`, `SendMessage`, `SendEscrowMessage`, `ClaimEscrow`, `RefundEscrow`) + `abci_query` adapter. |
| `web/index.html` | Interactive 4-tab browser playground: X25519 Identity & 25 GNOT Pro Subscribe, E2EE Chat & HTLC Escrows, Cross-Harness Agent Bus (`Ullumii` ↔ `gnosh.ai`), and Live `onyx-1` RPC Inspector. |
| `BENCHMARKS.md` / `WALKTHROUGH.md` | Live crypto throughput (`1,104–1,221 ops/s`), `7.1×` flat-gas AVL storage (`308.3M → 43.1M` gas at `1,000` messages), `onyx-1` status, and 3/6-month Gnome Tavern roadmap. |
| `CONTRIBUTORS.md` / `HACKATHON_SUBMISSION.md` | Team roles (`@iShowLinux`, `@ShadowPlague21`, `@canderson777`) and compliant Gnome Tavern submission guide. |

---

## Cross-Shell / Cross-Harness Agent Bus Utility

Agents operating across isolated shells, containers, or harnesses (`Ullumii` ↔ `gnosh.ai` ↔ realm) can seal and unseal authenticated handoff envelopes locally and relay only encrypted commitments on chain:

```bash
# 1. Generate X25519 agent bus keypairs on each host / container / harness
node bridge/whisper-agent-bus.mjs keygen

# 2. Seal a cross-harness handoff JSON packet from Ullumii (Windows pwsh) -> gnosh.ai (Linux container)
node bridge/whisper-agent-bus.mjs seal <RECIPIENT_X25519_PUB_HEX> packet.json > envelope.json

# 3. Unseal & authenticate on the receiving harness
node bridge/whisper-agent-bus.mjs open <RECIPIENT_X25519_PRIV_HEX> envelope.json
```

---

## Running Tests Locally

```bash
bash scripts/run-gno-tests.sh
node --test web/adena-whisper.test.mjs bridge/whisper-agent-bus.test.mjs bridge/gnosh-peer-relay.test.mjs

# Connect Arobi Whisper directly into gnosh.ai as a local MCP tool
node bridge/whisper-mcp-server.mjs --print-gnosh-mcp
```

`scripts/run-gno-tests.sh` is tested with `gno test` on current master (a parent `gnowork.toml` when this repo sits next to `immaculate-sdk-agent-builder`, otherwise a temporary workspace). Node tests cover the wallet adapter and the agent bus. Together they check:
- Handle normalization & reserved-name protection (`@arobi`, `@ullumii`, `@gaetano`, `@possumxi`, `@gno`, `@gnoland`, `@jaekwon`, duplicates)
- X25519 key, 24-byte nonce, and canonical AEAD Base64 ciphertext validation (and preserving existing `SignPubHex` when omitted on update)
- Free (`110` credits, `4 KiB`) vs Pro (`25 GNOT` / 30 days, `2,500` credits, `16 KiB`, DeFi escrows) metering, `0.01 GNOT` overage billing, atomic `init()` deployer-operator binding (`Operator` / `SetSettlementSink` / `TransferOperator` / `CollectServiceFees`), and direct-user-call guards on all payable entrypoints
- Key rotation, allowlists, and `minTipUgnot` anti-spam enforcement
- 100% direct tip forwarding to recipients
- HTLC hash-locked encrypted DeFi escrow claim (fee locked in `EscrowRecord.FeeBps` at creation time, claims refused at or after `ExpiryHeight`), double-claim rejection, and `100%` (`0%` fee) sender refund after expiry
- Cross-shell / cross-harness `AgentBusRoute` validation, cryptographic commitment binding, and end-to-end X25519 + ChaCha20-Poly1305 seal/open round-trip (`Ullumii` ↔ `gnosh.ai`)
- On-chain RFC 6962 Merkle inclusion proof verification

---

## Live Public Benchmarks

Full live measurements against `onyx-1` RPC and `bridge/whisper-agent-bus.mjs` are published in [BENCHMARKS.md](BENCHMARKS.md):

| Payload Tier (200 real X25519 + ChaCha20-Poly1305 round-trips) | Seal p50 | Open p50 | Throughput | Verified |
| --- | ---: | ---: | ---: | ---: |
| 256 B (Agent Handoff / Capability Lease) | `0.371 ms` | `0.442 ms` | **1,209 ops/s** | `100%` |
| 4 KiB (Free Tier Cap) | `0.369 ms` | `0.476 ms` | **1,221 ops/s** | `100%` |
| 16 KiB (Pro Tier Cap) | `0.397 ms` | `0.500 ms` | **1,104 ops/s** | `100%` |

- **Live Web Playground:** [https://possumxi.github.io/arobi-whisper/web/](https://possumxi.github.io/arobi-whisper/web/)
- **Google PageSpeed Insights:** [**100 Performance / 100 Best Practices / 100 SEO** (`LCP 0.2s`, `TBT 0ms`, `CLS 0`)](https://pagespeed.web.dev/analysis/https-possumxi-github-io-arobi-whisper-gno-web/q338wevmo1?form_factor=desktop)
- **Hugging Face Hub Benchmarks:** [Public Dataset](https://huggingface.co/datasets/TruLumecreator/immaculate-agent-gno-benchmarks) · [Interactive Space](https://huggingface.co/spaces/TruLumecreator/immaculate-agent-gno-benchmarks)

---

## Live on the Gno.land Onyx testnet (`onyx-1`)

The current code (this repository at `78234ca`) is live on `onyx-1` (`https://rpc.onyx.testnets.gno.land:443`) under the
project's deployer namespace `g1jkstuy23a8e44jvdjajc5gjjry9vwevmkvmdak`, deployed and enabled on 2026-11-27 (17:33 UTC):

| Path | Kind | Deployed at height | Open |
| --- | --- | --- | --- |
| `gno.land/p/g1jkstuy23a8e44jvdjajc5gjjry9vwevmkvmdak/whisper/v2` | package | 1,455,967 | [gnoweb](https://onyx.testnets.gno.land/p/g1jkstuy23a8e44jvdjajc5gjjry9vwevmkvmdak/whisper/v2) |
| `gno.land/r/g1jkstuy23a8e44jvdjajc5gjjry9vwevmkvmdak/whisper/v2` | realm | 1,455,968 | [gnoweb](https://onyx.testnets.gno.land/r/g1jkstuy23a8e44jvdjajc5gjjry9vwevmkvmdak/whisper/v2) |

- **The first submission.** The 2026-11-23 code stays live under the earlier namespace `g1jdc6h96he7wf7xfycu6u7wqhv5j762qtxu5k5t`
  (`gno.land/p/g1jdc6h96he7wf7xfycu6u7wqhv5j762qtxu5k5t/whisper` at height 1,343,650, `gno.land/r/g1jdc6h96he7wf7xfycu6u7wqhv5j762qtxu5k5t/whisper` at 1,343,652). A Gno path is
  immutable once submitted, so the current code is the `/v2` set above.
- **Operator.** `r/whisper/v2`'s operator is the deployer, set in `init()`. The first submission's realm had no operator
  set, so the same deployer claimed it on 2026-11-27, and nobody else can take its fee sink or pricing.
- **Check it yourself.** `gnokey query vm/qfile -data gno.land/r/g1jkstuy23a8e44jvdjajc5gjjry9vwevmkvmdak/whisper/v2 -remote https://rpc.onyx.testnets.gno.land:443`
  lists the realm's files. The gnoweb links above render it.

*(Also supports cross-harness Familiar `capability_lease`, `memory_sync`, and `gnosh.ai` `gnomem/v2` peer-plan relay envelopes carrying `CapabilityDigestHex` and `MemoryRecallDigestHex` in `gno.land/p/arobi/whisper/agentbus.gno`.)*

---

## Deploying to Gno.land Onyx Testnet (`onyx-1`)

```bash
# 1. Deploy dependency packages (from immaculate-sdk-agent-builder)
gnokey maketx addpkg --pkgpath gno.land/p/<your-namespace>/signals --pkgdir ../immaculate-sdk-agent-builder/gno.land/p/arobi/signals \
  -remote https://rpc.onyx.testnets.gno.land:443 -chainid onyx-1 \
  --gas-fee 1000000ugnot --gas-wanted 10000000 --broadcast <your-testnet-key>

gnokey maketx addpkg --pkgpath gno.land/p/<your-namespace>/assurance --pkgdir ../immaculate-sdk-agent-builder/gno.land/p/arobi/assurance \
  -remote https://rpc.onyx.testnets.gno.land:443 -chainid onyx-1 \
  --gas-fee 1000000ugnot --gas-wanted 10000000 --broadcast <your-testnet-key>

# 2. Deploy Whisper package + realm
gnokey maketx addpkg --pkgpath gno.land/p/<your-namespace>/whisper --pkgdir ./gno.land/p/arobi/whisper \
  -remote https://rpc.onyx.testnets.gno.land:443 -chainid onyx-1 \
  --gas-fee 1000000ugnot --gas-wanted 10000000 --broadcast <your-testnet-key>

gnokey maketx addpkg --pkgpath gno.land/r/<your-namespace>/whisper --pkgdir ./gno.land/r/arobi/whisper \
  -remote https://rpc.onyx.testnets.gno.land:443 -chainid onyx-1 \
  --gas-fee 1000000ugnot --gas-wanted 10000000 --broadcast <your-testnet-key>
```

---

## License

MIT — Copyright (c) 2026 Arobi Technology Alliance, Inc.
