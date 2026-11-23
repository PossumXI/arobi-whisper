#!/usr/bin/env node
/**
 * Arobi Whisper Cross-Shell / Cross-Environment / Cross-Harness Agent Communication Utility.
 *
 * Enables autonomous agents running across separate shells (bash, pwsh, zsh), containers
 * (Docker, WSL, cloud workers), or harnesses (Ullumii, gnosh.ai, MCP servers, realms)
 * to exchange end-to-end encrypted, warrant-bound tasks, evidence receipts, and halt signals
 * over Whisper's sealed-box format and `gno.land/r/arobi/whisper`.
 *
 * Cryptography (zero external npm dependencies — uses Node.js built-in `node:crypto`):
 *   - Ephemeral X25519 ECDH key agreement per message (forward secrecy)
 *   - HKDF-SHA256 key derivation (`arobi-whisper-agent-bus-x25519-v1`)
 *   - AEAD ChaCha20-Poly1305 encryption with 24-byte envelope nonce (12-byte cipher IV + 12-byte salt)
 *   - Tamper-evident SHA-256(ciphertext || ephemeralPub || nonce) commitment
 *
 * CLI usage:
 *   node bridge/whisper-agent-bus.mjs keygen
 *   node bridge/whisper-agent-bus.mjs seal <recipientPubHex> <packet.json>
 *   node bridge/whisper-agent-bus.mjs open <recipientPrivHex> <envelope.json>
 */

import crypto from 'node:crypto';
import fs from 'node:fs';
import { buildSendMessageTx, buildSendEscrowTx, WHISPER_REALM_PATH } from '../web/adena-whisper.mjs';

export const AGENT_BUS_VERSION = 'whisper-agent-bus/1';
const HKDF_INFO = Buffer.from('arobi-whisper-agent-bus-x25519-v1', 'utf8');
// Standard RFC 8410 ASN.1 DER prefixes for raw 32-byte X25519 keys.
const X25519_SPKI_PREFIX = Buffer.from('302a300506032b656e032100', 'hex');
const X25519_PKCS8_PREFIX = Buffer.from('302e020100300506032b656e04220420', 'hex');

function x25519PubFromRaw(raw32) {
  return crypto.createPublicKey({ key: Buffer.concat([X25519_SPKI_PREFIX, raw32]), format: 'der', type: 'spki' });
}
function x25519PrivFromRaw(raw32) {
  return crypto.createPrivateKey({ key: Buffer.concat([X25519_PKCS8_PREFIX, raw32]), format: 'der', type: 'pkcs8' });
}
function rawFromX25519Pub(pubKeyObj) {
  const der = pubKeyObj.export({ format: 'der', type: 'spki' });
  return der.subarray(der.length - 32);
}
function rawFromX25519Priv(privKeyObj) {
  const der = privKeyObj.export({ format: 'der', type: 'pkcs8' });
  return der.subarray(der.length - 32);
}

/** Generate a fresh local X25519 keypair for a shell/harness agent identity (32-byte hex keys). */
export function generateAgentBusKeys() {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('x25519');
  return {
    encPubHex: rawFromX25519Pub(publicKey).toString('hex'),
    encPrivHex: rawFromX25519Priv(privateKey).toString('hex'),
  };
}

function deriveAeadKey(sharedSecret, ephPubRaw, recipientPubRaw, nonceTail12) {
  const salt = crypto.createHash('sha256').update(Buffer.concat([ephPubRaw, recipientPubRaw, nonceTail12])).digest();
  return Buffer.from(crypto.hkdfSync('sha256', sharedSecret, salt, HKDF_INFO, 32));
}

export function computeEnvelopeCommitment(ciphertextB64, ephemeralPubHex, nonceHex) {
  const ct = Buffer.from(ciphertextB64, 'base64');
  const eph = Buffer.from(ephemeralPubHex, 'hex');
  const nonce = Buffer.from(nonceHex, 'hex');
  return crypto.createHash('sha256').update(Buffer.concat([ct, eph, nonce])).digest('hex');
}

/**
 * Seal a structured cross-shell / cross-harness AgentBusPacket for recipientEncPubHex.
 * Produces an envelope directly compatible with `gno.land/r/arobi/whisper` `SendMessage`.
 */
