---
trigger: always_on
description: "Arobi Whisper name, repo URLs, companion SDK workspace, and Gnome Tavern constraints. Leave gno.land paths and protocol strings unchanged."
---

# Arobi Whisper project context

Persistent facts for every change in this repository. The same facts are in root `AGENTS.md`. Update both files together.

## Name and repository

- The project name is **Arobi Whisper** (renamed November 2026). The name has no `Gno` prefix.
- The repository is [PossumXI/arobi-whisper](https://github.com/PossumXI/arobi-whisper). It was renamed from `PossumXI/arobi-whisper-gno`.
- Use the new name and URLs for the project, repository, and public links. Retired repo slugs are `arobi-whisper-gno` and `gno-immaculate-sdk-agent-builder`.

## Companion project

- Arobi Whisper depends on **Immaculate SDK Agent Builder**, repository [PossumXI/immaculate-sdk-agent-builder](https://github.com/PossumXI/immaculate-sdk-agent-builder) (formerly `gno-immaculate-sdk-agent-builder`).
- Local development uses a parent `gnowork.toml` workspace with both repositories as siblings (`arobi-whisper` and `immaculate-sdk-agent-builder`).

## Gnome Tavern hackathon

Rules for the DoraHacks hackathon: [Gnome Tavern](https://dorahacks.io/hackathon/gnome-tavern/detail).

- Project names must not use a `Gno` prefix or imply an official connection to Gno.land. Factual wording is fine: "built on Gno.land" and "deployed to the Gno.land Onyx testnet".
- The project must be deployed and working on the Gno.land testnet at submission.
- A submission needs a public repository, a real realm or package, a README, a demo video, and a short description.
- Submissions close December 17, 2026, 8 PM ET (December 18, 2026, 01:00 UTC).
- There is no code freeze. The BUIDL stays editable until the deadline.
- The retention prize expects monthly releases.

## Technical identifiers to leave unchanged

- `gno.land/...` paths
- `.gno` files
- `gno`, `gnokey`, and `gnodev` commands
- Protocol strings `arobi-whisper-gno-envelope-v1` and `arobi-whisper-gno-escrow-v1`
- The Onyx proof table and its transaction hashes
- Release tag `v1.0.0-gnome-tavern`
- Hugging Face slugs, including `immaculate-agent-gno-benchmarks`
