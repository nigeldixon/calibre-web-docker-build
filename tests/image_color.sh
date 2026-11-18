#!/bin/sh
# Assert the shipped default kcc-c2e options keep a colour comic in colour.
#
# KCC's -p KoLC profile sets the Kobo Libra Colour geometry but still
# converts pages to grayscale; only --forcecolor keeps colour. This converts
# a genuinely coloured comic using the watcher's shipped defaults and fails
# if the output contains no colour image, guarding against a regression to
# grayscale output.
# Usage: image_color.sh <image>
set -eu

image="${1:?usage: image_color.sh <image>}"
engine="${CONTAINER_ENGINE:-docker}"
repo="$(cd "$(dirname "$0")/.." && pwd)"
fixtures="$repo/tests/fixtures"

# Read the shipped default straight from the watcher, so this guards what
# users actually get rather than a copy pasted into the test.
default_opts="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import kcc_watch; print(kcc_watch.DEFAULTS["options"])' "$repo/scripts")"
echo "shipped default options: $default_opts"

"$engine" run -i --rm -e KCC_WATCH_ENABLED=false -e KCC_OPTS="$default_opts" "$image" sh -eu -c '
cat > /tmp/color.cbz
mkdir -p /tmp/out
kcc-c2e $KCC_OPTS -o /tmp/out /tmp/color.cbz
test -n "$(ls -A /tmp/out)"
/opt/kcc_venv/bin/python3 - <<PY
import zipfile, io, glob
from PIL import Image
epub = glob.glob("/tmp/out/*.kepub.epub")[0]
z = zipfile.ZipFile(epub)
modes = [Image.open(io.BytesIO(z.read(n))).mode
         for n in z.namelist() if n.lower().endswith((".jpg", ".jpeg", ".png"))]
print("image modes:", modes)
assert any(m == "RGB" for m in modes), "colour comic flattened to grayscale: %s" % modes
print("colour preserved OK")
PY
' < "$fixtures/sample-color.cbz"

echo "colour test passed for $image"
