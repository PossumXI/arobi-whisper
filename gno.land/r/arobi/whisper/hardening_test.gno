package whisper

import (
	"testing"

	pw "gno.land/p/arobi/whisper"
	"gno.land/p/nt/uassert/v0"
)

// The operator is bound atomically to the deploying account inside init(), closing any
// post-deployment front-running window.
func TestOperatorIsTheDeployerAndAStrangerCannotTakeIt(cur realm, t *testing.T) {
	resetWhisper()
	uassert.Equal(t, deployAcct, deployer, "init records deploying account")
	uassert.Equal(t, deployAcct, Operator(), "deployer is initial operator")

	testing.SetRealm(testing.NewUserRealm(charlie))
	sendCoins(0)
	uassert.AbortsContains(t, cur, "operator only", func() { SetSettlementSink(cross(cur), charlie) })
	testing.SetRealm(testing.NewUserRealm(charlie))
	sendCoins(0)
	uassert.AbortsContains(t, cur, "operator only", func() { TransferOperator(cross(cur), charlie) })
	testing.SetRealm(testing.NewUserRealm(charlie))
	sendCoins(0)
	uassert.AbortsContains(t, cur, "operator only", func() { SetPricing(cross(cur), 0, 0, 500) })
	testing.SetRealm(testing.NewUserRealm(charlie))
	sendCoins(0)
	uassert.AbortsContains(t, cur, "operator only", func() { CollectServiceFees(cross(cur), charlie) })

	uassert.Equal(t, deployer, Operator())
	uassert.Equal(t, address(""), settlementSink)
}

// From ExpiryHeight onward, only RefundEscrow may move an expired escrow; ClaimEscrow fails closed.
func TestClaimAtOrAfterExpiryIsRefused(cur realm, t *testing.T) {
	resetWhisper()
	testing.SetRealm(testing.NewUserRealm(alice))
	sendCoins(0)
	RegisterIdentity(cross(cur), aliceEnc, "", "alice_exp", "Alice")
	testing.SetRealm(testing.NewUserRealm(bob))
	sendCoins(0)
	RegisterIdentity(cross(cur), bobEnc, "", "bob_exp", "Bob")
	testing.SetRealm(testing.NewUserRealm(alice))
	sendCoins(subscriptionPriceUgnot)
	Subscribe(cross(cur))

	secret := "swap-secret"
	testing.SetRealm(testing.NewUserRealm(alice))
	sendCoins(5000)
	_, escID := SendEscrowMessage(cross(cur), "@bob_exp", ephPub, nonce24, sampleCT(), commit1, pw.ComputeHashLock(secret), 5)

	testing.SkipHeights(5)
	testing.SetRealm(testing.NewUserRealm(bob))
	sendCoins(0)
	uassert.AbortsContains(t, cur, "escrow expired", func() { ClaimEscrow(cross(cur), escID, secret) })

	aliceBefore := balance(alice)
	testing.SetRealm(testing.NewUserRealm(alice))
	sendCoins(0)
	uassert.Equal(t, int64(5000), RefundEscrow(cross(cur), escID))
	uassert.Equal(t, aliceBefore+5000, balance(alice))
}

// Escrow settlement fee is locked in EscrowRecord.FeeBps at creation time so later SetPricing
// calls never affect open escrows.
func TestEscrowFeeIsFixedAtCreation(cur realm, t *testing.T) {
	resetWhisper()
	testing.SetRealm(testing.NewUserRealm(alice))
	sendCoins(0)
	RegisterIdentity(cross(cur), aliceEnc, "", "alice_fee", "Alice")
	testing.SetRealm(testing.NewUserRealm(bob))
	sendCoins(0)
	RegisterIdentity(cross(cur), bobEnc, "", "bob_fee", "Bob")
	testing.SetRealm(testing.NewUserRealm(alice))
	sendCoins(subscriptionPriceUgnot)
	Subscribe(cross(cur))

	testing.SetRealm(testing.NewUserRealm(alice))
	sendCoins(100000)
	_, escID := SendEscrowMessage(cross(cur), "@bob_fee", ephPub, nonce24, sampleCT(), commit1, "", 20)

	// Operator raises fee from 1% to 5% cap after escrow creation.
	testing.SetRealm(testing.NewUserRealm(deployer))
	sendCoins(0)
	SetPricing(cross(cur), 25000000, 10000, 500)

	testing.SetRealm(testing.NewUserRealm(bob))
	sendCoins(0)
	uassert.Equal(t, int64(99000), ClaimEscrow(cross(cur), escID, "")) // 1% locked, not 5%
}

func TestReservedHandlesIncludeFounderAndGnoNames(cur realm, t *testing.T) {
	resetWhisper()
	for _, h := range []string{"gaetano", "possumxi", "gno", "gnoland", "jaekwon"} {
		testing.SetRealm(testing.NewUserRealm(charlie))
		sendCoins(0)
		uassert.AbortsContains(t, cur, "reserved", func() { RegisterIdentity(cross(cur), aliceEnc, "", h, "") })
	}
}

func TestRegisterIdentityPreservesSignPubHexWhenOmitted(cur realm, t *testing.T) {
	resetWhisper()
	testing.SetRealm(testing.NewUserRealm(alice))
	sendCoins(0)
	RegisterIdentity(cross(cur), aliceEnc, bobEnc, "alice_sig", "Alice")
	id := mustIdentity(alice.String())
	uassert.Equal(t, bobEnc, id.SignPubHex)

	// Updating encPubHex with empty signPubHex preserves the existing signing key.
	testing.SetRealm(testing.NewUserRealm(alice))
	sendCoins(0)
	RegisterIdentity(cross(cur), bobEnc2, "", "", "Alice Updated")
	id = mustIdentity(alice.String())
	uassert.Equal(t, bobEnc2, id.EncPubHex)
	uassert.Equal(t, bobEnc, id.SignPubHex)
}

// Every payment function reads OriginSend only after asserting cur.Previous().IsUserCall(),
// refusing code-realm callers before any coins are counted.
func TestPaymentFunctionsRefuseCodeRealmCallers(cur realm, t *testing.T) {
	resetWhisper()
	testing.SetRealm(testing.NewUserRealm(alice))
	sendCoins(0)
	RegisterIdentity(cross(cur), aliceEnc, "", "alice_code", "Alice")
	testing.SetRealm(testing.NewUserRealm(bob))
	sendCoins(0)
	RegisterIdentity(cross(cur), bobEnc, "", "bob_code", "Bob")

	for _, path := range []string{"gno.land/r/attacker/caller", "gno.land/r/demo/other"} {
		testing.SetRealm(testing.NewCodeRealm(path))
		sendCoins(subscriptionPriceUgnot)
		uassert.AbortsContains(t, cur, "direct user call", func() { Subscribe(cross(cur)) })
		testing.SetRealm(testing.NewCodeRealm(path))
		sendCoins(1000)
		uassert.AbortsContains(t, cur, "direct user call", func() {
			SendMessage(cross(cur), "@bob_code", ephPub, nonce24, sampleCT(), commit1)
		})
		testing.SetRealm(testing.NewCodeRealm(path))
		sendCoins(5000)
		uassert.AbortsContains(t, cur, "direct user call", func() {
			SendEscrowMessage(cross(cur), "@bob_code", ephPub, nonce24, sampleCT(), commit2, "", 20)
		})
	}
}
