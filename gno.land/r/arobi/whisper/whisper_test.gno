package whisper

import (
	"chain"
	"chain/banker"
	"encoding/base64"
	"strings"
	"testing"

	"gno.land/p/arobi/assurance"
	pw "gno.land/p/arobi/whisper"
	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

var (
	alice    = testutils.TestAddress("whisper-alice")
	bob      = testutils.TestAddress("whisper-bob")
	charlie  = testutils.TestAddress("whisper-charlie")
	selfAddr = chain.PackageAddress("gno.land/r/arobi/whisper")
)

const (
	aliceEnc = "1111111111111111111111111111111111111111111111111111111111111111"
	bobEnc   = "2222222222222222222222222222222222222222222222222222222222222222"
	bobEnc2  = "3333333333333333333333333333333333333333333333333333333333333333"
	ephPub   = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	nonce24  = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
	commit1  = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
	commit2  = "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
)

func sampleCT() string {
	return base64.StdEncoding.EncodeToString([]byte("sealed-xchacha20-poly1305-ciphertext-payload"))
}

func resetWhisper() {
	identities = avl.NewTree()
	handles = avl.NewTree()
	identityOrder = nil
	messages = nil
	escrows = nil
	evidenceAcc = assurance.Accumulator{}
	totalTips = 0
	totalEscrowed = 0
}

func balance(who address) int64 {
	return banker.NewReadonlyBanker().GetCoin(who, "ugnot")
}

func sendCoins(amount int64) {
	testing.SetOriginSend(chain.Coins{chain.NewCoin("ugnot", amount)})
	if amount > 0 {
		testing.IssueCoins(selfAddr, chain.Coins{chain.NewCoin("ugnot", amount)})
	}
}

func TestIdentityRegistrationAntiSpamAndDirectTipMessaging(cur realm, t *testing.T) {
	resetWhisper()

	// Alice & Bob register X25519 keys + claim-once @handles.
	testing.SetRealm(testing.NewUserRealm(alice))
	sendCoins(0)
	RegisterIdentity(cross(cur), aliceEnc, "", "@alice_gno", "Alice")

	testing.SetRealm(testing.NewUserRealm(bob))
	sendCoins(0)
	RegisterIdentity(cross(cur), bobEnc, "", "bob_defi", "Bob")

	// Charlie cannot steal Bob's handle or register reserved @arobi.
	testing.SetRealm(testing.NewUserRealm(charlie))
	sendCoins(0)
	uassert.AbortsContains(t, cur, "already taken", func() {
		RegisterIdentity(cross(cur), aliceEnc, "", "bob_defi", "Charlie")
	})
	testing.SetRealm(testing.NewUserRealm(charlie))
	sendCoins(0)
	uassert.AbortsContains(t, cur, "reserved", func() {
		RegisterIdentity(cross(cur), aliceEnc, "", "arobi", "Fake")
	})

	// Bob rotates his encryption key and sets anti-spam min tip = 5000ugnot + allowlist only.
	testing.SetRealm(testing.NewUserRealm(bob))
	sendCoins(0)
	RotateKeys(cross(cur), bobEnc2, "")
	testing.SetRealm(testing.NewUserRealm(bob))
	sendCoins(0)
	SetInboxPolicy(cross(cur), 5000, true)

	// Alice blocked until allowlisted.
	testing.SetRealm(testing.NewUserRealm(alice))
	sendCoins(5000)
	uassert.AbortsContains(t, cur, "allowlisted", func() {
		SendMessage(cross(cur), "@bob_defi", ephPub, nonce24, sampleCT(), commit1)
	})

	// Bob allowlists Alice.
	testing.SetRealm(testing.NewUserRealm(bob))
	sendCoins(0)
	SetAllowedSender(cross(cur), alice.String(), true)

	// Under-tipping fails.
	testing.SetRealm(testing.NewUserRealm(alice))
	sendCoins(1000)
	uassert.AbortsContains(t, cur, "minimum tip", func() {
		SendMessage(cross(cur), "@bob_defi", ephPub, nonce24, sampleCT(), commit1)
	})

	// Exact/higher tip delivers E2EE envelope + forwards 100% of tip directly to Bob!
	bobBefore := balance(bob)
	realmBefore := balance(selfAddr)
	testing.SetRealm(testing.NewUserRealm(alice))
	sendCoins(5000)
	msgID := SendMessage(cross(cur), "@bob_defi", ephPub, nonce24, sampleCT(), commit1)
	uassert.Equal(t, uint64(1), msgID)
	uassert.Equal(t, bobBefore+5000, balance(bob))
	uassert.Equal(t, realmBefore, balance(selfAddr))

	// RFC 6962 proof for message #1 verifies on-chain!
	leafHex := MessageLeafHex(1)
	proofCSV := ProofForLeaf(0, AccumulatorSize())
	uassert.True(t, VerifyLeafProof(0, AccumulatorSize(), leafHex, proofCSV))

	// Directory & gnoweb pages render cleanly.
	uassert.True(t, strings.Contains(ResolveRecipient("@bob_defi"), bobEnc2))
	uassert.True(t, strings.Contains(Render(""), "@bob_defi"))
	uassert.True(t, strings.Contains(Render("u/bob_defi"), bobEnc2))
	uassert.True(t, strings.Contains(Render("inbox/bob_defi"), "Msg #1"))
}

func TestDeFiHashLockedEscrowClaimAndExpiredRefund(cur realm, t *testing.T) {
	resetWhisper()

	testing.SetRealm(testing.NewUserRealm(alice))
	sendCoins(0)
	RegisterIdentity(cross(cur), aliceEnc, "", "alice_otc", "Alice")
	testing.SetRealm(testing.NewUserRealm(bob))
	sendCoins(0)
	RegisterIdentity(cross(cur), bobEnc, "", "bob_otc", "Bob")

	// 1. HTLC encrypted escrow: Alice locks 100,000 ugnot behind SHA-256("arobi-secret-key").
	secret := "arobi-secret-key"
	lock := pw.ComputeHashLock(secret)
	testing.SetRealm(testing.NewUserRealm(alice))
	sendCoins(100000)
	msgID, escID := SendEscrowMessage(cross(cur), "@bob_otc", ephPub, nonce24, sampleCT(), commit1, lock, 20)
	uassert.Equal(t, uint64(1), msgID)
	uassert.Equal(t, uint64(1), escID)

	// Wrong preimage MUST fail.
	testing.SetRealm(testing.NewUserRealm(bob))
	sendCoins(0)
	uassert.AbortsContains(t, cur, "invalid hashlock preimage", func() {
		ClaimEscrow(cross(cur), escID, "wrong-secret")
	})

	// Correct preimage settles 100% (100,000ugnot) peer-to-peer to Bob with zero residual realm balance!
	bobBefore := balance(bob)
	testing.SetRealm(testing.NewUserRealm(bob))
	sendCoins(0)
	payout := ClaimEscrow(cross(cur), escID, secret)
	uassert.Equal(t, int64(100000), payout)
	uassert.Equal(t, bobBefore+100000, balance(bob))
	uassert.Equal(t, int64(0), balance(selfAddr))

	// Double-claim MUST fail.
	testing.SetRealm(testing.NewUserRealm(bob))
	sendCoins(0)
	uassert.AbortsContains(t, cur, "already CLAIMED", func() {
		ClaimEscrow(cross(cur), escID, secret)
	})

	// 2. Unclaimed escrow refunds 100% to Alice after expiry (zero fee).
	testing.SetRealm(testing.NewUserRealm(alice))
	sendCoins(50000)
	_, escID2 := SendEscrowMessage(cross(cur), "@bob_otc", ephPub, nonce24, sampleCT(), commit2, "", 10)

	// Refund before expiry MUST fail.
	testing.SetRealm(testing.NewUserRealm(alice))
	sendCoins(0)
	uassert.AbortsContains(t, cur, "not expired yet", func() {
		RefundEscrow(cross(cur), escID2)
	})

	testing.SkipHeights(10)
	aliceBefore := balance(alice)
	testing.SetRealm(testing.NewUserRealm(alice))
	sendCoins(0)
	refunded := RefundEscrow(cross(cur), escID2)
	uassert.Equal(t, int64(50000), refunded)
	uassert.Equal(t, aliceBefore+50000, balance(alice))
	uassert.Equal(t, int64(0), balance(selfAddr))

	// Escrow gnoweb page renders cleanly.
	uassert.True(t, strings.Contains(Render("escrow/1"), "CLAIMED"))
	uassert.True(t, strings.Contains(Render("escrow/2"), "REFUNDED"))
}
