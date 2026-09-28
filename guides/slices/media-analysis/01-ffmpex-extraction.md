---
kind: implementation
serves: [P-03]
skills: [defdo-architecture-boundary-guardian, defdo-exunit-quality-tests]
---

# Slice 01 — FFprobe inventory and bounded media extraction

## Ecosystem

- `uses: ffmpex@0.11.1` — call FFprobe and build/execute FFmpeg commands
  behind KoeFrame's adapter boundary. The package API is quoted below from
  the resolved `deps/ffmpex` source at version 0.11.1.
- `gap: FFmpeg/FFprobe executable provisioning — local to the KoeFrame runtime
  image; the image must provide compatible binaries on PATH. Do not download
  or bundle binaries in this slice. Rationale:
  `.ai/decisions/media-analysis-boundary.md`.

## Goal

After this slice, a KoeFrame caller can inventory a local media file's format
and streams, copy one selected subtitle stream, or extract one bounded audio
segment to WAV. Callers use one KoeFrame-owned API; product code does not
construct Ffmpex commands directly.

## Preconditions

- Read `00-conventions.md` and `.ai/decisions/media-analysis-boundary.md`.
- Dependency preparation commit `c56d2b2` already adds `ffmpex 0.11.1` and
  `rambo 0.3.4` to `mix.exs`/`mix.lock`. Do not run `mix deps.get`, edit
  `mix.lock`, or change those versions in this slice.
- The approved scenario is P-03 in `product.md`. This is internal plumbing;
  it adds no browser surface, so no browser acceptance test applies.
- Do not add database schemas, `defdo_order` steps, Hub calls, HTTP routes,
  Sonarr/Jellyfin calls, or real-episode media fixtures.

## Targets

The code and test paths were verified absent at KoeFrame `0.1.0` / commit
`c56d2b2`; re-locate before editing. `.ai/capabilities.md` is introduced by
this documentation set and must be updated by the implementation.

- `lib/koe_frame/media_analysis.ex` — NEW
- `lib/koe_frame/media_analysis/adapter.ex` — NEW
- `lib/koe_frame/media_analysis/media_info.ex` — NEW
- `lib/koe_frame/media_analysis/media_stream.ex` — NEW
- `lib/koe_frame/media_analysis/ffmpex_adapter.ex` — NEW
- `test/koe_frame/media_analysis_test.exs` — NEW
- `test/koe_frame/media_analysis/ffmpex_adapter_test.exs` — NEW
- `.ai/capabilities.md` — created by this slice set at `# KoeFrame capabilities`;
  update it with the API introduced here

## Step 1 — Define the application-owned contract

1. Add `Defdo.KoeFrame.MediaAnalysis.Adapter` with callbacks for `probe/1`,
   `extract_subtitle/4`, and `extract_audio_segment/6`.
2. Add `Defdo.KoeFrame.MediaAnalysis.MediaStream` and `MediaInfo` structs. Keep
   FFprobe's global stream index and normalize its string-keyed JSON metadata:
   codec type/name, language/title, default/forced disposition, video
   width/height, audio sample rate/channels, attached-picture state, container
   name, duration, and file size when present. Missing optional metadata stays
   nil; never invent a language or stream role.
3. Add `Defdo.KoeFrame.MediaAnalysis` as the public entry point. It must:
   - accept absolute existing regular input files only;
   - reject negative/non-integer stream indexes;
   - accept start offsets and durations only as non-negative/positive integer
     milliseconds; reject audio segments longer than 60,000 ms;
   - default audio extraction to 16,000 Hz mono and validate positive integer
     sample-rate/channel values;
   - require an absolute output path, an existing parent directory, and a
     nonexistent output file;
   - route through application config `:media_analysis_adapter`, defaulting
     to `Defdo.KoeFrame.MediaAnalysis.FfmpexAdapter`.
4. Return stable tagged errors for invalid input, including
   `:source_file_not_found`, `:source_path_must_be_absolute`,
   `:source_not_regular_file`, `:invalid_stream_index`, `:invalid_time_range`,
   `:segment_too_long`, `:invalid_audio_profile`,
   `:output_path_must_be_absolute`, `:output_directory_not_found`,
   `:output_already_exists`, `:probe_failed`, `:ffmpeg_unavailable`,
   `{:ffmpeg_failed, exit_status}`, `:output_not_created`, and
   `:output_empty`. Invalid input must fail before the adapter is called.
   Convert FFprobe/FFmpeg failures to these documented errors without leaking
   exceptions, command output, or media paths to callers.

## Step 2 — Implement the Ffmpex adapter

