# Changelog

## Unreleased

### Security — decimal 3.2.0 (EEF-CVE-2026-97853)
- Dependencies updated to latest compatible versions: bandit 1.12.5 → 1.13.1, decimal 3.1.1 → 3.2.0, defdo_auth_client 0.11.1 → 0.12.0, defdo_migrator 0.5.0 → 0.5.1, defdo_order 0.7.1 → 0.8.0, defdo_theme_components 0.21.0 → 0.25.0, ex_ast 0.13.1 → 0.16.0, flop 0.29.0 → 0.29.1, oban 2.24.1 → 2.24.2, phoenix_pubsub 2.3.0 → 2.4.1, req 0.7.4 → 0.7.5, sourceror 1.12.3 → 1.12.4, spitfire 0.4.2 → 0.4.3, swoosh 1.28.1 → 1.29.0, tesla 1.21.3 → 1.22.0, thousand_island 1.5.0 → 1.6.0.

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
