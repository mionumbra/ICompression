# Attach build numbering to the target's owning directory, after the generated
# extension generator's copy commands. Stamp then recopy the final DLL/receipt.
function(ic_enable_build_counter target)
  cmake_parse_arguments(IC "" "METADATA;STATE_DIRECTORY;SOURCE_DIRECTORY;OUTPUT_DIRECTORY" "" ${ARGN})
  # The stamp step shells out to a Windows-only PowerShell counter; other
  # platforms skip version stamping and ship the unstamped library.
  if(NOT WIN32)
    return()
  endif()
  foreach(required IN ITEMS METADATA STATE_DIRECTORY SOURCE_DIRECTORY)
    if(NOT IC_${required})
      message(FATAL_ERROR "ic_enable_build_counter requires ${required}")
    endif()
  endforeach()
  find_program(IC_COUNTER_POWERSHELL NAMES pwsh REQUIRED)
  get_filename_component(counter_script "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/../scripts/update-build-counter.ps1" ABSOLUTE)
  set_target_properties(${target} PROPERTIES
    IC_COUNTER_METADATA "${IC_METADATA}"
    IC_COUNTER_STATE "${IC_STATE_DIRECTORY}"
    IC_COUNTER_SOURCE "${IC_SOURCE_DIRECTORY}"
    IC_COUNTER_OUTPUT "${IC_OUTPUT_DIRECTORY}"
    IC_COUNTER_SCRIPT "${counter_script}"
    IC_COUNTER_POWERSHELL "${IC_COUNTER_POWERSHELL}")
  get_target_property(owner ${target} SOURCE_DIR)
  cmake_language(EVAL CODE
    "cmake_language(DEFER DIRECTORY \"${owner}\" CALL ic_attach_build_counter \"${target}\")")
endfunction()

function(ic_attach_build_counter target)
  foreach(property IN ITEMS METADATA STATE SOURCE OUTPUT SCRIPT POWERSHELL)
    get_target_property(IC_${property} ${target} IC_COUNTER_${property})
  endforeach()
  if(NOT IC_OUTPUT)
    if(DEFINED _EXT_OUT_DIR)
      set(IC_OUTPUT "${_EXT_OUT_DIR}")
    else()
      set(IC_OUTPUT "$<TARGET_FILE_DIR:${target}>")
    endif()
  endif()
  add_custom_command(TARGET ${target} POST_BUILD
    COMMAND "${IC_POWERSHELL}" -NoProfile -File "${IC_SCRIPT}"
      -Binary "$<TARGET_FILE:${target}>"
      -MetadataPath "${IC_METADATA}"
      -StateDirectory "${IC_STATE}"
      -SourceDirectory "${IC_SOURCE}"
      -OutputDirectory "${IC_OUTPUT}"
      -Configuration "$<CONFIG>"
      -CompilerVersion "${CMAKE_CXX_COMPILER_VERSION}"
      -Generator "${CMAKE_GENERATOR}"
    COMMENT "Recording the successful ICompression DLL build"
    VERBATIM)
endfunction()
