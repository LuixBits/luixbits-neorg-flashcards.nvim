#!/usr/bin/env sh
set -eu

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
NVIM_BIN="${NVIM:-nvim}"
LUAC_BIN="${LUAC:-}"
TEST_STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/neorg-flashcards-test-state.XXXXXX")"
trap 'rm -rf -- "$TEST_STATE_DIR"' EXIT HUP INT TERM

if [ -z "$LUAC_BIN" ]; then
  if command -v luac >/dev/null 2>&1; then
    LUAC_BIN="luac"
  elif command -v luac5.4 >/dev/null 2>&1; then
    LUAC_BIN="luac5.4"
  else
    echo "luac or luac5.4 is required" >&2
    exit 1
  fi
fi

find "$ROOT/lua" -name '*.lua' -print0 | xargs -0 "$LUAC_BIN" -p
find "$ROOT/scripts" -maxdepth 1 -name '*.lua' -print0 | xargs -0 "$LUAC_BIN" -p
find "$ROOT/tests" -name '*.lua' -print0 | xargs -0 "$LUAC_BIN" -p
if command -v stylua >/dev/null 2>&1; then
  stylua --check "$ROOT/lua" "$ROOT/tests"
fi
XDG_STATE_HOME="$TEST_STATE_DIR" NVIM_LOG_FILE="${NVIM_LOG_FILE:-/dev/null}" "$NVIM_BIN" --headless -u NONE -i NONE -n \
  --cmd "set rtp^=$ROOT" \
  -c "luafile $ROOT/tests/run.lua" \
  -c "if !get(g:, 'neorg_flashcards_tests_passed', v:false) | cquit 1 | endif" \
  -c "qa!"
