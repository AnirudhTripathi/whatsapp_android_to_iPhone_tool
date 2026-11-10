#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# One-time setup on a Mac: tools, Python environment, compiled helpers, self-test.
# Needs: macOS 12+, Xcode Command Line Tools (NOT full Xcode), Homebrew, internet.
# Python 3.11+ is installed with Homebrew if python3 is older. Python packages: requirements.txt.
# usage: scripts/00-setup.sh [--no-ocr]     (--no-ocr skips Tesseract, only needed for 02-decrypt.sh --screenshot)
source "$(dirname "$0")/lib.sh"

OCR=1; [[ "${1:-}" == "--no-ocr" ]] && OCR=0

say "Checking the Mac"
[[ "$(uname)" == "Darwin" ]] || die "macOS only (watoi and the helpers use Apple's Core Data and PDFKit)"
xcode-select -p >/dev/null 2>&1 || die "Install the Xcode Command Line Tools first:  xcode-select --install"
ok "Command Line Tools: $(xcode-select -p)"
command -v brew >/dev/null || die "Install Homebrew first: https://brew.sh"
ok "Homebrew present"

say "Installing command-line tools with Homebrew"
brew list libimobiledevice >/dev/null 2>&1 || brew install libimobiledevice
brew list ideviceinstaller >/dev/null 2>&1 || brew install ideviceinstaller
command -v adb >/dev/null 2>&1 || brew install --cask android-platform-tools
if [[ $OCR == 1 ]]; then brew list tesseract >/dev/null 2>&1 || brew install tesseract; fi
for t in adb idevicebackup2 ideviceinfo idevicepair idevice_id sqlite3; do need "$t"; ok "$t"; done

say "Python 3.11+ (needed by wa-crypt-tools)"
py_ok() { "$1" -c 'import sys; sys.exit(sys.version_info < (3, 11))' >/dev/null 2>&1; }
SYS_PY="$(command -v python3 || true)"
if [[ -z "$SYS_PY" ]] || ! py_ok "$SYS_PY"; then   # the Command Line Tools' python3 is 3.9
  SYS_PY="$(brew --prefix)/bin/python3"
  [[ -x "$SYS_PY" ]] || brew install python
  py_ok "$SYS_PY" || die "Python 3.11 or newer is needed. Install it with:  brew install python"
fi
ok "Python $("$SYS_PY" -c 'import platform; print(platform.python_version())')  ($SYS_PY)"

say "Python environment ($VENV)"
[[ -x "$PY" ]] && py_ok "$PY" || "$SYS_PY" -m venv --clear "$VENV"   # (re)create if missing or too old
"$PY" -m pip install -q --upgrade pip
"$PY" -m pip install -q -r "$REPO/requirements.txt"
ok "wa-crypt-tools $("$PY" -m pip show wa-crypt-tools | awk '/^Version/{print $2}'), Pillow $("$PY" -m pip show pillow | awk '/^Version/{print $2}')"

say "Building helpers into $BUILD"
mkdir -p "$BUILD"
clang -fobjc-arc -O2 -mmacosx-version-min=12.0 -framework Foundation -framework CoreData -lsqlite3 \
      "$REPO/third_party/watoi/main.m" -o "$BUILD/watoi"
ok "watoi (Core Data importer)"
xcrun swiftc -O "$REPO/tools/extract_model.swift" -o "$BUILD/extract_model"
ok "extract_model (recovers WhatsApp's data model from its own database)"
xcrun swiftc -O "$REPO/tools/pdfthumb.swift" -o "$BUILD/pdfthumb"
ok "pdfthumb (PDF page count + page-1 thumbnail)"

say "Self-test"
bash "$REPO/tests/run_tests.sh"
say "Setup complete. Next: scripts/01-pull-android.sh"
