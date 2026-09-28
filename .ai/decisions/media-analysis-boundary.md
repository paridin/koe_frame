---
kind: architecture
---

# Decision — KoeFrame owns media analysis; FFmpeg binaries belong to the runtime

**Date:** 2026-09-28
**Status:** Accepted for the first media-analysis slice

## Context

KoeFrame needs to inspect embedded audio/subtitle streams and extract bounded
segments before it can compare subtitles with ASR. Subtitler is a generic cue
and translation service and should not need video-container or NAS concerns.
Ffmpex 0.11.1 provides Elixir APIs over the FFmpeg/FFprobe command-line tools,
but it and its Rambo process helper do not supply those media executables.

## Decisions

1. KoeFrame owns `Defdo.KoeFrame.MediaAnalysis` and its adapter behaviour.
   The application owns the media path, stream index, extraction destination,
   and later Sonarr/Jellyfin workflow; Subtitler receives cues only after
   extraction and normalization.
2. The first adapter uses Ffmpex 0.11.1 for FFprobe and FFmpeg command
   construction/execution. Keep the library replaceable behind KoeFrame's
   behaviour.
3. The runtime image/operator supplies compatible `ffprobe` and `ffmpeg`
   executables on PATH. Do not download binaries at app boot or commit them.
   Image-level provisioning and smoke checks are a separate runtime-readiness
   task because each deployment target needs its own trusted binary build.
4. Raw media remains on the local/NAS side. Only selected, bounded text and
   context may later cross the approved Hub task API.

## Consequences

- The first slice tests argument construction and normalized metadata without
  requiring a real episode or live NAS.
- A later runtime-readiness slice must prove both executables exist in the
  actual KoeFrame image before claiming production media analysis is ready.
- Subtitler's public cue contract remains generic and contains no anime,
  container, stream-index, or filesystem details.
