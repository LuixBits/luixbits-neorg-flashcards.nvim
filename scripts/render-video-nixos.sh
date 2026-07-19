#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"

if ! command -v nix >/dev/null 2>&1; then
  echo "error: nix is required" >&2
  exit 1
fi

if [[ ! -d "$repo_dir/video/node_modules" ]]; then
  echo "error: run 'npm ci --prefix video' first" >&2
  exit 1
fi

chromium_bin="$(nix shell nixpkgs#chromium -c which chromium)"

NIXPKGS_ALLOW_UNFREE=1 nix shell --impure nixpkgs#steam-run -c \
  steam-run npm run render --prefix "$repo_dir/video" -- \
  --browser-executable="$chromium_bin"
