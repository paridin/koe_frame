---
kind: implementation
---

# Media-analysis conventions

Read this file before implementing any slice in this set. Work only inside the
`koe_frame` repository; the runner must not depend on files in a sibling repo.

## Environment and build

- Run Mix commands from the repository root.
- `ffmpex 0.11.1` and `rambo 0.3.4` are already declared and pinned in
  `mix.exs`/`mix.lock` at the slice base. Do not run `mix deps.get` or change
  dependency versions in slice 01.
- `mix setup`, `mix test`, and `mix release` invoke `compile.rambo`. On Apple
  Silicon this compiles Rambo's helper; the helper is not an FFmpeg binary.
- KoeFrame's test alias creates the tenant schema and runs Ecto wrapper
  migrations before ExUnit. PostgreSQL must be available for `mix test`.
- This set has no `STATUS.md`; the approved P-03 product contract is in the
  root `product.md`, and current app capabilities are recorded in
  `.ai/capabilities.md` by slice 01.

## Ownership rules

- KoeFrame owns media probing, stream selection, extraction paths, and the
  application-facing adapter contract because it owns the media files and
  library workflow.
- Keep the Ffmpex implementation behind `Defdo.KoeFrame.MediaAnalysis` and its
  adapter behaviour. Do not make product workflows call `FFprobe` or build
  FFmpex commands directly.
- Subtitler stays generic: it consumes normalized cue data after extraction;
  it does not own video containers, stream indexes, or NAS paths.
- Do not send raw media or media bytes to the Hub. A future Hub task receives
  only bounded text and context through its approved task API.
- No schema, migration, uploader, Sonarr, or Jellyfin changes belong in slice
  01.

## Language and framework rules

- Keep runtime modules under `Defdo.KoeFrame`.
- Validate source/output paths and stream/time arguments at the app context
  edge before calling the adapter.
- Return stable tagged errors for invalid input and failed extraction. Do not
  leak exceptions from FFprobe/FFmpeg into callers.
- Do not overwrite an existing extraction output. Use FFmpeg's no-overwrite
  option and verify that a successful command produced a non-empty file.
- Preserve stream indexes and cue timings; do not infer that the first audio or
  subtitle stream is the Japanese/Spanish track.
- Use `String.to_existing_atom/1` only for known static atoms; never atomize
  stream metadata from a file.

## Ecosystem

- `uses: ffmpex@0.11.1` — installed package API used by this set; API notes and
  exact signatures are in slice 01.
- Existing Defdo app dependencies in `mix.lock`: `defdo_migrator 0.4.1`,
  `defdo_order 0.7.1`, `defdo_tenant 0.17.0`, and `defdo_vault 0.16.0`. Slice
  01 does not invoke them: it adds no tables, tenant-owned records, durable
  order, or credentials. Do not add them to this adapter's call chain.
- `gap: FFmpeg/FFprobe executable provisioning — the deployment image supplies
  the binaries on PATH; Ffmpex/Rambo do not bundle them. See
  `../../../.ai/decisions/media-analysis-boundary.md`.

## Tests

- API validation and adapter routing tests belong in
  `test/koe_frame/media_analysis_test.exs`.
- FFprobe normalization and FFmpex command-shape tests belong in
  `test/koe_frame/media_analysis/ffmpex_adapter_test.exs`.
- The automated suite must not require a copyrighted media file or a live NAS.
  Use fake adapter results/FFprobe maps and assert generated FFmpeg arguments.
- An actual-media smoke against the Aoyama file is a separate operator-run
  pilot; do not make it a CI gate.

## i18n

- Slice 01 adds no UI strings. If a later slice adds translatable strings, run
  `mix gettext.extract --merge` and review the generated PO files. Remove any
  `, fuzzy` marker from translations that must be served at runtime.

## Verification loop

Run these commands in this order from the app directory:

```sh
mix compile --warnings-as-errors
mix test test/koe_frame/media_analysis_test.exs
mix test test/koe_frame/media_analysis/ffmpex_adapter_test.exs
mix test
mix format --check-formatted
git diff --check
```

Every command above is also present in slice 01's executable verification
block. A green compile without the new module and tests is not completion.

## Git

- Implement one slice per job/commit. Do not edit the slice document while a
  job is running; the harness checks it against the submitted base.
- Do not commit media files, audio, transcripts, secrets, or local runtime
  configuration.
- If the same gate fails twice, stop and report the failing command and its
  full diagnostic; do not spend more iterations repeating it.
