// Package whisper is the stateful Gno.land realm for Arobi Whisper — an end-to-end
// encrypted DeFi messenger with native GNOT tipping, conditional HTLC/expiry escrows,
// programmable anti-spam inbox gating, and RFC 6962 cryptographic evidence anchoring
// built directly on gno.land/p/arobi/assurance.
//
// Zero plaintext or secret keys ever touch chain state. Clients seal messages locally
// using X25519 + HKDF-SHA256 + XChaCha20-Poly1305 (exact Arobi Whisper v1 wire format).
//
// Strictly peer-to-peer settlement: 100% of tips and claimed escrows forward directly
// to the recipient, and 100% of expired escrows refund directly to the sender.
package whisper

import (
	"chain"
	"chain/banker"
	"chain/runtime"
	"chain/runtime/unsafe"
	"strconv"
	"strings"

	"gno.land/p/arobi/assurance"
	pw "gno.land/p/arobi/whisper"
	"gno.land/p/nt/avl/v0"
)

const (
	denom = "ugnot"
	// MinEscrowUgnot prevents dust escrows.
	MinEscrowUgnot int64 = 1000
	// MinEscrowTTLBlocks is the minimum escrow lock window before sender refund.
	MinEscrowTTLBlocks int64 = 5
	// MaxEscrowTTLBlocks caps escrow lock duration (~1 year at 2s blocks).
	MaxEscrowTTLBlocks int64 = 15000000
)

// Identity binds a native Gno g1... address to local X25519/Ed25519 messaging keys,
// an optional claim-once @handle, and programmable anti-spam inbox rules.
type Identity struct {
	Address       address
	EncPubHex     string // 32-byte X25519 public key (hex)
	SignPubHex    string // 32-byte Ed25519 public key (hex, optional cross-chain parity)
	Handle        string // optional claim-once handle
	DisplayName   string
	MinTipUgnot   int64
	AllowListOnly bool
	Allowed       *avl.Tree // senderAddr -> bool
	InboxIDs      []uint64
	SentIDs       []uint64
	CreatedHeight int64
	UpdatedHeight int64
}

var (
	identities    = avl.NewTree() // addr.String() -> *Identity
	handles       = avl.NewTree() // handle -> addr.String()
	identityOrder []string

	messages []*pw.SealedEnvelope
	escrows  []*pw.EscrowRecord

	// Append-only RFC 6962 accumulator over every message envelope & escrow transition.
	evidenceAcc   assurance.Accumulator
	totalTips     int64
	totalEscrowed int64
)

// RegisterIdentity registers (or updates displayName/keys for) the caller's E2EE identity.
// Handles are strictly claim-once: once claimed, a handle cannot be changed or stolen.
func RegisterIdentity(cur realm, encPubHex, signPubHex, handle, displayName string) {
	prev := cur.Previous()
	if !prev.IsUserCall() {
		panic("register identity with a direct user call")
	}
	if err := pw.ValidateKeyHex(encPubHex); err != nil {
		panic("encPubHex: " + err.Error())
	}
	if signPubHex != "" {
		if err := pw.ValidateKeyHex(signPubHex); err != nil {
			panic("signPubHex: " + err.Error())
		}
	}
	if len(displayName) > 64 {
		panic("displayName too long (max 64)")
	}

	caller := prev.Address()
	key := caller.String()
	height := runtime.ChainHeight()

	var normHandle string
	if strings.TrimSpace(handle) != "" {
		var err error
		normHandle, err = pw.NormalizeHandle(handle)
		if err != nil {
			panic("handle: " + err.Error())
		}
	}

	if id, exists := identities.Get(key).(*Identity); exists && id != nil {
		if normHandle != "" {
			if id.Handle != "" && id.Handle != normHandle {
				panic("identity already owns @" + id.Handle + "; handles cannot be reassigned")
			}
			if id.Handle == "" {
				if handles.Has(normHandle) {
					panic("handle @" + normHandle + " is already taken")
				}
				handles.Set(normHandle, key)
				id.Handle = normHandle
			}
		}
		id.EncPubHex = encPubHex
		id.SignPubHex = signPubHex
		if displayName != "" {
			id.DisplayName = displayName
		}
		id.UpdatedHeight = height
		chain.Emit("WhisperIdentityUpdated", "addr", key, "handle", id.Handle, "enc_pub", encPubHex)
		return
	}

	if normHandle != "" {
		if handles.Has(normHandle) {
			panic("handle @" + normHandle + " is already taken")
		}
		handles.Set(normHandle, key)
	}

	id := &Identity{
		Address:       caller,
		EncPubHex:     encPubHex,
		SignPubHex:    signPubHex,
		Handle:        normHandle,
		DisplayName:   displayName,
		Allowed:       avl.NewTree(),
		CreatedHeight: height,
		UpdatedHeight: height,
	}
	identities.Set(key, id)
	identityOrder = append(identityOrder, key)

	chain.Emit("WhisperIdentityRegistered",
		"addr", key,
		"handle", normHandle,
		"enc_pub", encPubHex,
		"height", strconv.FormatInt(height, 10),
	)
}

