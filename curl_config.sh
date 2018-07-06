#!/bin/bash

set -e
SELF_SCRIPT="$0"
if [ -L "$SELF_SCRIPT" ]; then
    SELF_SCRIPT=$(readlink -e $SELF_SCRIPT)
fi
DIR_HERE=$(cd $(dirname $SELF_SCRIPT) && pwd)
DIR_HOME=$(cd ~ && pwd)

DIR_DOWNLOADS="$DIR_HERE/downloads"

DIR_OBJ="$DIR_HERE/obj"
mkdir -p $DIR_OBJ

DIR_SRC="$DIR_HERE/src"
mkdir -p $DIR_SRC

PLATFORM=$(uname -s)

source "$DIR_HERE/conf.inc"

XPATCH_TOOL="$DIR_HERE/xpatch/xpatch.py"

# $1 msg
abort()
{
    echo "ERROR: $1"
    exit 1
}

# $1: URL
download_once()
{
    local URL=$1
    local ARC_NAME=$(basename $URL)
    local DL_RET
    mkdir -p $DIR_DOWNLOADS
    if [ ! -f "$DIR_DOWNLOADS/$ARC_NAME" ]; then
        echo "Downloading $ARC_NAME ..."
        set +e
        curl -L --fail -o "$DIR_DOWNLOADS/$ARC_NAME" $URL
        DL_RET="$?"
        set -e
        if [ "$DL_RET" != "0" ] ; then
            rm -rf "$DIR_DOWNLOADS/$ARC_NAME"
            abort "URL '$URL' is not ready"
        fi
    fi
}

# $1: URL
# $2: Destination dir
# $3: Number of strip depth
untar_downloaded()
{
    local URL=$1
    local DEST_DIR=$2
    local STRIP_PREFIX
    if [ -n "$3" ]; then
        STRIP_PREFIX="--strip-components=$3"
    fi
    local ARC_NAME=$(basename $URL)
    local STAMP_FILE="$DIR_SRC/${ARC_NAME}.stamp"
    local DEST_PATH="$DIR_SRC/$DEST_DIR"
    if [ ! -f "$STAMP_FILE" ]; then
        rm -rf $DEST_PATH
        mkdir -p $DEST_PATH
        echo "Extracting $ARC_NAME ..."
        tar xzf "$DIR_DOWNLOADS/$ARC_NAME" $STRIP_PREFIX -C $DEST_PATH
        touch "$STAMP_FILE"
    fi
}

# $1: URL
# $2: Destination dir
unzip_downloaded()
{
    local URL=$1
    local DEST_DIR="$2"
    local ARC_NAME=$(basename $URL)
    local STAMP_FILE="$DIR_SRC/${ARC_NAME}.stamp"
    local DEST_PATH="$DIR_SRC/$DEST_DIR"
    if [ ! -f "$STAMP_FILE" ]; then
        rm -rf $DEST_PATH
        mkdir -p $DEST_PATH
        echo "Extracting $ARC_NAME ..."
        unzip "$DIR_DOWNLOADS/$ARC_NAME" -d $DEST_PATH
        touch "$STAMP_FILE"
    fi
}

