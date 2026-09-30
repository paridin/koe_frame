# Changelog

## 0.1.0-dev.3 — 2026-09-30

### Added

- Add tenant-scoped resumable media intake with checksum-verified local staging
  and server-configured media file and directory permissions.
- Add FFprobe stream inventory and bounded subtitle/audio extraction through
  KoeFrame's FFmpex adapter.
- Add a generic Subtitler cue-normalization client with Vault-backed token
  lookup and bounded HTTP responses.

### Changed

- Run KoeFrame's versioned database migrations before the Docker container starts.
- Align dependency requirement ranges with the versions recorded in the lockfile.

### Fixed

- Reject tenant mismatches, unsafe upload IDs and paths, and symlinked recovery
  paths before writes; remove private partial files after checksum failure.

This is a server foundation. The authenticated HTTP/Tus upload route and Mac
folder client are not included.
