<p align="center">
    <a href="https://atomicdex.io" alt="Komodo Wallet">
        <img width="420" alt="komodo-wallet-logo_dark-theme" src="https://user-images.githubusercontent.com/24797699/252409662-eb03b0b1-5f6e-4494-9267-132eba827718.png">
    </a>
</p>

## What is Komodo Wallet?

Komodo Wallet is a secure wallet and non-custodial decentralized exchange rolled into one application. Store your coins,
trade peer-to-peer with minimal fees and never give up control over your digital assets.

This tree is an **Apple Silicon (arm64) native build**. It compiles and runs natively on Apple Silicon Macs using the
developer machine's existing Anaconda (Qt) and Homebrew (C++) environments. There is no Rosetta 2 dependency, and
Windows and Linux builds are not covered here.

Supported platform:

- macOS on Apple Silicon (arm64), e.g. macOS 14+ with Xcode Command Line Tools

## Dependencies

Dependencies are taken from the existing local environment wherever possible instead of vendored package managers
(no vcpkg, no Conan). Versions below are what this tree is currently built and tested against:

| Dependency | Version | Provider | Description | Category |
|---|---|---|---|---|
| Qt (Core, Quick, Qml, Svg, Widgets, WebEngine) | 5.15.2 (WebEngine 5.15.9) | Anaconda conda-forge (`/opt/anaconda3`) | Cross-platform application and UI framework | GUI |
| cmake | 4.4.2 | Homebrew | Build configuration | Build |
| ninja | 1.13.2 | Homebrew | Build backend | Build |
| AppleClang | 17.x | Xcode Command Line Tools | Native arm64 compiler, no Rosetta | Build |
| boost (random, system, thread) | 1.92.0 | Homebrew | Portable C++ source libraries | General Programming |
| fmt | 12.2.0 | Homebrew | Formatting library | Formatting |
| spdlog | 1.17.0 | Homebrew | Logging library | Logging |
| nlohmann_json | 3.12.0 | Homebrew | JSON for Modern C++ | Parsing |
| entt | 4.0.0 | Homebrew | Entity component system and much more | Architecture |
| date | 3.0.5 | Homebrew (`howard-hinnant-date`) | Date/time library based on `<chrono>` | Timezone/Calendar |
| cpr | 1.14.2 | Homebrew | C++ HTTP client library | HTTP |
| tl-expected | 1.3.1 | Homebrew | `std::expected` with functional-style extensions | Error handling |
| asyncplusplus | 1.2 | Homebrew | Concurrency framework | Threading |
| libsodium | 1.0.22 | Homebrew | Crypto library | Network/Crypto |
| openssl | 3.6.x | Homebrew (`openssl@3`) | TLS/SSL and crypto library | Network/Crypto |
| secp256k1 | 0.7.1 | Homebrew | Elliptic curve library | Crypto |
| libwally-core | current master | Built from source into `.deps/` by the build script | Bitcoin wallet library | Crypto |
| strong_type | v15 | CMake FetchContent | Strong typedefs for C++ | Types |
| refl-cpp | v0.12.4 | CMake FetchContent | Compile-time reflection | Reflection |
| doom/meta | master | CMake FetchContent | Metaprogramming utilities | Meta |
| Qaterial | pinned commit | CMake FetchContent | Material Design QML components | GUI |
| coins metadata | `nogeo` | `cipig/coins` (fetched at configure time) | Coin definitions and icons | Data |
| KDF backend | v2.6.0-beta universal2 executable | GitHub release asset (fetched at configure time) | Komodo DeFi Framework node binary (arm64+x86_64) | Backend |

## Build instructions

Prerequisites: Apple Silicon Mac with Anaconda (`/opt/anaconda3`, Qt 5.15) and Homebrew (`/opt/homebrew`) installed.
The script only *adds* missing Homebrew formulae (e.g. `cpr`, `tl-expected`, `asyncplusplus`); it never upgrades your
existing boost/Qt/OpenSSL installations and never touches conda.

```bash
./build_apple_silicon.sh
```

This will:

1. Verify the native arm64 toolchain (AppleClang, cmake, ninja, Anaconda Qt).
2. Build `libwally-core` from source into the local `.deps/` prefix (nothing installed system-wide).
3. Fetch the universal2 KDF backend, coin metadata, Qaterial and header-only C++ dependencies.
4. Configure with CMake + Ninja (`-DCMAKE_OSX_ARCHITECTURES=arm64`) and build `komodo-wallet`.
5. Verify the result: `Mach-O 64-bit executable arm64` linked against Qt5.

Verify the binary yourself:

