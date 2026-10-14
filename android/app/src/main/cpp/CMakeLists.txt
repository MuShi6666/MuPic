# MuPic native core.
#
# Builds libmupic_core.so: LibRaw-based decoder + dual render pipeline
# (GPU preview via OpenGL ES 3.1, CPU export). Linked into the app through
# android/app/build.gradle.kts externalNativeBuild.
#
cmake_minimum_required(VERSION 3.22.1)
project(mupic_core LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(MUPIC_SOURCES
        jni_bridge.cpp
        core/adjustments.cpp
        core/image_buffer.cpp
        core/raw_decoder.cpp
        core/color_pipeline.cpp
        core/preview_cpu.cpp
        core/export_cpu.cpp
        gl/gl_context.cpp
        gl/gl_pipeline.cpp
        gl/lut_builder.cpp)

add_library(mupic_core SHARED ${MUPIC_SOURCES})

# Android system libraries used by the pipeline.
find_library(android-lib android)
find_library(log-lib log)
find_library(math-lib m)
find_library(gles-lib GLESv3)
find_library(egl-lib EGL)
find_library(dl-lib dl)

target_include_directories(mupic_core PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/core
        ${CMAKE_CURRENT_SOURCE_DIR}/gl)

target_link_libraries(mupic_core PRIVATE
        ${android-lib}
        ${log-lib}
        ${math-lib}
        ${gles-lib}
        ${egl-lib}
        ${dl-lib})

# OpenMP enables tiled multi-threaded CPU export (M6).
find_package(OpenMP QUIET)
if(OpenMP_CXX_FOUND)
    target_link_libraries(mupic_core PRIVATE OpenMP::OpenMP_CXX)
endif()

# ---------------------------------------------------------------------------
# LibRaw integration point.
#
# Drop the LibRaw sources under third_party/libraw and this block wires them
# into the build. Kept optional so the M0 skeleton links without the vendor
# library present. See plan section "风险与应对" for the fallback (Android
# HARDWARE_RAW + DngCreator).
# ---------------------------------------------------------------------------
if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/third_party/libraw/CMakeLists.txt)
    add_subdirectory(third_party/libraw)
    target_compile_definitions(mupic_core PRIVATE MUPIC_HAVE_LIBRAW=1)
    target_link_libraries(mupic_core PRIVATE libraw)
else()
    message(STATUS "LibRaw not present under third_party/libraw - using placeholder decoder")
endif()
