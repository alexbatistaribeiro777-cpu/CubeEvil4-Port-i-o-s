# CMake toolchain for the CubeEvil4 iOS core (device, arm64).
#
#   cmake -S port -B build/ios-core \
#       -DCMAKE_TOOLCHAIN_FILE="$PWD/port/ios/cmake/ios.toolchain.cmake" \
#       -DCMAKE_BUILD_TYPE=Debug \
#       -DRE4_BUILD_TESTS=OFF
#   cmake --build build/ios-core --target re4_ios_core
#
# The result is build/ios-core/libre4.a: the ported core as one Mach-O arm64
# static library. It is not linked into the app yet; the phase-1 gate is that
# the scheduler, its Mach-O fcontext backend and the ported core compile
# against the device SDK.
#
# The deployment target matches port/ios/project.yml (iOS 15.0). This is the
# device SDK, never the simulator: the app delivers arm64 device builds.
cmake_minimum_required(VERSION 3.22)

set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_SYSTEM_PROCESSOR arm64)

set(RE4_IOS_DEPLOYMENT_TARGET "15.0" CACHE STRING "Minimum supported iOS version")
set(CMAKE_OSX_DEPLOYMENT_TARGET "${RE4_IOS_DEPLOYMENT_TARGET}" CACHE STRING "")
set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "")

execute_process(
    COMMAND xcrun --sdk iphoneos --show-sdk-path
    OUTPUT_VARIABLE RE4_IOS_SDK_PATH
    OUTPUT_STRIP_TRAILING_WHITESPACE
    RESULT_VARIABLE RE4_IOS_SDK_RESULT)
if(NOT RE4_IOS_SDK_RESULT EQUAL 0 OR NOT EXISTS "${RE4_IOS_SDK_PATH}")
    message(FATAL_ERROR
        "xcrun cannot locate the iPhoneOS SDK. Install Xcode and select it with "
        "xcode-select, or run this only on macOS.")
endif()
set(CMAKE_OSX_SYSROOT "${RE4_IOS_SDK_PATH}" CACHE STRING "" FORCE)

execute_process(
    COMMAND xcrun --sdk iphoneos --find clang
    OUTPUT_VARIABLE RE4_IOS_CLANG
    OUTPUT_STRIP_TRAILING_WHITESPACE
    RESULT_VARIABLE RE4_IOS_CLANG_RESULT)
execute_process(
    COMMAND xcrun --sdk iphoneos --find clang++
    OUTPUT_VARIABLE RE4_IOS_CLANGXX
    OUTPUT_STRIP_TRAILING_WHITESPACE
    RESULT_VARIABLE RE4_IOS_CLANGXX_RESULT)
if(NOT RE4_IOS_CLANG_RESULT EQUAL 0 OR NOT RE4_IOS_CLANGXX_RESULT EQUAL 0)
    message(FATAL_ERROR "xcrun cannot locate clang for the iPhoneOS SDK")
endif()
set(CMAKE_C_COMPILER "${RE4_IOS_CLANG}" CACHE FILEPATH "" FORCE)
set(CMAKE_CXX_COMPILER "${RE4_IOS_CLANGXX}" CACHE FILEPATH "" FORCE)
set(CMAKE_ASM_COMPILER "${RE4_IOS_CLANG}" CACHE FILEPATH "" FORCE)

# Compiler checks build a static library instead of trying to link an
# executable: there is no iOS runtime on the build host.
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

# Everything that comes from the SDK lives in the sysroot; host tools (Python,
# libtool, CMake helpers) must still be found on the build machine.
set(CMAKE_FIND_ROOT_PATH "${RE4_IOS_SDK_PATH}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE NEVER)

# No bitcode (Xcode 14+ removed device bitcode anyway) and no code signing for
# a static archive.
set(CMAKE_XCODE_ATTRIBUTE_ENABLE_BITCODE NO CACHE STRING "")
set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED NO CACHE STRING "")
