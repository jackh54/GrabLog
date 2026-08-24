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
GRABLOG_SERVER="__GRABLOG_SERVER__"
GRABLOG_YES="__GRABLOG_YES__"

_tmp="${TMPDIR:-/tmp}"
CANDIDATES_FILE="$(mktemp "$_tmp/grablog.XXXXXX")"
UPLOAD_RESP="$(mktemp "$_tmp/grablog-up.XXXXXX")"
trap 'rm -f "$CANDIDATES_FILE" "$UPLOAD_RESP"' EXIT

# --- UI helpers -------------------------------------------------------------

USE_COLOR=0
if [ -t 2 ] && [ "${NO_COLOR:-}" = "" ] && [ "${TERM:-}" != "dumb" ]; then
  if command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    USE_COLOR=1
  fi
fi

if [ "$USE_COLOR" -eq 1 ]; then
  C_RESET="$(printf '\033[0m')"
  C_DIM="$(printf '\033[2m')"
  C_BOLD="$(printf '\033[1m')"
  C_GREEN="$(printf '\033[32m')"
  C_CYAN="$(printf '\033[36m')"
  C_YELLOW="$(printf '\033[33m')"
  C_RED="$(printf '\033[31m')"
else
  C_RESET="" C_DIM="" C_BOLD="" C_GREEN="" C_CYAN="" C_YELLOW="" C_RED=""
fi

log() { printf '%s\n' "$*" >&2; }
log_step() { printf '%s›%s %s\n' "$C_CYAN" "$C_RESET" "$*" >&2; }
log_ok() { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*" >&2; }
log_warn() { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_err() { printf '%s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
log_dim() { printf '%s%s%s\n' "$C_DIM" "$*" "$C_RESET" >&2; }

print_banner() {
  log ""
  log "${C_BOLD}${C_GREEN}  GrabLog${C_RESET}  ${C_DIM}minecraft log share${C_RESET}"
  log "${C_DIM}  ────────────────────────────${C_RESET}"
  log_dim "  $GRABLOG_API"
  log ""
}

# --- discovery --------------------------------------------------------------

is_macos() {
  [ "$(uname -s 2>/dev/null || true)" = "Darwin" ]
}

add_candidate() {
  _path="$1"
  [ -n "$_path" ] || return 0
  [ -f "$_path" ] || return 0
  [ -r "$_path" ] || return 0
  [ -s "$_path" ] || return 0
  case "$_path" in
    *.log|*.txt|*.gz) ;;
    *) return 0 ;;
  esac
  printf '%s\n' "$_path" >>"$CANDIDATES_FILE"
}

scan_tree() {
  _root="$1"
  [ -d "$_root" ] || return 0
  if command -v find >/dev/null 2>&1; then
    find "$_root" -maxdepth 8 \
      \( -type d \( -name cache -o -name libraries -o -name assets -o -name versions -o -name natives -o -name .git -o -name node_modules \) -prune \) -o \
      \( -type f \( -name 'latest.log' -o -name 'debug.log' -o -name 'crash-*.txt' -o -name '*.log.gz' \) -print \) 2>/dev/null \
      | while IFS= read -r _f; do
          add_candidate "$_f"
        done
  fi
}

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
  elif [ "$(uname -s 2>/dev/null || true)" = "Linux" ]; then
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

# Match server hostname/IP inside log contents (Connecting to …, etc.)
server_matches() {
  _path="$1"
  _want="$2"
  [ -z "$_want" ] && return 0
  case "$_path" in
    *.gz)
      if command -v gzip >/dev/null 2>&1; then
        gzip -cd "$_path" 2>/dev/null | grep -F -i -q -- "$_want"
      else
        return 1
      fi
      ;;
    *)
      grep -F -i -q -- "$_want" "$_path" 2>/dev/null
      ;;
  esac
}

score_path() {
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
  # Prefer logs that mention a recent connection when filtering by server
  if [ -n "$GRABLOG_SERVER" ]; then
    case "$_path" in
      *.gz) ;;
      *)
        if tail -n 200 "$_path" 2>/dev/null | grep -F -i -q -- "$GRABLOG_SERVER"; then
          _score=$((_score + 50000000000))
        fi
        ;;
    esac
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

# --- main -------------------------------------------------------------------

print_banner

FILTERS=""
[ -n "$GRABLOG_LAUNCHER" ] && FILTERS="$FILTERS launcher=$GRABLOG_LAUNCHER"
[ -n "$GRABLOG_INSTANCE" ] && FILTERS="$FILTERS instance=$GRABLOG_INSTANCE"
[ -n "$GRABLOG_NAME" ] && FILTERS="$FILTERS name=$GRABLOG_NAME"
[ -n "$GRABLOG_TYPE" ] && FILTERS="$FILTERS type=$GRABLOG_TYPE"
[ -n "$GRABLOG_SERVER" ] && FILTERS="$FILTERS server=$GRABLOG_SERVER"
if [ -n "$FILTERS" ]; then
  log_dim "filters:${FILTERS}"
