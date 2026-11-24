package whisper

import (
	"chain/runtime"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// A `gnokey maketx run` script executes as the ephemeral realm gno.land/e/<addr>/run.
// runtime's IsUser() accepts that realm (through IsUserRun), but IsUserCall() does not, and a
// run script could spend the transaction's coin envelope before a payment function counts it.
// So every payment function guards with IsUserCall(). This test pins that choice: if a guard
// were relaxed to IsUser(), the MsgRun caller below would get through and the test would fail.
func TestPaymentFunctionsRefuseMsgRunCallers(cur realm, t *testing.T) {
	resetWhisper()
	testing.SetRealm(testing.NewUserRealm(alice))
	sendCoins(0)
	RegisterIdentity(cross(cur), aliceEnc, "", "alice_run", "Alice")
	testing.SetRealm(testing.NewUserRealm(bob))
	sendCoins(0)
	RegisterIdentity(cross(cur), bobEnc, "", "bob_run", "Bob")

	run := runtime.NewRealm(alice, "gno.land/e/"+alice.String()+"/run")
	uassert.True(t, run.IsUser(), "IsUser() accepts a MsgRun realm")
	uassert.False(t, run.IsUserCall(), "IsUserCall() does not")

	feesBefore := accruedServiceFees
	messagesBefore := MessageCount()
	escrowsBefore := EscrowCount()
	testing.SetRealm(run)
	sendCoins(subscriptionPriceUgnot)
	uassert.AbortsContains(t, cur, "direct user call", func() { Subscribe(cross(cur)) })
	testing.SetRealm(run)
	sendCoins(1000)
	uassert.AbortsContains(t, cur, "direct user call", func() {
		SendMessage(cross(cur), "@bob_run", ephPub, nonce24, sampleCT(), commit1)
	})
	testing.SetRealm(run)
	sendCoins(5000)
	uassert.AbortsContains(t, cur, "direct user call", func() {
		SendEscrowMessage(cross(cur), "@bob_run", ephPub, nonce24, sampleCT(), commit2, "", 20)
	})
	uassert.Equal(t, feesBefore, accruedServiceFees, "nothing was charged")
	uassert.Equal(t, messagesBefore, MessageCount(), "nothing was sent")
	uassert.Equal(t, escrowsBefore, EscrowCount(), "no escrow was opened")
	uassert.Equal(t, TierFree, EffectiveTier(alice.String()), "the subscription did not start")
}
