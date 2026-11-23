/**
 * Gnosh Peer Relay over Arobi Whisper (Non-Custodial E2E Encrypted Cross-Harness Bridge).
 *
 * Bridges gnosh.ai `gnomem/v2` multi-session peer plans (`.Parallel()` todos) across
 * separate machines, shells, and harnesses (gnosh.ai, Ullumii, HUE, MCP) using
 * forward-secret X25519 + HKDF-SHA256 + ChaCha20-Poly1305 Whisper sealed envelopes
 * and optional SHA-256 HTLC escrows on `gno.land/r/arobi/whisper`.
 */

import crypto from 'node:crypto';
import {
  AGENT_BUS_VERSION,
  sealAgentMessage,
  openAgentMessage,
  buildAgentWhisperTx,
} from './whisper-agent-bus.mjs';
import { buildClaimEscrowTx, WHISPER_REALM_PATH } from '../web/adena-whisper.mjs';

export const GNOSH_PEER_KINDS = Object.freeze([
  'peer_claim',
  'peer_handoff',
  'peer_done',
  'peer_halt',
]);

/** Generate a random 32-byte HTLC preimage and its SHA-256 hashLockHex for escrow settlement. */
export function createTaskHashLock() {
  const preimageHex = crypto.randomBytes(32).toString('hex');
  const hashLockHex = crypto.createHash('sha256').update(Buffer.from(preimageHex, 'hex')).digest('hex');
  return { preimageHex, hashLockHex };
}

/**
 * Seal a gnosh.ai peer todo handoff / completion / halt packet for recipientEncPubHex.
 * Optionally attaches an HTLC hashLockHex for trustless Gno Whisper escrow settlement.
 */
export function createGnoshPeerDispatch({
  kind = 'peer_handoff',
  fromHarness = 'gnosh.ai',
  fromAgentId = 'gnosh-peer',
  toHarness = 'ullumii',
  toAgentId = 'ullumii-worker',
  todoPath,
  planDigestHex = '',
  evidenceRootHex = null,
  parentWarrantDigest = null,
  taskPayload = {},
  recipientEncPubHex,
  correlationId = '',
  hashLockHex = '',
}) {
  if (!GNOSH_PEER_KINDS.includes(kind)) {
    throw new Error(`unsupported gnosh peer kind: ${kind}`);
  }
  const cleanTodo = String(todoPath || '').trim();
  if (!cleanTodo) {
    throw new Error('todoPath is required (e.g. "plan/work/alpha")');
  }
  if (hashLockHex && !/^[0-9a-f]{64}$/.test(hashLockHex)) {
    throw new Error('hashLockHex must be 64 lowercase hex chars');
  }

  const packet = {
    fromHarness,
    fromAgentId,
    toHarness,
    toAgentId,
    kind,
    correlationId: correlationId || `gnosh-${cleanTodo}-${crypto.randomUUID().slice(0, 8)}`,
    parentWarrantDigest,
    evidenceRootHex,
    payload: {
      protocol: 'gnosh-peers-whisper/1',
      todoPath: cleanTodo,
      planDigestHex: String(planDigestHex || ''),
      hashLockHex: hashLockHex || null,
      task: taskPayload ?? {},
    },
  };

  const envelope = sealAgentMessage(packet, recipientEncPubHex);
  return {
    version: AGENT_BUS_VERSION,
    kind,
    todoPath: cleanTodo,
    correlationId: packet.correlationId,
    envelope,
  };
}

/**
 * Decrypt and verify a gnosh peer Whisper envelope fail-closed against expected plan / kind.
 */
export function openGnoshPeerDispatch(envelope, recipientEncPrivHex, expect = {}) {
  const opened = openAgentMessage(envelope, recipientEncPrivHex);
  if (!GNOSH_PEER_KINDS.includes(opened.kind)) {
    throw new Error(`unexpected packet kind for gnosh peer relay: ${opened.kind}`);
  }
  if (opened.payload?.protocol !== 'gnosh-peers-whisper/1') {
    throw new Error('unexpected gnosh peer relay protocol tag');
  }
  if (!opened.payload?.todoPath) {
    throw new Error('missing todoPath in gnosh peer relay packet');
  }
  if (expect.kind && opened.kind !== expect.kind) {
    throw new Error(`kind mismatch: expected ${expect.kind}, got ${opened.kind}`);
  }
  if (expect.planDigestHex && opened.payload.planDigestHex !== expect.planDigestHex) {
    throw new Error('planDigestHex mismatch: packet belongs to a different gnomem plan');
  }
  if (expect.todoPath && opened.payload.todoPath !== expect.todoPath) {
    throw new Error(`todoPath mismatch: expected ${expect.todoPath}, got ${opened.payload.todoPath}`);
  }
  return opened;
}

/**
 * Build a ready-to-broadcast Gno.land Whisper transaction (message or HTLC escrow)
 * carrying a sealed gnosh peer dispatch envelope. Pure non-custodial P2P.
 */
export function buildGnoshPeerRelayTx(caller, toAddrOrHandle, dispatch, opts = {}) {
  if (!dispatch?.envelope) throw new Error('dispatch.envelope is required');
  return buildAgentWhisperTx(caller, toAddrOrHandle, dispatch.envelope, {
    pkgPath: opts.pkgPath || WHISPER_REALM_PATH,
    tipUgnot: opts.tipUgnot || 0,
    escrowAmountUgnot: opts.escrowAmountUgnot || 0,
    hashLockHex: opts.hashLockHex || '',
    ttlBlocks: opts.ttlBlocks || 100,
  });
}

/** Build a Gno.land Whisper `ClaimEscrow` tx once a peer completes its todo and reveals preimage. */
export function buildGnoshPeerClaimTx(caller, { escrowId, preimageHex = '' }, pkgPath = WHISPER_REALM_PATH) {
  return buildClaimEscrowTx(caller, { escrowId, preimage: preimageHex }, pkgPath);
}
