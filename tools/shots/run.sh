#!/bin/sh
# usage: tools/shots/run.sh <godot> <target> <out.png> [WxH]
GODOT="$1"; TARGET="$2"; OUT="$3"; RES="${4:-1920x1080}"
xvfb-run -a -s "-screen 0 ${RES}x24" "$GODOT" --path "$(dirname "$0")/../.." --rendering-method gl_compatibility --rendering-driver opengl3 --resolution "$RES" tools/shots/shot.tscn -- --target="$TARGET" --out="$OUT" 2>&1 | grep -E "SHOT|SCRIPT ERROR|Parse Error"
