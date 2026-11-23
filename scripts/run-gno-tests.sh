#!/usr/bin/env bash
# Runs `gno test` for gno.land/p/arobi/whisper and gno.land/r/arobi/whisper.
#
# Current gno resolves imports from a gnowork.toml workspace. It does not
# load gno.land/p/arobi/assurance by copying that package into
# $GNOROOT/examples. signals and assurance come from a checkout of
# immaculate-sdk-agent-builder.
set -euo pipefail
export GOWORK=off

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSURANCE_REPO="${ASSURANCE_REPO:-$REPO/../immaculate-sdk-agent-builder}"

if [ -n "${GNO_BIN:-}" ]; then
  :
elif [ -n "${GNO_SRC:-}" ] && [ -x "${GNO_SRC}/build/gno" ]; then
  GNO_BIN="${GNO_SRC}/build/gno"
elif [ -n "${GNO_SRC:-}" ] && [ -x "${GNO_SRC}/build/gno.exe" ]; then
  GNO_BIN="${GNO_SRC}/build/gno.exe"
elif command -v gno >/dev/null 2>&1; then
  GNO_BIN="$(command -v gno)"
else
  echo "ERROR: gno is not on PATH. Install github.com/gnolang/gno master, or set GNO_BIN / GNO_SRC." >&2
  exit 2
fi

if [ -n "${GNO_SRC:-}" ]; then
  if command -v cygpath >/dev/null 2>&1; then
    export GNOROOT="$(cygpath -m "$GNO_SRC")"
  else
    export GNOROOT="$GNO_SRC"
  fi
fi

if [ ! -d "$ASSURANCE_REPO/gno.land/p/arobi/assurance" ] || [ ! -d "$ASSURANCE_REPO/gno.land/p/arobi/signals" ]; then
  echo "ERROR: gno.land/p/arobi/assurance or signals is missing under $ASSURANCE_REPO." >&2
  echo "Clone https://github.com/PossumXI/immaculate-sdk-agent-builder next to this repo, or set ASSURANCE_REPO." >&2
  exit 2
fi

ASSURANCE_REAL="$(cd "$ASSURANCE_REPO" && pwd)"
PARENT="$(cd "$REPO/.." && pwd)"

run_in() {
  local root="$1"
  shift
  ( cd "$root" && "$GNO_BIN" test "$@" )
}

if [ -f "$PARENT/gnowork.toml" ] && [ "${ASSURANCE_REAL#"$PARENT"/}" != "$ASSURANCE_REAL" ]; then
  echo "=== gno test (workspace $PARENT) ==="
  run_in "$REPO" ./gno.land/p/arobi/whisper ./gno.land/r/arobi/whisper
else
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  : > "$WORK/gnowork.toml"
  mkdir -p "$WORK/whisper" "$WORK/sdk"
  cp -a "$REPO/gno.land" "$WORK/whisper/gno.land"
  cp -a "$ASSURANCE_REAL/gno.land" "$WORK/sdk/gno.land"
  echo "=== gno test (temporary workspace) ==="
  run_in "$WORK" ./whisper/gno.land/p/arobi/whisper ./whisper/gno.land/r/arobi/whisper
fi

echo "=== ALL AROBI WHISPER TESTS PASSED ==="
