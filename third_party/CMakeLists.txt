cmake_minimum_required(VERSION 3.18)

# =============================================================================
# ICompression third_party - libarchive + zlib (deflate decompression)
# =============================================================================

include(FetchContent)

# -----------------------------------------------------------------------------
# zlib (required for ZIP deflate + gzip decompression)
# -----------------------------------------------------------------------------
FetchContent_Declare(
    zlib
    GIT_REPOSITORY https://github.com/madler/zlib.git
    GIT_TAG v1.3.1
    GIT_SHALLOW TRUE
    GIT_PROGRESS TRUE
)
FetchContent_MakeAvailable(zlib)
set(ZLIB_INCLUDE_DIR ${zlib_SOURCE_DIR} ${zlib_BINARY_DIR} CACHE PATH "zlib include" FORCE)
set(ZLIB_LIBRARY zlibstatic CACHE FILEPATH "zlib library" FORCE)
set(ZLIB_FOUND TRUE CACHE BOOL "zlib found" FORCE)

# -----------------------------------------------------------------------------
# libarchive
# -----------------------------------------------------------------------------

set(LIBARCHIVE_VERSION "3.7.7")

message(STATUS "[third_party] Fetching libarchive v${LIBARCHIVE_VERSION}...")

set(ENABLE_ZLIB ON CACHE BOOL "" FORCE)
set(ENABLE_BZip2 OFF CACHE BOOL "" FORCE)
set(ENABLE_LZ4 OFF CACHE BOOL "" FORCE)
set(ENABLE_ZSTD OFF CACHE BOOL "" FORCE)
set(ENABLE_LZMA OFF CACHE BOOL "" FORCE)
set(ENABLE_CAT OFF CACHE BOOL "" FORCE)
set(ENABLE_TAR ON CACHE BOOL "" FORCE)
set(ENABLE_CPIO OFF CACHE BOOL "" FORCE)
set(ENABLE_PCREPOSIX OFF CACHE BOOL "" FORCE)
set(ENABLE_OPENSSL OFF CACHE BOOL "" FORCE)
set(ENABLE_ICONV OFF CACHE BOOL "" FORCE)
set(ENABLE_EXPAT OFF CACHE BOOL "" FORCE)
set(ENABLE_LIBXML2 OFF CACHE BOOL "" FORCE)
set(ENABLE_NETTLE OFF CACHE BOOL "" FORCE)
set(ENABLE_CNG ON CACHE BOOL "" FORCE)
set(ENABLE_WERROR OFF CACHE BOOL "" FORCE)
set(ENABLE_TEST OFF CACHE BOOL "" FORCE)
set(ENABLE_INSTALL OFF CACHE BOOL "" FORCE)

if(WIN32)
  set(ENABLE_CNG ON CACHE BOOL "" FORCE)
elseif(APPLE)
  set(ENABLE_COMMON_CRYPTO ON CACHE BOOL "" FORCE)
endif()

FetchContent_Declare(
  libarchive
  GIT_REPOSITORY https://github.com/libarchive/libarchive.git
  GIT_TAG v${LIBARCHIVE_VERSION}
  GIT_SHALLOW TRUE
  GIT_PROGRESS TRUE
)

# Work around MSVC intrinsic detection issues with CMake 4.x
set(HAVE_WCSCPY 1 CACHE INTERNAL "")
set(HAVE_WCSLEN 1 CACHE INTERNAL "")
set(HAVE_WCSNCPY 1 CACHE INTERNAL "")
set(HAVE_WMEMCPY 1 CACHE INTERNAL "")
set(HAVE_WMEMMOVE 1 CACHE INTERNAL "")

FetchContent_MakeAvailable(libarchive)

# -----------------------------------------------------------------------------
# Our ext_third_party INTERFACE target
# -----------------------------------------------------------------------------
add_library(ext_third_party INTERFACE)

target_link_libraries(ext_third_party INTERFACE archive_static)
target_compile_definitions(ext_third_party INTERFACE LIBARCHIVE_STATIC)

target_include_directories(ext_third_party INTERFACE
  "${libarchive_SOURCE_DIR}/libarchive"
  "${libarchive_BINARY_DIR}/libarchive"
)

# Platform-specific system libs
if(WIN32)
  target_link_libraries(ext_third_party INTERFACE
    ws2_32
    bcrypt
  )
elseif(APPLE)
  find_library(COMMON_CRYPTO_FW CommonCrypto)
  if(COMMON_CRYPTO_FW)
    target_link_libraries(ext_third_party INTERFACE "${COMMON_CRYPTO_FW}")
  endif()
elseif(UNIX AND NOT APPLE)
  target_link_libraries(ext_third_party INTERFACE
    pthread
    dl
    m
  )
endif()

message(STATUS "[third_party] libarchive v${LIBARCHIVE_VERSION} configured successfully")
