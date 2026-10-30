# CMake toolchain file for the bundled clang-cl + lld-link (release zip, no Visual Studio). Used by
# tools\build_runtime_portable.cmd and tools\build_ps2recomp_tools_portable.cmd through -DCMAKE_TOOLCHAIN_FILE.
# Paths are relative to this file: <root>\tools\ -> <root>\toolchain\.
get_filename_component(T4_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
set(T4_TC "${T4_ROOT}/toolchain")
set(CMAKE_C_COMPILER   "${T4_TC}/llvm/bin/clang-cl.exe")
set(CMAKE_CXX_COMPILER "${T4_TC}/llvm/bin/clang-cl.exe")
set(CMAKE_LINKER       "${T4_TC}/llvm/bin/lld-link.exe")
set(CMAKE_AR           "${T4_TC}/llvm/bin/llvm-lib.exe")
set(CMAKE_RC_COMPILER  "${T4_TC}/llvm/bin/llvm-rc.exe")
set(CMAKE_MT           "${T4_TC}/llvm/bin/llvm-mt.exe")
set(CMAKE_MAKE_PROGRAM "${T4_TC}/ninja/ninja.exe" CACHE FILEPATH "")
# A clean player PC has no VC redistributable. Link our C/C++ targets to the fetched static CRT/STL.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>" CACHE STRING "" FORCE)
set(Python3_EXECUTABLE "${T4_ROOT}/python/python.exe" CACHE FILEPATH "" FORCE)
set(PS2X_ENABLE_SCCACHE OFF CACHE BOOL "" FORCE)
set(FETCHCONTENT_FULLY_DISCONNECTED ON CACHE BOOL "" FORCE)
# Libraries the runtime's CMake would clone with Git are vendored in the zip (deps\fetch\<name>).
foreach(dep raylib imgui rlimgui sse2neon elfio toml11 fmt libdwarf rabbitizer)
  string(TOUPPER "${dep}" DEP)
  if(EXISTS "${T4_ROOT}/deps/fetch/${dep}")
    set(FETCHCONTENT_SOURCE_DIR_${DEP} "${T4_ROOT}/deps/fetch/${dep}" CACHE PATH "" FORCE)
  else()
    message(FATAL_ERROR "Incomplete release: deps/fetch/${dep} is missing")
  endif()
endforeach()
# prepare_portable_tree.py changes only the staged source to honour this override.
set(FFMPEG_PREBUILT_URL "${T4_ROOT}/deps/ffmpeg/ffmpeg.zip" CACHE STRING "" FORCE)
