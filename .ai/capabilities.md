# KoeFrame capabilities

## Current capabilities

- `Defdo.KoeFrame.MediaAnalysis` probes local media through Ffmpex/FFprobe,
  returns normalized stream metadata, extracts a selected subtitle stream, and
  extracts bounded PCM audio segments. Its entry points are `probe/1`,
  `extract_subtitle/4`, and `extract_audio_segment/6`. Audio extraction takes
  non-negative integer `start_ms` and positive integer `duration_ms`; duration
  is capped at 60,000 ms. Output defaults to 16 kHz mono WAV/PCM; requested
  profiles are bounded to 8–192 kHz and one to eight channels. Ffmpex stays
  behind the KoeFrame-owned adapter contract, and returned failures omit
  process output and media paths.
- `Defdo.KoeFrame.MediaIntake.Uploads` creates tenant-scoped upload sessions,
  reports committed offsets, appends bounded chunks, lists an intake in stable
  path order, and finalizes only after whole-file SHA-256 verification.
- `Defdo.KoeFrame.MediaIntake.Staging` writes into a configured local staging
  root. Temporary files use mode `0600` inside `0700` owner-only directories.
  Completed files use `0640`; KoeFrame-owned intake directories use `0750` and
  the configured media group. Final publication goes through the
  `Defdo.Uploader.Adapter` contract implemented by KoeFrame's filesystem
  adapter.
- `Defdo.KoeFrame.MediaIntake.RelativePath` accepts only safe paths relative to
  one generated intake directory. It does not choose a Sonarr root or final
  library destination.
- KoeFrame's versioned migrator owns the upload-session schema. `defdo_tenant`
  owns tenant identity and supplies the process-context boundary.

## Use when

- A trusted KoeFrame workflow needs to inspect a local media file, copy an
  embedded subtitle stream, or extract a bounded audio segment for analysis.
- A server-side caller has already authenticated and restored tenant context,
  and needs to persist an upload session or stage verified file chunks.
- A future HTTP/Tus controller needs an application-owned session and staging
  API.

## Not provided yet

- No upload HTTP route is registered. These modules must not be called from an
  unauthenticated client boundary.
- There is no Mac directory scanner/client, Tus endpoint, batch-completion
  action, retention worker, or Sonarr import planner yet.
- There is no route for final media-library placement. The current destination
  is a review staging tree only.
- ASR, cue parsing/translation, Hub task submission, Sonarr catalog matching,
  and final media import remain separate follow-up capabilities.
- The runtime image must provide compatible `ffprobe` and `ffmpeg` binaries;
  Ffmpex/Rambo do not bundle them.

## Replaces

- KoeFrame media workflows use the adapter instead of building FFprobe/FFmpeg
  process commands in controllers, LiveViews, or domain workflows.
- Nothing in the operator workflow replaces `rsync` yet. Existing `rsync`
  usage remains the practical transfer path until the authenticated API and
  client are delivered.
- `defdo_uploader` supplies the storage-adapter boundary, not the resumable
  media session protocol; KoeFrame owns that protocol and its NAS adapter.
- This does not replace Subtitler's generic cue contract or the future
  authenticated Hub task client.

## Integration boundary

- Call intake only after an HTTP or task edge establishes
  `Defdo.Tenant.Context`. Core code reads tenant identity from process state;
  callers cannot choose `tenant_id`, file modes, owner/group, or absolute
  paths through upload attributes.
- Keep Ffmpex behind `Defdo.KoeFrame.MediaAnalysis` and
  `Defdo.KoeFrame.MediaAnalysis.Adapter`.
- Pass only absolute source paths from trusted KoeFrame code to media analysis;
  do not accept arbitrary client paths or model-generated destinations at an
  HTTP boundary.
- Do not send media bytes to the Hub.
