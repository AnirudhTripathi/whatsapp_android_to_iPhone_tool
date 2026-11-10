#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Offline test suite (synthetic data only). Run after scripts/00-setup.sh.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PY="$REPO/.venv/bin/python"; [[ -x "$PY" ]] || PY=python3
for f in "$REPO"/scripts/*.sh "$REPO"/tools/post_lid.sh; do /bin/bash -n "$f"; done
echo "shell syntax: ok"
"$PY" -I -m py_compile "$REPO"/tools/*.py "$REPO"/third_party/sticker_inject/sticker_inject.py
echo "python syntax: ok"
cd "$REPO/tests" && "$PY" -m unittest -v test_offline 2>&1 | tail -25
