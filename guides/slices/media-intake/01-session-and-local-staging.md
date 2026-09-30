---
kind: implementation
serves: [P-01]
skills: [defdo-migration-helper, defdo-package-schema-ownership, defdo-tenant-edge-contract, defdo-exunit-quality-tests, defdo-safe-test-data]
---

## Ecosystem

- `uses: defdo_tenant@0.17.0` — tenant process context and tenant FK migration helper.
- `uses: defdo_migrator@0.4.1` — KoeFrame version 2 upload-session schema.
- `uses: defdo_uploader@0.3.0` — final publish implements its `Adapter`
  contract; KoeFrame owns the NAS-specific filesystem adapter and session
  protocol.
- `gap: authenticated HTTP boundary — reserved for slice 02; no upload route is registered by this slice.`

# Slice MF-01 — Durable upload sessions and local staging

## Goal

An authenticated future caller with tenant context can create one upload session
per file, append bounded bytes from the committed offset, resume after a
process interruption, and finalize a file only after the server verifies its
whole-file SHA-256. The verified file lands below a server-configured staging
root with server-selected permissions and owner/group.

## Preconditions

- Read `00-conventions.md` and `../../../product.md` P-01.
- Product scenario P-01 was approved 2026-09-27.
- The server-side domain API is not an HTTP route; authentication and Tus
  transport are slice 02.

## Targets

- `lib/koe_frame/migrator.ex` — versioned schema owner; verified at baseline
  `0d50fe0` with version 1. Re-locate `current_version:` before editing.
- `lib/koe_frame/migrator/v02.ex` — tenant-owned upload schema; created by
  this slice. Re-locate with `rg --files lib/koe_frame/migrator`.
- `priv/repo/migrations/` — generated Ecto wrapper; create with
  `mix ecto.gen.migration add_media_uploads`, then delegate to version 2.
- `lib/koe_frame/media_intake/` — schema, safe relative-path validator,
  session context, and local staging; created by this slice.
- `config/runtime.exs` — requires production staging root and media UID/GID.
- `test/koe_frame/media_intake/uploads_test.exs` — tenant, offset, checksum,
  path-safety, and mode contract.

## Step 1 — Create tenant-owned session metadata

Create `koe_frame_media_uploads` in `Defdo.KoeFrame.Migrator.V02`, with a
tenant FK, intake UUID, relative path validated at the application boundary,
total length, committed offset,
expected lowercase SHA-256, and state. Add tenant/intake/path uniqueness and
database checks for offset bounds, digest shape, and allowed states.

The app-local wrapper must be generated with
`mix ecto.gen.migration add_media_uploads` and call
`Defdo.KoeFrame.Migrator.up(version: 2, prefix: "defdo_koe_frame")` and the
matching pinned `down(version: 2, ...)`. The down migration must refuse to
drop the table while any upload row exists.

## Step 2 — Make tenant context the write source

Implement `Defdo.KoeFrame.MediaIntake.Uploads` with:

```elixir
create_upload(map()) :: {:ok, Upload.t()} | {:error, term()}
get_upload(Ecto.UUID.t()) :: {:ok, Upload.t() | nil} | {:error, term()}
list_intake_uploads(Ecto.UUID.t()) :: {:ok, [Upload.t()]} | {:error, term()}
append_chunk(Ecto.UUID.t(), non_neg_integer(), binary()) :: {:ok, Upload.t()} | {:error, term()}
finalize_upload(Ecto.UUID.t()) :: {:ok, Upload.t()} | {:error, term()}
```

Read `Defdo.Tenant.Context.tenant_id/0`; refuse operations without context.
Ignore any caller-supplied `tenant_id`. Lock the upload row for each chunk,
require the submitted offset to equal the committed offset, and cap a chunk at
8 MiB. A repeated creation with the same intake/path/size/digest returns the
existing session; changed size or digest is an idempotency conflict.

## Step 3 — Isolate staging paths and validate directory names

Use `RelativePath.validate/1` to reject absolute paths, empty segments,
`.`/`..`, NUL, backslash, and segments over 255 bytes. Build temporary names
from tenant/upload UUIDs only. Join final relative names beneath
`<staging-root>/intakes/<tenant>/<intake>` and verify the expanded path remains
inside that root. Reject symlinked staging files/directories and do not
overwrite a staged destination. The root cannot be `/`, `/tmp`, a symlink,
sticky, or group/world-writable; its existing ancestors must already exist and
have no group/world-writable directories, including sticky shared directories.
KoeFrame creates only the final root when absent. An existing root must already
have mode `0750` and the configured media group; never chmod/chgrp a preexisting
configured root.

