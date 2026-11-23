# Live Public Benchmarks — Arobi Whisper

**Measured:** `2026-11-23T05:31:21Z` | **Reproduce:** `node experiments/run_live_benchmarks.mjs` (in companion repo [`immaculate-sdk-agent-builder`](https://github.com/PossumXI/immaculate-sdk-agent-builder))

All measurements below were captured against **real running systems**: live Gno.land Onyx Testnet (`onyx-1`) RPC (`https://rpc.onyx.testnets.gno.land:443`) and real Node.js `node:crypto` X25519 + HKDF-SHA256 + ChaCha20-Poly1305 authenticated encryption across `bridge/whisper-agent-bus.mjs`.

---

## 1. Cross-Shell / Cross-Harness Agent Bus Crypto Throughput

200 real ephemeral-key round-trip `sealAgentEnvelope` + `openAgentEnvelope` + SHA-256 commitment verifications per payload tier (zero mock crypto):

| Payload Tier | Seal p50 (ms) | Open p50 (ms) | Round-Trip Throughput | Integrity Verified |
| --- | ---: | ---: | ---: | ---: |
| 256 B (Agent Handoff / Capability Lease) | `0.371` | `0.442` | **1,209 ops/s** | `100%` (`200/200`) |
| 4 KiB (Free Tier Ciphertext Cap) | `0.369` | `0.476` | **1,221 ops/s** | `100%` (`200/200`) |
| 16 KiB (Pro Tier Ciphertext Cap) | `0.397` | `0.500` | **1,104 ops/s** | `100%` (`200/200`) |

> **Takeaway:** Sub-millisecond (`< 0.9 ms` combined seal + open) client-side E2EE even at the full `16 KiB` Pro envelope ceiling, enabling high-frequency encrypted `Ullumii` ↔ `gnosh.ai` ↔ shell agent handoffs with zero plaintext exposure on Gno.land.

---

## 2. Live Gno.land Onyx Testnet (`onyx-1`) RPC & Real Deployment Gas

- **RPC:** `https://rpc.onyx.testnets.gno.land:443` | **Chain ID:** `onyx-1` | **Observed Block Height:** `1344098`
- **RPC `/status` Latency:** p50 `54.639 ms`, p95 `250.478 ms` | **`abci_query` (`vm/qinertpaths`):** `43.6 ms`
- **Verified On-Chain Submissions:** `gno.land/p/.../whisper` + `gno.land/r/.../whisper` (plus companion `signals` and `assurance` dependencies)

| Package / Realm Path | Block Height | Measured Gas Used | On-Chain Tx Hash |
| --- | ---: | ---: | --- |
| `gno.land/p/g1jdc6h96he7wf7xfycu6u7wqhv5j762qtxu5k5t/whisper` | `1343650` | `17,978,068` | `Y8yxq2g2dcj2q3PUrJDzHEk6TeyEq2mEDfXvn6yW0ow=` |
| `gno.land/r/g1jdc6h96he7wf7xfycu6u7wqhv5j762qtxu5k5t/whisper` | `1343652` | `45,410,622` | `/EB7ITw57NRhnrB9rIS5gi6hp73k9yRcHKwH6LWwOcc=` |

---

## 3. End-to-End Verification Matrix

| Suite | Command | Result |
| --- | --- | --- |
| `gno test` (`p/arobi/whisper`, `r/arobi/whisper`: handles, X25519/nonce/Base64, Free/Pro 25 GNOT billing, opaque settlement, HTLC 1%/0%, `AgentBusRoute` capability leases & memory sync, `Render()`, RFC 6962 proofs) | `bash scripts/run-gno-tests.sh` | **5/5 PASS** |
| Adena Wallet Tx Builders & `abci_query` Adapter | `node --test web/adena-whisper.test.mjs` | **PASS** |
| Cross-Harness Agent Bus (`Ullumii` ↔ `gnosh.ai`, tamper rejection) | `node --test bridge/whisper-agent-bus.test.mjs` | **PASS** |

---

## 4. Public Third-Party Benchmarks (Google PageSpeed Insights & Hugging Face Hub)

- **Live GitHub Pages Playground:** [https://possumxi.github.io/arobi-whisper/web/](https://possumxi.github.io/arobi-whisper/web/)
- **Google PageSpeed Insights (Desktop & Mobile):** **Performance `100`**, **Best Practices `100`**, **SEO `100`**, Accessibility `78` (`LCP 0.2s` desktop / `0.8s` mobile, `TBT 0 ms`, `CLS 0`) — [Verify Public Desktop Report](https://pagespeed.web.dev/analysis/https-possumxi-github-io-arobi-whisper-gno-web/q338wevmo1?form_factor=desktop) · [Verify Public Mobile Report](https://pagespeed.web.dev/analysis/https-possumxi-github-io-arobi-whisper-gno-web/q338wevmo1?form_factor=mobile)
- **Hugging Face Hub Public Benchmark Dataset & Interactive Space:** [Dataset (JSONL)](https://huggingface.co/datasets/TruLumecreator/immaculate-agent-gno-benchmarks) · [Interactive Space](https://huggingface.co/spaces/TruLumecreator/immaculate-agent-gno-benchmarks)
