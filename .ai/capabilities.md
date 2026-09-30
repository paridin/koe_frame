# KoeFrame capabilities

## Current capabilities

- KoeFrame provides a Phoenix application, a versioned migrator, and the
  approved product boundary for media intake, localization orders, and library
  management.
- `Defdo.KoeFrame.MediaAnalysis` probes local media through Ffmpex/FFprobe and
  returns normalized container and stream metadata while preserving FFprobe's
  global stream indexes. It can copy a selected subtitle stream and extract a
  bounded WAV audio segment (up to 60 seconds, defaulting to 16 kHz mono).
- `Defdo.KoeFrame.Subtitler.normalize_srt/1` posts bounded SRT text to
  Subtitler's authenticated cue API and validates ordered cue IDs, millisecond
  ranges, and non-empty text. Its HTTP adapter resolves its bearer token from
  `defdo_vault` under the process's established tenant context, requires HTTPS
  in production, rejects redirects, and caps response bodies at 8 MiB. It
  sends no media bytes and performs no translation yet.
- `Defdo.KoeFrame.MediaIntake.Uploads` creates tenant-scoped upload sessions,
  reports committed offsets, appends bounded chunks, lists files in stable
  relative-path order, and finalizes only after whole-file SHA-256 validation.
- `Defdo.KoeFrame.MediaIntake.Staging` writes files into a configured local
  staging root. Temporary files use mode `0600` in `0700` directories;
  finalized files use `0640`, with KoeFrame-owned intake directories at `0750`
  and the configured media group.
- The intake finalizer publishes through KoeFrame's implementation of the
  `Defdo.Uploader.Adapter` contract. It does not choose a Sonarr root or final
  library destination.
- `Defdo.KoeFrame.MediaIntake.RelativePath` accepts safe paths relative to one
  generated intake directory; clients cannot select absolute server paths.
- KoeFrame's versioned migrator owns the upload-session schema. `defdo_tenant`
  owns tenant identity and supplies the process-context boundary.

## Use when

- A trusted KoeFrame workflow needs to inspect a local media file, copy an
  embedded subtitle stream, or extract a bounded audio segment.
- A server-side caller has already authenticated and restored tenant context,
  and needs to persist an upload session or stage verified file chunks.
- A workflow needs to normalize selected SRT cues through the generic
  Subtitler service.

## Not provided yet

- No upload HTTP route is registered. These modules must not be called from an
  unauthenticated client boundary.
- There is no Mac directory scanner/client, Tus endpoint, batch-completion
  action, retention worker, or Sonarr import planner yet.
- There is no ASR integration, spoken-word alignment screen, subtitle
  translation flow, Hub task submission, or final media-library placement.
- The runtime image must provide compatible `ffprobe` and `ffmpeg` binaries;
  Ffmpex/Rambo do not bundle them. Image and NAS runtime readiness must be
  verified separately from these application modules.

## Replaces

- KoeFrame media workflows use the adapter instead of building FFprobe/FFmpeg
  process commands in controllers, LiveViews, or domain workflows.
- Nothing in the operator workflow replaces `rsync` yet. Existing rsync usage
  remains the practical transfer path until the authenticated API and client
  are delivered.
- `defdo_uploader` supplies the storage-adapter boundary, not the resumable
  media-session protocol; KoeFrame owns that protocol and its NAS adapter.
- This does not replace Subtitler's generic cue contract or KoeFrame's future
  authenticated Hub task client.

## Integration boundary

- Call intake only after an HTTP or task edge establishes
  `Defdo.Tenant.Context`. Core code reads tenant identity from process state;
  callers cannot choose `tenant_id`, file modes, owner/group, or absolute paths
  through upload attributes.
- Keep Ffmpex behind `Defdo.KoeFrame.MediaAnalysis` and
  `Defdo.KoeFrame.MediaAnalysis.Adapter`.
- Pass only absolute source paths from trusted KoeFrame code to media analysis;
  do not accept arbitrary client paths or model-generated destinations at an
  HTTP boundary.
- Do not send media bytes to the Hub.
