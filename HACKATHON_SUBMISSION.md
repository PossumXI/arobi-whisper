# Hackathon Submission Pack — **Arobi Whisper**

*(Build name is **Arobi Whisper**. Public MIT repository. Package and stateful realm submitted on `onyx-1`. No private wallet or proprietary disclosures.)*

---

## Copy-Paste DoraHacks `Create a new Build` Fields

- **Name of your Build:** `Arobi Whisper`
- **Brief description of this Build:**
  > End-to-end encrypted DeFi messenger and cross-shell / cross-harness Familiar Agent Bus built on Gno.land and submitted on-chain to the Gno.land Onyx testnet (awaiting activation) — client-sealed `X25519 + XChaCha20-Poly1305` chat, Free/Pro GNOT subscriptions, direct GNOT tips, HTLC DeFi escrows, and RFC 6962 cryptographic delivery proofs. Tested with `gno test` on current master.
- **Tags:** `Go`, `Smart Contracts`, `DeFi`, `Social`, `AI`, `dApps`
- **GitHub Repo:** `https://github.com/PossumXI/arobi-whisper`
- **Demo Video (1080p MP4, 2m 11s):** `https://github.com/PossumXI/arobi-whisper/releases/download/v1.0.0-gnome-tavern/Arobi_Whisper_Demo_1080p.mp4`
- **Live Web Playground:** `https://possumxi.github.io/arobi-whisper/web/`
- **Public Benchmarks (Hugging Face & PageSpeed):** `https://huggingface.co/spaces/TruLumecreator/immaculate-agent-gno-benchmarks` · [PageSpeed 100/100/100](https://pagespeed.web.dev/analysis/https-possumxi-github-io-arobi-whisper-gno-web/q338wevmo1?form_factor=desktop)
- **Website:** `https://aura-genesis.org/whisper`

---

## Copy-Paste DoraHacks `Submit Build` Modal Fields

- **Gno.land testnet deployment link (`gnoweb` URL):**
  `https://onyx.testnets.gno.land/r/g1jdc6h96he7wf7xfycu6u7wqhv5j762qtxu5k5t/whisper`
  *(Submitted on-chain to `onyx-1` at blocks `1343650` / `1343652`; verifiable right now via `gnokey query vm/qinertpaths` while awaiting Onyx `enablepkg` approver activation.)*
- **Realm or package path:**
  `gno.land/r/g1jdc6h96he7wf7xfycu6u7wqhv5j762qtxu5k5t/whisper`
  *(Pure package: `gno.land/p/g1jdc6h96he7wf7xfycu6u7wqhv5j762qtxu5k5t/whisper`, importing `gno.land/p/g1jdc6h96he7wf7xfycu6u7wqhv5j762qtxu5k5t/assurance`)*
- **Is this a new project, or one started before Gnome Tavern?**
  > Arobi Whisper exists as a live web E2EE messenger (`aura-genesis.org/whisper`). During Gnome Tavern, we built a brand-new smart-contract architecture (`p/arobi/whisper` + `r/arobi/whisper`) from scratch with on-chain X25519 keycards, claim-once `@handles`, GNOT Free/Pro subscription metering (`25 GNOT`/30d), HTLC DeFi escrows (`1%` claim fee / `0%` expired refund), RFC 6962 inclusion proofs, a **Cross-Shell / Cross-Harness Encrypted Agent Bus** (`agentbus.gno` + `bridge/whisper-agent-bus.mjs` connecting `Ullumii`, `gnosh.ai`, and local shells), and an Adena Wallet browser playground (`web/index.html`).
- **On-Chain Onyx (`onyx-1`) Proof Table (for `#gnome-tavern-hackathon` `enablepkg` activation):**
  | Package / Realm | Block | Gas Used | Tx Hash |
  | --- | ---: | ---: | --- |
  | `gno.land/p/g1jdc6h96he7wf7xfycu6u7wqhv5j762qtxu5k5t/whisper` | `1343650` | `17,978,068` | `Y8yxq2g2dcj2q3PUrJDzHEk6TeyEq2mEDfXvn6yW0ow=` |
  | `gno.land/r/g1jdc6h96he7wf7xfycu6u7wqhv5j762qtxu5k5t/whisper` | `1343652` | `45,410,622` | `/EB7ITw57NRhnrB9rIS5gi6hp73k9yRcHKwH6LWwOcc=` |

---

## Alignment with Judging Rubric

| Criterion (Weight) | What Judges Can Verify Immediately |
| --- | --- |
| **Technical Quality (40%)** | Package `p/arobi/whisper` + stateful realm `r/arobi/whisper`, tested with `gno test` on current master (5/5) + 2 Node test suites, green Ubuntu CI, verified on-chain `onyx-1` submissions (`17.98M` + `45.41M` gas). |
| **User Appeal (20%)** | Interactive 4-tab Adena browser playground (`web/index.html`) + `gnoweb` explorer (`Render("u/...")`, `Render("inbox/...")`), mirroring live `aura-genesis.org/whisper` Free/Pro GNOT UX. |
| **Creativity (20%)** | Zero-server E2EE DeFi messenger + HTLC hash-locked encrypted escrows (`1%` claim fee / `0%` expired refund) + Cross-Shell / Cross-Harness Encrypted Agent Bus (`Ullumii` ↔ `gnosh.ai`, `1,104–1,221 ops/s` measured in `BENCHMARKS.md`). |
| **Docs & Demo (20%)** | Complete `README.md`, `BENCHMARKS.md`, `CONTRIBUTORS.md`, reproducible CLI commands, and 2–3 min demo walkthrough. |

---

## 2–3 Minute Demo Video Shot List
1. **0:00–0:30 (Overview):** Zero-server E2EE DeFi chat + Familiar Agent Bus (plaintext never touches chain state).
2. **0:30–1:15 (Interactive Web Playground `web/index.html`):** Generate X25519 keypair in browser, build `RegisterIdentity` + **Pro Subscribe (`25 GNOT`)**, seal an encrypted HTLC escrow message (`SendEscrowMessage` + `ClaimEscrow` + `RefundEscrow`), and show zero plaintext in the `/vm.m_call` payload.
3. **1:15–2:00 (Cross-Harness Encrypted Agent Bus):** Seal an `Ullumii → gnosh.ai` `capability_lease` / `handoff` packet via `bridge/whisper-agent-bus.mjs` and show tamper rejection + real measured throughput (`1,104–1,221 ops/s` in `BENCHMARKS.md`).
4. **2:00–2:30 (`gno test` & Onyx-1 Proof):** Run `bash scripts/run-gno-tests.sh` and click **Query Live Onyx-1** in `web/index.html` to verify live on-chain block height & package submissions.
