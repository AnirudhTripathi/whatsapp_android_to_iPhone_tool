# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Shared settings and helpers. Sourced by every script in scripts/.
#
# All personal data lives in $WA_WORK (default ~/WA-Transfer), OUTSIDE this repository, so it can never be
# committed by accident. Override with:  export WA_WORK=/Volumes/SSD/WA-Transfer
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${WA_WORK:-$HOME/WA-Transfer}"
BUILD="$REPO/build"                       # compiled helpers: watoi, extract_model, pdfthumb
VENV="$REPO/.venv"
PY="$VENV/bin/python"
ANDROID="$WORK/android"                   # msgstore.db.crypt15, msgstore.db, msgstore_lid.db, Media/
BACKUPS="$WORK/backups"                   # idevicebackup2 writes $BACKUPS/<UDID>/
ORIGINALS="$WORK/originals"               # untouched copies of ChatStorage.sqlite + Manifest.db (for undo)
RUN="$WORK/run"                           # converted ChatStorage.sqlite, logs, thumbnails
CALIB="$WORK/calibration"

DOMAIN="AppDomainGroup-group.net.whatsapp.WhatsApp.shared"
CHATSTORAGE_ID="7c7fba66680ef796b916b067077cc246adacf01d"   # sha1("$DOMAIN-ChatStorage.sqlite"), same on every iPhone
WA_ANDROID_DIR="/sdcard/Android/media/com.whatsapp/WhatsApp"

say()  { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\n\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "'$1' not found. Run scripts/00-setup.sh first."; }
confirm() {  # confirm "question" "WORD"  -> user must type WORD
  local ans; printf '\n\033[1m%s\033[0m\nType %s to continue: ' "$1" "$2"; read -r ans
  [[ "$ans" == "$2" ]] || die "cancelled"
}

mkdir -p "$WORK"; chmod 700 "$WORK"

# Exactly one iPhone, or WA_UDID set.
udid() {
  if [[ -n "${WA_UDID:-}" ]]; then echo "$WA_UDID"; return; fi
  need idevice_id
  local ids n; ids="$(idevice_id -l 2>/dev/null || true)"; n="$(printf '%s' "$ids" | grep -c . || true)"
  [[ "$n" == "1" ]] || die "connect exactly one iPhone by USB, unlocked and trusted (found $n), or set WA_UDID"
  echo "$ids"
}

# The backup folder of the iPhone. Works offline when exactly one backup exists.
backup_udid_dir() {
  local d n
  if [[ -n "${WA_UDID:-}" ]]; then echo "$BACKUPS/$WA_UDID"; return; fi
  n="$(find "$BACKUPS" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | grep -c . || true)"
  if [[ "$n" == "1" ]]; then find "$BACKUPS" -mindepth 1 -maxdepth 1 -type d; return; fi
  d="$BACKUPS/$(udid)"; echo "$d"
}

latest_originals() { find "$ORIGINALS" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -1; }

zmax() { sqlite3 "$1" "select Z_MAX from Z_PRIMARYKEY where Z_NAME='$2'"; }
