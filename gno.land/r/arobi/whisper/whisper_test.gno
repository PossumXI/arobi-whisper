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
	opAdmin     = testutils.TestAddress("whisper-operator")
	opaqueVault = testutils.TestAddress("whisper-vault")
	alice       = testutils.TestAddress("whisper-alice")
	bob         = testutils.TestAddress("whisper-bob")
	charlie     = testutils.TestAddress("whisper-charlie")
	selfAddr    = chain.PackageAddress("gno.land/r/arobi/whisper")
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
	operator = ""
	settlementSink = ""
	accruedServiceFees = 0
	subscriptionPriceUgnot = 25000000
	overageFeeUgnot = 10000
	escrowFeeBps = 100
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
	if amount == 0 {
		testing.SetOriginSend(nil)
		return
	}
	testing.SetOriginSend(chain.Coins{chain.NewCoin("ugnot", amount)})
	testing.IssueCoins(selfAddr, chain.Coins{chain.NewCoin("ugnot", amount)})
}

func TestIdentityFreeTierAntiSpamOverageAndGnotSubscription(cur realm, t *testing.T) {
	resetWhisper()

	// Deployer initializes operator privately (no payout address hardcoded or rendered).
	testing.SetRealm(testing.NewUserRealm(opAdmin))
	sendCoins(0)
	InitOperator(cross(cur))

	// Alice & Bob register X25519 keys + claim-once @handles (start on Free tier = 110 credits).
	testing.SetRealm(testing.NewUserRealm(alice))
	sendCoins(0)
	RegisterIdentity(cross(cur), aliceEnc, "", "@alice_gno", "Alice")
	uassert.Equal(t, TierFree, EffectiveTier("@alice_gno"))

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

	// Bob rotates keys and sets anti-spam min tip = 5000ugnot + allowlist only.
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

	// Free tier credit send + direct tip forwards 100% of tip to Bob!
	bobBefore := balance(bob)
	testing.SetRealm(testing.NewUserRealm(alice))
	sendCoins(5000)
	msgID := SendMessage(cross(cur), "@bob_defi", ephPub, nonce24, sampleCT(), commit1)
	uassert.Equal(t, uint64(1), msgID)
	uassert.Equal(t, bobBefore+5000, balance(bob))

	// When Free credits reach 0, overage fee (10,000ugnot) is charged in GNOT while tip still reaches Bob!
	aliceID := mustIdentity(alice.String())
	aliceID.Credits = 0
	testing.SetRealm(testing.NewUserRealm(alice))
	sendCoins(5000) // insufficient for overage + tip
	uassert.AbortsContains(t, cur, "overage fee", func() {
		SendMessage(cross(cur), "@bob_defi", ephPub, nonce24, sampleCT(), commit1)
	})
	bobBefore2 := balance(bob)
	testing.SetRealm(testing.NewUserRealm(alice))
	sendCoins(overageFeeUgnot + 5000)
	msgID2 := SendMessage(cross(cur), "@bob_defi", ephPub, nonce24, sampleCT(), commit2)
	uassert.Equal(t, uint64(2), msgID2)
	uassert.Equal(t, bobBefore2+5000, balance(bob))
	uassert.Equal(t, overageFeeUgnot, accruedServiceFees)

	// Free user cannot create DeFi HTLC escrow until subscribing to Pro in GNOT!
	testing.SetRealm(testing.NewUserRealm(alice))
	sendCoins(100000)
	uassert.AbortsContains(t, cur, "active Pro subscription", func() {
		SendEscrowMessage(cross(cur), "@bob_defi", ephPub, nonce24, sampleCT(), commit1, "", 20)
	})

	// Alice subscribes to Pro with exact 25 GNOT (25,000,000 ugnot) -> gets 2,500 credits for 30 days!
	testing.SetRealm(testing.NewUserRealm(alice))
	sendCoins(subscriptionPriceUgnot)
	exp := Subscribe(cross(cur))
	uassert.True(t, exp > 0)
	uassert.Equal(t, TierPro, EffectiveTier("@alice_gno"))
	uassert.Equal(t, ProPeriodCredits, aliceID.Credits)

	// Non-operator cannot collect service fees; operator collects accrued fees cleanly without disclosing address publicly.
	testing.SetRealm(testing.NewUserRealm(charlie))
	sendCoins(0)
	uassert.AbortsContains(t, cur, "operator only", func() {
		CollectServiceFees(cross(cur), charlie)
	})
	vaultBefore := balance(opaqueVault)
	testing.SetRealm(testing.NewUserRealm(opAdmin))
	sendCoins(0)
	collected := CollectServiceFees(cross(cur), opaqueVault)
	uassert.Equal(t, overageFeeUgnot+subscriptionPriceUgnot, collected)
	uassert.Equal(t, vaultBefore+collected, balance(opaqueVault))

	// RFC 6962 proof verifies, and Render() never prints operator or settlement addresses!
	leafHex := MessageLeafHex(1)
	proofCSV := ProofForLeaf(0, AccumulatorSize())
	uassert.True(t, VerifyLeafProof(0, AccumulatorSize(), leafHex, proofCSV))
	home := Render("")
	uassert.True(t, strings.Contains(home, "Pro Subscription"))
	uassert.False(t, strings.Contains(home, opaqueVault.String()))
	uassert.False(t, strings.Contains(home, opAdmin.String()))
}

