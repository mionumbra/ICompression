set(SRC_DIR ${CMAKE_CURRENT_LIST_DIR})

# Extension metadata is the single source for the DLL and package version.
# Four fields follow project.version1.version2.build; this is not semantic versioning.
set(IC_EXTENSION_METADATA "${CMAKE_SOURCE_DIR}/project/extensions/ICompression/ICompression.yy")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${IC_EXTENSION_METADATA}")
file(READ "${IC_EXTENSION_METADATA}" IC_EXTENSION_METADATA_CONTENT)
string(REGEX MATCHALL "\"extensionVersion\"[ \t\r\n]*:[ \t\r\n]*\"[^\"]*\""
    IC_VERSION_FIELDS "${IC_EXTENSION_METADATA_CONTENT}")
list(LENGTH IC_VERSION_FIELDS IC_VERSION_FIELD_COUNT)
if(NOT IC_VERSION_FIELD_COUNT EQUAL 1)
  message(FATAL_ERROR "Expected exactly one extensionVersion in ${IC_EXTENSION_METADATA}")
endif()
string(REGEX REPLACE "^\"extensionVersion\"[ \t\r\n]*:[ \t\r\n]*\"([^\"]*)\"$" "\\1"
    IC_EXTENSION_VERSION "${IC_VERSION_FIELDS}")
if(NOT IC_EXTENSION_VERSION MATCHES "^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$")
  message(FATAL_ERROR "extensionVersion must use project.version1.version2.build: ${IC_EXTENSION_VERSION}")
endif()
set(IC_VERSION_PROJECT "${CMAKE_MATCH_1}")
set(IC_VERSION_FIRST "${CMAKE_MATCH_2}")
set(IC_VERSION_SECOND "${CMAKE_MATCH_3}")
set(IC_VERSION_BUILD "${CMAKE_MATCH_4}")
foreach(IC_VERSION_COMPONENT IN ITEMS IC_VERSION_PROJECT IC_VERSION_FIRST IC_VERSION_SECOND IC_VERSION_BUILD)
  string(LENGTH "${${IC_VERSION_COMPONENT}}" IC_VERSION_COMPONENT_LENGTH)
  if(IC_VERSION_COMPONENT_LENGTH GREATER 5 OR ${IC_VERSION_COMPONENT} GREATER 65535)
    message(FATAL_ERROR "Version components must be at most 65535")
  endif()
endforeach()
configure_file("${SRC_DIR}/native/ICompression_version.h.in"
    "${CMAKE_CURRENT_BINARY_DIR}/ICompression_version.h" @ONLY)
target_include_directories(${PROJECT_NAME} PRIVATE "${CMAKE_CURRENT_BINARY_DIR}")


# =============================================================================
# GameMaker iOS integration (optional)
# =============================================================================
set(EXT_GM_XCODEPROJ_OVERRIDE "" CACHE STRING "Optional GameMaker Xcode project override")
set(EXT_GM_APP_TARGET_OVERRIDE "" CACHE STRING "Optional GameMaker app target override")

# =============================================================================
# Public headers for Apple XCFramework packaging
# Users should edit these to match their project structure.
# The packager will copy these into a headers folder passed to xcodebuild.
# =============================================================================
set(EXT_PUBLIC_HEADERS_IOS
    "${CMAKE_SOURCE_DIR}/src/ios/${PROJECT_NAME}_ios.h;${CMAKE_SOURCE_DIR}/code_gen/ios/${PROJECT_NAME}Internal_ios.h"
    CACHE STRING "Semicolon-separated list of public headers to embed in the iOS xcframework")

set(EXT_PUBLIC_HEADERS_TVOS
    "${CMAKE_SOURCE_DIR}/src/tvos/${PROJECT_NAME}_tvos.h;${CMAKE_SOURCE_DIR}/code_gen/tvos/${PROJECT_NAME}Internal_tvos.h"
    CACHE STRING "Semicolon-separated list of public headers to embed in the tvOS xcframework")

# =============================================================================
# User implementation sources per platform (editable template)
# =============================================================================
if(WIN32)
  enable_language(RC)
  file(GLOB TARGET_SRCS CONFIGURE_DEPENDS "${SRC_DIR}/native/*.cpp")
  list(APPEND TARGET_SRCS "${SRC_DIR}/native/ICompression_version.rc")

elseif(APPLE)
  if(CMAKE_OSX_SYSROOT MATCHES "iphone")
    file(GLOB TARGET_SRCS CONFIGURE_DEPENDS
      "${SRC_DIR}/native/*.cpp"
      "${SRC_DIR}/ios/*.mm"
      "${SRC_DIR}/ios/*.cpp"
      "${SRC_DIR}/ios/*.swift")
  elseif(CMAKE_OSX_SYSROOT MATCHES "appletv")
    file(GLOB TARGET_SRCS CONFIGURE_DEPENDS
      "${SRC_DIR}/native/*.cpp"
      "${SRC_DIR}/tvos/*.mm"
      "${SRC_DIR}/tvos/*.cpp"
      "${SRC_DIR}/tvos/*.swift")
  else()
    file(GLOB TARGET_SRCS CONFIGURE_DEPENDS "${SRC_DIR}/native/*.mm" "${SRC_DIR}/native/*.cpp" "${SRC_DIR}/native/*.swift")
  endif()

elseif(ANDROID)
  file(GLOB TARGET_SRCS CONFIGURE_DEPENDS
    "${SRC_DIR}/native/*.cpp"
    "${SRC_DIR}/android/*.cpp")

elseif(UNIX)
  file(GLOB TARGET_SRCS CONFIGURE_DEPENDS "${SRC_DIR}/native/*.cpp")
endif()

target_sources(${PROJECT_NAME} PRIVATE ${TARGET_SRCS})
target_include_directories(${PROJECT_NAME} PRIVATE "${SRC_DIR}")

if(MSVC)
  target_compile_options(${PROJECT_NAME} PRIVATE /utf-8)
endif()
