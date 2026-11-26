# Team Roles & Contributors — Arobi Whisper

Built for the **Gnome Tavern hackathon** (submission deadline: **December 18, 2026 at 01:00 UTC**).

| Contributor | GitHub Status | Assigned Role | Primary Ownership |
| --- | --- | --- | --- |
| `@PossumXI` | Active (`admin`) | Project Lead & Core Architect | `p/arobi/whisper`, `r/arobi/whisper` (E2EE directory, Free/Pro GNOT subscriptions, overage & HTLC escrow settlement, opaque operator vault, RFC 6962 proofs), Onyx (`onyx-1`) deployment |
| `@iShowLinux` | Invited (`write`) | Systems, Linux & Cross-Harness Agent Bus Engineer | Cross-shell / cross-container encrypted Agent Bus verification (`bridge/whisper-agent-bus.mjs`, `bridge/whisper-mcp-server.mjs`) across Linux bash/Docker, `gnosh.ai`, and `Ullumii` (Issue `#1`) |
| `@ShadowPlague21` | Invited (`write`) | DeFi Escrow & Gas Stress-Test Lead | High-volume HTLC DeFi escrow claim/refund stress tests, `IsUserCall()` payment safety checks, and AVL flat-gas throughput profiling (Issue `#10`) |
| `@canderson777` | Invited (`write`) | Security QA, Frontend UX & Demo Producer | Interactive `web/index.html` E2EE + Adena Wallet + HTLC Escrow QA, security review, and demo walkthrough verification (Issue `#1`) |

## How Tasks Are Tracked
Contributor tasks and acceptance criteria are tracked in GitHub Issues on this repository and verified via green Ubuntu CI (`Verify` workflow).
