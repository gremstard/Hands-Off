#!/bin/zsh
# Rig every unrigged skin, 4 at a time. Usage: tools/rig_all.sh
cd "$(dirname "$0")/.."
B=/Applications/Blender.app/Contents/MacOS/Blender
rig_one() {
  n=$(basename "$1" .glb)
  RIG_SUBSURF=0 $B -b --python tools/rig_character.py -- "$1" "assets/characters/$n.glb" 2>&1 \
    | grep -E "^RIG (exported|mouth sync|arm chain)|Traceback|rror:" | sed "s/^/[$n] /"
}
i=0
for f in assets/characters/unrigged/*.glb; do
  rig_one "$f" &
  i=$((i+1))
  if (( i % 4 == 0 )); then wait; fi
done
wait
