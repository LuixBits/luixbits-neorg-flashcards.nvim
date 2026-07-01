#!/usr/bin/env sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/flashcards"
cp -R "$ROOT/docs/demo/flashcards/." "$TMP/flashcards/"

NEORG_FLASHCARDS_DEMO_ROOT="$ROOT" \
NEORG_FLASHCARDS_DEMO_DIR="$TMP/flashcards" \
XDG_STATE_HOME="$TMP/state" \
XDG_CACHE_HOME="$TMP/cache" \
XDG_DATA_HOME="$TMP/data" \
exec nvim -u "$ROOT/scripts/demo-init.lua" -i NONE -n --cmd "set shadafile=NONE"
