# Arobi Whisper on Gno.land

**End-to-end encrypted DeFi messenger natively on Gno.land — client-sealed `X25519 + XChaCha20-Poly1305` chat paired with GNOT tipping, HTLC/expiry DeFi escrows, programmable anti-spam inbox rules, and RFC 6962 cryptographic evidence proofs.**

Built by [Arobi Technology Alliance, Inc.](https://aura-genesis.org) (live web app at [aura-genesis.org/whisper](https://aura-genesis.org/whisper)) for the **Gnome Tavern Hackathon | Gno.land**.

---

## Why Whisper on Gno.land?

- **Zero Centralized Server / Zero TOFU:** Your X25519 encryption public key and claim-once `@handle` bind directly to your native Gno `g1...` address via `cur.Previous().Address()`.
- **True End-to-End Encryption:** Every message is sealed client-side with an ephemeral X25519 key + `HKDF-SHA256` (`arobi-whisper-x25519-xchacha-v1`) + `XChaCha20-Poly1305` (24-byte nonce). Only ciphertext, ephemeral public key, nonce, and `SHA-256` commitment ever touch Gno.land state.
- **Tiered GNOT Subscriptions & Service Fees (mirroring live `aura-genesis.org/whisper`):**
  - **Free Tier:** `110` credits, `4 KiB` max ciphertext, standard E2EE messaging.
  - **Pro Subscription (`Subscribe` in GNOT — default `25 GNOT` / 30 days):** `2,500` credits per 30-day period, `16 KiB` encrypted envelopes, and DeFi HTLC escrow creation.
  - **Pay-Per-Message Overage & Escrow Settlement Fees in GNOT:** Optional `0.01 GNOT` overage fee when credits reach `0`, plus a `1%` (`100 bps`) protocol settlement fee on claimed DeFi escrows (`0%` fee on expired refunds; `100%` of direct user tips forward straight to recipients). Operator settlement routing is configured privately at deployment time and never hardcoded or publicly disclosed.
- **Built-In Arobi Assurance Evidence:** Directly imports `gno.land/p/arobi/assurance` so every delivered ciphertext envelope and DeFi escrow state transition is appended to an on-chain **RFC 6962 / RFC 9162 Merkle Accumulator** with independently verifiable inclusion proofs (`ProofForLeaf` / `VerifyLeafProof`).
- **Cross-Shell / Cross-Environment / Cross-Harness Encrypted Agent Bus (`agentbus.gno` + `bridge/whisper-agent-bus.mjs`):** Whisper is a standalone E2EE DeFi messenger, and also ships a dedicated **Agent Bus utility** so autonomous agents running across different shells (`bash`, `pwsh`), environments (containers, WSL, cloud runners), and harnesses (**`Ullumii`**, **`gnosh.ai`**, Gno realms) can exchange X25519 + ChaCha20-Poly1305 encrypted handoffs, delegated warrants, and RFC 6962 evidence digests directly over Whisper without sharing local pipes or centralized message brokers.

---

## Repository Layout

| Path | Description |
| --- | --- |
| `gno.land/p/arobi/whisper` | Pure Gno package: wire-compatible envelope & escrow types, `AgentBusRoute` + `BindAgentEnvelopeCommitment` (`agentbus.gno`), strict X25519/nonce/canonical-Base64/handle validators, RFC 6962 leaf hashing (imports `gno.land/p/arobi/assurance`). |
| `gno.land/r/arobi/whisper` | Stateful Gno.land realm: on-chain key directory, claim-once `@handles`, key rotation, Free/Pro GNOT subscriptions (`Subscribe`), GNOT overage & 1% escrow settlement fees with private opaque operator settlement, anti-spam inbox policies, direct GNOT tip messaging, HTLC/expiry DeFi escrows, RFC 6962 proofs, and `gnoweb` `Render(path)` UI. |
| `bridge/whisper-agent-bus.mjs` | Zero-dependency Node.js CLI & SDK (`keygen`, `seal`, `open`, `buildAgentWhisperTx`) for cross-shell / cross-environment / cross-harness (`Ullumii`, `gnosh.ai`, Docker, WSL) encrypted agent communication over Whisper. |
| `web/adena-whisper.mjs` | Adena Wallet (`window.adena.DoContract`) transaction builders (`RegisterIdentity`, `Subscribe`, `SendMessage`, `CreateEscrow`, `ClaimEscrow`, `RefundEscrow`) + Gno.land `abci_query` adapter. |
| `web/index.html` | Interactive browser E2EE + DeFi Escrow & Adena Wallet playground. |

---

## Cross-Shell / Cross-Harness Agent Bus Utility

Agents operating across isolated shells, containers, or harnesses (`Ullumii` ↔ `gnosh.ai` ↔ Gno realm) can seal and unseal authenticated handoff envelopes locally and relay only encrypted commitments across Gno.land:

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
node --test web/adena-whisper.test.mjs bridge/whisper-agent-bus.test.mjs
```

Tests run against real Gno v1.8.0 (`gno test -v`) and Node.js covering:
- Handle normalization & reserved-name protection (`@arobi`, `@ullumii`, duplicates)
- X25519 key, 24-byte nonce, and canonical AEAD Base64 ciphertext validation
- Free (`110` credits, `4 KiB`) vs Pro (`25 GNOT` / 30 days, `2,500` credits, `16 KiB`, DeFi escrows) metering, `0.01 GNOT` overage billing, and private opaque operator fee settlement (`InitOperator` / `SetSettlementSink` / `CollectServiceFees` with zero wallet address disclosure)
- Key rotation, allowlists, and `minTipUgnot` anti-spam enforcement
- 100% direct tip forwarding to recipients
- HTLC hash-locked encrypted DeFi escrow claim (`1%` protocol settlement fee in GNOT, `99%` to recipient), double-claim rejection, and `100%` (`0%` fee) sender refund after expiry
- Cross-shell / cross-harness `AgentBusRoute` validation, cryptographic commitment binding, and end-to-end X25519 + ChaCha20-Poly1305 seal/open round-trip (`Ullumii` ↔ `gnosh.ai`)
- On-chain RFC 6962 Merkle inclusion proof verification

---

## Live Gno.land Onyx Testnet (`onyx-1`) Submission Proof

Submitted on-chain to `onyx-1` (`https://rpc.onyx.testnets.gno.land:443`; currently parked in Onyx's `code_submission_policy = "inert"` approver activation queue — verifiable via `gnokey query vm/qinertpaths`):

| Package / Realm Path | Block Height | Transaction Hash |
| --- | ---: | --- |
| `gno.land/p/g1jdc6h96he7wf7xfycu6u7wqhv5j762qtxu5k5t/whisper` | `1343650` | `Y8yxq2g2dcj2q3PUrJDzHEk6TeyEq2mEDfXvn6yW0ow=` |
| `gno.land/r/g1jdc6h96he7wf7xfycu6u7wqhv5j762qtxu5k5t/whisper` | `1343652` | `/EB7ITw57NRhnrB9rIS5gi6hp73k9yRcHKwH6LWwOcc=` |

*(Also supports cross-harness Familiar `capability_lease` & `memory_sync` envelopes carrying `CapabilityDigestHex` and `MemoryRecallDigestHex` in `gno.land/p/arobi/whisper/agentbus.gno`.)*

---

## Deploying to Gno.land Onyx Testnet (`onyx-1`)

```bash
# 1. Deploy dependency packages (from gno-immaculate-sdk-agent-builder)
gnokey maketx addpkg --pkgpath gno.land/p/<your-namespace>/signals --pkgdir ../gno-immaculate-sdk-agent-builder/gno.land/p/arobi/signals \
  -remote https://rpc.onyx.testnets.gno.land:443 -chainid onyx-1 \
  --gas-fee 1000000ugnot --gas-wanted 10000000 --broadcast <your-testnet-key>

gnokey maketx addpkg --pkgpath gno.land/p/<your-namespace>/assurance --pkgdir ../gno-immaculate-sdk-agent-builder/gno.land/p/arobi/assurance \
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
