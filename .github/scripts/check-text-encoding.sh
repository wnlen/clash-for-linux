#!/usr/bin/env bash
set -euo pipefail

export LANG=C.UTF-8
export LC_ALL=C.UTF-8

if grep -R -n '馃\|鑺\|绛\|閫\|璇\|摝\|殌' scripts/; then
  echo "Detected mojibake text in scripts/" >&2
  exit 1
fi

python3 - <<'PY'
from pathlib import Path
import sys

bad = []
for path in Path("scripts").rglob("*.sh"):
    data = path.read_bytes()
    if data.startswith(b"\xef\xbb\xbf"):
        bad.append(f"{path}: UTF-8 BOM is not allowed")
        continue
    try:
        data.decode("utf-8")
    except UnicodeDecodeError as exc:
        bad.append(f"{path}: invalid UTF-8 ({exc})")

if bad:
    print("\n".join(bad), file=sys.stderr)
    sys.exit(1)
PY
