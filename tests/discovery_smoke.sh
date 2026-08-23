#!/usr/bin/env bash
# Smoke-test GrabLog discovery scoring against a fake launcher tree.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Fake home with vanilla + prism + modrinth-ish layouts
export HOME="$TMP/home"
mkdir -p \
  "$HOME/.minecraft/logs" \
  "$HOME/.minecraft/assets" \
  "$HOME/.local/share/PrismLauncher/instances/CoolPack/minecraft/logs" \
  "$HOME/.local/share/modrinth-app/profiles/ATM/logs"

# Older vanilla log
printf 'old vanilla\n' >"$HOME/.minecraft/logs/latest.log"
touch -d '2020-01-01 00:00:00' "$HOME/.minecraft/logs/latest.log"

# Newer prism log (should win without filters)
printf 'prism latest\nline2\n' >"$HOME/.local/share/PrismLauncher/instances/CoolPack/minecraft/logs/latest.log"
touch -d '2026-01-01 12:00:00' "$HOME/.local/share/PrismLauncher/instances/CoolPack/minecraft/logs/latest.log"

# Crash report under modrinth
printf 'crash!\n' >"$HOME/.local/share/modrinth-app/profiles/ATM/logs/crash-2026-01-02.txt"
touch -d '2026-01-02 12:00:00' "$HOME/.local/share/modrinth-app/profiles/ATM/logs/crash-2026-01-02.txt"

# Heavy dir that must be pruned (should not hang / should ignore)
mkdir -p "$HOME/.minecraft/assets/objects"
printf 'nope\n' >"$HOME/.minecraft/assets/objects/latest.log"

SCRIPT="$TMP/grablog.sh"
cp "$ROOT/src/scripts/grablog.sh" "$SCRIPT"

# Stub upload endpoint by rewriting API + forcing yes, and stub curl
API_DIR="$TMP/api"
mkdir -p "$API_DIR"
cat >"$TMP/curl" <<'EOF'
#!/usr/bin/env bash
# Mimic: curl -fsS -X POST ... --data-binary @file URL
while [ $# -gt 0 ]; do
  case "$1" in
    --data-binary)
      shift
      FILE="${1#@}"
      ;;
    http*|https*)
      URL="$1"
      ;;
  esac
  shift || true
done
BYTES=$(wc -c <"$FILE" | tr -d ' ')
ID="TestSmokeId123456789012"
printf '{"id":"%s","url":"https://grablog.test/l/%s","expiresAt":1,"bytes":%s}\n' "$ID" "$ID" "$BYTES"
EOF
chmod +x "$TMP/curl"
export PATH="$TMP:$PATH"

fill() {
  local launcher="$1" instance="$2" name="$3" type="$4"
  sed \
    -e 's|__GRABLOG_API__|https://grablog.test|g' \
    -e "s|__GRABLOG_LAUNCHER__|${launcher}|g" \
    -e "s|__GRABLOG_INSTANCE__|${instance}|g" \
    -e "s|__GRABLOG_NAME__|${name}|g" \
    -e "s|__GRABLOG_TYPE__|${type}|g" \
    -e 's|__GRABLOG_YES__|1|g' \
    "$ROOT/src/scripts/grablog.sh" >"$SCRIPT"
}

assert_link() {
  local out="$1"
  printf '%s' "$out" | grep -q 'https://grablog.test/l/TestSmokeId123456789012'
}

echo "== most recent preferred log (prism latest.log) =="
fill "" "" "" ""
OUT="$(bash "$SCRIPT" 2>/dev/null)"
assert_link "$OUT"
# stderr has Found path — capture combined
COMBINED="$(bash "$SCRIPT" 2>&1)"
printf '%s\n' "$COMBINED" | grep -q 'PrismLauncher/instances/CoolPack/minecraft/logs/latest.log'

echo "== launcher=modrinth type=crash =="
fill "modrinth" "" "" "crash"
COMBINED="$(bash "$SCRIPT" 2>&1)"
printf '%s\n' "$COMBINED" | grep -q 'modrinth-app/profiles/ATM/logs/crash-2026-01-02.txt'

echo "== instance=CoolPack =="
fill "prism" "CoolPack" "" ""
COMBINED="$(bash "$SCRIPT" 2>&1)"
printf '%s\n' "$COMBINED" | grep -q 'CoolPack/minecraft/logs/latest.log'

echo "== launcher=vanilla picks .minecraft =="
fill "vanilla" "" "" ""
COMBINED="$(bash "$SCRIPT" 2>&1)"
printf '%s\n' "$COMBINED" | grep -q '.minecraft/logs/latest.log'

echo "discovery_smoke: ok"
