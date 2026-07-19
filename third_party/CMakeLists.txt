cmake_minimum_required(VERSION 3.18)

# =============================================================================
# ICompression third_party - libarchive + common compression backends
# =============================================================================

include(FetchContent)

set(ZLIB_VERSION "1.3.2")
set(BZIP2_VERSION "1.0.8")
set(ZSTD_VERSION "1.5.7")
set(LZ4_VERSION "1.10.0")
set(XZ_VERSION "5.8.3")
set(LIBARCHIVE_VERSION "3.8.8")

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(CMAKE_POLICY_VERSION_MINIMUM "3.5" CACHE STRING "" FORCE)

# -----------------------------------------------------------------------------
# zlib (ZIP deflate + gzip)
# -----------------------------------------------------------------------------
FetchContent_Declare(
    zlib
    GIT_REPOSITORY https://github.com/madler/zlib.git
    GIT_TAG v${ZLIB_VERSION}
    GIT_SHALLOW TRUE
    GIT_PROGRESS TRUE
)
FetchContent_MakeAvailable(zlib)
set(ZLIB_INCLUDE_DIR ${zlib_SOURCE_DIR} ${zlib_BINARY_DIR} CACHE PATH "zlib include" FORCE)
set(ZLIB_LIBRARY zlibstatic CACHE STRING "zlib library target" FORCE)
set(ZLIB_LIBRARIES zlibstatic CACHE STRING "zlib libraries" FORCE)
set(ZLIB_FOUND TRUE CACHE BOOL "zlib found" FORCE)

# -----------------------------------------------------------------------------
# bzip2 (.bz2, .tar.bz2)
# -----------------------------------------------------------------------------
FetchContent_Declare(
    bzip2
    GIT_REPOSITORY https://sourceware.org/git/bzip2.git
    GIT_TAG bzip2-${BZIP2_VERSION}
    GIT_SHALLOW TRUE
    GIT_PROGRESS TRUE
)
FetchContent_GetProperties(bzip2)
if(NOT bzip2_POPULATED)
  FetchContent_Populate(bzip2)
endif()

