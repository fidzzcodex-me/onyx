#!/usr/bin/env bash
set -u

DEST="$(cd "$(dirname "$0")/.." && pwd)/assets/google_fonts"
mkdir -p "$DEST"

JB_BASE="https://github.com/JetBrains/JetBrainsMono/raw/master/fonts/ttf"
PJ_BASE="https://github.com/tokotype/PlusJakartaSans/raw/master/fonts/ttf"

fetch() {
  local url="$1"
  local out="$2"
  if [ -s "$DEST/$out" ]; then
    echo "ada: $out"
    return 0
  fi
  if curl -fsSL --retry 3 --connect-timeout 15 "$url" -o "$DEST/$out"; then
    echo "ok: $out"
  else
    rm -f "$DEST/$out"
    echo "gagal: $out"
  fi
}

for weight in Regular Medium Bold; do
  fetch "$JB_BASE/JetBrainsMono-$weight.ttf" "JetBrainsMono-$weight.ttf"
done

for weight in Regular Medium SemiBold Bold; do
  fetch "$PJ_BASE/PlusJakartaSans-$weight.ttf" "PlusJakartaSans-$weight.ttf"
done

echo "Font disimpan di $DEST. Tanpa file ini google_fonts mengunduh saat runtime."
