# KoeFrame capabilities

## Current capabilities

- KoeFrame currently provides a Phoenix scaffold, a versioned migrator, and
  the approved product boundary for media intake, localization orders, and
  library management.
- The `Defdo.KoeFrame.MediaAnalysis` API and Ffmpex adapter are introduced by
  slice 01; after that slice passes its gates, this file must describe its
  probe, subtitle-extraction, and audio-segment-extraction entry points.

## Use when

- Use the KoeFrame media-analysis context to inventory a local media file's
  format and streams or extract a selected subtitle stream/audio segment.
- Call it from a KoeFrame workflow; do not call FFprobe/FFmpeg directly from a
  LiveView, controller, or future Subtitler module.

## Not provided

- ASR, subtitle cue parsing/translation, Hub task submission, Sonarr catalog
  matching, and final media import are separate follow-up capabilities.
- The runtime image must provide `ffprobe` and `ffmpeg`; this slice does not
  package or download those binaries.

## Replaces

- It replaces direct process-command construction in KoeFrame media workflows.
- It does not replace Subtitler's generic cue contract or KoeFrame's future
  authenticated Hub task client.

## Integration boundary

- Keep Ffmpex behind `Defdo.KoeFrame.MediaAnalysis` and
  `Defdo.KoeFrame.MediaAnalysis.Adapter`.
- Pass only absolute paths from trusted KoeFrame code; do not accept arbitrary
  client paths or model-generated destinations at an HTTP boundary.
- Do not send media bytes to the Hub.