```bash
file build/bin/komodo-wallet.app/Contents/MacOS/komodo-wallet  # should say arm64
otool -L build/bin/komodo-wallet.app/Contents/MacOS/komodo-wallet | grep -i qt
```

Run the app directly from the build tree:

```bash
./build/bin/komodo-wallet.app/Contents/MacOS/komodo-wallet
```

Logs are written to `~/Library/Application Support/Komodo Wallet/logs/`.

## Smoke tests

Basic end-to-end checks that the DEX can actually run (binary arch, Qt linkage, KDF backend execution,
full app launch to the event loop, clean shutdown with no stray processes):

```bash
./smoke_test.sh
```

## Refreshing the coins data

Upstream coin listings change roughly every other week (`cipig/coins`, `nogeo` branch), but the main build
fetches them only once (CMake caches the download under `build/_deps/`). To pick up new listings without a
`distclean`:

```bash
./refresh_coins.sh
./build_apple_silicon.sh && ./smoke_test.sh
```

The script validates the download (both JSON files must parse, icons must be present), backs up the current files
to `/tmp/`, installs the refresh into the same three destinations the build uses, syncs the FetchContent cache so a
later reconfigure cannot silently revert it, and touches `CMakeLists.txt` so the next build regenerates resources.
Note: a running installation keeps its existing `~/Library/Application Support/Komodo Wallet/.../coins.json` until
the app itself migrates it; the smoke test confirms the new bundle data parses.

### Is a coins refresh safe for existing wallets?

Yes. The refresh only updates bundled resources and the build cache -- it never touches
`~/Library/Application Support/Komodo Wallet/`, and the app itself is conservative about that folder:

- Wallet identity (encrypted seed, rpcpass, wallet objects, `cfg.ini`, address book) is unrelated to the coins
  pipeline and is never rewritten by a refresh.
- Enabled-coin selections live in the per-wallet `0.9.9-coins.<wallet>.json`, which the app copies from the bundle
  only when missing (new wallet) or invalid (login repair). A valid file, including the user's `active` flags, is
  kept as-is -- nothing looks reset.
- The raw `configs/coins.json` list is likewise copied from the bundle only when missing, so existing users keep
  running their current list (including any hand-added custom entries) with no surprise changes.

The trade-off: existing installs do not automatically gain the new listings. They arrive via fresh installs, app
version bumps (the data folder is versioned, so a new version starts from the fresh bundle), or the in-app reset,
which re-copies the defaults while preserving `active` flags.

## Cleaning

The ninja equivalent of `make clean` is `ninja -C build clean`, but used naively it also wipes the heavy
third-party products (notably the compiled Qaterial libraries, ~500 targets). The build script therefore offers tiers:

```bash
./build_apple_silicon.sh clean        # our code only (komodo-wallet, antara libs);
                                      # keeps Qaterial, libwally, downloads, CMakeCache
./build_apple_silicon.sh clean-all    # full `ninja clean`; keeps fetched sources,
                                      # downloads and CMakeCache
./build_apple_silicon.sh distclean    # removes build/ entirely (re-fetch + full
                                      # rebuild next time; .deps kept)
./build_apple_silicon.sh clean-wally  # removes .deps/ (libwally-core is re-fetched
                                      # and rebuilt next time)
```

Note: `clean` deletes our targets' outputs by path rather than `ninja -t clean`, because the latter follows the
dependency closure and would take Qaterial with it. Rebuilding after `clean` recompiles only our code (~2 minutes).

## Notes

- The bundled KDF backend is the v2.6.0-beta universal2 executable: the v3.0.0-beta release only ships macOS as a
  static library, not a runnable binary. See `docs/implementation_plan.md`.
- QtWebEngine runs with GPU acceleration disabled (`--disable-gpu`, software rendering). Qt 5.15 ships Chromium 87,
  whose GPU process crashes on recent macOS versions; everything else, including the wallet UI, is unaffected.

## Related projects

This Apple Silicon build is based first and foremost on the work below. If you use this software, these are the
projects to know, support and contribute upstream fixes to.

### [cipig/komodo-wallet-desktop](https://github.com/cipig/komodo-wallet-desktop) (upstream base)

The primary upstream this tree is derived from (fork of `GLEECBTC/komodo-wallet-desktop`, `nogeo` branch). It provides
the wallet/desktop source this build adapts for Apple Silicon, as well as the `cipig/coins` metadata (coin definitions
and icons) fetched at configure time. Bug fixes that are not Apple Silicon specific belong upstream here.

### [ShorelineCrypto/cheetahdex-wallet-desktop](https://github.com/ShorelineCrypto/cheetahdex-wallet-desktop)

