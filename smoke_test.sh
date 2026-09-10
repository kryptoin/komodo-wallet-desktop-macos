#!/usr/bin/env bash
#
# smoke_test.sh — basic smoke tests: can the DEX actually run?
#
# Checks (each reported PASS/FAIL, non-zero exit if any fail):
#   1. App binary exists and is native arm64
#   2. App links the expected Qt5 modules (WebEngine, Quick, Core)
#   3. KDF backend binary exists and is universal2 (arm64 slice present)
#   4. KDF backend executes (version banner, exits promptly, no strays)
#   5. App launches: QML engine loads, coins config parses, application launches
#   6. App shuts down cleanly on SIGTERM with no stray processes left
#
# Requirements: a built tree (./build_apple_silicon.sh) and a logged-in macOS
# GUI session (QApplication needs a display; this is not a headless test).
#
# Env knobs:
#   SMOKE_TIMEOUT   seconds to wait for app launch markers (default 90)
#   SMOKE_KEEP_APP  set to 1 to leave the app running on success for manual
#                   inspection (shutdown check is skipped in that case)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_BIN="$ROOT/build/bin/komodo-wallet.app/Contents/MacOS/komodo-wallet"
KDF_BIN="$ROOT/assets/tools/kdf/kdf_kwd"
DATA_DIR="$HOME/Library/Application Support/Komodo Wallet"
LOGS_DIR="$DATA_DIR/logs"
TIMEOUT="${SMOKE_TIMEOUT:-90}"
KEEP_APP="${SMOKE_KEEP_APP:-0}"

PASS=0
FAIL=0
APP_PID=""

