package whisper

import (
	"encoding/binary"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// The escrow encoding gained FeeBps, so its domain tag moved to v2 (PROTOCOL.md): a digest of the old encoding and one
// of the new can never be read as each other. FeeBps is bound into the evidence leaf.
func TestEscrowRecordUsesTheV2DomainAndBindsFeeBps(t *testing.T) {
	uassert.Equal(t, "arobi-whisper-gno-escrow-v2", DomainEscrow)
	uassert.Equal(t, "arobi-whisper-gno-envelope-v1", DomainEnvelope)

	r := EscrowRecord{
		ID: 1, MessageID: 7, Sender: "g1sender", Recipient: "g1recipient", AmountUgnot: 100000, FeeBps: 100,
		HashLockHex: "", ExpiryHeight: 50, Status: EscrowOpen, CreatedHeight: 30, SettledHeight: 0,
	}
	enc := r.Encode()
	tagLen := int(binary.BigEndian.Uint32(enc[:4]))
	uassert.Equal(t, len(DomainEscrow), tagLen)
	uassert.Equal(t, DomainEscrow, string(enc[4:4+tagLen]))
	uassert.Equal(t, EncodingVersion, enc[4+tagLen])

	raised := r
	raised.FeeBps = 500
	uassert.NotEqual(t, string(enc), string(raised.Encode()), "FeeBps is part of the encoding")
	a, b := r.LeafHash(), raised.LeafHash()
	uassert.NotEqual(t, string(a[:]), string(b[:]), "and of the evidence leaf")
}