// RotateKeys rotates the caller's X25519 / Ed25519 keys without losing handle or inbox history.
func RotateKeys(cur realm, newEncPubHex, newSignPubHex string) {
	prev := cur.Previous()
	if !prev.IsUserCall() {
		panic("rotate keys with a direct user call")
	}
	if err := pw.ValidateKeyHex(newEncPubHex); err != nil {
		panic("newEncPubHex: " + err.Error())
	}
	if newSignPubHex != "" {
		if err := pw.ValidateKeyHex(newSignPubHex); err != nil {
			panic("newSignPubHex: " + err.Error())
		}
	}
	id := mustIdentity(prev.Address().String())
	id.EncPubHex = newEncPubHex
	id.SignPubHex = newSignPubHex
	id.UpdatedHeight = runtime.ChainHeight()
	chain.Emit("WhisperKeysRotated", "addr", id.Address.String(), "enc_pub", newEncPubHex)
}

// SetInboxPolicy configures programmable DeFi anti-spam rules on the caller's inbox.
func SetInboxPolicy(cur realm, minTipUgnot int64, allowListOnly bool) {
	prev := cur.Previous()
	if !prev.IsUserCall() {
		panic("set inbox policy with a direct user call")
	}
	if minTipUgnot < 0 {
		panic("minTipUgnot cannot be negative")
	}
	id := mustIdentity(prev.Address().String())
	id.MinTipUgnot = minTipUgnot
	id.AllowListOnly = allowListOnly
	id.UpdatedHeight = runtime.ChainHeight()
	chain.Emit("WhisperInboxPolicy",
		"addr", id.Address.String(),
		"min_tip_ugnot", strconv.FormatInt(minTipUgnot, 10),
		"allowlist_only", strconv.FormatBool(allowListOnly),
	)
}

// SetAllowedSender adds or removes a sender address from the caller's inbox allowlist.
func SetAllowedSender(cur realm, senderAddr string, allowed bool) {
	prev := cur.Previous()
	if !prev.IsUserCall() {
		panic("set allowed sender with a direct user call")
	}
	id := mustIdentity(prev.Address().String())
	if allowed {
		id.Allowed.Set(senderAddr, true)
	} else {
		id.Allowed.Remove(senderAddr)
	}
	id.UpdatedHeight = runtime.ChainHeight()
}

// SendMessage delivers a client-sealed E2EE ciphertext envelope on-chain.
// Any attached ugnot tip (required >= recipient.MinTipUgnot) forwards 100% straight to recipient.
func SendMessage(
	cur realm,
	toAddrOrHandle string,
	ephemeralPubHex string,
	nonceHex string,
	ciphertextB64 string,
	commitmentHex string,
) uint64 {
	prev := cur.Previous()
	if !prev.IsUserCall() {
		panic("send message with a direct user call")
	}
	sender := mustIdentity(prev.Address().String())
	recipient := mustResolveIdentity(toAddrOrHandle)
	checkCanSend(sender, recipient)
	validateEnvelopeFields(ephemeralPubHex, nonceHex, ciphertextB64, commitmentHex)

	tip := sentUgnot()
	if tip < recipient.MinTipUgnot {
		panic("recipient requires minimum tip of " + strconv.FormatInt(recipient.MinTipUgnot, 10) + denom +
			"; got " + strconv.FormatInt(tip, 10) + denom)
	}

	height := runtime.ChainHeight()
	msgID := uint64(len(messages)) + 1
	env := &pw.SealedEnvelope{
		ID:              msgID,
		ChainID:         runtime.ChainID(),
		Realm:           cur.PkgPath(),
		From:            sender.Address.String(),
		To:              recipient.Address.String(),
		EphemeralPubHex: ephemeralPubHex,
		NonceHex:        nonceHex,
		CiphertextB64:   ciphertextB64,
		CommitmentHex:   commitmentHex,
		TipUgnot:        tip,
		EscrowID:        0,
		Height:          height,
	}
	leaf := env.LeafHash()
	env.LeafIndex = evidenceAcc.Append(leaf)
	messages = append(messages, env)
	recipient.InboxIDs = append(recipient.InboxIDs, msgID)
	sender.SentIDs = append(sender.SentIDs, msgID)

	if tip > 0 {
		totalTips += tip
		bk := banker.NewBanker(banker.BankerTypeRealmSend, cur)
		bk.SendCoins(cur.Address(), recipient.Address, chain.Coins{chain.NewCoin(denom, tip)})
	}

	chain.Emit("WhisperMessage",
		"id", strconv.FormatUint(msgID, 10),
		"from", env.From,
		"to", env.To,
		"commitment", commitmentHex,
		"tip_ugnot", strconv.FormatInt(tip, 10),
		"leaf_index", strconv.FormatUint(env.LeafIndex, 10),
		"acc_root", assurance.Hex(evidenceAcc.Root()),
	)
	return msgID
}

