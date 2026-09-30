---
kind: implementation
---

# Media intake conventions

Read this before implementing any slice in this set.

## Environment and build

- Work only in `koe_frame`; run Mix commands from that directory.
- `mix.exs` resolves Defdo packages from Hex. Do not add a path dependency to a
  sibling repository. The private `defdo_auth_client` package is not currently
  resolved by KoeFrame; resolve its package access before running slice 02.
- Do not run `mix deps.get` from a slice. The runner has no public network;
  resolve required packages before the slice starts and verify the intended
  versions in `mix.lock`.
- The test alias creates the `defdo_koe_frame` schema and runs Ecto wrapper
  migrations before ExUnit.

## Ownership rules

- KoeFrame owns media intake metadata, upload sessions, NAS layout, and its
  filesystem adapter. It implements `Defdo.Uploader.Adapter` from
  `defdo_uploader` for final publication. `defdo_tenant` owns tenant identity;
  `defdo_migrator` owns the migration engine; `defdo_vault` owns integration
  secret storage.
- Never edit generated files under `_build`, `deps`, or `priv/static/assets`.
- The staging root is server configuration. Never derive it from a request,
  client absolute path, or model output.
- Subtitler remains a generic subtitle service. Sonarr remains the source of
  truth for final series paths.

## Language and framework rules

- Keep server modules under `Defdo.KoeFrame` and Phoenix modules under
  `Defdo.KoeFrameWeb`.
- Establish tenant context at the request or task edge. Core intake modules
  read tenant from `Defdo.Tenant.Context`; they do not accept `tenant_id` as a
  business argument.
- A client path is a validated relative path under a server-generated intake
  root. Client input never selects an absolute destination, UID/GID, or mode.
- Persist only the committed offset. Filesystem bytes beyond that offset are
  truncated before the next accepted chunk.
- Finalize only after the complete file digest matches. Never overwrite an
  existing staged destination.
- Partial files use mode `0600` below owner-only `0700` upload directories.
  Published media files use `0640`; published directories use `0750`, remain
  owned by KoeFrame for future writes, and carry the configured media group for
  read/traverse access. The storage root cannot be `/`, `/tmp`, a symlink, a
  sticky directory, or an existing group/world-writable directory. Its
  ancestor directories cannot be group/world-writable, even when the sticky
  bit is set. The parent chain must already exist. KoeFrame creates only the
  final root directory; an existing root must already have mode `0750` and the
  configured media group, and is never chmod’d or chgrp’d by KoeFrame.
  Production config must supply media UID/GID.
- Do not add `skip_tenant_id` to business code.

## Ecosystem

- `uses: defdo_tenant@0.17.0` — tenant process context and migration helper.
- `uses: defdo_migrator@0.4.1` — app-owned versioned migrator.
- `uses: defdo_vault@0.16.0` — external integration secrets, not media bytes.
- `uses: defdo_uploader@0.3.0` — shared storage-adapter contract. The package
  does not own KoeFrame's resumable session/chunk protocol; the application
  supplies a filesystem adapter for its NAS path and permissions.
- `gap: upload HTTP authentication — use defdo_auth_client after its package
  resolves; register `koe_frame:media:write` in the tenant's auth scope catalog.`

## Tests

- Focused intake tests live in `test/koe_frame/media_intake/`.
- Run `mix test` for the full repository gate after focused tests.
- Tests using tenant-owned Repo data establish `Defdo.Tenant.Context` first.

## Verification loop

Run these in order from the app directory:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test test/koe_frame/media_intake/uploads_test.exs
mix test
git diff --check
```

Do not report P-01 complete from these tests alone; the later browser/client
slice needs an end-to-end interrupted transfer against a running API.

## Git

- Keep one feature branch or docs branch per independently reviewable slice.
- Generate Ecto wrapper migrations with `mix ecto.gen.migration <name>`.
- The wrapper delegates to `Defdo.KoeFrame.Migrator` with an explicit version;
  never hand-create a timestamped migration or use floating latest mode.
- Do not commit secrets, `.env`, media fixtures, or staged videos.
