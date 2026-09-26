#!/bin/sh
# =====================================================================
# 可复现构建脚本:ffmpeg-trim —— 仅裁剪(MP3/MKV/AVI/MP4/TS,-c copy)的
# 最小 FFmpeg。零编码器、零视频解码器,musl 静态链接。
#
# 用法:
#   sh build.sh                    # 默认 x86_64
#   ARCH=aarch64 sh build.sh       # 交叉编译 aarch64(自动搭 musl 交叉工具链)
# =====================================================================
set -e

ARCH="${ARCH:-x86_64}"
SRC_DIR="$(pwd)/src"
FFMPEG_VER=7.1.1
MUSL_VER=1.2.5

mkdir -p "$SRC_DIR"

# ---------------- 依赖 ----------------
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential pkg-config xz-utils wget

if [ "$ARCH" = "x86_64" ]; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y musl-tools
    CC="musl-gcc"
    FF_ARCH_FLAGS=""
else
    # aarch64:交叉 gcc + musl 源码自建交叉工具链
    DEBIAN_FRONTEND=noninteractive apt-get install -y gcc-aarch64-linux-gnu
    MUSL_PREFIX="$(pwd)/musl-aarch64"
    [ -x "$MUSL_PREFIX/bin/musl-gcc" ] || {
        [ -d "$SRC_DIR/musl-$MUSL_VER" ] || {
            wget -q "https://musl.libc.org/releases/musl-$MUSL_VER.tar.gz" -O "$SRC_DIR/musl.tgz"
            tar xf "$SRC_DIR/musl.tgz" -C "$SRC_DIR"
        }
        (cd "$SRC_DIR/musl-$MUSL_VER" \
            && ./configure ARCH=aarch64 --target=aarch64-linux-musl \
                 --prefix="$MUSL_PREFIX" CROSS_COMPILE=aarch64-linux-gnu- \
            && make -j"$(nproc)" && make install)
    }
    export PATH="$MUSL_PREFIX/bin:$PATH"
    export REALGCC=aarch64-linux-gnu-gcc
    CC="musl-gcc"
    FF_ARCH_FLAGS="--enable-cross-compile --target-os=linux --arch=aarch64"
fi

# ---------------- 源码 ----------------
cd "$SRC_DIR"
[ -f "ffmpeg-$FFMPEG_VER.tar.xz" ] || wget "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VER.tar.xz"
[ -d "ffmpeg-$FFMPEG_VER" ] || tar xf "ffmpeg-$FFMPEG_VER.tar.xz"

# ---------------- 配置:只留裁剪所需 ----------------
TRIM_COMPONENTS="
    --enable-demuxer=mp3 --enable-muxer=mp3
    --enable-demuxer=avi --enable-muxer=avi
    --enable-demuxer=mov --enable-muxer=mp4
    --enable-demuxer=matroska --enable-muxer=matroska
    --enable-demuxer=mpegts --enable-muxer=mpegts
    --enable-decoder=aac --enable-decoder=aac_latm
    --enable-parser=mpegaudio --enable-parser=aac --enable-parser=h264 --enable-parser=hevc --enable-parser=ac3
    --enable-bsf=h264_mp4toannexb --enable-bsf=hevc_mp4toannexb --enable-bsf=aac_adtstoasc --enable-bsf=extract_extradata
    --enable-protocol=file
    --enable-filter=aresample --enable-filter=aformat --enable-filter=anull
"

cd "$SRC_DIR/ffmpeg-$FFMPEG_VER"
make clean >/dev/null 2>&1 || true
./configure \
    --cc="$CC" $FF_ARCH_FLAGS \
    --prefix="$(pwd)/../stage" \
    --enable-static --disable-shared \
    --disable-everything --disable-autodetect \
    --disable-network --disable-doc --disable-debug \
    --disable-avdevice --disable-swscale --disable-postproc \
    --disable-ffprobe --disable-ffplay \
    --disable-zlib --disable-bzlib --disable-lzma --disable-iconv \
    --enable-small \
    $TRIM_COMPONENTS \
    --extra-ldflags="-static"
make -j"$(nproc)"

# aarch64 交叉编译时 make 的内置 strip 是主机的,需手动交叉 strip
if [ "$ARCH" = "aarch64" ]; then
    cp -f ffmpeg_g ffmpeg
    aarch64-linux-gnu-strip ffmpeg
fi

OUT_NAME="ffmpeg"
[ "$ARCH" = "aarch64" ] && OUT_NAME="ffmpeg-aarch64"
cp -f ffmpeg "$OUT_NAME"

echo "======================================================"
echo "构建完成: $(pwd)/$OUT_NAME ($ARCH, 全静态, 约 2MB)"
echo "======================================================"
