#!/bin/sh
# GrabLog client — finds Minecraft logs across common launchers and uploads them.
# Served by the GrabLog worker; placeholders below are replaced at request time.
# shellcheck shell=sh
set -eu

GRABLOG_API="__GRABLOG_API__"
GRABLOG_LAUNCHER="__GRABLOG_LAUNCHER__"
GRABLOG_INSTANCE="__GRABLOG_INSTANCE__"
GRABLOG_NAME="__GRABLOG_NAME__"
GRABLOG_TYPE="__GRABLOG_TYPE__"
GRABLOG_YES="__GRABLOG_YES__"

# Portable temporary directory
_tmp="${TMPDIR:-/tmp}"
CANDIDATES_FILE="$(mktemp "$_tmp/grablog.XXXXXX")"
trap 'rm -f "$CANDIDATES_FILE"' EXIT

is_macos() {
  [ "$(uname -s 2>/dev/null || true)" = "Darwin" ]
}

is_linux() {
  [ "$(uname -s 2>/dev/null || true)" = "Linux" ]
}

# Append path if it looks like a log file
add_candidate() {
  _path="$1"
  [ -n "$_path" ] || return 0
  [ -f "$_path" ] || return 0
  [ -r "$_path" ] || return 0
  # Skip empty files
  [ -s "$_path" ] || return 0
  case "$_path" in
    *.log|*.txt|*.gz) ;;
    *) return 0 ;;
  esac
  printf '%s\n' "$_path" >>"$CANDIDATES_FILE"
}

# Recursively find latest.log / crash reports under a root (depth-limited)
scan_tree() {
  _root="$1"
  [ -d "$_root" ] || return 0
  # Prefer find when available
  if command -v find >/dev/null 2>&1; then
    # Depth-limited scan; prune heavy Minecraft dirs for speed.
    find "$_root" -maxdepth 8 \
      \( -type d \( -name cache -o -name libraries -o -name assets -o -name versions -o -name natives -o -name .git -o -name node_modules \) -prune \) -o \
      \( -type f \( -name 'latest.log' -o -name 'debug.log' -o -name 'crash-*.txt' -o -name '*.log.gz' \) -print \) 2>/dev/null \
      | while IFS= read -r _f; do
          add_candidate "$_f"
        done
  fi
}

# Known launcher / game roots per OS
discover_roots() {
  _home="${HOME:-}"
  [ -n "$_home" ] || return 0

  if is_macos; then
    printf '%s\n' \
      "$_home/Library/Application Support/minecraft" \
      "$_home/Library/Application Support/PrismLauncher" \
      "$_home/Library/Application Support/PolyMC" \
      "$_home/Library/Application Support/MultiMC" \
      "$_home/Library/Application Support/com.modrinth.Theseus" \
      "$_home/Library/Application Support/modrinth-app" \
      "$_home/Library/Application Support/ATLauncher" \
      "$_home/Library/Application Support/gdlauncher_next" \
      "$_home/Library/Application Support/gdlauncher" \
      "$_home/Documents/Curse" \
      "$_home/curseforge/minecraft" \
      "$_home/.lunarclient" \
      "$_home/Library/Application Support/minecraft-launcher"
  elif is_linux; then
    printf '%s\n' \
      "$_home/.minecraft" \
      "$_home/.local/share/PrismLauncher" \
      "$_home/.local/share/PolyMC" \
      "$_home/.local/share/MultiMC" \
      "$_home/.local/share/ATLauncher" \
      "$_home/.local/share/gdlauncher_next" \
      "$_home/.local/share/gdlauncher" \
      "$_home/.local/share/modrinth-app" \
      "$_home/.config/modrinth-app" \
      "$_home/.var/app/org.prismlauncher.PrismLauncher/data/PrismLauncher" \
      "$_home/.var/app/org.polymc.PolyMC/data/PolyMC" \
      "$_home/.var/app/org.multimc.MultiMC/data/MultiMC" \
      "$_home/.var/app/com.modrinth.ModrinthApp/data" \
      "$_home/.var/app/com.modrinth.ModrinthApp/config" \
      "$_home/curseforge/minecraft" \
      "$_home/.lunarclient" \
      "$_home/snap/minecraft-launcher/common/.minecraft"
  else
    # Generic / Git Bash on Windows-ish
    printf '%s\n' \
      "$_home/.minecraft" \
      "$_home/AppData/Roaming/.minecraft" \
      "$_home/AppData/Roaming/PrismLauncher" \
      "$_home/AppData/Roaming/PolyMC" \
      "$_home/AppData/Roaming/MultiMC" \
      "$_home/AppData/Roaming/com.modrinth.Theseus" \
      "$_home/AppData/Roaming/ATLauncher" \
      "$_home/AppData/Roaming/gdlauncher_next" \
      "$_home/curseforge/minecraft" \
      "$_home/.lunarclient"
  fi
}