// SendEscrowMessage sends an E2EE ciphertext envelope paired with a locked DeFi GNOT escrow.
//
// If hashLockHex is non-empty (64-char SHA-256 hex), the recipient must reveal the matching
// preimage in ClaimEscrow (atomic HTLC encrypted trade / bounty / secret delivery).
// If hashLockHex is empty, the recipient may claim directly before expiry.
// After ExpiryHeight, the sender may call RefundEscrow to reclaim 100% with zero fee.
func SendEscrowMessage(
	cur realm,
	toAddrOrHandle string,
	ephemeralPubHex string,
	nonceHex string,
	ciphertextB64 string,
	commitmentHex string,
	hashLockHex string,
	ttlBlocks int64,
) (uint64, uint64) {
	prev := cur.Previous()
	if !prev.IsUserCall() {
		panic("send escrow message with a direct user call")
	}
	sender := mustIdentity(prev.Address().String())
	recipient := mustResolveIdentity(toAddrOrHandle)
	if sender.Address == recipient.Address {
		panic("cannot create escrow to self")
	}
	checkCanSend(sender, recipient)
	validateEnvelopeFields(ephemeralPubHex, nonceHex, ciphertextB64, commitmentHex)

	if hashLockHex != "" {
		if _, err := assurance.ParseDigest(hashLockHex); err != nil {
			panic("hashLockHex: " + err.Error())
		}
	}
	if ttlBlocks < MinEscrowTTLBlocks || ttlBlocks > MaxEscrowTTLBlocks {
		panic("ttlBlocks out of allowed range")
	}

	amount := sentUgnot()
	if amount < MinEscrowUgnot {
		panic("escrow requires at least " + strconv.FormatInt(MinEscrowUgnot, 10) + denom)
	}
	if amount < recipient.MinTipUgnot {
		panic("escrow amount below recipient min tip")
	}

	height := runtime.ChainHeight()
	msgID := uint64(len(messages)) + 1
	escID := uint64(len(escrows)) + 1

	env := &pw.SealedEnvelope{
		ID:              msgID,
		ChainID:         runtime.ChainID(),
		Realm:           cur.PkgPath(),
		From:            sender.Address.String(),
		To:              recipient.Address.String(),
		EphemeralPubHex: ephemeralPubHex,
		NonceHex:        nonceHex,
		CiphertextB64:   ciphertextB64,
		CommitmentHex:   commitmentHex,
		TipUgnot:        0,
		EscrowID:        escID,
		Height:          height,
	}
	env.LeafIndex = evidenceAcc.Append(env.LeafHash())
	messages = append(messages, env)
	recipient.InboxIDs = append(recipient.InboxIDs, msgID)
	sender.SentIDs = append(sender.SentIDs, msgID)

	esc := &pw.EscrowRecord{
		ID:            escID,
		MessageID:     msgID,
		Sender:        sender.Address.String(),
		Recipient:     recipient.Address.String(),
		AmountUgnot:   amount,
		HashLockHex:   hashLockHex,
		ExpiryHeight:  height + ttlBlocks,
		Status:        pw.EscrowOpen,
		CreatedHeight: height,
	}
	escLeafIdx := evidenceAcc.Append(esc.LeafHash())
	escrows = append(escrows, esc)
	totalEscrowed += amount

	chain.Emit("WhisperEscrowCreated",
		"escrow_id", strconv.FormatUint(escID, 10),
		"msg_id", strconv.FormatUint(msgID, 10),
		"from", esc.Sender,
		"to", esc.Recipient,
		"amount_ugnot", strconv.FormatInt(amount, 10),
		"hash_lock", hashLockHex,
		"expiry_height", strconv.FormatInt(esc.ExpiryHeight, 10),
		"leaf_index", strconv.FormatUint(escLeafIdx, 10),
		"acc_root", assurance.Hex(evidenceAcc.Root()),
	)
	return msgID, escID
}

