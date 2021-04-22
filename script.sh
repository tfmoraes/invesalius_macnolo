#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset
set -o xtrace

INVESALIUS_SOURCE_FOLDER=$1

APPLICATION_NAME="InVesalius"
PYTHON_VERSION="3.8.9"
OPENMP_VERSION="12.0.0"
SQLITE_VERSION="3350400"

CACHE_FOLDER="$HOME/.cache/inv_package"
BASE_FOLDER=$PWD
PACKAGE_FOLDER="$BASE_FOLDER/$APPLICATION_NAME.app"
APP_FOLDER="$PACKAGE_FOLDER/Contents/Resources/app"
LIBS_FOLDER="$PACKAGE_FOLDER/Contents/Resources/libs"
PREFIX=$LIBS_FOLDER
COMPILATION_FOLDER=$(mktemp -d)

cleanup() {
    echo "Cleaning up"
    rm -rf $COMPILATION_FOLDER
}

onerror() {
    echo "An error has occurred"
    cleanup
}
trap onerror ERR 
trap cleanup EXIT


function create_folder_structures () {
    mkdir -p $PACKAGE_FOLDER/Contents/{Resources,MacOS}
    mkdir -p $APP_FOLDER
    mkdir -p $LIBS_FOLDER
}


function download() {
    local url=$1
    local filename=$CACHE_FOLDER/$2
    mkdir -p $CACHE_FOLDER
    if  [ ! -f $filename ]; then
        curl -L $url -o $filename
    fi 
}

function compile_sqlite() {
    local SQLITE_URL="https://sqlite.org/2021/sqlite-autoconf-$SQLITE_VERSION.tar.gz"
    local SQLITE_TARGZ="sqlite.tar.gz"
    export CC="/usr/bin/clang"
    export CPPFLAGS="-DSQLITE_ENABLE_COLUMN_METADATA=1"
    export CPPFLAGS="$CPPFLAGS -DSQLITE_MAX_VARIABLE_NUMBER=250000"
    export CPPFLAGS="$CPPFLAGS -DSQLITE_ENABLE_RTREE=1"
    export CPPFLAGS="$CPPFLAGS -DSQLITE_ENABLE_FTS3=1 -DSQLITE_ENABLE_FTS3_PARENTHESIS=1"
    export CPPFLAGS="$CPPFLAGS -DSQLITE_ENABLE_JSON1=1"
    pushd $COMPILATION_FOLDER
    download $SQLITE_URL $SQLITE_TARGZ
    tar xf $CACHE_FOLDER/$SQLITE_TARGZ
    pushd "sqlite-autoconf-$SQLITE_VERSION"
    ./configure --prefix=$PREFIX -disable-dependency-tracking --enable-dynamic-extensions
    make install
    popd
    popd
    unset CC
    unset CPPFLAGS
}

function compile_python() {
    local PYTHON_URL="https://www.python.org/ftp/python/$PYTHON_VERSION/Python-$PYTHON_VERSION.tgz"
    local PYTHON_TARGZ="Python-$PYTHON_VERSION.tar.gz"
    export CC="/usr/bin/clang"
    export CFLAGS="-I$PREFIX/include"
    export LDFLAGS="-L$PREFIX/lib"
    export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
    export CPPFLAGS="$CFLAGS"
    pushd $COMPILATION_FOLDER
    download $PYTHON_URL $PYTHON_TARGZ
    tar xf $CACHE_FOLDER/$PYTHON_TARGZ
    pushd "Python-$PYTHON_VERSION"
    ./configure --prefix=$PREFIX --enable-framework=$PREFIX
    make
    make install
    popd
    popd
    unset CC
    unset CFLAGS
    unset CPPFLAGS
}

function compile_openmp() {
    local OPENMP_URL="https://github.com/llvm/llvm-project/releases/download/llvmorg-$OPENMP_VERSION/openmp-$OPENMP_VERSION.src.tar.xz"
    local OPENMP_TARGZ="openmp.tar.xf"
    local OPENMP_FOLDER="openmp-$OPENMP_VERSION.src"
    export CC="/usr/bin/clang"
    pushd $COMPILATION_FOLDER
    download $OPENMP_URL $OPENMP_TARGZ
    tar xf $CACHE_FOLDER/$OPENMP_TARGZ
    pushd $OPENMP_FOLDER
    cmake -DCMAKE_BUILD_TYPE=Debug -DCMAKE_INSTALL_PREFIX="$PREFIX" -DLIBOMP_INSTALL_ALIASES=OFF
    make install
    popd
    popd
    unset CC
}

create_folder_structures
#compile_sqlite
compile_python
compile_openmp