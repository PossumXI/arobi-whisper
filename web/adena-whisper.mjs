// Arobi Whisper — Adena Wallet + RPC Adapter & Wire-Compatible E2EE Helper.
//
// Connects client-side Arobi Whisper v1 sealed-box encryption (X25519 + HKDF-SHA256 +
// XChaCha20-Poly1305) directly to gno.land/r/arobi/whisper via Adena wallet (window.adena)
// and Gno.land ABCI queries (abci_query vm/qeval).

export const WHISPER_REALM_PATH = 'gno.land/r/arobi/whisper';
export const WHISPER_DOMAIN = 'arobi-whisper-x25519-xchacha-v1';

/** Build an Adena DoContract payload for any gno.land/r/arobi/whisper call. */
export function buildWhisperTx(caller, func, args, sendUgnot = 0, pkgPath = WHISPER_REALM_PATH) {
  const send = sendUgnot > 0 ? `${Math.trunc(sendUgnot)}ugnot` : '';
  return {
    messages: [
      {
        type: '/vm.m_call',
        value: {
          caller,
          send,
          pkg_path: pkgPath,
          func,
          args: args.map((a) => String(a)),
        },
      },
    ],
    gasFee: 1000000,
    gasWanted: 5000000,
    memo: `Arobi Whisper: ${func}`,
  };
}

export function buildRegisterIdentityTx(caller, { encPubHex, signPubHex = '', handle = '', displayName = '' }, pkgPath = WHISPER_REALM_PATH) {
  return buildWhisperTx(caller, 'RegisterIdentity', [encPubHex, signPubHex, handle, displayName], 0, pkgPath);
}

export function buildSubscribeTx(caller, subscriptionPriceUgnot = 25000000, pkgPath = WHISPER_REALM_PATH) {
  return buildWhisperTx(caller, 'Subscribe', [], subscriptionPriceUgnot, pkgPath);
}

export function buildSetInboxPolicyTx(caller, { minTipUgnot = 0, allowListOnly = false }, pkgPath = WHISPER_REALM_PATH) {
  return buildWhisperTx(caller, 'SetInboxPolicy', [minTipUgnot, allowListOnly ? 'true' : 'false'], 0, pkgPath);
}

export function buildSendMessageTx(
  caller,
  { toAddrOrHandle, ephemeralPubHex, nonceHex, ciphertextB64, commitmentHex, tipUgnot = 0 },
  pkgPath = WHISPER_REALM_PATH,
) {
  return buildWhisperTx(
    caller,
    'SendMessage',
    [toAddrOrHandle, ephemeralPubHex, nonceHex, ciphertextB64, commitmentHex],
    tipUgnot,
    pkgPath,
  );
}

export function buildSendEscrowTx(
  caller,
  { toAddrOrHandle, ephemeralPubHex, nonceHex, ciphertextB64, commitmentHex, hashLockHex = '', ttlBlocks = 100, amountUgnot },
  pkgPath = WHISPER_REALM_PATH,
) {
  return buildWhisperTx(
    caller,
    'SendEscrowMessage',
    [toAddrOrHandle, ephemeralPubHex, nonceHex, ciphertextB64, commitmentHex, hashLockHex, ttlBlocks],
    amountUgnot,
    pkgPath,
  );
}

export function buildClaimEscrowTx(caller, { escrowId, preimage = '' }, pkgPath = WHISPER_REALM_PATH) {
  return buildWhisperTx(caller, 'ClaimEscrow', [escrowId, preimage], 0, pkgPath);
}

export function buildRefundEscrowTx(caller, { escrowId }, pkgPath = WHISPER_REALM_PATH) {
  return buildWhisperTx(caller, 'RefundEscrow', [escrowId], 0, pkgPath);
}

/** Execute a built Whisper tx through the browser's Adena wallet extension. */
export async function broadcastWithAdena(tx) {
  if (typeof window === 'undefined' || !window.adena) {
    throw new Error('Adena wallet extension not detected. Install Adena (https://adena.app) to broadcast the transaction.');
  }
  await window.adena.AddEstablish('Arobi Whisper');
  return await window.adena.DoContract(tx);
}

/** Query a read-only Whisper realm expression via Gno.land Tendermint JSON-RPC abci_query. */
export async function queryWhisperEval(rpcUrl, expr, pkgPath = WHISPER_REALM_PATH) {
  const data = btoa(`${pkgPath}.${expr}`);
  const url = `${rpcUrl.replace(/\/$/, '')}/abci_query?path=%22vm/qeval%22&data=%22${encodeURIComponent(data)}%22`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`RPC HTTP ${res.status}`);
  const json = await res.json();
  const b64 = json?.result?.response?.ResponseBase?.Data;
  if (!b64) return null;
  return atob(b64);
}