else
  log_dim "auto: newest log across all launchers"
fi

log_step "Scanning launcher folders…"

while IFS= read -r _root; do
  [ -n "$_root" ] || continue
  add_candidate "$_root/logs/latest.log"
  add_candidate "$_root/minecraft/logs/latest.log"
  scan_tree "$_root"
done <<EOF
$(discover_roots)
EOF

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
  server_matches "$_cand" "$GRABLOG_SERVER" || continue
  COUNT=$((COUNT + 1))
  _sc="$(score_path "$_cand")"
  if [ "$_sc" -gt "$BEST_SCORE" ]; then
    BEST_SCORE="$_sc"
    BEST="$_cand"
  fi
done <"$CANDIDATES_FILE"

if [ -z "$BEST" ]; then
  log_err "No Minecraft log found${FILTERS}."
  log_dim "Tried vanilla / Prism / Modrinth / CurseForge / MultiMC / Lunar paths."
  exit 1
fi

BYTES="$(wc -c <"$BEST" | tr -d ' ')"
MTIME_HUMAN=""
if is_macos; then
  MTIME_HUMAN="$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$BEST" 2>/dev/null || true)"
else
  _mt="$(stat -c %Y "$BEST" 2>/dev/null || echo 0)"
  MTIME_HUMAN="$(date -d "@$_mt" '+%Y-%m-%d %H:%M' 2>/dev/null || true)"
fi

log_ok "Found ${C_BOLD}$(basename "$BEST")${C_RESET}  ${C_DIM}($(human_size "$BYTES")${MTIME_HUMAN:+ · $MTIME_HUMAN})${C_RESET}"
log_dim "  $BEST"
log_dim "  $COUNT candidate(s) matched"

case "$BEST" in
  *.gz)
    log_dim "  (compressed — preview skipped)"
    ;;
  *)
    log ""
    log_dim "  last lines"
    tail -n 6 "$BEST" 2>/dev/null | while IFS= read -r _line || [ -n "$_line" ]; do
      printf '  %s│%s %s\n' "$C_DIM" "$C_RESET" "$_line" >&2
    done || true
    ;;
esac
log ""

if [ "$GRABLOG_YES" != "1" ] && [ "$GRABLOG_YES" != "true" ]; then
  if [ ! -t 0 ]; then
    if [ -r /dev/tty ]; then
      exec </dev/tty
    else
      log_err "No TTY for confirmation. Re-run with ?yes=1 to skip."
      exit 2
    fi
  fi
  printf '%s›%s Upload for 24 hours? [y/N] ' "$C_CYAN" "$C_RESET" >&2
  read -r _ans || _ans=""
  case "$_ans" in
    y|Y|yes|YES) ;;
    *)
      log_warn "Cancelled."
      exit 0
      ;;
  esac
fi

FNAME="$(basename "$BEST")"
UPLOAD_FILE="$BEST"
CONTENT_TYPE="text/plain; charset=utf-8"
CONTENT_ENCODING=""
CLEANUP_UPLOAD=""

# Refuse absurd raw sizes before we spend time compressing/uploading.
if [ "$BYTES" -gt 104857600 ]; then
  log_err "Log is $(human_size "$BYTES") — too large (limit 100 MB)."
  exit 1
fi

# Compress plain logs — Minecraft logs shrink a lot and avoid slow uploads.
case "$BEST" in
  *.gz)
    CONTENT_TYPE="application/gzip"
    CONTENT_ENCODING="gzip"
    ;;
  *)
    if command -v gzip >/dev/null 2>&1; then
      GZ_BASE="$(mktemp "$_tmp/grablog.XXXXXX")"
      GZ_TMP="${GZ_BASE}.gz"
      rm -f "$GZ_BASE"
      log_step "Compressing…"
      if gzip -c -n "$BEST" >"$GZ_TMP"; then
        UPLOAD_FILE="$GZ_TMP"
        FNAME="${FNAME}.gz"
        CONTENT_TYPE="application/gzip"
        CONTENT_ENCODING="gzip"
        CLEANUP_UPLOAD="$GZ_TMP"
        GZ_BYTES="$(wc -c <"$GZ_TMP" | tr -d ' ')"
        log_dim "  $(human_size "$BYTES") → $(human_size "$GZ_BYTES")"
      else
        rm -f "$GZ_TMP"
      fi
    fi
    ;;
esac

