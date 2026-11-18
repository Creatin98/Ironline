#!/bin/sh
# Renders all menu preview images (maps + classes) into assets/ui/previews/.
# usage: tools/shots/generate_previews.sh <godot>   (needs xvfb + a GL driver; see shot.gd)
GODOT="$1"
cd "$(dirname "$0")/../.." || exit 1
OUT=assets/ui/previews
mkdir -p "$OUT"
for m in harbor frontier suburb mesa test_arena; do
  tools/shots/run.sh "$GODOT" "map_$m" "$(pwd)/$OUT/map_$m.png" 800x450
done
for c in assault smg shotgun sniper; do
  tools/shots/run.sh "$GODOT" "class_$c" "$(pwd)/$OUT/class_$c.png" 800x450
done
