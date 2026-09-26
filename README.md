# ffmpeg-trim —— 仅做"裁剪"的最小 FFmpeg

一个 **全静态、零重编码** 的裁剪工具(基于 FFmpeg 7.1.1,musl 静态链接):
对 **MP3 / MKV / AVI / MP4 / TS / WebM / FLV** 做 `-ss / -t / -to` 时间裁剪,数据**原样搬运(stream copy)**——
不解码视频、不重编码、不转格式(当然也可以跨容器重封装),速度接近磁盘拷贝。

**v2 变更(2026-09,配合 [tvtrim](https://github.com/totootao/tvtrim) 剧集去头去尾):**

- 新增 `silencedetect` / `volumedetect` 滤镜 + `null` muxer:
  可跑 `ffmpeg -i in.mp4 -af silencedetect=n=-40dB:d=0.5 -f null -` 定位静音边界,
  用于**自动识别片头/片尾**(音轨解码:mp3/ac3/eac3/flac/opus/vorbis 已启用)
- 新增视频解析器 av1/vp8/vp9/mpeg4video/mpegvideo(分帧能力,不改解码)
- 新增容器:webm(mux)/flv/ogg/mpegps/mpegvideo/h264、hevc 裸流/asf(wmv)/adts/latm
- 体积从 2.15 MB 增至 2.86 MB,仍然单文件全静态

| 文件 | 架构 | 体积 |
|---|---|---|
| `ffmpeg` | x86_64 | 2,994,224 字节(2.86 MB) |
| `ffmpeg-aarch64` | ARM64 | 2,690,944 字节(2.57 MB) |

与"MP3 降码率"项目(`ffmpeg-mp3-32k`)完全独立:本项目**没有任何视频解码器和音视频编码器**,
不做转码,裁剪永远走 `-c copy`。

## 用法

```sh
chmod +x ffmpeg   # ARM 设备改用 ffmpeg-aarch64

# 保留 10s~25s 的片段(输出与输入同格式,-c copy 即"原样搬运")
./ffmpeg -ss 10 -to 25 -i input.mp4 -c copy clip.mp4

# 各容器同理:mkv / avi / ts / mp3 / webm / flv
./ffmpeg -ss 60 -t 30 -i input.mkv -c copy clip.mkv    # 从 60s 剪 30 秒
./ffmpeg -ss 5  -t 15 -i input.ts  -c copy clip.ts
./ffmpeg -ss 0  -t 20 -i input.avi -c copy clip.avi

# 跨容器重封装也是 copy(输出格式由 -f 指定)
./ffmpeg -i input.mp4 -c copy -f matroska clip.mkv
./ffmpeg -i input.ts  -c copy -f mp4      clip.mp4

# 静音检测(自动找片头/片尾边界;需要 null muxer + wrapped_avframe/pcm_s16le 伪编码器)
./ffmpeg -i episode.mp4 -af silencedetect=n=-40dB:d=0.5 -f null -
```

> **注意 `-ss` 的位置**:本构建会**忽略 `-i` 之前的 `-ss`**(实测行为),
> 裁剪请把 `-ss`/`-to` 都放在 `-i` 之后:
> `./ffmpeg -i in.mp4 -ss 5 -to 25 -c copy out.mp4` ✓

参数说明:`-ss` 起始时间,`-t` 持续时长,`-to` 结束时间点(两者取其一);均可带小数,如 `-ss 1.5`。

## 关键特性与限制(stream copy 的固有规则)

- **音频(MP3/AAC)裁剪精确**到音频帧(约 20ms)。
- **视频切点对齐关键帧**:`-c copy` 不能从任意帧开始;裁剪窗口内必须包含关键帧,
  实际产出可能比设定早/晚一个关键帧间隔(常见视频 1~5 秒)。
- **TS → MP4/MKV** 时尤其注意:TS 没有关键帧索引,若起点落在非关键帧且窗口内无关键帧,
  视频轨会被丢弃(音频不受影响)。广播流通常 1~5 秒一个 GOP,一般无碍;拿不准就先输出 TS。
- **webm 限制(上游固有行为)**:webm 的 VP8/VP9 视频在"完整搬运"时正常,
  但配合**输出侧 `-ss`**(即 `-i in.webm -ss 5 ...`)会静默丢弃全部视频帧
  (实测与完整版 FFmpeg 行为一致)。webm 输入建议先重封装为 mkv 再裁剪,或只信任音频结果。
- **重编码(任意帧精确裁剪、转码)不在本工具能力内**——那是体积和复杂度的另一极。

## 内置组件(刻意裁剪)

| 类别 | 内容 |
|---|---|
| 容器(demux) | mp3、avi、mov/mp4、matroska/webm、mpegts、flv、ogg、asf、mpegps、mpegvideo、h264/hevc 裸流 |
| 容器(mux) | mp3、avi、mp4、matroska、webm、mpegts、flv、asf、adts、latm、null |
| 解码器 | aac / aac_latm(音频探测)、mp3 / ac3 / eac3 / flac / opus / vorbis(静音检测用) |
| 解析器 | mpegaudio、aac、h264、hevc、ac3、av1、vp8、vp9、mpeg4video、mpegvideo、opus、vorbis、flac |
| 码流过滤器 | h264_mp4toannexb、hevc_mp4toannexb、vvc_mp4toannexb、aac_adtstoasc、extract_extradata |
| 滤镜 | aresample、aformat、anull、atrim、trim、crop、hflip、vflip、transpose、rotate、**silencedetect**、**volumedetect** |
| 编码器 | 仅 wrapped_avframe / pcm_s16le 两个"伪编码器"(`-f null` 探测输出所需,不产出媒体文件) |
| 关闭 | 一切实体编码器、视频解码器、网络、设备、swscale、ffprobe/ffplay |

## 验证结果

- 同格式裁剪:mp4→mp4、mkv→mkv、ts→ts、avi→avi、mp3→mp3(全部精确,误差 <50ms)✓
- 跨容器:mp4→ts、ts→mp4、mkv→mp4、mp4→mkv、webm→mkv ✓
- 静音检测:2s 静音 + 4s 正弦 + 2s 静音样本,精确检出两段边界(x86_64 与 ARM64 结果一致)✓
- 全静态:`ldd` → not a dynamic executable;aarch64 版经 qemu-aarch64 三用例验证与 x86_64 一致 ✓

## 重新编译

```sh
sh build.sh                 # x86_64(默认)
ARCH=aarch64 sh build.sh    # aarch64 交叉编译(自动用 musl 源码搭交叉工具链)
```

> aarch64 交叉编译时 make 内置 strip 可能报 "Unable to recognise the format",
> 链接已成功,手动补一步即可:`cp -f ffmpeg_g ffmpeg && aarch64-linux-gnu-strip ffmpeg`

许可:FFmpeg 核心 LGPL-2.1+(本项目未链接 GPL 组件),详见 COPYING.LGPLv2.1。
