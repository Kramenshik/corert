#!/usr/bin/env bash
#
# This file invokes cmake and generates the build system for Clang.
#

if [ $# -lt 3 -o $# -gt 5 ]
then
  echo "Usage..."
  echo "gen-buildsys-clang.sh <path to top level CMakeLists.txt> <ClangMajorVersion> <ClangMinorVersion> <Architecture> [build flavor]"
  echo "Specify the path to the top level CMake file - <corert>/src/Native"
  echo "Specify the clang version to use, split into major and minor version"
  echo "Specify the target architecture." 
  echo "Optionally specify the build configuration (flavor.) Defaults to DEBUG." 
  exit 1
fi

# Set up the environment to be used for building with clang.
if command -v "clang-$2.$3" > /dev/null 2>&1 && command -v "clang++-$2.$3" > /dev/null 2>&1
    then
        export CC="$(command -v clang-$2.$3)"
        export CXX="$(command -v clang++-$2.$3)"
elif command -v "clang$2$3" > /dev/null 2>&1 && command -v "clang++$2$3" > /dev/null 2>&1
    then
        export CC="$(command -v clang$2$3)"
        export CXX="$(command -v clang++$2$3)"
elif command -v clang > /dev/null 2>&1 && command -v clang++ > /dev/null 2>&1
    then
        export CC="$(command -v clang)"
        export CXX="$(command -v clang++)"
else
    echo "Unable to find Clang Compiler"
    exit 1
fi

build_arch="$4"
if [ -z "$5" ]; then
    echo "Defaulting to DEBUG build."
    build_type="DEBUG"
else
    # Possible build types are DEBUG, RELEASE
    build_type="$(echo $5 | awk '{print toupper($0)}')"
    if [ "$build_type" != "DEBUG" ] && [ "$build_type" != "RELEASE" ]; then
        echo "Invalid Build type, only debug or release is accepted."
        exit 1
    fi
fi

OS=`uname`

# Locate llvm
# This can be a little complicated, because the common use-case of Ubuntu with
# llvm-3.5 installed uses a rather unusual llvm installation with the version
# number postfixed (i.e. llvm-ar-3.5), so we check for that first.
# On FreeBSD the version number is appended without point and dash (i.e.
# llvm-ar35).
# Additionally, OSX doesn't use the llvm- prefix.
if [ $OS = "Linux" -o $OS = "FreeBSD" -o $OS = "OpenBSD" -o $OS = "NetBSD" ]; then
  llvm_prefix="llvm-"
elif [ $OS = "Darwin" ]; then
  llvm_prefix=""
else
  echo "Unable to determine build platform"
  exit 1
fi

desired_llvm_major_version=$2
desired_llvm_minor_version=$3
if [ $OS = "FreeBSD" ]; then
    desired_llvm_version="$desired_llvm_major_version$desired_llvm_minor_version"
elif [ $OS = "OpenBSD" ]; then
    desired_llvm_version=""
elif [ $OS = "NetBSD" ]; then
    desired_llvm_version=""
else
  desired_llvm_version="-$desired_llvm_major_version.$desired_llvm_minor_version"
fi
locate_llvm_exec() {
  if command -v "$llvm_prefix$1$desired_llvm_version" > /dev/null 2>&1
  then
    echo "$(command -v $llvm_prefix$1$desired_llvm_version)"
  elif command -v "$llvm_prefix$1" > /dev/null 2>&1
  then
    echo "$(command -v $llvm_prefix$1)"
  else
    exit 1
  fi
}

llvm_ar="$(locate_llvm_exec ar)"
[[ $? -eq 0 ]] || { echo "Unable to locate llvm-ar"; exit 1; }
llvm_link="$(locate_llvm_exec link)"
[[ $? -eq 0 ]] || { echo "Unable to locate llvm-link"; exit 1; }
llvm_nm="$(locate_llvm_exec nm)"
[[ $? -eq 0 ]] || { echo "Unable to locate llvm-nm"; exit 1; }
if [ $OS = "Linux" -o $OS = "FreeBSD" -o $OS = "OpenBSD" -o $OS = "NetBSD" ]; then
  llvm_objdump="$(locate_llvm_exec objdump)"
  [[ $? -eq 0 ]] || { echo "Unable to locate llvm-objdump"; exit 1; }
fi

cmake_extra_defines=
if [[ -n "$LLDB_LIB_DIR" ]]; then
    cmake_extra_defines="$cmake_extra_defines -DWITH_LLDB_LIBS=$LLDB_LIB_DIR"
fi
if [[ -n "$LLDB_INCLUDE_DIR" ]]; then
    cmake_extra_defines="$cmake_extra_defines -DWITH_LLDB_INCLUDES=$LLDB_INCLUDE_DIR"
fi
if [[ -n "$CROSSCOMPILE" ]]; then
    if ! [[ -n "$ROOTFS_DIR" ]]; then
        echo "ROOTFS_DIR not set for crosscompile"
        exit 1
    fi
    if [[ -z $CONFIG_DIR ]]; then
        CONFIG_DIR="$1/cross"
    fi
    export TARGET_BUILD_ARCH=$build_arch
    cmake_extra_defines="$cmake_extra_defines -C $CONFIG_DIR/tryrun.cmake"
    cmake_extra_defines="$cmake_extra_defines -DCMAKE_TOOLCHAIN_FILE=$CONFIG_DIR/toolchain.cmake"
fi

if [ "${__ObjWriterBuild}" = 1 ]; then
    cmake_extra_defines="$cmake_extra_defines -DOBJWRITER_BUILD=${__ObjWriterBuild} -DCROSS_BUILD=${__CrossBuild}"
fi

if [ "$build_arch" = "wasm" ]; then
    emcmake $CMAKE \
        "-DEMSCRIPTEN_GENERATE_BITCODE_STATIC_LIBRARIES=1" \
        "-DCMAKE_TOOLCHAIN_FILE=$EMSCRIPTEN/cmake/Modules/Platform/Emscripten.cmake" \
        "-DCLR_CMAKE_TARGET_ARCH=$build_arch" \
        "-DCMAKE_BUILD_TYPE=$build_type" \
        "$1/src/Native"
else
    $CMAKE \
        "-DCMAKE_AR=$llvm_ar" \
        "-DCMAKE_LINKER=$llvm_link" \
        "-DCMAKE_NM=$llvm_nm" \
        "-DCMAKE_OBJDUMP=$llvm_objdump" \
        "-DCMAKE_RANLIB=$llvm_ranlib" \
        "-DCMAKE_BUILD_TYPE=$build_type" \
        "-DCLR_CMAKE_TARGET_ARCH=$build_arch" \
        $cmake_extra_defines \
        "$1/src/Native"
fi
