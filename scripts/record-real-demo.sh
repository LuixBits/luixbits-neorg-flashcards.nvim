#!/usr/bin/env sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
APP_ID="luixbits-flashcards-real-demo"
TITLE="LuixBits Flashcards Demo"
OUTPUT="${1:-DP-2}"
RAW="$TMP/review-real.mp4"
DEST="$ROOT/docs/demo/review.gif"

cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

mkdir -p "$TMP/flashcards" "$ROOT/docs/demo"
cat > "$TMP/flashcards/cards.norg" <<'CARDS'
* Japanese Flashcards Demo

CARDS

niri_output="$(niri msg -j outputs)"
output_geometry="$(printf '%s' "$niri_output" | jq -r --arg output "$OUTPUT" '.[$output].logical | "\(.x),\(.y) \(.width)x\(.height)"')"
if [ -z "$output_geometry" ] || [ "$output_geometry" = "null,null nullxnull" ]; then
  echo "Could not determine output geometry for $OUTPUT" >&2
  exit 1
fi

region="$(printf '%s' "$niri_output" | jq -r --arg output "$OUTPUT" '.[$output].logical | "\(.x + (.width / 2 | floor)),\(.y + 40) \((.width / 2 | floor))x\(.height - 120)"')"

niri msg action focus-monitor "$OUTPUT" >/dev/null
niri msg action focus-column-last >/dev/null || true

kitty \
  --class "$APP_ID" \
  --title "$TITLE" \
  --override remember_window_size=no \
  --override initial_window_width=140c \
  --override initial_window_height=40c \
  --detach \
  bash -lc "cd '$ROOT' && sleep 1.4 && exec nvim '$TMP/flashcards/cards.norg' -S '$ROOT/scripts/real-demo.lua'"

window_id=""
for _ in $(seq 1 80); do
  window_id="$(niri msg -j windows | jq -r --arg app "$APP_ID" '.[] | select(.app_id == $app) | .id' | head -n 1)"
  if [ -n "$window_id" ]; then
    break
  fi
  sleep 0.1
done

if [ -z "$window_id" ]; then
  echo "Could not find demo window with app id $APP_ID" >&2
  exit 1
fi

niri msg action move-window-to-monitor --id "$window_id" "$OUTPUT" >/dev/null
niri msg action focus-window --id "$window_id" >/dev/null
sleep 0.4

set +e
timeout 36 wf-recorder -g "$region" -r 30 -f "$RAW"
record_status=$?
set -e

if [ "$record_status" -ne 0 ] && [ "$record_status" -ne 124 ]; then
  exit "$record_status"
fi

ffmpeg -y -i "$RAW" \
  -vf "fps=8,scale=1200:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3" \
  -loop 0 \
  "$DEST"

echo "$DEST"
