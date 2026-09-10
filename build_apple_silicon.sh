#!/usr/bin/env bash
#
# build_apple_silicon.sh — native arm64 build of Komodo Wallet.
#
# Uses the user's EXISTING environment without disrupting it:
#   - Qt 5.15 + QtWebEngine  -> /opt/anaconda3 (conda-forge, arm64)
#   - cmake + ninja           -> Homebrew (/opt/homebrew)
#   - boost, fmt, spdlog, ... -> Homebrew (/opt/homebrew)
#   - AppleClang (Xcode CLT)  -> native arm64, no Rosetta 2
#   - libwally-core           -> built from source into .deps/ (local prefix,
#                                never installed system-wide)
#   - KDF binary              -> universal2 (arm64 + x86_64) via FetchContent
#
# What this script will NOT do:
#   - No `brew upgrade` (never changes your boost/Qt/ssl versions).
#   - No conda changes. Only additive `brew install` for packages that are
#     entirely missing (cpr, tl-expected, asyncplusplus, build tools).
#   - No sudo, no Rosetta.
#
# Cleaning (ninja `clean` equivalents -- see `clean_cmd` below):
#   ./build_apple_silicon.sh clean        # our code only; keeps Qaterial,
#                                         # libwally, downloads, CMakeCache
#   ./build_apple_silicon.sh clean-all    # `ninja clean`: all build products,
#                                         # keeps sources/downloads/CMakeCache
#   ./build_apple_silicon.sh distclean    # removes build/ entirely (re-fetch +
#                                         # full rebuild next time; .deps kept)
#   ./build_apple_silicon.sh clean-wally  # removes .deps/ (libwally rebuild
#                                         # next time)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 8)"

ANACONDA_PREFIX="/opt/anaconda3"
HOMEBREW_PREFIX="/opt/homebrew"
WALLY_SRC="$ROOT/.deps/libwally-core"
WALLY_PREFIX="$ROOT/.deps/wally-install"

log()  { printf '[build_apple_silicon] %s\n' "$*"; }
die()  { printf '[build_apple_silicon] ERROR: %s\n' "$*" >&2; exit 1; }

clean_cmd() {
    local tier="${1:-clean}"
    case "$tier" in
        clean)
            ## Surgical clean: delete ONLY our own targets' outputs by path.
            ## (Plain `ninja -t clean komodo-wallet` is NOT used: it follows the
            ## dependency closure and would also wipe the heavy Qaterial libs.)
            ## Preserved: build/_deps (Qaterial/QOlm libs + all fetched sources),
            ## .deps (libwally), CMakeCache/.ninja state, compile_commands.json.
            [[ -d "$BUILD_DIR" ]] || die "no build to clean (missing $BUILD_DIR)."
            log "Cleaning our targets only (Qaterial, libwally, downloads untouched)..."
            rm -rf \
                "$BUILD_DIR/bin" \
                "$BUILD_DIR/src" \
                "$BUILD_DIR/vendor" \
                "$BUILD_DIR/libantara_qrcode.a" \
                "$BUILD_DIR/antara_qrcode_autogen" \
                "$BUILD_DIR/CMakeFiles/antara_qrcode.dir" \
                "$BUILD_DIR/CMakeFiles/antara_qrcode_autogen.dir"
            ;;
        clean-all)
            [[ -f "$BUILD_DIR/build.ninja" ]] || die "no build to clean (missing $BUILD_DIR/build.ninja)."
            log "Running full ninja clean (sources/downloads/CMakeCache kept)..."
            ninja -C "$BUILD_DIR" clean
            ;;
        distclean)
            log "Removing $BUILD_DIR (next build re-fetches and rebuilds fully; .deps kept)..."
            rm -rf "$BUILD_DIR"
            ;;
        clean-wally)
            log "Removing $ROOT/.deps (libwally-core re-fetched and rebuilt next time)..."
            rm -rf "$ROOT/.deps"
            ;;
        *)
            die "unknown clean tier '$tier' (expected: clean, clean-all, distclean, clean-wally)."
            ;;
    esac
    log "Clean ($tier) done."
}

## `clean*` subcommands run before any toolchain checks.
if [[ "${1:-build}" == clean* || "${1:-build}" == "distclean" ]]; then
    clean_cmd "${1}"
    exit 0
