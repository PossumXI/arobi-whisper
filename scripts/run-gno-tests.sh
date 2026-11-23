#!/usr/bin/env bash
# Runs `gno test` for gno.land/p/arobi/whisper and gno.land/r/arobi/whisper.
#
# Supports BOTH:
#   1. Current github.com/gnolang/gno master (workspace resolution via gnowork.toml,
#      avoiding nested-workspace SkipDir when immaculate-sdk-agent-builder has its own gnowork.toml).
#   2. Gno v1.8.0 source checkouts (GNOROOT/examples/gno.land resolution when GNO_SRC points to v1.8.0).
set -euo pipefail
export GOWORK=off

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -n "${ASSURANCE_REPO:-}" ]; then
  :
elif [ -d "$REPO/../immaculate-sdk-agent-builder/gno.land/p/arobi/assurance" ]; then
  ASSURANCE_REPO="$REPO/../immaculate-sdk-agent-builder"
elif [ -d "$REPO/../gno-immaculate-sdk-agent-builder/gno.land/p/arobi/assurance" ]; then
  ASSURANCE_REPO="$REPO/../gno-immaculate-sdk-agent-builder"
else
  ASSURANCE_REPO="$REPO/../immaculate-sdk-agent-builder"
fi

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
  ( cd "$root" && "$GNO_BIN" test -v "$@" )
}

run_v18_examples() {
  echo "=== gno lint + test (Gno v1.8.0 examples workspace: $GNO_SRC) ==="
  for pkg in p/arobi/signals p/arobi/assurance; do
    rm -rf "$GNO_SRC/examples/gno.land/$pkg"
    mkdir -p "$GNO_SRC/examples/gno.land/$(dirname "$pkg")"
    cp -r "$ASSURANCE_REAL/gno.land/$pkg" "$GNO_SRC/examples/gno.land/$pkg"
  done
  for pkg in p/arobi/whisper r/arobi/whisper; do
    rm -rf "$GNO_SRC/examples/gno.land/$pkg"
    mkdir -p "$GNO_SRC/examples/gno.land/$(dirname "$pkg")"
    cp -r "$REPO/gno.land/$pkg" "$GNO_SRC/examples/gno.land/$pkg"
  done
  for pkg in p/arobi/whisper r/arobi/whisper; do
    ( cd "$GNO_SRC/examples/gno.land/$pkg" && "$GNO_BIN" lint . && "$GNO_BIN" test -v . )
  done
}

# Gno v1.8.0 resolves cross-package imports from $GNO_SRC/examples/gno.land rather than gnowork.toml.
if [ -n "${GNO_SRC:-}" ] && [ -d "$GNO_SRC/examples/gno.land/p/nt" ]; then
  # Check if gno binary supports gnowork.toml cleanly; v1.8.0 checkouts lack gnowork.toml support on Windows.
  if [ ! -f "$GNO_SRC/gnovm/pkg/packages/load.go" ] || ! grep -q "findWorkspaceRootDir" "$GNO_SRC/gnovm/pkg/packages/load.go" 2>/dev/null; then
    run_v18_examples
    echo "=== ALL AROBI WHISPER TESTS PASSED ==="
    exit 0
  fi
fi

# Note: gnolang/gno's workspace walker skips any child directory that contains its own gnowork.toml
# (fs.SkipDir in gnovm/pkg/packages/load.go). Only reuse $PARENT/gnowork.toml when neither repo
# contains a nested gnowork.toml; otherwise build a clean unified temporary workspace.
if [ -f "$PARENT/gnowork.toml" ] && [ "${ASSURANCE_REAL#"$PARENT"/}" != "$ASSURANCE_REAL" ] \
   && [ ! -f "$ASSURANCE_REAL/gnowork.toml" ] && [ ! -f "$REPO/gnowork.toml" ]; then
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
  if ! run_in "$WORK" ./whisper/gno.land/p/arobi/whisper ./whisper/gno.land/r/arobi/whisper; then
    if [ -n "${GNO_SRC:-}" ] && [ -d "$GNO_SRC/examples/gno.land" ]; then
      echo "=== falling back to Gno v1.8.0 examples workspace ==="
      run_v18_examples
    else
      exit 1
    fi
  fi
fi

echo "=== ALL AROBI WHISPER TESTS PASSED ==="
