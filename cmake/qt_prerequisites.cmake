## NOTE (Apple Silicon): never overwrite a -DCMAKE_PREFIX_PATH passed on the
## command line (e.g. Homebrew + local libwally prefix from
## build_apple_silicon.sh) -- append the Qt location instead.
if (WIN32)
    list(APPEND CMAKE_PREFIX_PATH "$ENV{QT_INSTALL_CMAKE_PATH}/lib/cmake")
else ()
    if (DEFINED ENV{QT_INSTALL_CMAKE_PATH} AND NOT "$ENV{QT_INSTALL_CMAKE_PATH}" STREQUAL "")
        list(APPEND CMAKE_PREFIX_PATH "$ENV{QT_INSTALL_CMAKE_PATH}")
    endif ()
endif ()
set(CMAKE_PREFIX_PATH "${CMAKE_PREFIX_PATH}" CACHE STRING "" FORCE)
message(STATUS "CMake Prefix path is: ${CMAKE_PREFIX_PATH}")