// ClaimEscrow settles 100% of an open DeFi escrow directly to its recipient
// (verifying SHA-256(preimage) == HashLockHex if hash-locked).
func ClaimEscrow(cur realm, escrowID uint64, preimage string) int64 {
	prev := cur.Previous()
	if !prev.IsUserCall() {
		panic("claim escrow with a direct user call")
	}
	esc := mustEscrow(escrowID)
	if esc.Status != pw.EscrowOpen {
		panic("escrow is already " + string(esc.Status))
	}
	caller := prev.Address()
	if caller.String() != esc.Recipient {
		panic("only recipient " + esc.Recipient + " may claim escrow")
	}
	if esc.HashLockHex != "" {
		if pw.ComputeHashLock(preimage) != esc.HashLockHex {
			panic("invalid hashlock preimage")
		}
	}

	payout := esc.AmountUgnot
	esc.Status = pw.EscrowClaimed
	esc.SettledHeight = runtime.ChainHeight()

	leafIdx := evidenceAcc.Append(esc.LeafHash())

	bk := banker.NewBanker(banker.BankerTypeRealmSend, cur)
	bk.SendCoins(cur.Address(), caller, chain.Coins{chain.NewCoin(denom, payout)})

	chain.Emit("WhisperEscrowClaimed",
		"escrow_id", strconv.FormatUint(esc.ID, 10),
		"recipient", esc.Recipient,
		"payout_ugnot", strconv.FormatInt(payout, 10),
		"leaf_index", strconv.FormatUint(leafIdx, 10),
		"acc_root", assurance.Hex(evidenceAcc.Root()),
	)
	return payout
}

// RefundEscrow returns 100% of an expired, unclaimed DeFi escrow back to its sender (zero fee).
func RefundEscrow(cur realm, escrowID uint64) int64 {
	prev := cur.Previous()
	if !prev.IsUserCall() {
		panic("refund escrow with a direct user call")
	}
	esc := mustEscrow(escrowID)
	if esc.Status != pw.EscrowOpen {
		panic("escrow is already " + string(esc.Status))
	}
	caller := prev.Address()
	if caller.String() != esc.Sender {
		panic("only sender " + esc.Sender + " may refund escrow")
	}
	height := runtime.ChainHeight()
	if height < esc.ExpiryHeight {
		panic("escrow has not expired yet; unlocks at height " + strconv.FormatInt(esc.ExpiryHeight, 10))
	}

	esc.Status = pw.EscrowRefunded
	esc.SettledHeight = height
	leafIdx := evidenceAcc.Append(esc.LeafHash())

	bk := banker.NewBanker(banker.BankerTypeRealmSend, cur)
	bk.SendCoins(cur.Address(), caller, chain.Coins{chain.NewCoin(denom, esc.AmountUgnot)})

	chain.Emit("WhisperEscrowRefunded",
		"escrow_id", strconv.FormatUint(esc.ID, 10),
		"sender", esc.Sender,
		"refund_ugnot", strconv.FormatInt(esc.AmountUgnot, 10),
		"leaf_index", strconv.FormatUint(leafIdx, 10),
		"acc_root", assurance.Hex(evidenceAcc.Root()),
	)
	return esc.AmountUgnot
}

// ResolveRecipient returns the public directory record for an address or @handle.
func ResolveRecipient(addrOrHandle string) string {
	id := mustResolveIdentity(addrOrHandle)
	return id.Address.String() + "|" + id.EncPubHex + "|" + id.Handle + "|" +
		strconv.FormatInt(id.MinTipUgnot, 10) + "|" + strconv.FormatBool(id.AllowListOnly)
}