UP_BYTES="$(wc -c <"$UPLOAD_FILE" | tr -d ' ')"
if [ "$UP_BYTES" -gt 10485760 ]; then
  [ -n "$CLEANUP_UPLOAD" ] && rm -f "$CLEANUP_UPLOAD"
  log_err "Upload payload is $(human_size "$UP_BYTES") — over the 10 MB limit."
  exit 1
fi

UPLOAD_URL="${GRABLOG_API}/api/upload"
log_step "Uploading $(human_size "$UP_BYTES")…"
log_dim "  $GRABLOG_API"
: >"$UPLOAD_RESP"
CURL_ERR=1

do_curl_upload() {
  if [ -n "$CONTENT_ENCODING" ]; then
    command curl -sS -f \
      --connect-timeout 8 \
      --max-time 45 \
      -X POST \
      -H "Content-Type: $CONTENT_TYPE" \
      -H "X-GrabLog-Encoding: $CONTENT_ENCODING" \
      -H "X-GrabLog-Filename: $FNAME" \
      -H "Expect:" \
      --data-binary @"$UPLOAD_FILE" \
      -o "$UPLOAD_RESP" \
      "$UPLOAD_URL"
  else
    command curl -sS -f \
      --connect-timeout 8 \
      --max-time 45 \
      -X POST \
      -H "Content-Type: $CONTENT_TYPE" \
      -H "X-GrabLog-Filename: $FNAME" \
      -H "Expect:" \
      --data-binary @"$UPLOAD_FILE" \
      -o "$UPLOAD_RESP" \
      "$UPLOAD_URL"
  fi
}

do_python_upload() {
  command python3 - "$UPLOAD_URL" "$UPLOAD_FILE" "$CONTENT_TYPE" "$CONTENT_ENCODING" "$FNAME" "$UPLOAD_RESP" <<'PY'
import sys, urllib.request, urllib.error
url, path, ctype, enc, fname, out = sys.argv[1:7]
data = open(path, "rb").read()
req = urllib.request.Request(url, data=data, method="POST")
req.add_header("Content-Type", ctype)
req.add_header("X-GrabLog-Filename", fname)
if enc:
    req.add_header("X-GrabLog-Encoding", enc)
try:
    with urllib.request.urlopen(req, timeout=45) as resp:
        body = resp.read()
    open(out, "wb").write(body)
except urllib.error.HTTPError as e:
    open(out, "wb").write(e.read() or b"")
    raise SystemExit(1)
PY
}

if command -v curl >/dev/null 2>&1; then
  if do_curl_upload; then
    CURL_ERR=0
  else
    CURL_ERR=$?
    log_warn "curl upload failed — trying python fallback…"
  fi
fi

if [ "$CURL_ERR" -ne 0 ] && command -v python3 >/dev/null 2>&1; then
  if do_python_upload; then
    CURL_ERR=0
  else
    CURL_ERR=$?
  fi
elif [ "$CURL_ERR" -ne 0 ] && command -v wget >/dev/null 2>&1; then
  if [ -n "$CONTENT_ENCODING" ]; then
    if wget -q -O "$UPLOAD_RESP" --timeout=45 --tries=1 \
      --method=POST \
      --header="Content-Type: $CONTENT_TYPE" \
      --header="X-GrabLog-Encoding: $CONTENT_ENCODING" \
      --header="X-GrabLog-Filename: $FNAME" \
      --body-file="$UPLOAD_FILE" \
      "$UPLOAD_URL"
    then
      CURL_ERR=0
    else
      CURL_ERR=$?
    fi
  else
    if wget -q -O "$UPLOAD_RESP" --timeout=45 --tries=1 \
      --method=POST \
      --header="Content-Type: $CONTENT_TYPE" \
      --header="X-GrabLog-Filename: $FNAME" \
      --body-file="$UPLOAD_FILE" \
      "$UPLOAD_URL"
    then
      CURL_ERR=0
    else
      CURL_ERR=$?
    fi
  fi
fi

[ -n "$CLEANUP_UPLOAD" ] && rm -f "$CLEANUP_UPLOAD"

RESP="$(cat "$UPLOAD_RESP" 2>/dev/null || true)"
if [ "$CURL_ERR" -ne 0 ]; then
  log_err "Upload failed (exit $CURL_ERR)."
  [ -n "$RESP" ] && log_dim "  $RESP"
  log_dim "  endpoint: $UPLOAD_URL"
  exit 1
fi

URL="$(printf '%s' "$RESP" | sed -n 's/.*"url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
if [ -z "$URL" ]; then
  log_err "Upload failed: unexpected response."
  log_dim "  $RESP"
  exit 1
fi

log ""
log_ok "Share link ${C_DIM}(expires in 24h)${C_RESET}"
printf '\n  %s%s%s\n\n' "$C_BOLD" "$URL" "$C_RESET"
