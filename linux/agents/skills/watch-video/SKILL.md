---
name: watch-video
description: Ver un video que el usuario comparte: descargarlo, sacar frames y describir qué pasa en pantalla.
---

# Watch a video

I cannot decode video, but a video is just images in sequence, and I **can** read
images. Download it, cut frames, look at them. That is watching it.

Never answer "no puedo ver videos" without trying this first.

## 1. Download

```bash
cd /tmp && yt-dlp -f "best[ext=mp4]/best" -o "vid.%(ext)s" "<URL>"
```

Works for X, YouTube, Instagram, TikTok and most sites (`yt-dlp` is installed).

The local cobalt app (`~/Proyectos/cobalt`, port 8792) is **only the web UI**: it
has no local API (`POST /` returns the HTML shell). Do not build on it; `yt-dlp`
is the downloader. If a site needs login, say so and ask for the file.

## 2. Know what you got

```bash
ffprobe -v error -show_entries format=duration,size \
  -show_entries stream=codec_type,width,height -of default=noprint_wrappers=1 vid.mp4
```

If `duration` is larger than ~5 minutes, do not sample blindly: ask which part
matters, or cut the range with `-ss`/`-to`.

## 3. Frames

One still every `duration / 8` seconds keeps it to 8 readable images:

```bash
mkdir -p frames
ffmpeg -v error -i vid.mp4 -vf "fps=1/7,scale=720:-1" frames/f%02d.jpg
```

A single contact sheet is the fastest first look (2×2 of four moments):

```bash
ffmpeg -v error -i vid.mp4 \
  -vf "select='eq(n\,60)+eq(n\,420)+eq(n\,900)+eq(n\,1500)',scale=640:-1,tile=2x2" \
  -frames:v 1 -y grid.jpg
```

Then `read_image` on `grid.jpg`, and on individual frames when the on-screen text
is small. Frames are cheap; read more before guessing.

## 4. Report

- **What happens, in order**, with the second where each thing appears.
- **On-screen text, verbatim.** In UI demos that text *is* the payload.
- **What it implies**, one paragraph. Separate what is shown from what you infer.
- If audio carries the meaning (a talk, a voiceover) and there is a local STT
  (their `dictado` service), extract `-vn` audio and transcribe it. Otherwise say
  the audio was not used.

## Rules

- Do not describe anything you did not see in a frame. "A 0:12 aparece un menú"
  is fine; inventing the menu is not.
- If frames come out blank or too small to read, say so and change the sampling
  (more frames, bigger scale, a specific range) instead of filling the gap.
- Clean up: `/tmp/vid.mp4`, `/tmp/frames/`, `/tmp/grid.jpg` are disposable.