Sibling DEX desktop wallet (CheetahDEX) built from the same Komodo Wallet codebase family. Useful as a reference for
how other communities adapt and maintain this wallet for their own networks.

### [internauta1/litecoincashdex-desktop](https://github.com/internauta1/litecoincashdex-desktop)

LitecoinCashDEX desktop wallet, another independent adaptation of this wallet codebase for the Litecoin Cash ecosystem.

## Useful links

- Komodo Wallet Documentation: https://developers.komodoplatform.com/basic-docs/atomicdex/atomicdex-tutorials/introduction-to-atomicdex.html
- Komodo Wallet Website: https://atomicdex.io/
- Komodo Wallet Discord: https://discord.gg/tvp96Gf

## Contributors / Thanks

<div align="center">
    <table>
      <tr>
        <td align="center">
            <a href="https://github.com/Milerius"><img src="https://avatars1.githubusercontent.com/u/21139416?s=400&u=12e0a99353ae95365801542b85e2fd69abd44a81&v=4" width="100px;" alt="Milerius"/><br /><sub><b>Milerius</b></sub></a><br />Lead Back-End Dev
        </td>
        <td align="center">
            <a href="https://github.com/SylEze"><img src="https://avatars1.githubusercontent.com/u/14373103?s=460&u=b303a2d2261008814800c2d7809efc6af685a460&v=4"width="100px;" alt="syl"/><br /><sub><b>syl</b></sub></a><br />Frontend and Back-End Dev
        </td>
        <td align="center">
            <a href="https://github.com/naezith"><img src="https://avatars2.githubusercontent.com/u/6732486?s=400&u=5d242e560be002ad4af597dd284eb3242ab28016&v=4" width="100px;" alt="naezith"/><br /><sub><b>naezith</b></sub></a><br />Front-End Dev
        </td>
        <td align="center">
            <a href="https://github.com/ssakone"><img src="https://avatars.githubusercontent.com/u/39985611?v=4" width="100px;" alt="ssakone"/><br /><sub><b>ssakone</b></sub></a><br />Front-End Dev
        </td>
      </tr>
      <tr>
        <td align="center">
            <a href="https://github.com/tonymorony"><img src="https://avatars3.githubusercontent.com/u/24797699?s=400&u=335984bcb93856f260ac6d139b18f0c596306e08&v=4" width="100px;" alt="Anton TonyL Lysakov"/><br /><sub><b>Anton "TonyL" Lysakov</b></sub></a><br />Lead QA / CI
        </td>
        <td align="center">
            <a href="https://github.com/ca333"><img src="https://avatars3.githubusercontent.com/u/10762374?s=60&v=4" width="100px;" alt="ca333"/><br /><sub><b>ca333</b></sub></a><br />Chief Technology Officer
        </td>
        <td align="center">
            <a href="https://github.com/smk762"><img src="https://i.imgur.com/gAD7BxX.jpg" width="100px;" alt="smk762"/><br /><sub><b>smk762</b></sub></a><br />QA Engineer
        </td>
        <td align="center">
            <a href="https://github.com/cipig"><img src="https://avatars0.githubusercontent.com/u/32116761?s=60&v=4" width="100px;" alt="cipig"/><br /><sub><b>cipig</b></sub></a><br />System Administrator
        </td>
      </tr>
      <tr>
        <td align="center">
            <a href="https://github.com/SirSevenG"><img src="https://avatars1.githubusercontent.com/u/44422309?s=60&v=4" width="100px;" alt="SirSevenG"/><br /><sub><b>SirSevenG</b></sub></a><br />QA Engineer
        </td>
        <td align="center">
            <a href="https://github.com/dathbezumniy"><img src="https://avatars2.githubusercontent.com/u/11756768?s=60&v=4" width="100px;" alt="dathbezumniy"/><br /><sub><b>dathbezumniy</b></sub></a><br />Junior QA Engineer
        </td>
        <td align="center">
            <a href="https://github.com/BloodyNora"><img src="https://avatars2.githubusercontent.com/u/4005813?s=60&v=4" width="100px;" alt="BloodyNora"/><br /><sub><b>BloodyNora</b></sub></a><br />IT allrounder
        </td>
        <td align="center">
            <a href="https://github.com/zatJUM"><img src="https://avatars3.githubusercontent.com/u/45312760?s=60&v=4" width="100px;" alt="zatJUM"/><br /><sub><b>zatJUM</b></sub></a><br />Community Dev
        </td>
      </tr>
    </table>
</div>

## License

For details please refer to our [license](https://github.com/KomodoPlatform/komodo-wallet-desktop/blob/master/LICENSE).

This is experimental alpha software - use at your own risk!

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