smoke_log() { printf '[smoke] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); smoke_log "PASS: $*"; }
fail() { FAIL=$((FAIL + 1)); smoke_log "FAIL: $*"; }

cleanup() {
    if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
        smoke_log "cleanup: terminating test app instance (pid $APP_PID)"
        kill -TERM "$APP_PID" 2>/dev/null || true
        for _ in $(seq 1 20); do
            kill -0 "$APP_PID" 2>/dev/null || break
            sleep 1
        done
        if kill -0 "$APP_PID" 2>/dev/null; then
            kill -KILL "$APP_PID" 2>/dev/null || true
        fi
    fi
}
trap cleanup EXIT

# ------------------------------------------------------------------ checks
check_app_binary() {
    if [[ -x "$APP_BIN" ]]; then
        pass "app binary exists ($APP_BIN)"
    else
        fail "app binary missing or not executable ($APP_BIN) -- run ./build_apple_silicon.sh first"
    fi
}

check_app_arch() {
    local info
    info="$(file -b "$APP_BIN" 2>/dev/null || true)"
    if [[ "$info" == *"arm64"* ]]; then
        pass "app binary is arm64 ($info)"
    else
        fail "app binary is not arm64 ($info)"
    fi
}

check_qt_linkage() {
    local missing=0
    for lib in libQt5Core libQt5Quick libQt5WebEngineCore libQt5WebEngineWidgets; do
        if otool -L "$APP_BIN" 2>/dev/null | grep -q "$lib"; then
            : # ok
        else
            fail "app does not link $lib"
            missing=1
        fi
    done
    [[ "$missing" -eq 0 ]] && pass "app links Qt5 Core/Quick/WebEngine"
}

check_kdf_binary() {
    if [[ ! -x "$KDF_BIN" ]]; then
        fail "kdf backend missing ($KDF_BIN)"
        return
    fi
    local info
    info="$(file -b "$KDF_BIN" 2>/dev/null || true)"
    if [[ "$info" == *"arm64"* ]]; then
        pass "kdf backend has arm64 slice ($info)"
    else
        fail "kdf backend has no arm64 slice ($info)"
    fi
}

check_kdf_runs() {
    [[ -x "$KDF_BIN" ]] || { fail "kdf run check skipped (binary missing)"; return; }
    local out
    if out="$(timeout 30 "$KDF_BIN" help 2>&1)"; then
        : # exited 0 (unexpected but fine)
    else
        : # non-zero exit is expected (no valid config) -- banner is what matters
    fi
    if [[ "$out" == *"Komodo DeFi Framework"* ]]; then
        pass "kdf backend executes (version banner printed)"
    else
        fail "kdf backend did not print version banner"
    fi
    if pgrep -f "assets/tools/kdf/kdf_kwd" >/dev/null 2>&1; then
        fail "stray kdf process left running after probe"
    else
        pass "no stray kdf process after probe"
    fi
}

# Wait up to $1 seconds for pattern $2 to appear in file $3.
wait_for_pattern() {
    local deadline=$1 pattern=$2 file=$3
    local waited=0
    while [[ "$waited" -lt "$deadline" ]]; do
        if grep -q "$pattern" "$file" 2>/dev/null; then
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done
    return 1
}

check_app_launch() {
    if [[ ! -x "$APP_BIN" ]]; then
        fail "app launch check skipped (binary missing)"
        return 1
    fi
    mkdir -p "$LOGS_DIR"
    local before
    before="$(ls "$LOGS_DIR" 2>/dev/null || true)"

    "$APP_BIN" >/tmp/kw-smoke-stdout.txt 2>&1 &
    APP_PID=$!
    smoke_log "launched app (pid $APP_PID), waiting up to ${TIMEOUT}s for launch markers..."

    # Identify this run's log file (newest .log not present before launch).
    local run_log="" waited=0
    while [[ "$waited" -lt 30 && -z "$run_log" ]]; do
        sleep 2
        waited=$((waited + 2))
        run_log="$(ls -t "$LOGS_DIR"/*.log 2>/dev/null | head -1 || true)"
        if [[ -n "$run_log" && "$before" == *$(basename "$run_log")* ]]; then
            run_log="" # pre-existing file, keep waiting for a fresh one
        fi
    done
    if [[ -z "$run_log" ]]; then
        fail "app did not create a log file within 30s"
        return 1
    fi
    smoke_log "tracking log: $run_log"

    if wait_for_pattern "$TIMEOUT" "qml engine successfully loaded" "$run_log"; then
        pass "QML engine loaded"
    else
        fail "QML engine did not load within ${TIMEOUT}s (see $run_log)"
        return 1
    fi
    if grep -q "coins size kdf: [1-9]" "$run_log" 2>/dev/null; then
        pass "coins config parsed ($(grep -o "coins size kdf: [0-9]*" "$run_log" | head -1))"
    else
        fail "coins config was not parsed (see $run_log)"
    fi
    if wait_for_pattern 30 "Launch the application" "$run_log"; then
        pass "application launched and event loop running"
    else
        fail "application did not reach launch marker (see $run_log)"
        return 1
    fi
    if grep -qiE "sigabort received|EXC_BAD_ACCESS|QtFatal|fatal error" "$run_log" 2>/dev/null; then
        fail "crash markers found in app log (see $run_log)"
        return 1
    else
        pass "no crash markers in app log"
    fi
    if kill -0 "$APP_PID" 2>/dev/null; then
        pass "app process alive after launch"
    else
        fail "app process died shortly after launch (see $run_log)"
        return 1
    fi
    return 0
}

check_app_shutdown() {
    if [[ "$KEEP_APP" == "1" ]]; then
        smoke_log "SMOKE_KEEP_APP=1 -- leaving app running (pid $APP_PID), skipping shutdown check"
        APP_PID="" # don't let the EXIT trap kill it
        return 0
    fi
    if [[ -z "$APP_PID" ]]; then
        fail "shutdown check skipped (app never launched)"
        return 1
    fi
    kill -TERM "$APP_PID" 2>/dev/null || true
    local waited=0
    while kill -0 "$APP_PID" 2>/dev/null && [[ "$waited" -lt 15 ]]; do
        sleep 1
        waited=$((waited + 1))
    done
    if kill -0 "$APP_PID" 2>/dev/null; then
        fail "app did not exit within 15s of SIGTERM"
        return 1
    else
        pass "app exited cleanly on SIGTERM"
    fi
    APP_PID=""
    sleep 2
    if pgrep -f "komodo-wallet.app" >/dev/null 2>&1 || pgrep -f "assets/tools/kdf/kdf_kwd" >/dev/null 2>&1; then
        fail "stray komodo-wallet/kdf processes left after shutdown"
    else
        pass "no stray processes after shutdown"
    fi
}

# ------------------------------------------------------------------ main
smoke_log "Komodo Wallet smoke tests (timeout ${TIMEOUT}s)"
check_app_binary
check_app_arch
check_qt_linkage
check_kdf_binary
check_kdf_runs
if check_app_launch; then
    check_app_shutdown
else
    # Launch failed; still try to report shutdown state, then summarize.
    check_app_shutdown || true
fi

smoke_log "----------------------------------------"
smoke_log "RESULT: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
exit 0
