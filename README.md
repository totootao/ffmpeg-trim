# ffmpeg-trim —— 仅做"裁剪"的最小 FFmpeg

一个 **全静态、零重编码** 的裁剪工具(基于 FFmpeg 7.1.1,musl 静态链接):
对 **MP3 / MKV / AVI / MP4 / TS** 做 `-ss / -t / -to` 时间裁剪,数据**原样搬运(stream copy)**——
不解码、不重编码、不转格式(当然也可以跨容器重封装),速度接近磁盘拷贝。

| 文件 | 架构 | 体积 |
|---|---|---|
| `ffmpeg` | x86_64 | 2.15 MB |
| `ffmpeg-aarch64` | ARM64 | 2.00 MB |

与"MP3 降码率"项目(`ffmpeg-mp3-32k`)完全独立:本项目**没有任何音频/视频编码器**,
不做转码,`-c:v/-c:a` 以外的一切编解码能力被裁剪干净。

## 用法

```sh
chmod +x ffmpeg   # ARM 设备改用 ffmpeg-aarch64

# 保留 10s~25s 的片段(输出与输入同格式,-c copy 即"原样搬运")
./ffmpeg -ss 10 -to 25 -i input.mp4 -c copy clip.mp4

# 各容器同理:mkv / avi / ts / mp3
./ffmpeg -ss 60 -t 30 -i input.mkv -c copy clip.mkv    # 从 60s 剪 30 秒
./ffmpeg -ss 5  -t 15 -i input.mp3 -c copy clip.mp3
./ffmpeg -ss 0  -t 20 -i input.ts  -c copy clip.ts

# 跨容器重封装也是 copy(输出格式由文件名后缀决定)
./ffmpeg -i input.mp4 -c copy clip.mkv
./ffmpeg -i input.ts  -c copy clip.mp4
```

参数说明:`-ss` 起始时间,`-t` 持续时长,`-to` 结束时间点(两者取其一);均可带小数,如 `-ss 1.5`。

## 关键特性与限制(stream copy 的固有规则)

- **音频(MP3/AAC)裁剪精确**到音频帧(约 20ms)。
- **视频切点对齐关键帧**:`-c copy` 不能从任意帧开始;裁剪窗口内必须包含关键帧,
  实际产出可能比设定早/晚一个关键帧间隔(常见视频 1~5 秒)。
- **TS → MP4/MKV** 时尤其注意:TS 没有关键帧索引,若起点落在非关键帧且窗口内无关键帧,
  视频轨会被丢弃(音频不受影响)。广播流通常 1~5 秒一个 GOP,一般无碍;拿不准就先输出 TS。
- **重编码(任意帧精确裁剪、转码)不在本工具能力内**——那是体积和复杂度的另一极。
- 测试中 webm / flv 等未启用容器直接拒绝(`Invalid data found`),保持最小攻击面。

## 内置组件(刻意裁剪)

| 类别 | 内容 |
|---|---|
| 容器(demux+mux) | mp3、avi、mov/mp4、matroska/mkv、mpegts |
| 解码器 | aac / aac_latm(仅用于 TS 内 AAC 参数探测,配合 stream copy) |
| 解析器 | mpegaudio、aac、h264、hevc、ac3(分帧与时间戳) |
| 码流过滤器 | h264_mp4toannexb、hevc_mp4toannexb(→TS)、aac_adtstoasc、extract_extradata |
| 关闭 | 一切编码器、视频解码器、网络、设备、滤镜链转码路径、ffprobe/ffplay |

## 验证结果(11/11 通过)

- 同格式裁剪:mp4→mp4(5.0s)、mkv→mkv、ts→ts、avi→avi(10.0s)、mp3→mp3(15.0s)✓
- 跨容器:mp4→ts、ts→mp4(含关键帧窗口)、mkv→mp4、mp4→mkv ✓
- 负向:webm / flv 输入被拒绝 ✓
- 全静态:`ldd` → not a dynamic executable;aarch64 版经 qemu-aarch64 三个核心用例验证一致

## 重新编译

```sh
sh build.sh                 # x86_64(默认)
ARCH=aarch64 sh build.sh    # aarch64 交叉编译(自动用 musl 源码搭交叉工具链)
```

许可:FFmpeg 核心 LGPL-2.1+(本项目未链接 GPL 组件),详见 COPYING.LGPLv2.1。