fi

# ---------------------------------------------------------------- arch check
ARCH="$(uname -m)"
if [[ "$ARCH" != "arm64" ]]; then
    die "This script builds native Apple Silicon (arm64), but uname -m says '$ARCH'."
fi
log "Architecture: $ARCH (native, no Rosetta)"

# ------------------------------------------------- required tools (no changes)
command -v cmake >/dev/null || die "cmake not found (expected Homebrew cmake)."
command -v ninja >/dev/null || die "ninja not found (expected Homebrew ninja)."
command -v git >/dev/null || die "git not found."
[[ -x "$ANACONDA_PREFIX/bin/qmake" ]] || die "Anaconda Qt not found at $ANACONDA_PREFIX/bin/qmake."
[[ -x "$ANACONDA_PREFIX/bin/macdeployqt" ]] || die "macdeployqt not found at $ANACONDA_PREFIX/bin/macdeployqt."
log "cmake: $(cmake --version | head -1)"
log "ninja: $(ninja --version)"
log "Qt: $($ANACONDA_PREFIX/bin/qmake -query QT_VERSION) at $ANACONDA_PREFIX"
xcrun --show-sdk-path >/dev/null || die "Xcode Command Line Tools not found."

# --------------------------------- additive brew installs only (never upgrade)
# Only installs formulae that are completely missing. Existing boost/Qt/ssl
# versions are left untouched.
ensure_brew_pkg() {
    local pkg="$1"
    if brew list --versions "$pkg" >/dev/null 2>&1; then
        log "brew $pkg already installed ($(brew list --versions "$pkg"))."
    else
        log "Installing missing brew package: $pkg (additive, no upgrades)..."
        brew install "$pkg"
    fi
}
if command -v brew >/dev/null; then
    ensure_brew_pkg cpr
    ensure_brew_pkg tl-expected
    ensure_brew_pkg asyncplusplus
    ensure_brew_pkg pkg-config
    ensure_brew_pkg autoconf
    ensure_brew_pkg automake
    ensure_brew_pkg libtool
else
    die "Homebrew not found at /opt/homebrew."
fi

# ------------------------------------------------- JS submodule fallback
# atomic_defi_design/imports/bignumberjs/bignumber.js is a git submodule that
# is empty in source trees without initialized submodules, but imports/qml.qrc
# references bignumber.js/bignumber.js. Fetch a pinned copy when missing.
BIGNUMBER_DIR="$ROOT/atomic_defi_design/imports/bignumberjs/bignumber.js"
BIGNUMBER_FILE="$BIGNUMBER_DIR/bignumber.js"
if [[ ! -s "$BIGNUMBER_FILE" ]]; then
    log "Fetching pinned bignumber.js (v9.1.2) into $BIGNUMBER_DIR ..."
    mkdir -p "$BIGNUMBER_DIR"
    curl -sL -o "$BIGNUMBER_FILE" \
        "https://raw.githubusercontent.com/MikeMcl/bignumber.js/v9.1.2/bignumber.js"
    [[ -s "$BIGNUMBER_FILE" ]] || die "Failed to download bignumber.js."
fi

# ------------------------------------------------- libwally-core from source
# Installed to a LOCAL prefix inside the repo so the system/Homebrew env is
# untouched. dependencies.cmake finds it via CMAKE_PREFIX_PATH.
WALLY_LIB="$WALLY_PREFIX/lib/libwallycore.a"
if [[ ! -f "$WALLY_LIB" ]]; then
    log "Building libwally-core from source (local prefix $WALLY_PREFIX)..."
    if [[ ! -d "$WALLY_SRC/.git" ]]; then
        mkdir -p "$(dirname "$WALLY_SRC")"
        git clone --recursive https://github.com/ElementsProject/libwally-core.git "$WALLY_SRC"
    else
        git -C "$WALLY_SRC" pull --ff-only || true
        git -C "$WALLY_SRC" submodule update --init --recursive
    fi
    pushd "$WALLY_SRC" >/dev/null
    export PATH="$HOMEBREW_PREFIX/bin:$HOMEBREW_PREFIX/opt/libtool/libexec/gnubin:$PATH"
    if [[ ! -x ./configure ]]; then
        # Newer libwally-core keeps autogen.sh under tools/.
        if [[ -x ./tools/autogen.sh ]]; then
            ./tools/autogen.sh
        else
            ./autogen.sh
        fi
    fi
    ./configure --prefix="$WALLY_PREFIX" \
        --disable-shared --enable-static \
        --disable-tests --disable-swig-python --disable-swig-java \
        CFLAGS="-arch arm64 -O2" LDFLAGS="-arch arm64"
    make -j"$JOBS"
    make install
    popd >/dev/null