add_library(bz2_static STATIC
  "${bzip2_SOURCE_DIR}/blocksort.c"
  "${bzip2_SOURCE_DIR}/huffman.c"
  "${bzip2_SOURCE_DIR}/crctable.c"
  "${bzip2_SOURCE_DIR}/randtable.c"
  "${bzip2_SOURCE_DIR}/compress.c"
  "${bzip2_SOURCE_DIR}/decompress.c"
  "${bzip2_SOURCE_DIR}/bzlib.c"
)
target_include_directories(bz2_static PUBLIC "${bzip2_SOURCE_DIR}")
target_compile_definitions(bz2_static PRIVATE _FILE_OFFSET_BITS=64)
set_target_properties(bz2_static PROPERTIES POSITION_INDEPENDENT_CODE ON)
if(MSVC)
  if(CMAKE_MSVC_RUNTIME_LIBRARY)
    set(_IC_MSVC_RUNTIME_LIBRARY "${CMAKE_MSVC_RUNTIME_LIBRARY}")
  else()
    set(_IC_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL")
  endif()
  set_property(TARGET bz2_static PROPERTY MSVC_RUNTIME_LIBRARY "${_IC_MSVC_RUNTIME_LIBRARY}")
  target_compile_options(bz2_static PRIVATE
    "$<$<CONFIG:Debug>:/MDd>"
    "$<$<NOT:$<CONFIG:Debug>>:/MD>"
  )
endif()

set(BZIP2_INCLUDE_DIR "${bzip2_SOURCE_DIR}" CACHE PATH "bzip2 include" FORCE)
set(BZIP2_INCLUDE_DIRS "${bzip2_SOURCE_DIR}" CACHE PATH "bzip2 includes" FORCE)
set(BZIP2_LIBRARY bz2_static CACHE STRING "bzip2 library target" FORCE)
set(BZIP2_LIBRARIES bz2_static CACHE STRING "bzip2 libraries" FORCE)
set(BZIP2_FOUND TRUE CACHE BOOL "bzip2 found" FORCE)

# -----------------------------------------------------------------------------
# zstd (.zst, .tar.zst)
# -----------------------------------------------------------------------------
set(ZSTD_BUILD_STATIC ON CACHE BOOL "" FORCE)
set(ZSTD_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_CONTRIB OFF CACHE BOOL "" FORCE)
set(ZSTD_MULTITHREAD_SUPPORT OFF CACHE BOOL "" FORCE)
set(ZSTD_LEGACY_SUPPORT OFF CACHE BOOL "" FORCE)

FetchContent_Declare(
    zstd
    GIT_REPOSITORY https://github.com/facebook/zstd.git
    GIT_TAG v${ZSTD_VERSION}
    GIT_SHALLOW TRUE
    GIT_PROGRESS TRUE
)
FetchContent_GetProperties(zstd)
if(NOT zstd_POPULATED)
  FetchContent_Populate(zstd)
  add_subdirectory("${zstd_SOURCE_DIR}/build/cmake" "${zstd_BINARY_DIR}" EXCLUDE_FROM_ALL)
endif()

set(ZSTD_INCLUDE_DIR "${zstd_SOURCE_DIR}/lib" CACHE PATH "zstd include" FORCE)
set(ZSTD_LIBRARY libzstd_static CACHE STRING "zstd library target" FORCE)
set(ZSTD_FOUND TRUE CACHE BOOL "zstd found" FORCE)
set(HAVE_LIBZSTD 1 CACHE INTERNAL "")
set(HAVE_ZSTD_compressStream 1 CACHE INTERNAL "")
set(HAVE_ZSTD_minCLevel 1 CACHE INTERNAL "")

# -----------------------------------------------------------------------------
# lz4 (.lz4, .tar.lz4)
# -----------------------------------------------------------------------------
set(LZ4_BUILD_CLI OFF CACHE BOOL "" FORCE)
set(LZ4_BUNDLED_MODE ON CACHE BOOL "" FORCE)
set(BUILD_STATIC_LIBS ON CACHE BOOL "" FORCE)

FetchContent_Declare(
    lz4
    GIT_REPOSITORY https://github.com/lz4/lz4.git
    GIT_TAG v${LZ4_VERSION}
    GIT_SHALLOW TRUE
    GIT_PROGRESS TRUE
)
FetchContent_GetProperties(lz4)
if(NOT lz4_POPULATED)
  FetchContent_Populate(lz4)
  add_subdirectory("${lz4_SOURCE_DIR}/build/cmake" "${lz4_BINARY_DIR}" EXCLUDE_FROM_ALL)
endif()

set(LZ4_INCLUDE_DIR "${lz4_SOURCE_DIR}/lib" CACHE PATH "lz4 include" FORCE)
set(LZ4_LIBRARY lz4_static CACHE STRING "lz4 library target" FORCE)
set(LZ4_FOUND TRUE CACHE BOOL "lz4 found" FORCE)

# -----------------------------------------------------------------------------
# xz / liblzma (.xz, .tar.xz, 7z compression)
# -----------------------------------------------------------------------------
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(XZ_NLS OFF CACHE BOOL "" FORCE)
set(XZ_DOC OFF CACHE BOOL "" FORCE)
set(XZ_DOXYGEN OFF CACHE BOOL "" FORCE)
set(XZ_THREADS no CACHE STRING "" FORCE)
set(XZ_SANDBOX no CACHE STRING "" FORCE)
set(XZ_TOOL_XZ OFF CACHE BOOL "" FORCE)
set(XZ_TOOL_XZDEC OFF CACHE BOOL "" FORCE)
set(XZ_TOOL_LZMADEC OFF CACHE BOOL "" FORCE)
set(XZ_TOOL_LZMAINFO OFF CACHE BOOL "" FORCE)
set(XZ_TOOL_SCRIPTS OFF CACHE BOOL "" FORCE)
set(XZ_TOOL_SYMLINKS OFF CACHE BOOL "" FORCE)
set(XZ_TOOL_SYMLINKS_LZMA OFF CACHE BOOL "" FORCE)

FetchContent_Declare(
    xz
    GIT_REPOSITORY https://github.com/tukaani-project/xz.git
    GIT_TAG v${XZ_VERSION}
    GIT_SHALLOW TRUE
    GIT_PROGRESS TRUE
)
FetchContent_GetProperties(xz)
if(NOT xz_POPULATED)
  FetchContent_Populate(xz)
  add_subdirectory("${xz_SOURCE_DIR}" "${xz_BINARY_DIR}" EXCLUDE_FROM_ALL)
endif()

set(LIBLZMA_INCLUDE_DIR "${xz_SOURCE_DIR}/src/liblzma/api" CACHE PATH "liblzma include" FORCE)
set(LIBLZMA_INCLUDE_DIRS "${xz_SOURCE_DIR}/src/liblzma/api" CACHE PATH "liblzma includes" FORCE)
set(LIBLZMA_LIBRARY liblzma CACHE STRING "liblzma library target" FORCE)
set(LIBLZMA_LIBRARIES liblzma CACHE STRING "liblzma libraries" FORCE)
set(LIBLZMA_FOUND TRUE CACHE BOOL "liblzma found" FORCE)
set(LIBLZMA_HAS_AUTO_DECODER TRUE CACHE BOOL "liblzma auto decoder" FORCE)
set(LIBLZMA_HAS_EASY_ENCODER TRUE CACHE BOOL "liblzma easy encoder" FORCE)
set(LIBLZMA_HAS_LZMA_PRESET TRUE CACHE BOOL "liblzma preset encoder" FORCE)

# -----------------------------------------------------------------------------
# libarchive
# -----------------------------------------------------------------------------

message(STATUS "[third_party] Fetching libarchive v${LIBARCHIVE_VERSION}...")
message(STATUS "[third_party] Backends: zlib v${ZLIB_VERSION}, bzip2 v${BZIP2_VERSION}, zstd v${ZSTD_VERSION}, lz4 v${LZ4_VERSION}, xz v${XZ_VERSION}")

set(ENABLE_ZLIB ON CACHE BOOL "" FORCE)
set(ENABLE_BZip2 ON CACHE BOOL "" FORCE)
set(ENABLE_LZ4 ON CACHE BOOL "" FORCE)
set(ENABLE_ZSTD ON CACHE BOOL "" FORCE)
set(ENABLE_LZMA ON CACHE BOOL "" FORCE)
set(ENABLE_CAT OFF CACHE BOOL "" FORCE)
set(ENABLE_TAR ON CACHE BOOL "" FORCE)
set(ENABLE_CPIO OFF CACHE BOOL "" FORCE)
set(ENABLE_PCREPOSIX OFF CACHE BOOL "" FORCE)
set(ENABLE_PCRE2POSIX OFF CACHE BOOL "" FORCE)
set(ENABLE_OPENSSL OFF CACHE BOOL "" FORCE)
set(ENABLE_ICONV OFF CACHE BOOL "" FORCE)
set(ENABLE_EXPAT OFF CACHE BOOL "" FORCE)
set(ENABLE_LIBXML2 OFF CACHE BOOL "" FORCE)
set(ENABLE_LIBB2 OFF CACHE BOOL "" FORCE)
set(ENABLE_LZO OFF CACHE BOOL "" FORCE)
set(ENABLE_MBEDTLS OFF CACHE BOOL "" FORCE)
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
