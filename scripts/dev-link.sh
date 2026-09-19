#!/usr/bin/env bash
#
# Points this package at a hangar checkout instead of the published tag.
#
# hangar-vapor tracks hangar's released API. While a feature is landing in
# both at once, that tag does not exist yet — this swaps in a path
# dependency so the two can be developed together, and `--undo` puts the
# URL back before you commit.
#
#   ./scripts/dev-link.sh            # use ../hangar
#   ./scripts/dev-link.sh ~/src/hangar
#   ./scripts/dev-link.sh --undo
#
set -euo pipefail
cd "$(dirname "$0")/.."

url_line='        .package(url: "https://github.com/Flight-Framework/hangar.git", from: "0.9.0"),'

if [ "${1:-}" = "--undo" ]; then
  if grep -q '.package(path:' Package.swift; then
    python3 - "$url_line" <<'PY'
import re, sys, pathlib
p = pathlib.Path("Package.swift")
p.write_text(re.sub(r'^ *\.package\(path: "[^"]*"\),$', sys.argv[1], p.read_text(), flags=re.M))
PY
    echo "Package.swift points at the published tag again."
  else
    echo "Already pointing at the published tag."
  fi
  exit 0
fi

target=${1:-../hangar}
if [ ! -f "$target/Package.swift" ]; then
  echo "No hangar checkout at $target." >&2
  exit 1
fi

python3 - "$target" <<'PY'
import re, sys, pathlib
p = pathlib.Path("Package.swift")
text = re.sub(
    r'^ *\.package\(url: "https://github\.com/Flight-Framework/hangar\.git".*$',
    f'        .package(path: "{sys.argv[1]}"),',
    p.read_text(), flags=re.M)
p.write_text(text)
PY
echo "Package.swift points at $target. Run ./scripts/dev-link.sh --undo before committing."
