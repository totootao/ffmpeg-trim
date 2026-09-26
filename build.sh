#!/bin/sh
# =====================================================================
# 可复现构建脚本:ffmpeg-trim —— 仅裁剪(零重编码,-c copy)的最小 FFmpeg。
# 零编码器、零视频解码器,musl 静态链接,单文件约 2MB。
#
# v2 变更(2026-09,配合 tvtrim):
#   + 视频解析器 av1/vp8/vp9/mpeg4video/mpegvideo(webm 与 avi 裁剪的分帧能力)
#   + 容器 webm/flv/mpegps/mpegvideo/ogg/asf(输入输出)/h264、hevc 裸流/adts、latm
#   + 音频解码器 mp3/ac3/eac3/flac/opus/vorbis(仅解码用于静音检测,不重编码)
#   + 滤镜 silencedetect/volumedetect(自动定位片头片尾的静音边界)
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
# 优先官方 tarball;ffmpeg.org 不可达时自动回退 GitHub mirror(git archive)
if [ ! -d "ffmpeg-$FFMPEG_VER" ]; then
    if [ ! -f "ffmpeg-$FFMPEG_VER.tar.xz" ] || ! tar tf "ffmpeg-$FFMPEG_VER.tar.xz" >/dev/null 2>&1; then
        if wget -q --timeout=15 "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VER.tar.xz" 2>/dev/null; then
            tar xf "ffmpeg-$FFMPEG_VER.tar.xz"
        else
            echo "[build.sh] ffmpeg.org 不可达,改用 GitHub mirror…"
            rm -f "ffmpeg-$FFMPEG_VER.tar.xz"
            wget -q "https://ghproxy.totootao.top/https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n$FFMPEG_VER.tar.gz" -O mirror.tgz
            mkdir -p "ffmpeg-$FFMPEG_VER"
            tar xzf mirror.tgz -C "ffmpeg-$FFMPEG_VER" --strip-components=1
            rm -f mirror.tgz
        fi
    else
        tar xf "ffmpeg-$FFMPEG_VER.tar.xz"
    fi
fi

# ---------------- 配置:只留裁剪与探测所需 ----------------
TRIM_COMPONENTS="
    --enable-demuxer=mp3 --enable-muxer=mp3
    --enable-demuxer=avi --enable-muxer=avi
    --enable-demuxer=mov --enable-muxer=mp4
    --enable-demuxer=matroska --enable-muxer=matroska --enable-muxer=webm
    --enable-demuxer=mpegts --enable-muxer=mpegts
    --enable-demuxer=flv --enable-muxer=flv
    --enable-demuxer=mpegvideo --enable-demuxer=mpegps
    --enable-demuxer=h264 --enable-demuxer=hevc
    --enable-demuxer=ogg
    --enable-demuxer=asf --enable-muxer=asf
    --enable-muxer=adts --enable-muxer=latm
    --enable-muxer=null
    --enable-encoder=wrapped_avframe --enable-encoder=pcm_s16le
    --enable-decoder=aac --enable-decoder=aac_latm
    --enable-decoder=mp3 --enable-decoder=ac3 --enable-decoder=eac3
    --enable-decoder=flac --enable-decoder=opus --enable-decoder=vorbis
    --enable-parser=mpegaudio --enable-parser=aac --enable-parser=h264 --enable-parser=hevc --enable-parser=ac3
    --enable-parser=av1 --enable-parser=vp8 --enable-parser=vp9
    --enable-parser=mpeg4video --enable-parser=mpegvideo
    --enable-parser=opus --enable-parser=vorbis --enable-parser=flac
    --enable-bsf=h264_mp4toannexb --enable-bsf=hevc_mp4toannexb --enable-bsf=vvc_mp4toannexb
    --enable-bsf=aac_adtstoasc --enable-bsf=extract_extradata
    --enable-protocol=file
    --enable-filter=aresample --enable-filter=aformat --enable-filter=anull
    --enable-filter=silencedetect --enable-filter=volumedetect
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
echo "构建完成: $(pwd)/$OUT_NAME ($ARCH, 全静态)"
ls -la "$OUT_NAME"
echo "======================================================"
