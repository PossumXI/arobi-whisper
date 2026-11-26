# Technical Walkthrough & Independent Reproduction Guide — Arobi Whisper

This guide shows Gno.land developers and judges how to reproduce every `gno test`, E2EE crypto throughput benchmark, AVL flat-gas curve, and cross-harness Agent Bus round-trip in **`arobi-whisper`**, along with its live **Gno.land Onyx (`onyx-1`)** status.

---

## 1. Reproducing Tests & Benchmarks Locally

```bash
# 1. Run Gno lint + realm/package unit tests (including MsgRun IsUserCall() payment guards & v2 escrow domain tags)
bash scripts/run-gno-tests.sh

# 2. Run Adena web adapter, cross-harness Agent Bus, gnosh peer relay, and MCP stdio tests
node --test web/adena-whisper.test.mjs bridge/gnosh-peer-relay.test.mjs

# 3. Verify clean MCP stdio setup & shutdown for gnosh.ai / Ullumii / HUE
node bridge/whisper-mcp-server.mjs --print-gnosh-mcp
```

### Key Measured Results (`BENCHMARKS.md`)
- **Client-side E2EE Throughput (`X25519 + ChaCha20-Poly1305`):** `1,104–1,221 ops/s` zero-plaintext seal/open round-trips; any 1-bit ciphertext or commitment mutation fails closed.
- **Flat-Gas AVL Storage (`PR #8`):** Replacing linear slice scans with Gno AVL trees and O(1) counters cut the 1,000th `SendMessage` from **`308,296,265` gas to `43,122,198` gas (`7.15×` reduction)** on an in-memory Gno node.

---

## 2. Live Gno.land Onyx (`onyx-1`) Deployment Status

- **Upstream dependency `gno.land/p/g1jdc6h96he7wf7xfycu6u7wqhv5j762qtxu5k5t/signals`:** **`ACTIVE` on `onyx-1`** (queryable via `gnokey query vm/qfile`).
- **`gno.land/p/g1jdc6h96he7wf7xfycu6u7wqhv5j762qtxu5k5t/whisper` (block `1,343,650`) & `gno.land/r/g1jdc6h96he7wf7xfycu6u7wqhv5j762qtxu5k5t/whisper` (block `1,343,652`):** Confirmed on-chain in `vm/qinertpaths` (`gnokey query vm/qinertpaths -remote https://rpc.onyx.testnets.gno.land:443`), awaiting Onyx approver `enablepkg` activation alongside `p/.../assurance`.

---

## 3. 3-Month & 6-Month Gnome Tavern Roadmap

- **Month 1–3:** Activate `/v2` flat-gas Whisper realms on `onyx-1`, add multi-recipient group key-ratchet channels for DAO/team rooms, and ship live Adena one-click HTLC bounty settlement templates.
- **Month 3–6:** Deploy `r/arobi/whisper` to Gno.land mainnet, integrate threshold arbiter resolution for disputed DeFi escrows, and bridge cross-harness `gnosh.ai` ↔ `Ullumii` peer plans over on-chain Whisper mailboxes.
