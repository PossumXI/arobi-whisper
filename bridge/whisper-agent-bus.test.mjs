import test from 'node:test';
import assert from 'node:assert/strict';
import {
  AGENT_BUS_VERSION,
  generateAgentBusKeys,
  sealAgentMessage,
  openAgentMessage,
  buildAgentWhisperTx,
} from './whisper-agent-bus.mjs';

test('Cross-harness Ullumii -> gnosh.ai encrypted Agent Bus seal/open and tamper rejection', () => {
  const gnoshKeys = generateAgentBusKeys();
  const wrongKeys = generateAgentBusKeys();

  const packet = {
    fromHarness: 'ullumii',
    fromEnv: 'cloud-worker',
    fromAgentId: 'ullumii-coordinator',
    toHarness: 'gnosh.ai',
    toEnv: 'linux-docker-shell',
    toAgentId: 'gnosh-builder-1',
    kind: 'warrant_delegate',
    correlationId: 'corr-2026-11-23-01',
    parentWarrantDigest: 'a'.repeat(64),
    evidenceRootHex: 'b'.repeat(64),
    payload: { action: 'run_gno_tests', repo: 'immaculate-sdk-agent-builder', maxBudgetUgnot: 400 },
  };

  const sealed = sealAgentMessage(packet, gnoshKeys.encPubHex);
  assert.match(sealed.ephemeralPubHex, /^[0-9a-f]{64}$/);
  assert.match(sealed.nonceHex, /^[0-9a-f]{48}$/);
  assert.match(sealed.commitmentHex, /^[0-9a-f]{64}$/);
  // Zero plaintext leakage in ciphertext!
  assert.equal(sealed.ciphertextB64.includes('run_gno_tests'), false);

  // Intended gnosh.ai agent decrypts cleanly.
  const opened = openAgentMessage(sealed, gnoshKeys.encPrivHex);
  assert.equal(opened.version, AGENT_BUS_VERSION);
  assert.equal(opened.fromHarness, 'ullumii');
  assert.equal(opened.toHarness, 'gnosh.ai');
  assert.equal(opened.payload.action, 'run_gno_tests');
  assert.equal(opened.parentWarrantDigest, 'a'.repeat(64));

  // Wrong recipient key fails AEAD authentication.
  assert.throws(() => openAgentMessage(sealed, wrongKeys.encPrivHex));

  // Tampered commitment fails immediately before decryption.
  assert.throws(() => openAgentMessage({ ...sealed, commitmentHex: '0'.repeat(64) }, gnoshKeys.encPrivHex), /commitment mismatch/);

  // Builds a ready-to-broadcast Whisper transaction.
  const tx = buildAgentWhisperTx('g1ullumii00000000000000000000000000000000', '@gnosh_builder', sealed, { tipUgnot: 5000 });
  assert.equal(tx.messages[0].value.func, 'SendMessage');
  assert.equal(tx.messages[0].value.send, '5000ugnot');
});
