#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset
set -o xtrace

INVESALIUS_SOURCE_FOLDER=$1

APPLICATION_NAME="InVesalius"
VERSION="3.1.99995"

PYTHON_VERSION="3.8.9"
OPENMP_VERSION="12.0.0"
SQLITE_VERSION="3350400"
GETTEXT_VERSION="0.21"
OPENSSL_VERSION="1.1.1k"

CACHE_FOLDER="$HOME/.cache/inv_package"
BASE_FOLDER=$PWD
PACKAGE_FOLDER="$BASE_FOLDER/$APPLICATION_NAME.app"
APP_FOLDER="$PACKAGE_FOLDER/Contents/Resources/app"
LIBS_FOLDER="$PACKAGE_FOLDER/Contents/Resources/libs"
PREFIX=$LIBS_FOLDER
COMPILATION_FOLDER=$(mktemp -d)
EXE_FOLDER=$PACKAGE_FOLDER/Contents/MacOS

PYTHON_BIN="$PREFIX/Python.framework/Versions/Current/bin/python3"

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

function compile_gettext() {
    local GETTEXT_URL="https://ftp.gnu.org/gnu/gettext/gettext-$GETTEXT_VERSION.tar.xz"
    local GETTEXT_TARGZ="gettext.tar.xz"
    export CC="/usr/bin/clang"
    pushd $COMPILATION_FOLDER
    download $GETTEXT_URL $GETTEXT_TARGZ
    tar xf $CACHE_FOLDER/$GETTEXT_TARGZ
    pushd "gettext-$GETTEXT_VERSION"
    local PARAMS=(
        --prefix=$PREFIX
        --disable-dependency-tracking
        --disable-debug
        --disable-silent-rules
        --with-included-gettext
        --with-included-glib
        --with-included-libcroco
        --with-included-libunistring
        --with-included-libxml
        --disable-csharp
        --disable-java
        --without-git
        --without-cvs
        --without-xz
    )
    ./configure ${PARAMS[@]}
    make
    make install
    popd
    popd
    unset CC   
}