1. Implement probing through these APIs, verified against the installed
   Ffmpex 0.11.1 source (`deps/ffmpex/lib/ffprobe.ex`):

   ```elixir
   @spec FFprobe.format(binary) ::
           {:ok, FFprobe.format_map()} | {:error, :invalid_file} | {:error, :no_such_file}
   @spec FFprobe.streams(binary) ::
           {:ok, FFprobe.streams_list()} | {:error, :invalid_file} | {:error, :no_such_file}
   @spec FFmpex.execute(FFmpex.Command.t()) ::
           {:ok, binary()} | {:error, {Collectable.t(), non_neg_integer()}}
   @spec FFmpex.prepare(FFmpex.Command.t()) :: {binary() | nil, [binary()]}
   ```

   Call `FFprobe.format(source_path)` and `FFprobe.streams(source_path)` and
   normalize their string-keyed maps with pure functions. Keep Ffmpex structs
   out of the app contract.
2. Build subtitle extraction with explicit `-map 0:<stream_index>`, a subtitle
   stream specifier, `-c:s copy`, and FFmpeg no-overwrite mode. Copy the chosen
   subtitle stream without transcoding or guessing its language.
3. Build audio extraction with start/duration converted from integer
   milliseconds to seconds, an explicit `-map 0:<stream_index>`, WAV output,
   signed 16-bit PCM, and the validated sample rate/channel count. The public
   API rejects any segment longer than 60,000 ms. Do not hardcode Japanese,
   Spanish, or a stream number.
4. Return success only when execution succeeds and the output is a regular,
   non-empty file. Return a tagged error for command failure or missing output.
   Never modify the source file or overwrite an existing destination.

## Step 3 — Record the capability

Update `.ai/capabilities.md` in this slice. Document the exact `probe/1`,
`extract_subtitle/4`, and `extract_audio_segment/6` entry points, when to use
them, the Ffmpex implementation boundary, and the required runtime `ffmpeg`
and `ffprobe` executables. Do not claim ASR, cue parsing, Hub submission, or
production-image readiness.

## Tests

- `Defdo.KoeFrame.MediaAnalysisTest` proves adapter routing, supported defaults,
  and that invalid paths/indexes/ranges/oversized segments/profiles/existing
  outputs are rejected before adapter invocation.
- `MediaInfo`/`MediaStream` normalization tests prove string-keyed FFprobe maps
  produce the documented structs and absent optional metadata remains nil.
- `FfmpexAdapterTest` command-shape tests use `FFmpex.prepare/1` and prove the
  selected subtitle stream is mapped/copied and selected audio is bounded and
  emitted as WAV/PCM at the requested profile.
- Capability checks prove `.ai/capabilities.md` describes the app API and
  executable requirement.
- Tests use fake adapters and small JSON maps. They do not require NAS access,
  a copyrighted media file, or a live FFmpeg binary.

## Verification

```sh
mix compile --warnings-as-errors
test -f lib/koe_frame/media_analysis.ex
test -f lib/koe_frame/media_analysis/adapter.ex
test -f lib/koe_frame/media_analysis/media_info.ex
test -f lib/koe_frame/media_analysis/media_stream.ex
test -f lib/koe_frame/media_analysis/ffmpex_adapter.ex
test -f test/koe_frame/media_analysis_test.exs
mix test test/koe_frame/media_analysis_test.exs
test -f test/koe_frame/media_analysis/ffmpex_adapter_test.exs
mix test test/koe_frame/media_analysis/ffmpex_adapter_test.exs
grep -qF 'probe/1' .ai/capabilities.md
grep -qF 'extract_audio_segment/6' .ai/capabilities.md
mix test
mix format --check-formatted
git diff --check
```

## Acceptance criteria

- [ ] `probe/1` returns normalized container/stream metadata for successful
      FFprobe results and a tagged error for failed probes.
- [ ] Invalid inputs are rejected before the configured adapter is invoked.
- [ ] Subtitle extraction maps the requested stream, copies subtitle data,
      refuses overwrite, and verifies non-empty output.
- [ ] Audio extraction maps the requested stream and emits bounded WAV/PCM at
      the validated sample rate and channel count.
- [ ] Source media is never modified; no media bytes or transcript are sent to
      the Hub.
- [ ] `.ai/capabilities.md` documents the public API and runtime executable
      requirement.
- [ ] Both focused tests, the full test suite, formatting, and `git diff --check`
      pass.

Two attempts with the same failed step/gate mean stop and report the command and
diagnostic; do not retry the same failure a third time.
