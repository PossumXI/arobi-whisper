import test from 'node:test';
import assert from 'node:assert/strict';
import {
  WHISPER_REALM_PATH,
  buildRegisterIdentityTx,
  buildSubscribeTx,
  buildSetInboxPolicyTx,
  buildSendMessageTx,
  buildSendEscrowTx,
  buildClaimEscrowTx,
  buildRefundEscrowTx,
} from './adena-whisper.mjs';

test('Adena tx builders emit canonical Gno /vm.m_call payloads', () => {
  const caller = 'g1alice0000000000000000000000000000000000';
  const enc = '1'.repeat(64);
  const reg = buildRegisterIdentityTx(caller, { encPubHex: enc, handle: 'alice_gno', displayName: 'Alice' });
  assert.equal(reg.messages[0].type, '/vm.m_call');
  assert.equal(reg.messages[0].value.pkg_path, WHISPER_REALM_PATH);
  assert.equal(reg.messages[0].value.func, 'RegisterIdentity');
  assert.deepEqual(reg.messages[0].value.args, [enc, '', 'alice_gno', 'Alice']);
  assert.equal(reg.messages[0].value.send, '');

  const sub = buildSubscribeTx(caller, 25000000);
  assert.equal(sub.messages[0].value.func, 'Subscribe');
  assert.equal(sub.messages[0].value.send, '25000000ugnot');

  const pol = buildSetInboxPolicyTx(caller, { minTipUgnot: 5000, allowListOnly: true });
  assert.deepEqual(pol.messages[0].value.args, ['5000', 'true']);

  const msg = buildSendMessageTx(caller, {
    toAddrOrHandle: '@bob',
    ephemeralPubHex: 'a'.repeat(64),
    nonceHex: 'b'.repeat(48),
    ciphertextB64: 'YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXo=',
    commitmentHex: 'c'.repeat(64),
    tipUgnot: 5000,
  });
  assert.equal(msg.messages[0].value.send, '5000ugnot');
  assert.equal(msg.messages[0].value.func, 'SendMessage');

  const esc = buildSendEscrowTx(caller, {
    toAddrOrHandle: '@bob',
    ephemeralPubHex: 'a'.repeat(64),
    nonceHex: 'b'.repeat(48),
    ciphertextB64: 'YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXo=',
    commitmentHex: 'c'.repeat(64),
    hashLockHex: 'd'.repeat(64),
    ttlBlocks: 50,
    amountUgnot: 100000,
  });
  assert.equal(esc.messages[0].value.func, 'SendEscrowMessage');
  assert.equal(esc.messages[0].value.send, '100000ugnot');
  assert.equal(esc.messages[0].value.args[6], '50');

  const claim = buildClaimEscrowTx(caller, { escrowId: 1, preimage: 'secret' });
  assert.deepEqual(claim.messages[0].value.args, ['1', 'secret']);

  const refund = buildRefundEscrowTx(caller, { escrowId: 2 });
  assert.deepEqual(refund.messages[0].value.args, ['2']);
});