launcher_matches() {
  _path="$1"
  _want="$2"
  [ -z "$_want" ] && return 0
  _lp="$(printf '%s' "$_path" | tr '[:upper:]' '[:lower:]')"
  _lw="$(printf '%s' "$_want" | tr '[:upper:]' '[:lower:]')"
  case "$_lw" in
    vanilla|minecraft|official)
      case "$_lp" in
        */.minecraft/*|*/minecraft/logs/*|*/minecraft\\logs\\*) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    prism|prismlauncher)
      case "$_lp" in *prism*) return 0 ;; *) return 1 ;; esac
      ;;
    polymc)
      case "$_lp" in *polymc*) return 0 ;; *) return 1 ;; esac
      ;;
    multimc)
      case "$_lp" in *multimc*) return 0 ;; *) return 1 ;; esac
      ;;
    modrinth|theseus)
      case "$_lp" in *modrinth*|*theseus*) return 0 ;; *) return 1 ;; esac
      ;;
    curse|curseforge)
      case "$_lp" in *curse*) return 0 ;; *) return 1 ;; esac
      ;;
    atlauncher|at)
      case "$_lp" in *atlauncher*) return 0 ;; *) return 1 ;; esac
      ;;
    lunar)
      case "$_lp" in *lunar*) return 0 ;; *) return 1 ;; esac
      ;;
    gdlauncher|gd)
      case "$_lp" in *gdlauncher*) return 0 ;; *) return 1 ;; esac
      ;;
    *)
      case "$_lp" in *"$_lw"*) return 0 ;; *) return 1 ;; esac
      ;;
  esac
}

instance_matches() {
  _path="$1"
  _want="$2"
  [ -z "$_want" ] && return 0
  _lp="$(printf '%s' "$_path" | tr '[:upper:]' '[:lower:]')"
  _lw="$(printf '%s' "$_want" | tr '[:upper:]' '[:lower:]')"
  case "$_lp" in *"$_lw"*) return 0 ;; *) return 1 ;; esac
}

name_matches() {
  _path="$1"
  _want="$2"
  [ -z "$_want" ] && return 0
  _base="$(basename "$_path")"
  _lb="$(printf '%s' "$_base" | tr '[:upper:]' '[:lower:]')"
  _lw="$(printf '%s' "$_want" | tr '[:upper:]' '[:lower:]')"
  case "$_lb" in *"$_lw"*) return 0 ;; *) return 1 ;; esac
}

type_matches() {
  _path="$1"
  _want="$2"
  _base="$(basename "$_path" | tr '[:upper:]' '[:lower:]')"
  case "$_want" in
    ""|any) return 0 ;;
    crash)
      case "$_base" in crash-*.txt|*-crash*.txt) return 0 ;; *) return 1 ;; esac
      ;;
    log|latest)
      case "$_base" in latest.log|debug.log|*.log|*.log.gz) return 0 ;; *) return 1 ;; esac
      ;;
    *) return 0 ;;
  esac
}

score_path() {
  # Higher score = more preferred. Prefer latest.log, then newer mtime.
  _path="$1"
  _base="$(basename "$_path" | tr '[:upper:]' '[:lower:]')"
  _score=0
  case "$_base" in
    latest.log) _score=1000000000000 ;;
    debug.log) _score=900000000000 ;;
    crash-*.txt) _score=800000000000 ;;
    *.log) _score=700000000000 ;;
    *.log.gz) _score=600000000000 ;;
    *) _score=500000000000 ;;
  esac
  _mtime=0
  if is_macos; then
    _mtime="$(stat -f %m "$_path" 2>/dev/null || echo 0)"
  else
    _mtime="$(stat -c %Y "$_path" 2>/dev/null || echo 0)"
  fi
  printf '%s\n' "$((_score + _mtime))"
}

human_size() {
  _bytes="$1"
  if [ "$_bytes" -lt 1024 ]; then
    printf '%s B' "$_bytes"
  elif [ "$_bytes" -lt 1048576 ]; then
    printf '%s KB' "$((_bytes / 1024))"
  else
    printf '%s MB' "$((_bytes / 1048576))"
  fi
}

printf '\n  GrabLog — Minecraft log finder\n\n' >&2

# Direct known latest.log shortcuts (fast path)
while IFS= read -r _root; do
  [ -n "$_root" ] || continue
  add_candidate "$_root/logs/latest.log"
  add_candidate "$_root/minecraft/logs/latest.log"
  scan_tree "$_root"
done <<EOF
$(discover_roots)
EOF

