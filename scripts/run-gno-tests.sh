#!/usr/bin/env bash
# Runs real `gno test -v` for gno.land/p/arobi/whisper and gno.land/r/arobi/whisper
# (together with gno.land/p/arobi/assurance) against a Gno v1.8.0 source tree.
set -euo pipefail
export GOWORK=off

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSURANCE_REPO="${ASSURANCE_REPO:-$REPO/../gno-immaculate-sdk-agent-builder}"
GNO_SRC="${GNO_SRC:-/tmp/gno-v1.8.0}"
GNO_BIN="$GNO_SRC/build/gno"
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) GNO_BIN="$GNO_BIN.exe" ;; esac

if [ ! -x "$GNO_BIN" ]; then
  echo "ERROR: gno binary not found at $GNO_BIN. Set GNO_SRC to your gnolang/gno checkout." >&2
  exit 2
fi

if command -v cygpath >/dev/null 2>&1; then
  export GNOROOT="$(cygpath -m "$GNO_SRC")"
else
  export GNOROOT="$GNO_SRC"
fi

# Sync dependency packages p/arobi/signals and p/arobi/assurance first if available locally.
for dep in p/arobi/signals p/arobi/assurance; do
  if [ -d "$ASSURANCE_REPO/gno.land/$dep" ]; then
    rm -rf "$GNO_SRC/examples/gno.land/$dep"
    mkdir -p "$GNO_SRC/examples/gno.land/$(dirname "$dep")"
    cp -r "$ASSURANCE_REPO/gno.land/$dep" "$GNO_SRC/examples/gno.land/$dep"
  fi
done

for pkg in p/arobi/whisper r/arobi/whisper; do
  rm -rf "$GNO_SRC/examples/gno.land/$pkg"
  mkdir -p "$GNO_SRC/examples/gno.land/$(dirname "$pkg")"
  cp -r "$REPO/gno.land/$pkg" "$GNO_SRC/examples/gno.land/$pkg"
done

for pkg in p/arobi/whisper r/arobi/whisper; do
  echo "=== gno lint + test -v gno.land/$pkg ==="
  ( cd "$GNO_SRC/examples/gno.land/$pkg" && "$GNO_BIN" lint . && "$GNO_BIN" test -v . )
done
echo "=== ALL AROBI WHISPER GNO TESTS PASSED ==="
