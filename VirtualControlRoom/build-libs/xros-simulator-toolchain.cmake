# Toolchain for cross-compiling to visionOS Simulator
set(CMAKE_SYSTEM_NAME Darwin)
set(CMAKE_SYSTEM_PROCESSOR arm64)

# Set the sysroot to visionOS simulator SDK
set(CMAKE_OSX_SYSROOT /Applications/Xcode.app/Contents/Developer/Platforms/XRSimulator.platform/Developer/SDKs/XRSimulator2.5.sdk)
set(CMAKE_OSX_ARCHITECTURES "arm64")

# Set deployment target
set(CMAKE_OSX_DEPLOYMENT_TARGET "2.5")

# Set the compiler flags for visionOS simulator
set(CMAKE_C_FLAGS_INIT "-target arm64-apple-xros2.5-simulator")
set(CMAKE_CXX_FLAGS_INIT "-target arm64-apple-xros2.5-simulator")

# Set the compilers
set(CMAKE_C_COMPILER "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang")
set(CMAKE_CXX_COMPILER "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++")

# Don't run the linker on compiler check
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

# Search for programs only in the host directories
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
# Search for libraries and headers only in the target directories
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Disable features that don't work on visionOS
set(WITH_OPENSSL OFF CACHE BOOL "")
set(WITH_GNUTLS OFF CACHE BOOL "")
set(WITH_GCRYPT OFF CACHE BOOL "")
set(WITH_SYSTEMD OFF CACHE BOOL "")
set(WITH_THREADS OFF CACHE BOOL "")
set(WITH_IPv6 OFF CACHE BOOL "")
set(BUILD_SHARED_LIBS OFF CACHE BOOL "")