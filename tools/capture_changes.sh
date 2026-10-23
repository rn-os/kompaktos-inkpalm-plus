#!/bin/zsh
# Saves a screenshot every time the InkPalm's screen changes, while the user
# pages through the UI by hand. Read-only: never taps or types.
#   usage: tools/capture_changes.sh <out_dir> [interval_s]
# Stop with: touch <out_dir>/STOP
set -u
out=${1:?out dir}; iv=${2:-2}
mkdir -p "$out"; rm -f "$out/STOP"
last=""; n=$(ls "$out"/*.png 2>/dev/null | wc -l | tr -d ' ')
while [ ! -f "$out/STOP" ]; do
  tmp="$out/.cur.png"
  adb exec-out screencap -p > "$tmp" 2>/dev/null || { sleep $iv; continue; }
  [ -s "$tmp" ] || { sleep $iv; continue; }
  h=$(shasum -a 256 "$tmp" | cut -d' ' -f1)
  if [ "$h" != "$last" ]; then
    n=$((n+1))
    app=$(adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | sed -E 's/.* ([^ /]+)\/.*/\1/; s/[^A-Za-z0-9._-]//g')
    f=$(printf '%s/%03d_%s_%s.png' "$out" $n "$(date +%H%M%S)" "${app:-unknown}")
    mv "$tmp" "$f"; last=$h; echo "saved $(basename "$f")"
  fi
  sleep $iv
done
rm -f "$out/.cur.png"; echo "stopped, $n screenshots"