// Root returns the global RFC 6962 accumulator root over all Whisper messages & escrows.
func Root() string {
	return assurance.Hex(evidenceAcc.Root())
}

// AccumulatorSize returns the number of RFC 6962 evidence leaves recorded by Whisper.
func AccumulatorSize() uint64 {
	return evidenceAcc.Size()
}

// MessageCount returns the total number of encrypted envelopes delivered.
func MessageCount() uint64 {
	return uint64(len(messages))
}

// EscrowCount returns the total number of DeFi escrows created.
func EscrowCount() uint64 {
	return uint64(len(escrows))
}

// MessageLeafHex returns the RFC 6962 leaf hash of message msgID.
func MessageLeafHex(msgID uint64) string {
	if msgID == 0 || msgID > uint64(len(messages)) {
		panic("no message " + strconv.FormatUint(msgID, 10))
	}
	return assurance.Hex(messages[msgID-1].LeafHash())
}

// ProofForLeaf returns the comma-separated RFC 6962 audit path for leafIndex at treeSize.
func ProofForLeaf(leafIndex, treeSize uint64) string {
	proof, err := evidenceAcc.Proof(leafIndex, treeSize)
	if err != nil {
		panic(err.Error())
	}
	parts := make([]string, len(proof))
	for i, h := range proof {
		parts[i] = assurance.Hex(h)
	}
	return strings.Join(parts, ",")
}

// VerifyLeafProof checks an RFC 6962 inclusion proof on-chain against Whisper's historical root.
func VerifyLeafProof(leafIndex, treeSize uint64, leafHex, proofCSV string) bool {
	if leafIndex >= treeSize || treeSize > evidenceAcc.Size() {
		return false
	}
	leaf, err := assurance.ParseDigest(leafHex)
	if err != nil {
		return false
	}
	rootAt, err := evidenceAcc.RootAt(treeSize)
	if err != nil {
		return false
	}
	var proof [][32]byte
	if strings.TrimSpace(proofCSV) != "" {
		for _, tok := range strings.Split(proofCSV, ",") {
			d, err := assurance.ParseDigest(strings.TrimSpace(tok))
			if err != nil {
				return false
			}
			proof = append(proof, d)
		}
	}
	return assurance.VerifyInclusion(leafIndex, treeSize, leaf, proof, rootAt)
}

func mustIdentity(addr string) *Identity {
	id, ok := identities.Get(addr).(*Identity)
	if !ok || id == nil {
		panic("identity not registered for " + addr)
	}
	return id
}

func mustResolveIdentity(addrOrHandle string) *Identity {
	q := strings.TrimSpace(addrOrHandle)
	if id, ok := identities.Get(q).(*Identity); ok && id != nil {
		return id
	}
	clean := strings.ToLower(strings.TrimLeft(q, "@"))
	if targetAddr, ok := handles.Get(clean).(string); ok && targetAddr != "" {
		return mustIdentity(targetAddr)
	}
	panic("recipient not found: " + addrOrHandle)
}

func mustEscrow(id uint64) *pw.EscrowRecord {
	if id == 0 || id > uint64(len(escrows)) {
		panic("escrow not found: " + strconv.FormatUint(id, 10))
	}
	return escrows[id-1]
}

func checkCanSend(sender, recipient *Identity) {
	if recipient.AllowListOnly && sender.Address != recipient.Address {
		if !recipient.Allowed.Has(sender.Address.String()) {
			panic("recipient only accepts messages from allowlisted senders")
		}
	}
}

func validateEnvelopeFields(ephemeralPubHex, nonceHex, ciphertextB64, commitmentHex string) {
	if err := pw.ValidateKeyHex(ephemeralPubHex); err != nil {
		panic("ephemeralPubHex: " + err.Error())
	}
	if err := pw.ValidateNonceHex(nonceHex); err != nil {
		panic("nonceHex: " + err.Error())
	}
	if err := pw.ValidateCiphertextB64(ciphertextB64); err != nil {
		panic("ciphertextB64: " + err.Error())
	}
	if _, err := assurance.ParseDigest(commitmentHex); err != nil {
		panic("commitmentHex: " + err.Error())
	}
}

func sentUgnot() int64 {
	var total int64
	for _, c := range unsafe.OriginSend() {
		if c.Amount == 0 {
			continue
		}
		if c.Denom != denom || c.Amount < 0 {
			panic("only " + denom + " is accepted")
		}
		total += c.Amount
	}
	return total
}
