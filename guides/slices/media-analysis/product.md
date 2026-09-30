---
kind: product
topic: media-analysis
approved: 2026-09-27
approved_by: owner
approval_source: KoeFrame root product.md, P-03
---

# Media analysis — product scenario

## Who and why

The operator wants to inspect an episode's subtitle and audio tracks, compare
the existing translation with speech recognition, and then review a first
translation draft before asking the Hub to compare model candidates.

## P-03 — Translate and edit subtitle cues with context

1. Opens an episode and selects embedded or external subtitle cues.
2. Chooses source/target languages, audience style, glossary, and a context
   profile. The app can request story research through the Hub and review the
   source citations before using them.
3. KoeFrame uses a `defdo_order` workflow for the media-level order. KoeFrame
   and the standalone Subtitler service send the same bounded subtitle task
   type to the Hub; Subtitler keeps its own subtitle-job lifecycle.
4. Each task keeps cue IDs, timestamps, and order unchanged. The Hub validates
   the result and sends a signed callback to the registered consumer. KoeFrame
   resumes its matching order step; Subtitler updates its matching job. Each
   consumer retries only its failed batch.
5. Reviews and edits the output through the subtitle workflow, then exports a
   sidecar subtitle or prepares an external track for playback.

Done when: cue IDs and time ranges are unchanged, translation is editable,
and the result remains linked to the episode and the context revision used.

The root product scenario P-03 was approved by the owner on 2026-09-27. This
slice set does not change that scenario; it implements the media-analysis
foundation only.

## Out of scope for slice 01

- Calling Hub task-jobs, ACP translation, callbacks, or `defdo_order`.
- Sending raw video/audio to the Hub.
- ASR transcript quality evaluation or accepting a translation without human
  review.
- Writing into or replacing the original video file.
- A browser UI, Mac client, final Sonarr import path, or voice conversion.

## Ecosystem

- `uses: ffmpex@0.11.1` — FFprobe stream inventory and FFmpeg command builder;
  Ffmpex delegates to the installed `ffprobe` and `ffmpeg` executables.
- `gap: managed ffmpeg/ffprobe runtime — local to KoeFrame's deployment image;
  this first slice assumes the operator/runtime supplies compatible binaries
  on PATH. The image provisioning check is a separate runtime-readiness task.