Use `Defdo.Uploader.Adapter` as the final storage boundary. Do not use
`Defdo.Uploader.Storage.put/3` for video: that API applies image policies and
S3/R2 asset storage. The KoeFrame filesystem adapter receives only a verified
staging source, a validated intake-relative object key, and server-owned root,
mode, and UID/GID configuration.

## Step 4 — Commit bytes and final permissions

Write partial data to `<staging-root>/uploads/<tenant>/<upload>.part`. Before
each append, compare the file size with the database offset; truncate any
uncommitted tail and continue from the committed offset. If the file is
shorter than the committed offset, return `:staging_data_lost`.

After the full length is committed, hash the file in bounded reads. On a digest
mismatch, persist `checksum_mismatch` and remove the private partial file. If
cleanup fails, return that cleanup error. On success, call the KoeFrame
filesystem adapter through the uploader contract. It links without replacing
an existing destination, syncs the file and parent directories before the
status commit, applies mode 0640 to media files, and uses mode 0750 for
directories owned by KoeFrame with the configured media group. This lets the
media service read and traverse the tree without granting the group write
access. The final path is still a review staging path, never a Sonarr library
path.

Production runtime must require `KOE_FRAME_STAGING_ROOT`,
`KOE_FRAME_MEDIA_UID`, and `KOE_FRAME_MEDIA_GID`. Reject startup on absent or
non-integer ownership values. No client input may set these values.

## Tests

- `Defdo.KoeFrame.MediaIntake.UploadsTest` resumes after a first chunk and
  proves the resulting file matches the whole digest and has mode 0640.
- The same test proves duplicate creation with identical inputs returns one
  session and an old offset is rejected with the current offset.
- Symlinked parent directories are rejected during both publication and staged
  verification; directory group permissions do not include write access.
- Unsafe staging roots are rejected before the application changes permissions.
- Unsafe paths are rejected before staging output is created.
- A bad whole-file digest persists `checksum_mismatch` and is not staged.
- A request that supplies another tenant ID still writes under process tenant;
  that other tenant cannot find or list the upload.
- Missing tenant context returns `:missing_tenant_context`.

## Verification

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test test/koe_frame/media_intake/uploads_test.exs
mix test
git diff --check
```

## Acceptance criteria

- [x] The app migrator is at version 2 and the generated wrapper pins version 2.
- [x] The upload table has a tenant FK, offset/digest/state constraints, and a unique tenant/intake/path index.
- [x] Every Repo operation in the intake context requires process tenant context.
- [x] The caller cannot set tenant, absolute staging path, final library path, mode, or owner.
- [x] Repeated chunks at the same stale offset cannot duplicate bytes or advance the database offset.
- [x] A final file is staged only if its complete SHA-256 matches.
- [x] Final publication uses `Defdo.Uploader.Adapter`; resumable sessions and
  the NAS filesystem adapter stay application-owned.
- [x] Current local evidence at `4ff2f2e`: formatting, test and production
  warnings-as-errors compilation, `mix test` (62 tests, 0 failures), release
  assembly, unused-dependency check, and `git diff --check` passed. The suite
  covers tenant-bound staging, unsafe paths and symlinks, permissions, media
  extraction command bounds, and redacted FFmpeg failures. A synthetic MKV
  smoke probes global stream indexes and extracts an SRT subtitle plus a
  0.5-second WAV segment.
- [x] An independent clean-checkout review at `4ff2f2e` reproduced the 62/0
  suite, compile checks, release assembly, and migration idempotency against a
  fresh test database. It found no active code findings.
- [x] Woodpecker pipeline #15 for `4ff2f2e` passed on 2026-09-30, including
  locked dependency resolution, tests, production assets setup/deploy, and
  release assembly.
- [ ] Remaining gate: run migrations through the actual release startup path,
  build the Docker image, configure and validate NAS UID/GID, and exercise the
  authenticated HTTP/Tus API, Mac folder client, and an interrupted
  multi-gigabyte transfer. P-01 remains incomplete.
