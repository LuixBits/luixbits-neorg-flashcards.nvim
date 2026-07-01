#!/usr/bin/env sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

find "$ROOT/lua" -name '*.lua' -print0 | xargs -0 luac -p
find "$ROOT/scripts" -maxdepth 1 -name '*.lua' -print0 | xargs -0 -r luac -p
if command -v stylua >/dev/null 2>&1; then
  stylua --check "$ROOT/lua" "$ROOT/tests"
fi
nvim --headless -u NONE -i NONE -n --cmd "set rtp^=$ROOT" -c "luafile $ROOT/tests/run.lua" -c "qa!"
