#!/bin/bash

#需要编译FFpmeg版本号
FF_VERSION="3.4.5"
SOURCE="ffmpeg-$FF_VERSION"
SHELL_PATH=`pwd`
FF_PATH=$SHELL_PATH/$SOURCE
#输出路径
PREFIX=$SHELL_PATH/FFmpeg_android
COMP_BUILD=$1

#需要编译的Android API版本
ANDROID_API=19
#需要编译的NDK路径，NDK版本需大等于r15c
NDK=/Users/zhaoliangtai/Downloads/android-ndk-r16b

#x264库路径
x264=$SHELL_PATH/x264_android
if [ "$x264" ] && [[ $FF_VERSION == 3.0.* ]] || [[ $FF_VERSION == 3.1.* ]]
then
echo "Use low version x264"
sh $SHELL_PATH/build-x264-android.sh
elif [ "$x264" ]
then
sh $SHELL_PATH/build-x264-android.sh last $ANDROID_API $NDK
fi

#需要编译的平台:arm arm64 x86 x86_64，可传入平台单独编译对应的库
ARCHS=(arm arm64 x86 x86_64)
TRIPLES=(arm-linux-androideabi aarch64-linux-android i686-linux-android x86_64-linux-android)
TRIPLES_PATH=(arm-linux-androideabi-4.9 aarch64-linux-android-4.9 x86-4.9 x86_64-4.9)

FF_CONFIGURE_FLAGS="--enable-static --disable-shared --enable-pic --enable-gpl --enable-postproc --disable-stripping --enable-small --enable-version3"

rm -rf "$SOURCE"
if [ ! -r $SOURCE ]
then
    echo "$SOURCE source not found, Trying to download..."
    curl http://www.ffmpeg.org/releases/$SOURCE.tar.bz2 | tar xj || exit 1
fi

#若使用android-ndk-r15c及以上NDK需要打此补丁(修改FFmepg与NDK代码冲突)
sh $SHELL_PATH/build-ffmpeg-patch.sh $FF_PATH