else
    log "libwally-core already built at $WALLY_LIB."
fi
[[ -f "$WALLY_LIB" ]] || die "libwally-core build did not produce $WALLY_LIB."
file "$WALLY_LIB" | grep -q "arm64" || log "WARNING: $WALLY_LIB is not arm64: $(file "$WALLY_LIB")"

# ------------------------------------------------- environment for the build
# Anaconda Qt first on PATH so lrelease/lupdate/macdeployqt resolve to Qt 5.15.
export PATH="$ANACONDA_PREFIX/bin:$PATH"
export QT_INSTALL_CMAKE_PATH="$ANACONDA_PREFIX"
export QT_ROOT="$ANACONDA_PREFIX"
## IMPORTANT: Homebrew FIRST. Both Homebrew and Anaconda provide Boost, fmt and
## OpenSSL; the first prefix on CMAKE_PREFIX_PATH wins for headers AND libs, so
## Homebrew-first guarantees header/lib consistency (e.g. fmt v12 headers with
## libfmt v12, not Anaconda's libfmt v9). Anaconda still provides Qt 5.15,
## which Homebrew does not link.
DESIRED_PREFIX_PATH="$HOMEBREW_PREFIX;$ANACONDA_PREFIX;$WALLY_PREFIX"
export CMAKE_PREFIX_PATH="$DESIRED_PREFIX_PATH"
export PKG_CONFIG_PATH="$HOMEBREW_PREFIX/lib/pkgconfig:$HOMEBREW_PREFIX/opt/openssl@3/lib/pkgconfig:$WALLY_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export OPENSSL_ROOT_DIR="$HOMEBREW_PREFIX/opt/openssl@3"

## Drop a stale CMakeCache when the prefix order changed (e.g. Anaconda-first
## caches from an earlier run), otherwise cached *_DIR paths would keep mixing
## headers from one provider with libs from another.
if [[ -f "$BUILD_DIR/CMakeCache.txt" ]]; then
    CACHED_PREFIX="$(grep '^CMAKE_PREFIX_PATH:' "$BUILD_DIR/CMakeCache.txt" | cut -d= -f2- || true)"
    if [[ "$CACHED_PREFIX" != "$DESIRED_PREFIX_PATH" ]]; then
        log "Prefix path changed (was: $CACHED_PREFIX) -- dropping stale CMakeCache.txt"
        rm -f "$BUILD_DIR/CMakeCache.txt"
    fi
fi

log "QT_INSTALL_CMAKE_PATH=$QT_INSTALL_CMAKE_PATH"
log "CMAKE_PREFIX_PATH=$CMAKE_PREFIX_PATH"

# ------------------------------------------------- configure
log "Configuring ($BUILD_TYPE, arm64, Ninja)..."
cmake -S "$ROOT" -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_PREFIX_PATH="$HOMEBREW_PREFIX;$ANACONDA_PREFIX;$WALLY_PREFIX" \
    -DOPENSSL_ROOT_DIR="$HOMEBREW_PREFIX/opt/openssl@3" \
    -DDEX_SHOW_COMMIT_HASH=OFF

# ------------------------------------------------- build
log "Building with $JOBS jobs..."
cmake --build "$BUILD_DIR" -j"$JOBS"

# ------------------------------------------------- verify (per docs/implementation_plan.md)
BIN="$BUILD_DIR/bin/komodo-wallet.app/Contents/MacOS/komodo-wallet"
if [[ -f "$BIN" ]]; then
    log "Verifying $BIN ..."
    file "$BIN"
    file "$BIN" | grep -q "arm64" || die "Binary is not arm64!"
    otool -L "$BIN" | grep -i qt || log "WARNING: no Qt libs in otool output."
    log "BUILD OK: $BIN (arm64)"
else
    die "Expected binary not found: $BIN"
fi