function compile_openssl() {
    local OPENSSL_URL="https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz"
    local OPENSSL_TARGZ="openssl.tar.gz"
    export CC="/usr/bin/clang"
    pushd $COMPILATION_FOLDER
    download $OPENSSL_URL $OPENSSL_TARGZ
    tar xf $CACHE_FOLDER/$OPENSSL_TARGZ
    pushd openssl-$OPENSSL_VERSION
    local PARAMS=(
        --prefix=$PREFIX
        no-ssl3
        no-ssl3-method
        no-zlib
    )
    ./config ${PARAMS[@]}
    make
    make install
    popd
    popd
    unset CC
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
    # To not depends on gettext libintl
    sed -i '.original' 's/libintl.h//g' configure
    sed -i '.original' 's/ac_cv_lib_intl_textdomain=yes/ac_cv_lib_intl_textdomain=no/g' configure
    local PARAMS=(
        --prefix=$PREFIX
        --enable-framework=$PREFIX
        --with-openssl=$PREFIX
        --enable-ipv6
    )
    ./configure ${PARAMS[@]}
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

function install_python() {
    relocatable-python/make_relocatable_python_framework.py  --python-version=3.8.9 --destination=$PREFIX
}

function copy_app_folder() {
    cp -r $INVESALIUS_SOURCE_FOLDER $APP_FOLDER
    pushd $APP_FOLDER
    rm -rf .git*
    rm -rf docs/devel
    rm -rf docs/user_guide_figures
    rm -rf docs/*_source
    rm -rf po
    popd
}

function install_requirements() {
    pushd $APP_FOLDER
    $PYTHON_BIN -m pip install -r requirements.txt --no-warn-script-location
    popd
}

function compile_cython_code() {
    export CC="/usr/bin/clang"
    export CPP="/usr/bin/clang++"
    export CFLAGS="-I$PREFIX/include"
    export LDFLAGS="-L$PREFIX/lib"
    export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
    export CPPFLAGS="$CFLAGS"
    pushd $APP_FOLDER
    $PYTHON_BIN setup.py build_ext --inplace
    rm -rf build
    popd
}

function copy_plugins() {
    export CC="/usr/bin/clang"
    export CPP="/usr/bin/clang++"
    export CFLAGS="-I$PREFIX/include"
    export LDFLAGS="-L$PREFIX/lib"
    export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
    export CPPFLAGS="$CFLAGS"
    pushd $COMPILATION_FOLDER
    git clone https://github.com/tfmoraes/inv_plugin_test1.git
    mkdir -p $APP_FOLDER/plugins/
    cp -r inv_plugin_test1/change_spacing $APP_FOLDER/plugins/
    cp -r inv_plugin_test1/porous_creation $APP_FOLDER/plugins/
    cp -r inv_plugin_test1/remove_tiny_objects $APP_FOLDER/plugins/
    popd

    pushd $APP_FOLDER/plugins/porous_creation
    $PYTHON_BIN setup.py build_ext --inplace
    rm -rf build
    popd

    pushd $APP_FOLDER/plugins/remove_tiny_objects
    $PYTHON_BIN setup.py build_ext --inplace
    rm -rf build
    popd
}

function make_relocatable() {
    pushd $APP_FOLDER/invesalius_cy
    for so in *.so; do
        echo "Adding rpath to $so"
        install_name_tool -add_rpath "@loader_path/../../libs/lib/" $so
    done
    popd

    pushd $APP_FOLDER/plugins/porous_creation
    for so in *.so; do
        echo "Adding rpath to $so"
        install_name_tool -add_rpath "@loader_path/../../../libs/lib/" $so
    done
    popd

    pushd $APP_FOLDER/plugins/remove_tiny_objects
    for so in *.so; do
        echo "Adding rpath to $so"
        install_name_tool -add_rpath "@loader_path/../../../libs/lib/" $so
    done
    popd
}

function create_exe() {
    cp invesalius.c $COMPILATION_FOLDER
    pushd $COMPILATION_FOLDER
    clang invesalius.c -o invesalius
    cp invesalius $EXE_FOLDER
    popd
}

function copy_icon() {
    cp invesalius.icns $PACKAGE_FOLDER/Contents/Resources
}

function create_info_plist() {
        local FILENAME="$PACKAGE_FOLDER/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c "add CFBundlePackageType string APPL" $FILENAME
        /usr/libexec/PlistBuddy -c "add CFBundleInfoDictionaryVersion string 6.0" $FILENAME
        /usr/libexec/PlistBuddy -c "add CFBundleIconFile string invesalius.icns" $FILENAME
        /usr/libexec/PlistBuddy -c "add CFBundleName string $APPLICATION_NAME" $FILENAME
        /usr/libexec/PlistBuddy -c "add CFBundleDisplayName string $APPLICATION_NAME" $FILENAME
        /usr/libexec/PlistBuddy -c "add CFBundleExecutable string $APPLICATION_NAME" $FILENAME
        /usr/libexec/PlistBuddy -c "add CFBundleIdentifier string br.gov.cti.invesalius" $FILENAME
        /usr/libexec/PlistBuddy -c "add CFBundleVersion string $VERSION" $FILENAME
        /usr/libexec/PlistBuddy -c "add CFBundleGetInfoString string $VERSION" $FILENAME
        /usr/libexec/PlistBuddy -c "add CFBundleShortVersionString string $VERSION" $FILENAME
        /usr/libexec/PlistBuddy -c "add NSPrincipalClass string NSApplication" $FILENAME
        /usr/libexec/PlistBuddy -c "add NSMainNibFile string MainMenu" $FILENAME
}


function remove_unused_files() {
    rm -rf $PREFIX/include
}

create_folder_structures
#compile_sqlite
#compile_gettext
#compile_openssl
#compile_python
install_python
compile_openmp
copy_app_folder
install_requirements
compile_cython_code
copy_plugins
make_relocatable
create_exe
copy_icon
create_info_plist
remove_unused_files