cd $FF_PATH
export TMPDIR=$FF_PATH/tmpdir
mkdir $TMPDIR
for i in "${!ARCHS[@]}";
do
    ARCH=${ARCHS[$i]}
    TOOLCHAIN=$NDK/toolchains/${TRIPLES_PATH[$i]}/prebuilt/darwin-x86_64
    SYSROOT=$NDK/platforms/android-$ANDROID_API/arch-$ARCH/
    ISYSROOT=$NDK/sysroot
    ASM=$ISYSROOT/usr/include/${TRIPLES[$i]}
    CROSS_PREFIX=$TOOLCHAIN/bin/${TRIPLES[$i]}-
    PREFIX_ARCH=$PREFIX/$ARCH

    if [ "$COMP_BUILD" = "" -o "$COMP_BUILD" = "$ARCH" ]
    then
        if [ "$ARCH" = "arm" ]
        then
            FF_EXTRA_CONFIGURE_FLAGS="--disable-asm"
            FF_EXTRA_CFLAGS="-fpic -ffunction-sections -funwind-tables -fstack-protector -march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3-d16 -fomit-frame-pointer -fstrict-aliasing -funswitch-loops -finline-limit=300"
        elif [ "$ARCH" = "arm64" ]
        then
            FF_EXTRA_CONFIGURE_FLAGS="--enable-asm"
            FF_EXTRA_CFLAGS=""
            ARCH="aarch64"
        elif [ "$ARCH" = "x86" -o "$ARCH" = "x86_64" ]
        then
            FF_EXTRA_CONFIGURE_FLAGS="--disable-asm"
            FF_EXTRA_CFLAGS="-Dipv6mr_interface=ipv6mr_ifindex -fasm -Wno-psabi -fno-short-enums -fno-strict-aliasing -fomit-frame-pointer -march=k8"
        else
            echo "Unrecognized arch:$ARCH"
            exit 1
        fi

        if [ "$x264" ]
        then
            FF_EXTRA_CONFIGURE_FLAGS="$FF_EXTRA_CONFIGURE_FLAGS --enable-libx264 --enable-encoder=libx264"
            FF_EXTRA_CFLAGS="$FF_EXTRA_CFLAGS -I$x264/${ARCHS[$i]}/include"
            FF_LDFLAGS="-L$x264/${ARCHS[$i]}/lib"
        else
            FF_LDFLAGS=""
        fi
    else
        continue
    fi
    FF_CFLAGS="-I$ASM -isysroot $ISYSROOT -D__ANDROID_API__=$ANDROID_API -U_FILE_OFFSET_BITS -O3 -pipe -Wall -ffast-math -fstrict-aliasing -Werror=strict-aliasing -Wno-psabi -Wa,--noexecstack -DANDROID"

    ./configure \
    --prefix=$PREFIX_ARCH \
    --sysroot=$SYSROOT \
    --target-os=android \
    --arch=$ARCH \
    --cross-prefix=$CROSS_PREFIX \
    --enable-cross-compile \
    --disable-runtime-cpudetect \
    --cpu=cortex-a8 \
    --disable-doc \
    --disable-debug \
    --disable-ffmpeg \
    --disable-ffprobe \
    --disable-ffserver \
    --disable-decoders \
    --enable-decoder=aac \
    --enable-decoder=mjpeg \
    --enable-decoder=png \
    --enable-decoder=gif \
    --enable-decoder=mp3 \
    --enable-decoder=h264 \
    --enable-decoder=pcm_s16le \
    --disable-encoders \
    --enable-encoder=pcm_s16le \
    --enable-encoder=aac \
    --enable-encoder=mp2 \
    --disable-muxers \
    --enable-muxer=avi \
    --enable-muxer=flv \
    --enable-muxer=mp4 \
    --enable-muxer=m4v \
    --enable-muxer=mp3 \
    --enable-muxer=mov \
    --enable-muxer=h264 \
    --enable-muxer=wav \
    --enable-muxer=adts \
    --disable-demuxers \
    --enable-demuxer=mjpeg \
    --enable-demuxer=m4v \
    --enable-demuxer=gif \
    --enable-demuxer=mov \
    --enable-demuxer=avi \
    --enable-demuxer=flv \
    --enable-demuxer=h264 \
    --enable-demuxer=aac \
    --enable-demuxer=mp3 \
    --enable-demuxer=wav \
    --disable-protocols \
    --enable-protocol=rtmp \
    --enable-protocol=file \
    --enable-protocol=http \
    $FF_CONFIGURE_FLAGS \
    $FF_EXTRA_CONFIGURE_FLAGS \
    --extra-cflags="$FF_EXTRA_CFLAGS $FF_CFLAGS" \
    --extra-ldflags="$FF_LDFLAGS" \
    $ADDITIONAL_CONFIGURE_FLAG || exit 1
    make -j3 install || exit 1
    make distclean
    $TOOLCHAIN/bin/arm-linux-androideabi-ld -rpath-link=$SYSROOT/usr/lib -L$SYSROOT/usr/lib -L$PREFIX_ARCH/lib -soname libffmpeg.so -shared -nostdlib -Bsymbolic --whole-archive --no-undefined -o $PREFIX_ARCH/libffmpeg.so \
    $x264/arm/lib/libx264.a \
    $PREFIX_ARCH/lib/libavcodec.a \
    $PREFIX_ARCH/lib/libavfilter.a \
    $PREFIX_ARCH/lib/libswresample.a \
    $PREFIX_ARCH/lib/libavformat.a \
    $PREFIX_ARCH/lib/libavutil.a \
    $PREFIX_ARCH/lib/libswscale.a \
    $PREFIX_ARCH/lib/libpostproc.a \
    $PREFIX_ARCH/lib/libavdevice.a \
    -lc -lm -lz -ldl -llog --dynamic-linker=/system/bin/linker $TOOLCHAIN/lib/gcc/arm-linux-androideabi/4.9.x/libgcc.a
    rm -rf "$PREFIX_ARCH/share"
    rm -rf "$PREFIX_ARCH/lib/pkgconfig"
done

echo "Android FFmpeg bulid success!"


