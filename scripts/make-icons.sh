#!/bin/bash
#
# Fill AppIcon.appiconset from a single 1024x1024 master.
#
#   ./scripts/make-icons.sh [assets/AppIcon-1024.png]
#
# Uses sips, which ships with macOS, so there is nothing to install. Replace the
# master with real artwork and re-run; nothing else needs editing.
set -euo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly MASTER="${1:-$ROOT/assets/AppIcon-1024.png}"
readonly SET="$ROOT/TokenBar/Assets.xcassets/AppIcon.appiconset"

# point size, scale — macOS wants all ten, and several land on the same pixel
# size (32, 256 and 512 each appear twice) with different names.
readonly SLOTS=(
    "16 1" "16 2" "32 1" "32 2" "128 1"
    "128 2" "256 1" "256 2" "512 1" "512 2"
)

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ -f "$MASTER" ] || die "no master image at $MASTER"
[ -d "$SET" ] || die "no appiconset at $SET"

dimensions="$(sips -g pixelWidth -g pixelHeight "$MASTER" | awk '/pixel/ {print $2}' | paste -sd x -)"
[ "$dimensions" = "1024x1024" ] || die "master must be 1024x1024, got ${dimensions:-unknown}"

rm -f "$SET"/*.png
entries=""

for slot in "${SLOTS[@]}"; do
    read -r pt scale <<<"$slot"
    px=$((pt * scale))
    suffix=""
    [ "$scale" -eq 2 ] && suffix="@2x"
    name="icon_${pt}x${pt}${suffix}.png"

    sips -z "$px" "$px" "$MASTER" --out "$SET/$name" >/dev/null
    printf '  %-22s %sx%s\n' "$name" "$px" "$px"

    [ -n "$entries" ] && entries="${entries},"
    entries="${entries}
    {
      \"filename\" : \"${name}\",
      \"idiom\" : \"mac\",
      \"scale\" : \"${scale}x\",
      \"size\" : \"${pt}x${pt}\"
    }"
done

cat > "$SET/Contents.json" <<JSON
{
  "images" : [${entries}
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$SET/Contents.json" 2>/dev/null ||
    die "generated Contents.json is not valid JSON"

printf '\nwrote %s icons into %s\n' "${#SLOTS[@]}" "${SET#"$ROOT"/}"
