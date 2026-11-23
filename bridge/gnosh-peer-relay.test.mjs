import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import readline from 'node:readline';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { generateAgentBusKeys } from './whisper-agent-bus.mjs';
import {
  createTaskHashLock,
  createGnoshPeerDispatch,
  openGnoshPeerDispatch,
  buildGnoshPeerRelayTx,
  buildGnoshPeerClaimTx,
} from './gnosh-peer-relay.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const MCP_SERVER_PATH = path.join(__dirname, 'whisper-mcp-server.mjs');

test('Gnosh peer relay seals, verifies planDigest fail-closed, and builds HTLC escrow + claim txs', () => {
  const peerKeys = generateAgentBusKeys();
  const htlc = createTaskHashLock();
  assert.match(htlc.preimageHex, /^[0-9a-f]{64}$/);
  assert.match(htlc.hashLockHex, /^[0-9a-f]{64}$/);

  const planDigestHex = 'c'.repeat(64);
  const dispatch = createGnoshPeerDispatch({
    kind: 'peer_handoff',
    fromHarness: 'gnosh.ai',
    fromAgentId: 'gnosh-coord-1',
    toHarness: 'ullumii',
    toAgentId: 'ullumii-gpu-worker',
    todoPath: 'recall/work/alpha',
    planDigestHex,
    evidenceRootHex: 'd'.repeat(64),
    taskPayload: { log: 'logs/alpha.log', maxTokens: 32000 },
    recipientEncPubHex: peerKeys.encPubHex,
    hashLockHex: htlc.hashLockHex,
  });

  // Zero plaintext leakage
  assert.equal(dispatch.envelope.ciphertextB64.includes('alpha.log'), false);

  // Decrypt + strict plan verification passes
  const opened = openGnoshPeerDispatch(dispatch.envelope, peerKeys.encPrivHex, {
    kind: 'peer_handoff',
    planDigestHex,
    todoPath: 'recall/work/alpha',
  });
  assert.equal(opened.payload.todoPath, 'recall/work/alpha');
  assert.equal(opened.payload.task.log, 'logs/alpha.log');
  assert.equal(opened.payload.hashLockHex, htlc.hashLockHex);

  // Plan digest mismatch fails closed
  assert.throws(
    () => openGnoshPeerDispatch(dispatch.envelope, peerKeys.encPrivHex, { planDigestHex: 'f'.repeat(64) }),
    /planDigestHex mismatch/,
  );

  // Build non-custodial Gno Whisper escrow + claim transactions
  const escrowTx = buildGnoshPeerRelayTx(
    'g1gnoshpeer000000000000000000000000000000',
    '@ullumii_worker',
    dispatch,
    { escrowAmountUgnot: 25000, hashLockHex: htlc.hashLockHex, ttlBlocks: 200 },
  );
  assert.equal(escrowTx.messages[0].value.func, 'SendEscrowMessage');
  assert.equal(escrowTx.messages[0].value.send, '25000ugnot');
  assert.equal(escrowTx.messages[0].value.args[5], htlc.hashLockHex);

  const claimTx = buildGnoshPeerClaimTx('g1ullumii00000000000000000000000000000000', {
    escrowId: 7,
    preimageHex: htlc.preimageHex,
  });
  assert.equal(claimTx.messages[0].value.func, 'ClaimEscrow');
  assert.equal(claimTx.messages[0].value.args[1], htlc.preimageHex);
});

test('Whisper MCP stdio server runs keygen, seal, open, and relay tx over JSON-RPC 2.0', async () => {
  const child = spawn(process.execPath, [MCP_SERVER_PATH], { stdio: ['pipe', 'pipe', 'pipe'] });
  const rl = readline.createInterface({ input: child.stdout });
  const pending = new Map();
  let nextId = 1;

  rl.on('line', (line) => {
    const msg = JSON.parse(line);
    const resolve = pending.get(msg.id);
    if (resolve) {
      pending.delete(msg.id);
      resolve(msg);
    }
  });

  function call(method, params = {}) {
    const id = nextId++;
    return new Promise((resolve, reject) => {
      pending.set(id, resolve);
      child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
      setTimeout(() => {
        if (pending.has(id)) {
          pending.delete(id);
          reject(new Error(`MCP timeout for ${method}`));
        }
      }, 5000);
    });
  }

  try {
    const init = await call('initialize', { protocolVersion: '2024-11-05' });
    assert.equal(init.result.serverInfo.name, 'arobi-whisper-gno-mcp');

    const list = await call('tools/list');
    assert.equal(list.result.tools.length, 5);

    const keysRes = await call('tools/call', { name: 'whisper_keygen', arguments: {} });
    const keys = keysRes.result.structuredContent;
    assert.match(keys.encPubHex, /^[0-9a-f]{64}$/);

    const sealRes = await call('tools/call', {
      name: 'whisper_seal_peer_handoff',
      arguments: {
        todoPath: 'plan/work/beta',
        planDigestHex: 'e'.repeat(64),
        recipientEncPubHex: keys.encPubHex,
        taskPayload: { cmd: 'go test ./beta' },
      },
    });
    const dispatch = sealRes.result.structuredContent;

    const openRes = await call('tools/call', {
      name: 'whisper_open_peer_handoff',
      arguments: {
        envelope: dispatch.envelope,
        recipientEncPrivHex: keys.encPrivHex,
        expectedPlanDigestHex: 'e'.repeat(64),
      },
    });
    assert.equal(openRes.result.structuredContent.payload.todoPath, 'plan/work/beta');
    assert.equal(openRes.result.structuredContent.payload.task.cmd, 'go test ./beta');

    const txRes = await call('tools/call', {
      name: 'whisper_build_relay_tx',
      arguments: {
        caller: 'g1gnoshpeer000000000000000000000000000000',
        toAddrOrHandle: '@gnosh_helper',
        dispatch,
        tipUgnot: 1000,
      },
    });
    assert.equal(txRes.result.structuredContent.messages[0].value.func, 'SendMessage');
    assert.equal(txRes.result.structuredContent.messages[0].value.send, '1000ugnot');
  } finally {
    rl.close();
    child.kill();
  }
});
