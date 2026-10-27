# Changelog

## 0.1.0-dev.10 — 2026-10-26

### Changed

- Rework Admin status diagnostics into a compact service list with a clear
  overall state.
- Reshape speech model evaluation into a model workspace with a dedicated
  comparison bench and a separate experimental section.

## 0.1.0-dev.9 — 2026-10-26

### Changed

- Use the shared responsive admin shell for system status and speech models.
- Centralize admin LiveView state transitions and keep async effects outside
  the pure update functions.
- Update Bandit to 1.14.0 to clear reported security advisories.

## 0.1.0-dev.8 — 2026-10-26

### Added

- Add authenticated, resumable Tus uploads with tenant-scoped staging and
  SHA-256 verification.

### Updated

- Refresh compatible dependencies, including Decimal 3.2.0.
- Carry the dev.6 admin diagnostics and dev.7 IdP tenant-session fix into this
  media API candidate.

## 0.1.0-dev.7 — 2026-10-04

### Fixed

- Accept authenticated IdP sessions when the IdP and KoeFrame use distinct
  tenant namespaces; keep KoeFrame's tenant for local credential lookup.

## 0.1.0-dev.6 — 2026-10-03

### Added

- Add admin identity diagnostics and scope-protected system administration.
- Add a Japanese speech model lab with provider inventory, guarded downloads,
  temporary cross-provider comparisons, and optional character error rate.
- Add Cactus Whistle as an experimental native-provider candidate with visible
  evaluation and promotion blockers.

## 0.1.0-dev.5 — 2026-10-02

### Fixed

- Normalize the identity-service setup token before the installer sends its
  authorization request, and report malformed tokens as an installer error.

### Changed

- Update the installer to `defdo_tenant_provision_web` 0.3.3, requiring
  `defdo_tenant` 0.18.0 and compatible Vault and Theme Components dependencies.
- Update the runtime lock to `defdo_vault` 0.18.0,
  `defdo_tenant_boundary` 0.5.0, `defdo_migrator` 0.5.0, and `finch` 0.24.0.

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
