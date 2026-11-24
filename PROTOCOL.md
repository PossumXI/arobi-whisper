# Arobi Whisper on gno.land: record encodings

The realm's evidence accumulator stores RFC 6962 leaves, `LeafHash(Encode())` through `gno.land/p/arobi/assurance`. There are two record types, and each encoding begins with its own domain tag, so a leaf of one kind can never be read as the other.

Every encoding is:
- the domain tag, as a string;
- `EncodingVersion`, one byte, currently 1;
- the record's fields, in the order below.

Strings are a big-endian `uint32` length followed by the bytes. Integers are big-endian `uint64`.

| Record | Domain tag | Fields after the tag and the version byte |
|---|---|---|
| `SealedEnvelope` | `arobi-whisper-gno-envelope-v1` | `ID`, `ChainID`, `Realm`, `From`, `To`, `EphemeralPubHex`, `NonceHex`, SHA-256 of `CiphertextB64` (32 raw bytes), `CommitmentHex`, `TipUgnot`, `EscrowID`, `Height` |
| `EscrowRecord` | `arobi-whisper-gno-escrow-v2` | `ID`, `MessageID`, `Sender`, `Recipient`, `AmountUgnot`, `FeeBps`, `HashLockHex`, `ExpiryHeight`, `Status`, `CreatedHeight`, `SettledHeight` |

The source of truth is `gno.land/p/arobi/whisper/whisper.gno` (`SealedEnvelope.Encode`, `EscrowRecord.Encode`).

## Escrow v2 (2026-11-24)

The escrow record now carries `FeeBps`, the settlement fee fixed when the escrow opens. A later `SetPricing` therefore cannot change what an open escrow pays.

Because the encoding changed, its domain tag moved from `arobi-whisper-gno-escrow-v1` to `arobi-whisper-gno-escrow-v2`. A digest of the old encoding and one of the new can never be confused.

No realm was deployed under v1, so no record migrates.

The envelope encoding did not change and keeps `-v1`. `EncodingVersion` is shared by both records and stays 1.