# $1: src dir
# $2: build dir
# $3: ABI
# $4: prebuilt dir
configure_curl_for_abi()
{
    local SRC_DIR=$1
    local BUILD_DIR=$2
    local ABI=$3
    local PREBUILT_DIR=$4

    case $ABI in
            x86_64)
                XT_DIR="$HOME/x-tools/x86_64-unknown-linux-gnu/bin"
                XT_TARGET='x86_64-unknown-linux-gnu'
                ;;
            x86)
                XT_DIR="$HOME/x-tools/i686-unknown-linux-gnu/bin"
                XT_TARGET='i686-unknown-linux-gnu'
                ;;
            arm64)
                XT_DIR="$HOME/x-tools/aarch64-unknown-linux-gnueabi/bin"
                XT_TARGET='aarch64-unknown-linux-gnueabi'
                ;;
            arm)
                XT_DIR="$HOME/x-tools/arm-unknown-linux-gnueabi/bin"
                XT_TARGET='arm-unknown-linux-gnueabi'
                ;;
            *)
                abort "Unknown ABI: '$ABI'"
                ;;
    esac
    if [ ! -d "$XT_DIR" ]; then
        abort "cross-tools not configured for ABI '$ABI', directory '$XT_DIR' not found."
    fi

    local CC="${XT_DIR}/${XT_TARGET}-gcc"
    local CPP="${XT_DIR}/${XT_TARGET}-gcc -E"
    local AR="${XT_DIR}/${XT_TARGET}-ar"
    local RANLIB="${XT_DIR}/${XT_TARGET}-ranlib"
    local READELF="${XT_DIR}/${XT_TARGET}-readelf"

    local CFLAGS="-I${PREBUILT_DIR}/include"
    local CPPFLAGS=$CFLAGS
    local LDFLAGS="-L${PREBUILT_DIR}/libs/$ABI"
    local LIBS='-lssl -lcrypto -lz'

    rm -rf $BUILD_DIR
    mkdir -p $BUILD_DIR

    BUILD_ON_PLATFORM=$($SRC_DIR/config.guess)

    local CONFIGURE_WRAPPER="$BUILD_DIR/configure.sh"
    {
        echo "#!/bin/bash"
        echo 'set -e'
        echo ''
        echo "export CC='$CC'"
        echo "export CPP='$CPP'"
        echo "export CFLAGS='$CFLAGS'"
        echo "export CPPFLAGS='$CPPFLAGS'"
        echo "export LDFLAGS='$LDFLAGS'"
        echo "export LIBS='$LIBS'"
        echo "export AR='$AR'"
        echo "export RANLIB='$RANLIB'"
        echo "export READELF='$READELF'"

        echo ''
        echo 'cd $(dirname $0)'
        echo ''
        echo "exec $SRC_DIR/configure \\"
        echo "    --host=$XT_TARGET \\"
        echo "    --build=$BUILD_ON_PLATFORM \\"
        echo '    --with-zlib \'
        echo '    --with-ssl'

    } >$CONFIGURE_WRAPPER
   chmod +x $CONFIGURE_WRAPPER

   $CONFIGURE_WRAPPER
}

# $1: src dir
# $2: build dir
# $3: prebuilt dir
configure_curl_for_macosx()
{
    local SRC_DIR=$1
    local BUILD_DIR=$2
    local PREBUILT_DIR=$3

    local CFLAGS="-I${PREBUILT_DIR}/include"
    local CPPFLAGS=$CFLAGS
    local LDFLAGS="-L${PREBUILT_DIR}/libs/macosx/x86_64"
    local LIBS='-lssl -lcrypto -lz'

    rm -rf $BUILD_DIR
    mkdir -p $BUILD_DIR

    local CONFIGURE_WRAPPER="$BUILD_DIR/configure.sh"
    {
        echo "#!/bin/bash"
        echo 'set -e'
        echo ''
        echo "export CFLAGS='$CFLAGS'"
        echo "export CPPFLAGS='$CPPFLAGS'"
        echo "export LDFLAGS='$LDFLAGS'"
        echo "export LIBS='$LIBS'"
        echo "export DYLD_LIBRARY_PATH='${PREBUILT_DIR}/libs/x86_64'"

        echo ''
        echo 'cd $(dirname $0)'
        echo ''
        echo "exec $SRC_DIR/configure \\"
        echo '    --with-zlib \'
        echo '    --with-ssl'

    } >$CONFIGURE_WRAPPER
   chmod +x $CONFIGURE_WRAPPER

   $CONFIGURE_WRAPPER
}

# $1: src dir
# $2: build dir
configure_curl_native()
{
    local SRC_DIR=$1
    local BUILD_DIR=$2

    rm -rf $BUILD_DIR
    mkdir -p $BUILD_DIR

    local CONFIGURE_WRAPPER="$BUILD_DIR/configure.sh"
    {
        echo "#!/bin/bash"
        echo 'set -e'
        echo ''
        echo 'cd $(dirname $0)'
        echo ''
        echo "exec $SRC_DIR/configure \\"
        echo '    --with-zlib \'
        echo '    --with-ssl'

    } >$CONFIGURE_WRAPPER
   chmod +x $CONFIGURE_WRAPPER

   $CONFIGURE_WRAPPER
}