func TestProDeFiHashLockedEscrowWithOpaqueSettlementFeeAndZeroFeeRefund(cur realm, t *testing.T) {
	resetWhisper()

	// Operator configures an opaque direct settlement sink (never printed in Render or events).
	testing.SetRealm(testing.NewUserRealm(opAdmin))
	sendCoins(0)
	InitOperator(cross(cur))
	testing.SetRealm(testing.NewUserRealm(opAdmin))
	sendCoins(0)
	SetSettlementSink(cross(cur), opaqueVault)

	testing.SetRealm(testing.NewUserRealm(alice))
	sendCoins(0)
	RegisterIdentity(cross(cur), aliceEnc, "", "alice_otc", "Alice")
	testing.SetRealm(testing.NewUserRealm(bob))
	sendCoins(0)
	RegisterIdentity(cross(cur), bobEnc, "", "bob_otc", "Bob")

	// Alice subscribes to Pro in GNOT -> fee routes automatically to opaque sink!
	vaultBeforeSub := balance(opaqueVault)
	testing.SetRealm(testing.NewUserRealm(alice))
	sendCoins(subscriptionPriceUgnot)
	Subscribe(cross(cur))
	uassert.Equal(t, vaultBeforeSub+subscriptionPriceUgnot, balance(opaqueVault))

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

	// Correct preimage settles 99% (99,000ugnot) to Bob and 1% (1,000ugnot) to opaque settlement sink!
	bobBefore := balance(bob)
	vaultBeforeEsc := balance(opaqueVault)
	testing.SetRealm(testing.NewUserRealm(bob))
	sendCoins(0)
	payout := ClaimEscrow(cross(cur), escID, secret)
	uassert.Equal(t, int64(99000), payout)
	uassert.Equal(t, bobBefore+99000, balance(bob))
	uassert.Equal(t, vaultBeforeEsc+1000, balance(opaqueVault))
	uassert.Equal(t, int64(0), balance(selfAddr))

	// 2. Expired unclaimed escrow refunds 100% to Alice (zero fee).
	testing.SetRealm(testing.NewUserRealm(alice))
	sendCoins(50000)
	_, escID2 := SendEscrowMessage(cross(cur), "@bob_otc", ephPub, nonce24, sampleCT(), commit2, "", 10)
	testing.SkipHeights(10)
	aliceBefore := balance(alice)
	testing.SetRealm(testing.NewUserRealm(alice))
	sendCoins(0)
	refunded := RefundEscrow(cross(cur), escID2)
	uassert.Equal(t, int64(50000), refunded)
	uassert.Equal(t, aliceBefore+50000, balance(alice))
	uassert.Equal(t, int64(0), balance(selfAddr))

	// Render never discloses opaqueVault or opAdmin.
	uassert.False(t, strings.Contains(Render("escrow/1"), opaqueVault.String()))
}
