# KoeFrame capabilities

## Current capabilities

- KoeFrame provides a Phoenix application scaffold, a versioned migrator, and
  the approved product boundary for media intake, localization orders, and
  library management.
- `Defdo.KoeFrame.MediaAnalysis` provides local media inventory and bounded
  extraction through these entry points:
  - `probe/1` (`probe(source_path)`) returns normalized container metadata
    and streams, preserving each FFprobe global stream index.
  - `extract_subtitle/4`
    (`extract_subtitle(source_path, stream_index, output_path, output_format)`)
    copies the selected subtitle stream. Set `output_format` to `nil` to infer
    it from the destination extension.
  - `extract_audio_segment/6`
    (`extract_audio_segment(source_path, stream_index, start_ms, duration_ms,
    output_path, profile)`) writes a WAV segment no longer than 60 seconds.
    `profile` accepts `sample_rate` and `channels`, defaulting to 16,000 Hz
    mono.

## Use when

- Use the KoeFrame media-analysis context to inventory a local media file's
  format and streams or extract a selected subtitle stream/audio segment.
- Call it from a KoeFrame workflow; do not call FFprobe/FFmpeg directly from a
  LiveView, controller, or future Subtitler module.

## Not provided

- ASR, subtitle cue parsing/translation, Hub task submission, Sonarr catalog
  matching, and final media import are separate follow-up capabilities.
- The runtime image must provide compatible `ffprobe` and `ffmpeg` executables
  on `PATH`; Ffmpex and Rambo do not bundle them. This slice does not package
  or download binaries and does not establish production-image readiness.

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