invoke_native_build()
{
    local OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    local ABI=$(uname -m | tr '[:upper:]' '[:lower:]')
    local CURL_OUTPUT_FILE="curl_config_${OS}_${ABI}.h"

    mkdir -p "$DIR_HERE/input-native"
    if [ ! -f "$DIR_OBJ/config-native.stamp" ]; then
        configure_curl_native "$DIR_SRC/curl" "$DIR_OBJ/curl-native"
        rm -f "$DIR_HERE/input-native/$CURL_OUTPUT_FILE"
        cp "$DIR_OBJ/curl-native/lib/curl_config.h" "$DIR_HERE/input-native/$CURL_OUTPUT_FILE"
        touch "$DIR_OBJ/config-native.stamp"
    fi
}

invoke_linux_final_build()
{
    mkdir -p "$DIR_HERE/input"
    mkdir -p "$DIR_HERE/output"
    for abi in $(echo $ABI_ALL | tr ',' ' '); do

        case $abi in
            x86)
                CURL_OUTPUT_FILE='curl_config_linux_i686.h'
                ;;
            arm64)
                CURL_OUTPUT_FILE='curl_config_linux_aarch64.h'
                ;;
            *)
                CURL_OUTPUT_FILE="curl_config_linux_${abi}.h"
                ;;
        esac

        if [ ! -f "$DIR_OBJ/config-${abi}.stamp" ]; then
            configure_curl_for_abi "$DIR_SRC/curl" "$DIR_OBJ/curl-$abi" $abi "$DIR_SRC/prebuilt"
            rm -f "$DIR_HERE/input/$CURL_OUTPUT_FILE"
            cp "$DIR_OBJ/curl-$abi/lib/curl_config.h" "$DIR_HERE/input/$CURL_OUTPUT_FILE"
            touch "$DIR_OBJ/config-${abi}.stamp"
        fi

        python "$XPATCH_TOOL" --config "$DIR_HERE/xpatch.ini"  --input "$DIR_OBJ/curl-$abi/lib/curl_config.h" --output "$DIR_HERE/output/$CURL_OUTPUT_FILE" --abi $abi
    done
}

invoke_macosx_build()
{
    mkdir -p "$DIR_HERE/input"
    mkdir -p "$DIR_HERE/output"
    if [ ! -f "$DIR_OBJ/config-macosx.stamp" ]; then
        configure_curl_for_macosx "$DIR_SRC/curl" "$DIR_OBJ/curl-macosx" "$DIR_SRC/prebuilt"
        rm -f "$DIR_HERE/input/curl_config_macosx.h"
        cp "$DIR_OBJ/curl-macosx/lib/curl_config.h" "$DIR_HERE/input/curl_config_macosx.h"
        touch "$DIR_OBJ/config-macosx.stamp"
    fi
    python "$XPATCH_TOOL" --config "$DIR_HERE/xpatch.ini"  --input "$DIR_OBJ/curl-macosx/lib/curl_config.h" --output "$DIR_HERE/output/curl_config_macosx.h" --abi macosx
}

download_once $CURL_URL
untar_downloaded $CURL_URL 'curl' 1

case $PLATFORM in
    Linux)
        download_once $PREBULT_LINUX_URL
        unzip_downloaded $PREBULT_LINUX_URL 'prebuilt'
        invoke_linux_final_build
        if [ -f "$DIR_HERE/input/curl_config_macosx.h" ]; then
            python "$XPATCH_TOOL" --config "$DIR_HERE/xpatch.ini" --input "$DIR_HERE/input/curl_config_macosx.h" --output "$DIR_HERE/output/curl_config_macosx.h" --abi macosx
        fi
        ;;
    Darwin)
        download_once $PREBULT_MACOSX_URL
        unzip_downloaded $PREBULT_MACOSX_URL 'prebuilt'
        invoke_macosx_build
        ;;
    *)
        abort "Unknown platform: '$PLATFORM'"
        ;;
esac

invoke_native_build
