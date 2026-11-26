#!/usr/bin/env node
/**
 * Arobi Whisper — Zero-Dependency MCP Stdio Server for gnosh.ai, Ullumii, and HUE.
 *
 * Exposes forward-secret X25519 + ChaCha20-Poly1305 cross-harness agent messaging
 * and non-custodial Gno.land Whisper transaction builders over JSON-RPC 2.0 stdio.
 *
 * One-line gnosh setup:
 *   node bridge/whisper-mcp-server.mjs --print-gnosh-mcp
 */

import readline from 'node:readline';
import { fileURLToPath } from 'node:url';
import { generateAgentBusKeys } from './whisper-agent-bus.mjs';
import {
  createTaskHashLock,
  createGnoshPeerDispatch,
  openGnoshPeerDispatch,
  buildGnoshPeerRelayTx,
} from './gnosh-peer-relay.mjs';

const SERVER_INFO = {
  name: 'arobi-whisper-mcp',
  version: '1.0.0',
};

if (process.argv.includes('--print-gnosh-mcp')) {
  const scriptPath = fileURLToPath(import.meta.url);
  const cfg = {
    command: 'node',
    args: [scriptPath],
  };
  console.log(`gnosh mcp add-json arobi-whisper '${JSON.stringify(cfg)}'`);
  process.exit(0);
}

const TOOLS = [
  {
    name: 'whisper_keygen',
    description: 'Generate a fresh ephemeral X25519 keypair (64-char hex pub/priv) for encrypted cross-harness agent messaging.',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'whisper_create_hashlock',
    description: 'Generate a random 32-byte HTLC preimage and SHA-256 hashLockHex for peer compute escrow settlement.',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'whisper_seal_peer_handoff',
    description: 'Seal an E2E-encrypted gnosh.ai peer todo handoff / completion / halt packet for a recipient X25519 public key.',
    inputSchema: {
      type: 'object',
      required: ['todoPath', 'recipientEncPubHex'],
      properties: {
        kind: { type: 'string' },
        fromHarness: { type: 'string' },
        fromAgentId: { type: 'string' },
        toHarness: { type: 'string' },
        toAgentId: { type: 'string' },
        todoPath: { type: 'string' },
        planDigestHex: { type: 'string' },
        evidenceRootHex: { type: 'string' },
        parentWarrantDigest: { type: 'string' },
        taskPayload: { type: 'object' },
        recipientEncPubHex: { type: 'string' },
        hashLockHex: { type: 'string' },
      },
    },
  },
  {
    name: 'whisper_open_peer_handoff',
    description: 'Verify envelope commitment and decrypt a sealed gnosh peer Whisper envelope fail-closed.',
    inputSchema: {
      type: 'object',
      required: ['envelope', 'recipientEncPrivHex'],
      properties: {
        envelope: { type: 'object' },
        recipientEncPrivHex: { type: 'string' },
        expectedPlanDigestHex: { type: 'string' },
        expectedTodoPath: { type: 'string' },
        expectedKind: { type: 'string' },
      },
    },
  },
  {
    name: 'whisper_build_relay_tx',
    description: 'Build a non-custodial Gno.land /vm.m_call Whisper transaction (SendMessage or SendEscrowMessage) carrying a sealed peer dispatch.',
    inputSchema: {
      type: 'object',
      required: ['caller', 'toAddrOrHandle', 'dispatch'],
      properties: {
        caller: { type: 'string' },
        toAddrOrHandle: { type: 'string' },
        dispatch: { type: 'object' },
        tipUgnot: { type: 'number' },
        escrowAmountUgnot: { type: 'number' },
        hashLockHex: { type: 'string' },
        ttlBlocks: { type: 'number' },
        pkgPath: { type: 'string' },
      },
    },
  },
];

function handleToolCall(name, args = {}) {
  switch (name) {
    case 'whisper_keygen':
      return generateAgentBusKeys();
    case 'whisper_create_hashlock':
      return createTaskHashLock();
    case 'whisper_seal_peer_handoff':
      return createGnoshPeerDispatch(args);
    case 'whisper_open_peer_handoff':
      return openGnoshPeerDispatch(args.envelope, args.recipientEncPrivHex, {
        planDigestHex: args.expectedPlanDigestHex,
        todoPath: args.expectedTodoPath,
        kind: args.expectedKind,
      });
    case 'whisper_build_relay_tx':
      return buildGnoshPeerRelayTx(args.caller, args.toAddrOrHandle, args.dispatch, {
        tipUgnot: args.tipUgnot,
        escrowAmountUgnot: args.escrowAmountUgnot,
        hashLockHex: args.hashLockHex,
        ttlBlocks: args.ttlBlocks,
        pkgPath: args.pkgPath,
      });
    default:
      throw new Error(`Unknown MCP tool: ${name}`);
  }
}

function send(msg) {
  if (!process.stdout.writable) return;
  try {
    process.stdout.write(JSON.stringify(msg) + '\n');
  } catch {
    // Ignore broken pipe during harness teardown.
  }
}

let shuttingDown = false;
function gracefulShutdown() {
  if (shuttingDown) return;
  shuttingDown = true;
  try {
    rl.close();
  } catch {
    // Ignore close races.
  }
  process.exit(0);
}

process.on('SIGINT', gracefulShutdown);
process.on('SIGTERM', gracefulShutdown);
process.stdin.on('error', gracefulShutdown);
process.stdout.on('error', gracefulShutdown);

const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
rl.on('close', () => {
  if (!shuttingDown) {
    shuttingDown = true;
    process.exitCode = 0;
  }
});
rl.on('line', (line) => {
  const trimmed = line.trim();
  if (!trimmed) return;
  let req;
  try {
    req = JSON.parse(trimmed);
  } catch (err) {
    send({ jsonrpc: '2.0', id: null, error: { code: -32700, message: `Parse error: ${err.message}` } });
    return;
  }

  const { id, method, params } = req;
  if (method === 'notifications/initialized' || method === 'notifications/cancelled') return;

  try {
    if (method === 'initialize') {
      send({
        jsonrpc: '2.0',
        id,
        result: {
          protocolVersion: '2024-11-05',
          serverInfo: SERVER_INFO,
          capabilities: { tools: {} },
        },
      });
    } else if (method === 'ping') {
      send({ jsonrpc: '2.0', id, result: {} });
    } else if (method === 'shutdown') {
      send({ jsonrpc: '2.0', id, result: null });
      setImmediate(gracefulShutdown);
    } else if (method === 'exit') {
      gracefulShutdown();
    } else if (method === 'tools/list') {
      send({ jsonrpc: '2.0', id, result: { tools: TOOLS } });
    } else if (method === 'tools/call') {
      const data = handleToolCall(params?.name, params?.arguments || {});
      send({
        jsonrpc: '2.0',
        id,
        result: {
          content: [{ type: 'text', text: JSON.stringify(data) }],
          structuredContent: data,
        },
      });
    } else if (id !== undefined && id !== null) {
      send({ jsonrpc: '2.0', id, error: { code: -32601, message: `Method not found: ${method}` } });
    }
  } catch (err) {
    if (id !== undefined && id !== null) {
      send({ jsonrpc: '2.0', id, error: { code: -32000, message: String(err.message || err) } });
    }
  }
});
