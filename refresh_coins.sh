#!/usr/bin/env bash
#
# refresh_coins.sh — manually refresh the coins data from upstream.
#
# The coins file is updated approximately every other week in
# https://github.com/cipig/coins (branch `nogeo`). The main build script only
# fetches it once (CMake FetchContent caches it under build/_deps/), so run
# this script to pick up new listings without a full `distclean`.
#
# What it does (same three destinations as CMakeLists.txt, lines ~89-92):
#   1. Downloads the same `nogeo.zip` URL the build uses (single source of
#      truth -- if upstream changes the URL, change it in CMakeLists.txt and
#      here).
#   2. Validates the download (both JSON files must parse, icons non-empty).
#   3. Backs up the current files to /tmp/kw-coins-backup-<timestamp>/.
#   4. Installs: `coins` -> assets/tools/kdf/coins,
#      `utils/coins_config_tcp.json` -> assets/config/<version>-coins.json,
#      `icons/` -> atomic_defi_design/assets/images/coins/ (full sync).
#   5. Syncs the same files into build/_deps/jl777-coins-src/ when present, so
#      a later reconfigure reproduces these files instead of reverting to the
#      stale FetchContent cache. Stamp/subbuild bookkeeping is left untouched.
#   6. Touches CMakeLists.txt (content unchanged) so the next
#      ./build_apple_silicon.sh run reconfigures: this regenerates the asset
#      .qrc files and re-stages the bundle Resources with the new data.
#
# After running: ./build_apple_silicon.sh && ./smoke_test.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COINS_URL="https://github.com/cipig/coins/archive/nogeo.zip"

log() { printf '[refresh_coins] %s\n' "$*"; }
die() { printf '[refresh_coins] ERROR: %s\n' "$*" >&2; exit 1; }

command -v curl >/dev/null || die "curl not found."
command -v unzip >/dev/null || die "unzip not found."
command -v python3 >/dev/null || die "python3 not found (needed for JSON validation)."

# Version suffix matches CMakeLists.txt: project(... VERSION x.y.z).
PROJECT_VERSION="$(grep -m1 -oE 'VERSION [0-9]+\.[0-9]+\.[0-9]+' "$ROOT/CMakeLists.txt" | awk '{print $2}')"
[[ -n "$PROJECT_VERSION" ]] || die "could not parse project VERSION from CMakeLists.txt."
log "Project version: $PROJECT_VERSION"

COINS_DST="$ROOT/assets/tools/kdf/coins"
CONFIG_DST="$ROOT/assets/config/${PROJECT_VERSION}-coins.json"
ICONS_DST="$ROOT/atomic_defi_design/assets/images/coins"
FETCHCONTENT_SRC="$ROOT/build/_deps/jl777-coins-src"

TMPDIR="$(mktemp -d /tmp/kw-coins-refresh.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

# ------------------------------------------------------------ download
log "Downloading $COINS_URL ..."
curl -sSL --fail -o "$TMPDIR/nogeo.zip" "$COINS_URL" || die "download failed."
[[ -s "$TMPDIR/nogeo.zip" ]] || die "downloaded zip is empty."
unzip -q -o "$TMPDIR/nogeo.zip" -d "$TMPDIR/unzipped" || die "unzip failed."
SRC_DIR="$(find "$TMPDIR/unzipped" -maxdepth 1 -type d -name 'coins-*' | head -1)"
[[ -n "$SRC_DIR" ]] || die "unexpected zip layout (no coins-* top directory)."

# ------------------------------------------------------------ validate
log "Validating download..."
[[ -f "$SRC_DIR/coins" ]] || die "zip has no top-level 'coins' file."
[[ -f "$SRC_DIR/utils/coins_config_tcp.json" ]] || die "zip has no utils/coins_config_tcp.json."
[[ -d "$SRC_DIR/icons" ]] || die "zip has no icons/ directory."
python3 - "$SRC_DIR/coins" "$SRC_DIR/utils/coins_config_tcp.json" <<'EOF' || die "JSON validation failed."
import json, sys
coins = json.load(open(sys.argv[1]))
assert isinstance(coins, list) and len(coins) > 0, "coins file must be a non-empty JSON list"
cfg = json.load(open(sys.argv[2]))
assert isinstance(cfg, dict) and len(cfg) > 0, "coins config must be a non-empty JSON object"
print(f"coins entries: {len(coins)}, config entries: {len(cfg)}")
EOF
ICON_COUNT="$(find "$SRC_DIR/icons" -type f | wc -l | tr -d ' ')"
[[ "$ICON_COUNT" -gt 0 ]] || die "icons/ directory is empty."
log "icons files: $ICON_COUNT"

# ------------------------------------------------------------ backup
BACKUP="/tmp/kw-coins-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
[[ -f "$COINS_DST" ]] && cp "$COINS_DST" "$BACKUP/coins"
[[ -f "$CONFIG_DST" ]] && cp "$CONFIG_DST" "$BACKUP/${PROJECT_VERSION}-coins.json"
log "Current files backed up to $BACKUP"

# ------------------------------------------------------------ install
log "Installing refreshed files..."
cp "$SRC_DIR/coins" "$COINS_DST"
cp "$SRC_DIR/utils/coins_config_tcp.json" "$CONFIG_DST"
rm -rf "$ICONS_DST"
mkdir -p "$ICONS_DST"
cp -R "$SRC_DIR/icons/." "$ICONS_DST/"

# ------------------------------------------------------------ keep FetchContent cache consistent
if [[ -d "$FETCHCONTENT_SRC" ]]; then
    log "Syncing build/_deps/jl777-coins-src so reconfigure cannot revert this refresh..."
    cp "$SRC_DIR/coins" "$FETCHCONTENT_SRC/coins"
    cp "$SRC_DIR/utils/coins_config_tcp.json" "$FETCHCONTENT_SRC/utils/coins_config_tcp.json"
    rm -rf "$FETCHCONTENT_SRC/icons"
    mkdir -p "$FETCHCONTENT_SRC/icons"
    cp -R "$SRC_DIR/icons/." "$FETCHCONTENT_SRC/icons/"
else
    log "No build/_deps/jl777-coins-src present (fresh build will fetch current upstream anyway)."
fi

# ------------------------------------------------------------ trigger reconfigure on next build
touch "$ROOT/CMakeLists.txt"

log "Refresh complete."
log "Next steps: ./build_apple_silicon.sh && ./smoke_test.sh"
log "(The smoke test asserts the coins config parses and reports its entry count.)"
