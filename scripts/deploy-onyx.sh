#!/usr/bin/env bash
# Deploy Arobi Whisper on Gno.land package & realm to Gno.land Onyx Testnet (onyx-1).
#
# Prerequisite: Deploy gno.land/p/<namespace>/signals and gno.land/p/<namespace>/assurance
# first using gno-immaculate-sdk-agent-builder/scripts/deploy-onyx.sh (or set ASSURANCE_NAMESPACE).
#
# Usage:
#   GNOKEY_BIN=gnokey bash scripts/deploy-onyx.sh <testnet-key-name> [namespace]
set -euo pipefail

KEY_NAME="${1:?Usage: bash scripts/deploy-onyx.sh <testnet-key-name> [namespace]}"
GNOKEY_BIN="${GNOKEY_BIN:-gnokey}"
REMOTE="${GNO_REMOTE:-https://rpc.onyx.testnets.gno.land:443}"
CHAIN_ID="${GNO_CHAIN_ID:-onyx-1}"
GAS_FEE="${GNO_GAS_FEE:-4000000ugnot}"
GAS_WANTED="${GNO_GAS_WANTED:-150000000}"
MAX_DEPOSIT="${GNO_MAX_DEPOSIT:-100000000ugnot}"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${2:-}"
if [ -z "$NAMESPACE" ]; then
  NAMESPACE="$("$GNOKEY_BIN" list | awk -v k="$KEY_NAME" '$2 == k || $2 == k"," {for(i=1;i<=NF;i++) if($i ~ /^g1[a-z0-9]+$/) {print $i; exit}}')"
  if [ -z "$NAMESPACE" ]; then
    echo "ERROR: Could not resolve g1 address for key '$KEY_NAME'. Pass [namespace] explicitly." >&2
    exit 2
  fi
fi
ASSURANCE_NAMESPACE="${ASSURANCE_NAMESPACE:-$NAMESPACE}"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

deploy_pkg() {
  local kind="$1" # p or r
  local src="$REPO/gno.land/$kind/arobi/whisper"
  local dst="$STAGE/$kind/whisper"
  mkdir -p "$dst"
  cp "$src"/*.gno "$src"/gnomod.toml "$dst/"
  rm -f "$dst"/*_test.gno
  for f in "$dst"/*.gno "$dst"/gnomod.toml; do
    sed -i.bak \
      -e "s|gno.land/p/arobi/assurance|gno.land/p/${ASSURANCE_NAMESPACE}/assurance|g" \
      -e "s|gno.land/p/arobi/whisper|gno.land/p/${NAMESPACE}/whisper|g" \
      -e "s|gno.land/r/arobi/whisper|gno.land/r/${NAMESPACE}/whisper|g" \
      -e "s|/r/arobi/whisper|/r/${NAMESPACE}/whisper|g" \
      "$f"
    rm -f "$f.bak"
  done
  local pkgpath="gno.land/$kind/${NAMESPACE}/whisper"
  echo "=== Deploying $pkgpath to $CHAIN_ID ($REMOTE) ==="
  "$GNOKEY_BIN" maketx addpkg \
    --pkgpath "$pkgpath" \
    --pkgdir "$dst" \
    --max-deposit "$MAX_DEPOSIT" \
    --remote "$REMOTE" \
    --chainid "$CHAIN_ID" \
    --gas-fee "$GAS_FEE" \
    --gas-wanted "$GAS_WANTED" \
    --broadcast \
    "$KEY_NAME"
}

deploy_pkg p
deploy_pkg r

echo ""
echo "=== Deployed Arobi Whisper on Gno.land to Onyx ($CHAIN_ID) ==="
echo "Explorer: https://onyx.testnets.gno.land/r/${NAMESPACE}/whisper"
echo ""
echo "Next (private operator initialization — never commit payout addresses):"
echo "  $GNOKEY_BIN maketx call --pkgpath gno.land/r/${NAMESPACE}/whisper --func InitOperator --remote $REMOTE --chainid $CHAIN_ID --gas-fee $GAS_FEE --gas-wanted 2000000 --broadcast $KEY_NAME"
