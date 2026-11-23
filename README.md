# Arobi Whisper on Gno.land

**End-to-end encrypted DeFi messenger natively on Gno.land — client-sealed `X25519 + XChaCha20-Poly1305` chat paired with GNOT tipping, HTLC/expiry DeFi escrows, programmable anti-spam inbox rules, and RFC 6962 cryptographic evidence proofs.**

Built by [Arobi Technology Alliance, Inc.](https://aura-genesis.org) (live web app at [aura-genesis.org/whisper](https://aura-genesis.org/whisper)) for the **Gnome Tavern Hackathon | Gno.land**.

---

## Why Whisper on Gno.land?

- **Zero Centralized Server / Zero TOFU:** Your X25519 encryption public key and claim-once `@handle` bind directly to your native Gno `g1...` address via `cur.Previous().Address()`.
- **True End-to-End Encryption:** Every message is sealed client-side with an ephemeral X25519 key + `HKDF-SHA256` (`arobi-whisper-x25519-xchacha-v1`) + `XChaCha20-Poly1305` (24-byte nonce). Only ciphertext, ephemeral public key, nonce, and `SHA-256` commitment ever touch Gno.land state.
- **DeFi-Native Encrypted Chat:**
  - **Direct Tips & Anti-Spam Gating:** Set a programmable `minTipUgnot` or `allowListOnly` rule on your inbox; 100% of direct GNOT tips forward atomically to the recipient in the same call.
  - **Conditional Encrypted Escrows (`SendEscrowMessage` / `ClaimEscrow` / `RefundEscrow`):** Lock GNOT alongside an encrypted message — with an optional `SHA-256(preimage)` HTLC hashlock for atomic encrypted OTC trades, bounties, or paid secret reveals — and 100% zero-fee refund to sender after expiry.
- **Built-In Arobi Assurance Evidence:** Directly imports `gno.land/p/arobi/assurance` so every delivered ciphertext envelope and DeFi escrow state transition is appended to an on-chain **RFC 6962 / RFC 9162 Merkle Accumulator** with independently verifiable inclusion proofs (`ProofForLeaf` / `VerifyLeafProof`).

---

## Repository Layout

| Path | Description |
| --- | --- |
| `gno.land/p/arobi/whisper` | Pure Gno package: wire-compatible envelope & escrow types, strict X25519/nonce/canonical-Base64/handle validators, RFC 6962 leaf hashing (imports `gno.land/p/arobi/assurance`). |
| `gno.land/r/arobi/whisper` | Stateful Gno.land realm: on-chain key directory, claim-once `@handles`, key rotation, anti-spam inbox policies, direct GNOT tip messaging, HTLC/expiry DeFi escrows, RFC 6962 proofs, and `gnoweb` `Render(path)` UI. |
| `web/adena-whisper.mjs` | Adena Wallet (`window.adena.DoContract`) transaction builders + Gno.land `abci_query` adapter. |
| `web/index.html` | Interactive browser E2EE + DeFi Escrow & Adena Wallet playground. |

---

## Running Tests Locally

```bash
bash scripts/run-gno-tests.sh
```

Tests run against real Gno v1.8.0 (`gno test -v`) covering:
- Handle normalization & reserved-name protection (`@arobi`, `@ullumii`, duplicates)
- X25519 key, 24-byte nonce, and canonical AEAD Base64 ciphertext validation
- Key rotation, allowlists, and `minTipUgnot` anti-spam enforcement
- 100% direct tip forwarding with zero residual realm custody
- HTLC hash-locked encrypted DeFi escrow claim (100% peer-to-peer settlement to recipient with zero residual realm balance), double-claim rejection, and 100% zero-fee sender refund after expiry
- On-chain RFC 6962 Merkle inclusion proof verification

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
