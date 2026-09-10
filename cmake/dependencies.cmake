##! Dependancies
include(FetchContent)

if (WIN32)
    find_package(ZLIB)
    set(BUILD_SHARED_LIBS OFF CACHE BOOL "Override option" FORCE)
endif ()

## Homebrew installs asyncplusplus's CMake config into <prefix>/cmake/
## (not lib/cmake or share/cmake), which is outside CMake's default search
## paths -- hint it directly when using the Apple Silicon Homebrew layout.
if (APPLE AND NOT Async++_DIR AND EXISTS "/opt/homebrew/opt/asyncplusplus/cmake/Async++Config.cmake")
    set(Async++_DIR "/opt/homebrew/opt/asyncplusplus/cmake")
endif ()
find_package(Async++ REQUIRED)
find_package(EnTT REQUIRED)
find_package(nlohmann_json REQUIRED)
find_package(date REQUIRED)
find_package(cpr REQUIRED)

find_package(fmt REQUIRED)
add_library(fmt INTERFACE)
target_link_libraries(fmt INTERFACE fmt::fmt)

find_package(spdlog REQUIRED)
add_library(spdlog INTERFACE)
target_link_libraries(spdlog INTERFACE spdlog::spdlog)

#find_package(absl CONFIG REQUIRED)
find_package(Boost COMPONENTS random system thread REQUIRED)
if (CONAN_ENABLED)
    if (NOT TARGET Boost::random)
        add_library(Boost::random INTERFACE IMPORTED)
        if (WIN32)
            target_link_libraries(Boost::random INTERFACE CONAN_LIB::Boost_libboost_random)
        else ()
            target_link_libraries(Boost::random INTERFACE CONAN_LIB::Boost_boost_random)
        endif ()
    endif ()
endif ()

add_library(komodo-date INTERFACE)
if (CONAN_ENABLED)
    target_link_libraries(komodo-date INTERFACE date::date)
else ()
    target_link_libraries(komodo-date INTERFACE date::date-tz)
endif ()
add_library(komodo-date::date ALIAS komodo-date)

find_package(Qt5 5.15 COMPONENTS Core Quick LinguistTools Svg WebEngine WebEngineCore WebEngineWidgets Widgets REQUIRED)

set(BUILD_TESTING OFF CACHE BOOL "Override option" FORCE)
set(EXPECTED_ENABLE_TESTS OFF CACHE BOOL "Override option" FORCE)

FetchContent_Declare(
        doom_meta
        URL https://github.com/doom/meta/archive/master.zip
)

## strong_type is not available in Homebrew: prefer an existing install,
## otherwise fetch it (uses the user's env when possible, never forces an
## environment change).
find_package(strong_type CONFIG QUIET)
if (NOT strong_type_FOUND)
    FetchContent_Declare(
            strong_type
            GIT_REPOSITORY https://github.com/rollbear/strong_type.git
            GIT_TAG v15
    )
endif ()

## refl-cpp is not available in Homebrew and nothing declares it, so fetch it.
FetchContent_Declare(
        refl-cpp
        GIT_REPOSITORY https://github.com/veselink1/refl-cpp.git
        GIT_TAG v0.12.4
)
if (NOT strong_type_FOUND)
    FetchContent_MakeAvailable(doom_meta strong_type refl-cpp)
else ()
    FetchContent_MakeAvailable(doom_meta refl-cpp)
endif ()

## rollbear/strong_type may expose `strong_type` without the namespaced alias
## that antara's ecs module expects (`strong_type::strong_type`).
if (NOT TARGET strong_type::strong_type AND TARGET strong_type)
    add_library(strong_type::strong_type ALIAS strong_type)
endif ()

find_package(tl-expected CONFIG REQUIRED)

add_library(antara_entt INTERFACE)
target_link_libraries(antara_entt INTERFACE EnTT::EnTT)
add_library(antara::entt ALIAS antara_entt)

## veselink1/refl-cpp ships its own `refl-cpp` CMake target; only define the
## fallback interface target when the fetched project did not provide one.
## (Layouts differ by version (root vs include/), so add both.)
if (NOT TARGET refl-cpp)
    add_library(refl-cpp INTERFACE)
    target_include_directories(refl-cpp INTERFACE ${refl-cpp_SOURCE_DIR} ${refl-cpp_SOURCE_DIR}/include)
endif ()
if (NOT TARGET antara::refl-cpp)
    add_library(antara::refl-cpp ALIAS refl-cpp)
endif ()


##! Sodium
## Homebrew's libsodium ships pkg-config, not the `unofficial-sodium` CMake
## config, so prefer the config but fall back to pkg-config/system paths in
## order to reuse the user's existing environment.
add_library(komodo-sodium INTERFACE)
if (CONAN_ENABLED)
    find_package(libsodium REQUIRED)
else ()
    find_package(unofficial-sodium CONFIG QUIET)
    if (unofficial-sodium_FOUND)
        target_link_libraries(komodo-sodium INTERFACE unofficial-sodium::sodium)
    else ()
        find_package(PkgConfig QUIET)
        if (PkgConfig_FOUND)
            pkg_check_modules(SODIUM IMPORTED_TARGET libsodium)
        endif ()
        if (SODIUM_FOUND)
            target_link_libraries(komodo-sodium INTERFACE PkgConfig::SODIUM)
        else ()
            find_library(SODIUM_LIBRARY sodium REQUIRED)
            find_path(SODIUM_INCLUDE_DIR sodium.h REQUIRED)
            target_link_libraries(komodo-sodium INTERFACE ${SODIUM_LIBRARY})
            target_include_directories(komodo-sodium INTERFACE ${SODIUM_INCLUDE_DIR})
            message(STATUS "sodium fallback -> ${SODIUM_LIBRARY} ${SODIUM_INCLUDE_DIR}")
        endif ()
    endif ()
endif ()
add_library(komodo-sodium::sodium ALIAS komodo-sodium)


## Unofficial BTC
add_library(unofficial-bitcoin INTERFACE)
if (WIN32)
    target_link_libraries(unofficial-bitcoin INTERFACE ${PROJECT_SOURCE_DIR}/libwally-core/wally.lib)
    target_include_directories(unofficial-bitcoin INTERFACE ${PROJECT_SOURCE_DIR}/libwally-core/include)
else ()
    find_library(unofficial-secp secp256k1)
    find_library(unofficial-wally wallycore)
    find_path(unofficial-wally-headers wally_core.h)
    target_link_libraries(unofficial-bitcoin INTERFACE ${unofficial-wally} ${unofficial-secp})
    target_include_directories(unofficial-bitcoin INTERFACE ${unofficial-wally-headers})
    message(STATUS "Found wally -> ${unofficial-wally} ${unofficial-wally-headers}")
endif ()
add_library(unofficial-btc::bitcoin ALIAS unofficial-bitcoin)