export function sealAgentMessage(packet, recipientEncPubHex) {
  if (!packet || typeof packet !== 'object') throw new Error('packet object is required');
  if (!/^[0-9a-f]{64}$/.test(recipientEncPubHex)) throw new Error('recipientEncPubHex must be 64 lowercase hex chars');

  const normalized = {
    version: AGENT_BUS_VERSION,
    fromHarness: String(packet.fromHarness || 'shell'),
    fromEnv: String(packet.fromEnv || `${process.platform}-${process.arch}`),
    fromAgentId: String(packet.fromAgentId || 'agent'),
    toHarness: String(packet.toHarness || 'shell'),
    toEnv: String(packet.toEnv || 'any'),
    toAgentId: String(packet.toAgentId || 'peer'),
    kind: String(packet.kind || 'task_dispatch'),
    correlationId: String(packet.correlationId || crypto.randomUUID()),
    parentWarrantDigest: packet.parentWarrantDigest || null,
    evidenceRootHex: packet.evidenceRootHex || null,
    ts: packet.ts || new Date().toISOString(),
    payload: packet.payload ?? null,
  };

  const recipientPubRaw = Buffer.from(recipientEncPubHex, 'hex');
  const recipientPub = x25519PubFromRaw(recipientPubRaw);

  const eph = crypto.generateKeyPairSync('x25519');
  const ephPubRaw = rawFromX25519Pub(eph.publicKey);
  const shared = crypto.diffieHellman({ privateKey: eph.privateKey, publicKey: recipientPub });

  // 24-byte Whisper wire nonce: first 12 bytes = ChaCha20-Poly1305 IV, last 12 bytes = HKDF salt entropy.
  const nonce24 = crypto.randomBytes(24);
  const iv12 = nonce24.subarray(0, 12);
  const tail12 = nonce24.subarray(12, 24);
  const key = deriveAeadKey(shared, ephPubRaw, recipientPubRaw, tail12);

  const cipher = crypto.createCipheriv('chacha20-poly1305', key, iv12, { authTagLength: 16 });
  const plaintext = Buffer.from(JSON.stringify(normalized), 'utf8');
  const enc = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  const tag = cipher.getAuthTag();
  const ctWithTag = Buffer.concat([enc, tag]);

  const ephemeralPubHex = ephPubRaw.toString('hex');
  const nonceHex = nonce24.toString('hex');
  const ciphertextB64 = ctWithTag.toString('base64');
  const commitmentHex = computeEnvelopeCommitment(ciphertextB64, ephemeralPubHex, nonceHex);

  return {
    ephemeralPubHex,
    nonceHex,
    ciphertextB64,
    commitmentHex,
  };
}

/** Verify commitment integrity and decrypt a Whisper Agent Bus envelope locally. */
export function openAgentMessage(envelope, recipientEncPrivHex) {
  if (!/^[0-9a-f]{64}$/.test(recipientEncPrivHex)) throw new Error('recipientEncPrivHex must be 64 lowercase hex chars');
  const recomputed = computeEnvelopeCommitment(envelope.ciphertextB64, envelope.ephemeralPubHex, envelope.nonceHex);
  if (recomputed !== envelope.commitmentHex) {
    throw new Error('commitment mismatch: envelope was tampered with in transit');
  }

  const privRaw = Buffer.from(recipientEncPrivHex, 'hex');
  const privKey = x25519PrivFromRaw(privRaw);
  const pubRaw = rawFromX25519Pub(crypto.createPublicKey(privKey));

  const ephPubRaw = Buffer.from(envelope.ephemeralPubHex, 'hex');
  const ephPub = x25519PubFromRaw(ephPubRaw);
  const shared = crypto.diffieHellman({ privateKey: privKey, publicKey: ephPub });

  const nonce24 = Buffer.from(envelope.nonceHex, 'hex');
  const iv12 = nonce24.subarray(0, 12);
  const tail12 = nonce24.subarray(12, 24);
  const key = deriveAeadKey(shared, ephPubRaw, pubRaw, tail12);

  const ctWithTag = Buffer.from(envelope.ciphertextB64, 'base64');
  if (ctWithTag.length < 17) throw new Error('ciphertext too short');
  const ct = ctWithTag.subarray(0, ctWithTag.length - 16);
  const tag = ctWithTag.subarray(ctWithTag.length - 16);

  const decipher = crypto.createDecipheriv('chacha20-poly1305', key, iv12, { authTagLength: 16 });
  decipher.setAuthTag(tag);
  const plain = Buffer.concat([decipher.update(ct), decipher.final()]).toString('utf8');
  return JSON.parse(plain);
}

/** Build a Gno.land `/vm.m_call` transaction to relay a sealed Agent Bus packet via Whisper. */
export function buildAgentWhisperTx(caller, toAddrOrHandle, sealedEnvelope, opts = {}) {
  const pkgPath = opts.pkgPath || WHISPER_REALM_PATH;
  if (opts.escrowAmountUgnot > 0) {
    return buildSendEscrowTx(
      caller,
      {
        toAddrOrHandle,
        ...sealedEnvelope,
        hashLockHex: opts.hashLockHex || '',
        ttlBlocks: opts.ttlBlocks || 100,
        amountUgnot: opts.escrowAmountUgnot,
      },
      pkgPath,
    );
  }
  return buildSendMessageTx(
    caller,
    {
      toAddrOrHandle,
      ...sealedEnvelope,
      tipUgnot: opts.tipUgnot || 0,
    },
    pkgPath,
  );
}

// CLI mode for cross-shell scripting (bash / pwsh / Docker / gnosh.ai / Ullumii)
if (process.argv[1]?.endsWith('whisper-agent-bus.mjs')) {
  const cmd = process.argv[2];
  if (cmd === 'keygen') {
    console.log(JSON.stringify(generateAgentBusKeys(), null, 2));
  } else if (cmd === 'seal' && process.argv[3] && process.argv[4]) {
    const pkt = JSON.parse(fs.readFileSync(process.argv[4], 'utf8'));
    console.log(JSON.stringify(sealAgentMessage(pkt, process.argv[3]), null, 2));
  } else if (cmd === 'open' && process.argv[3] && process.argv[4]) {
    const env = JSON.parse(fs.readFileSync(process.argv[4], 'utf8'));
    console.log(JSON.stringify(openAgentMessage(env, process.argv[3]), null, 2));
  }
}
