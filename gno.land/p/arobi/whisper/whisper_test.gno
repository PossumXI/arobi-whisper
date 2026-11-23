package whisper

import (
	"encoding/base64"
	"testing"

	"gno.land/p/arobi/assurance"
	"gno.land/p/nt/uassert/v0"
)

func TestHandleAndCryptoFieldValidation(t *testing.T) {
	h, err := NormalizeHandle("@Alice_42")
	uassert.NoError(t, err)
	uassert.Equal(t, "alice_42", h)

	_, err = NormalizeHandle("ab")
	uassert.Error(t, err)

	_, err = NormalizeHandle("bad__name")
	uassert.Error(t, err)

	_, err = NormalizeHandle("arobi")
	uassert.Error(t, err)

	_, err = NormalizeHandle("ullumii")
	uassert.Error(t, err)

	validKey := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	validNonce := "0123456789abcdef0123456789abcdef0123456789abcdef"
	validCT := base64.StdEncoding.EncodeToString([]byte("0123456789abcdef-sealed-ciphertext"))

	uassert.NoError(t, ValidateKeyHex(validKey))
	uassert.Error(t, ValidateKeyHex("short"))
	uassert.Error(t, ValidateKeyHex("0123456789ABCDEF0123456789abcdef0123456789abcdef0123456789abcdef"))

	uassert.NoError(t, ValidateNonceHex(validNonce))
	uassert.Error(t, ValidateNonceHex("deadbeef"))

	uassert.NoError(t, ValidateCiphertextB64(validCT))
	uassert.Error(t, ValidateCiphertextB64("not-valid-base64!"))
	uassert.Error(t, ValidateCiphertextB64(base64.StdEncoding.EncodeToString([]byte("too-short"))))
}

func TestEnvelopeAndEscrowIntegrateWithArobiAssuranceAccumulator(t *testing.T) {
	var acc assurance.Accumulator

	env := SealedEnvelope{
		ID:              1,
		ChainID:         "gnoland-testnet",
		Realm:           "gno.land/r/arobi/whisper",
		From:            "g1alice",
		To:              "g1bob",
		EphemeralPubHex: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		NonceHex:        "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
		CiphertextB64:   base64.StdEncoding.EncodeToString([]byte("sealed-aead-payload-plus-16b-tag")),
		CommitmentHex:   "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
		TipUgnot:        5000,
		EscrowID:        1,
		Height:          42,
	}
	esc := EscrowRecord{
		ID:            1,
		MessageID:     1,
		Sender:        "g1alice",
		Recipient:     "g1bob",
		AmountUgnot:   50000,
		HashLockHex:   ComputeHashLock("secret-preimage-42"),
		ExpiryHeight:  142,
		Status:        EscrowOpen,
		CreatedHeight: 42,
	}

	i0 := acc.Append(env.LeafHash())
	i1 := acc.Append(esc.LeafHash())
	uassert.Equal(t, uint64(0), i0)
	uassert.Equal(t, uint64(1), i1)

	root := acc.Root()
	p0, err := acc.Proof(0, 2)
	uassert.NoError(t, err)
	uassert.True(t, assurance.VerifyInclusion(0, 2, env.LeafHash(), p0, root))

	p1, err := acc.Proof(1, 2)
	uassert.NoError(t, err)
	uassert.True(t, assurance.VerifyInclusion(1, 2, esc.LeafHash(), p1, root))
}

func TestCrossHarnessAgentBusRouteCommitment(t *testing.T) {
	route := AgentBusRoute{
		FromHarness:         "ullumii",
		FromEnv:             "cloud-worker",
		FromAgentID:         "ullumii-coord-1",
		ToHarness:           "gnosh.ai",
		ToEnv:               "linux-container",
		ToAgentID:           "gnosh-worker-1",
		Kind:                AgentKindWarrantDelegate,
		CorrelationID:       "corr-99",
		ParentWarrantDigest: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		EvidenceRootHex:     "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
	}
	uassert.NoError(t, route.Validate())
	bound, err := BindAgentEnvelopeCommitment(route, "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")
	uassert.NoError(t, err)
	uassert.Equal(t, 64, len(bound))

	bad := route
	bad.Kind = "invalid_kind"
	uassert.Error(t, bad.Validate())

	// Familiar capability lease & memory sync routes validate 64-hex digests and reject malformed hex.
	famRoute := route
	famRoute.Kind = AgentKindCapabilityLease
	famRoute.CapabilityDigestHex = "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
	famRoute.MemoryRecallDigestHex = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
	uassert.NoError(t, famRoute.Validate())
	uassert.Equal(t, 64, len(assurance.Hex(famRoute.LeafHash())))

	memRoute := famRoute
	memRoute.Kind = AgentKindMemorySync
	uassert.NoError(t, memRoute.Validate())

	badCap := famRoute
	badCap.CapabilityDigestHex = "not-64-hex"
	uassert.Error(t, badCap.Validate())
}