# Deduplicate
if [ -s "$CANDIDATES_FILE" ]; then
  sort -u "$CANDIDATES_FILE" -o "$CANDIDATES_FILE"
fi

BEST=""
BEST_SCORE=-1
COUNT=0

while IFS= read -r _cand; do
  [ -n "$_cand" ] || continue
  launcher_matches "$_cand" "$GRABLOG_LAUNCHER" || continue
  instance_matches "$_cand" "$GRABLOG_INSTANCE" || continue
  name_matches "$_cand" "$GRABLOG_NAME" || continue
  type_matches "$_cand" "$GRABLOG_TYPE" || continue
  COUNT=$((COUNT + 1))
  _sc="$(score_path "$_cand")"
  if [ "$_sc" -gt "$BEST_SCORE" ]; then
    BEST_SCORE="$_sc"
    BEST="$_cand"
  fi
done <"$CANDIDATES_FILE"

if [ -z "$BEST" ]; then
  printf 'No Minecraft log found' >&2
  [ -n "$GRABLOG_LAUNCHER" ] && printf ' (launcher=%s)' "$GRABLOG_LAUNCHER" >&2
  [ -n "$GRABLOG_INSTANCE" ] && printf ' (instance=%s)' "$GRABLOG_INSTANCE" >&2
  [ -n "$GRABLOG_NAME" ] && printf ' (name=%s)' "$GRABLOG_NAME" >&2
  printf '.\nTried common vanilla / Prism / Modrinth / CurseForge / MultiMC / Lunar paths.\n' >&2
  exit 1
fi

BYTES="$(wc -c <"$BEST" | tr -d ' ')"
MTIME_HUMAN=""
if is_macos; then
  MTIME_HUMAN="$(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$BEST" 2>/dev/null || true)"
else
  _mt="$(stat -c %Y "$BEST" 2>/dev/null || echo 0)"
  MTIME_HUMAN="$(date -d "@$_mt" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
fi

printf 'Found:  %s\n' "$BEST" >&2
printf 'Size:   %s\n' "$(human_size "$BYTES")" >&2
[ -n "$MTIME_HUMAN" ] && printf 'Modified: %s\n' "$MTIME_HUMAN" >&2
printf 'Matched %s candidate(s); selecting most recent preferred log.\n\n' "$COUNT" >&2

# Preview last few lines (skip gzip)
case "$BEST" in
  *.gz)
    printf '%s\n\n' '(compressed log — preview skipped)' >&2
    ;;
  *)
    printf '%s\n' '--- last 8 lines ---' >&2
    tail -n 8 "$BEST" 2>/dev/null >&2 || true
    printf '%s\n\n' '--------------------' >&2
    ;;
esac

if [ "$GRABLOG_YES" != "1" ] && [ "$GRABLOG_YES" != "true" ]; then
  if [ ! -t 0 ]; then
    # When piped from curl, reopen the terminal for confirmation
    if [ -r /dev/tty ]; then
      exec </dev/tty
    else
      printf 'No TTY for confirmation. Re-run with ?yes=1 to skip, or pipe from an interactive shell.\n' >&2
      exit 2
    fi
  fi
  printf 'Upload this log to GrabLog for 24 hours? [y/N] ' >&2
  read -r _ans || _ans=""
  case "$_ans" in
    y|Y|yes|YES) ;;
    *)
      printf 'Cancelled.\n' >&2
      exit 0
      ;;
  esac
fi

FNAME="$(basename "$BEST")"
printf 'Uploading...\n' >&2

# Prefer curl; fall back to wget
UPLOAD_BODY="$BEST"
CONTENT_TYPE="text/plain"
case "$BEST" in
  *.gz)
    CONTENT_TYPE="application/gzip"
    ;;
esac

if command -v curl >/dev/null 2>&1; then
  RESP="$(curl -fsS -X POST \
    -H "Content-Type: $CONTENT_TYPE" \
    -H "X-GrabLog-Filename: $FNAME" \
    --data-binary @"$UPLOAD_BODY" \
    "$GRABLOG_API/api/upload")"
elif command -v wget >/dev/null 2>&1; then
  RESP="$(wget -qO- --method=POST \
    --header="Content-Type: $CONTENT_TYPE" \
    --header="X-GrabLog-Filename: $FNAME" \
    --body-file="$UPLOAD_BODY" \
    "$GRABLOG_API/api/upload")"
else
  printf 'Need curl or wget to upload.\n' >&2
  exit 1
fi

# Extract url field without requiring jq
URL="$(printf '%s' "$RESP" | sed -n 's/.*"url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
if [ -z "$URL" ]; then
  printf 'Upload failed: %s\n' "$RESP" >&2
  exit 1
fi

printf '\nShare link (expires in 24h):\n%s\n\n' "$URL"
