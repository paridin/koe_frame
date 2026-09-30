---
kind: implementation
serves: [P-06]
skills: [defdo-architecture-boundary-guardian, defdo-exunit-quality-tests, defdo-package-architect]
---

# Slice 01 — Local ASR and subtitle alignment preview

## Goal

The operator can inspect the streams in a local media file, select one audio
and one subtitle stream, and request a 1–60 second transcript preview. KoeFrame
prints word-level transcript times on the source-video timeline and the
subtitle cues whose time ranges overlap those words.

The preview uses local FFmpeg extraction and the configured Speaches service;
it leaves the source untouched and removes its temporary WAV/SRT files.

## Preconditions

- Read `00-conventions.md`.
- Base release: KoeFrame `0.1.0-dev.3`, including the MediaAnalysis foundation
  from media pilot PR #1.
- `ffmpeg` and `ffprobe` must be on the operator's `PATH`.
- Subtitler's released `POST /api/cues/parse` contract must be reachable at a
  private service address. This slice consumes the HTTP JSON contract and
  does not add a compile-time dependency on the Subtitler repository.
- Set `KOE_FRAME_SPEACHES_BASE_URL` to a private Speaches endpoint and
  `KOE_FRAME_SPEACHES_MODEL` to an installed model. Do not put an endpoint or
  secret in CLI arguments or source control.
- This slice does not depend on the Hub task-job API or `defdo_order` and does
  not submit a translation task.

## Targets

Verified for the `0.1.0-dev.3` base release — re-locate before editing;
line numbers move, anchors do not.

- `lib/koe_frame/media_analysis.ex` — 212 lines, first definition at :1 — defmodule Defdo.KoeFrame.MediaAnalysis do
- `lib/koe_frame/media_analysis/ffmpex_adapter.ex` — 233 lines, first definition at :1 — defmodule Defdo.KoeFrame.MediaAnalysis.FfmpexAdapter do
- `.ai/capabilities.md` — 49 lines, `# KoeFrame capabilities`
- `test/koe_frame/media_analysis/ffmpex_adapter_test.exs` — 174 lines, subtitle command test at :88
- `lib/koe_frame/transcript_review.ex` — NEW
- `lib/koe_frame/transcript_review/adapter.ex` — NEW
- `lib/koe_frame/transcript_review/speaches_adapter.ex` — NEW
- `lib/koe_frame/transcript_review/subtitler_client.ex` — NEW
- `lib/koe_frame/transcript_review/alignment.ex` — NEW
- `lib/mix/tasks/koe_frame.transcript_review.ex` — NEW
- `README.md` — operator entry points and dependency order
- `.ai/capabilities.md` — update after implementation and tests
- `config/dev.exs` — Speaches and Subtitler settings for Mix
- `config/runtime.exs` — Speaches and Subtitler settings for releases
- `config/test.exs` — deterministic fake-adapter and Req test-plug settings
- `test/koe_frame/transcript_review_test.exs` — NEW
- `test/koe_frame/transcript_review/speaches_adapter_test.exs` — NEW
- `test/koe_frame/transcript_review/subtitler_client_test.exs` — NEW
- `test/mix/tasks/koe_frame.transcript_review_test.exs` — NEW

## Step 1 — convert the selected subtitle stream to SRT

1. Extend `MediaAnalysis.extract_subtitle/4` and its Ffmpex adapter so
   `output_format: nil` keeps codec-copy behavior and explicit
   `output_format: "srt"` transcodes the selected subtitle stream to SRT.
   ASS-to-SRT needs the SRT muxer (`-f srt`) and subtitle codec (`-c:s srt`).
   Preserve global stream mapping, no-overwrite behavior, and tagged errors.
2. Validate the selected subtitle codec before extraction. Support text codecs
   `ass`, `ssa`, and `subrip` for this pilot; return
   `{:error, :unsupported_subtitle_codec}` for unknown or bitmap codecs such
   as PGS/DVD subtitles instead of exposing an opaque FFmpeg exit status.
3. Correct the existing test at
   `test/koe_frame/media_analysis/ffmpex_adapter_test.exs:88`: its current
   `"srt"` case asserts codec copy and contradicts the requested conversion.
   Change it to an `.ass` destination with `output_format: nil` to cover
   same-format codec copy, then add a test named
   `converts ASS subtitle streams to SRT for cue parsing` for explicit SRT
   conversion. Both tests assert stream mapping and no-overwrite behavior.

## Step 2 — obtain normalized cues from Subtitler and normalize words

1. Add `TranscriptReview.SubtitlerClient` to POST the full extracted SRT text
   to `#{base_url}/api/cues/parse` as JSON `%{format: "srt", content: srt}`.
   Accept success only as `{"cues":[...]}` and validate each cue has a unique
   string `id`, integer `start_ms`/`end_ms` with `0 <= start_ms < end_ms`, and
   string `text`. Preserve Subtitler's cue IDs and text verbatim. Do not parse
   SRT or regenerate IDs in KoeFrame. Filter the returned full-track cue list
   to cues overlapping the requested source clip window
   `[clip_start_ms, clip_end_ms)` while preserving full cue times.
   Return `:subtitler_unavailable` for connection failures,
   `:subtitler_timeout` for timeouts, `{:subtitler_http_error, status}` for
   other non-2xx statuses, and `:invalid_subtitler_response` for malformed JSON
   or cue shapes. Do not include the body or SRT text in errors or logs.
2. Define transcript words with `text`, `start_ms`, and `end_ms` relative to
   the extracted WAV at the adapter boundary. Convert Speaches seconds to
   integer milliseconds once using `round(seconds * 1000)`. After conversion,
   reject a word when `start_ms < 0`, `start_ms >= duration_ms`,
   `end_ms < start_ms`, or `end_ms > duration_ms` with
   `{:error, :word_timestamp_outside_clip}`. Preserve zero-duration words
   inside the clip as point events. The context adds the source clip offset
   once before matching; do not modify adapter-relative times.
3. Add a pure interval-overlap aligner using half-open intervals `[start, end)`.
   Attach zero, one, or multiple cue IDs to each word based on overlap. For a
   zero-duration word at time `t`, match a cue when
   `cue.start_ms <= t < cue.end_ms`. Keep unmatched words and unmatched cues
   within the selected clip visible; do not infer semantic matches from text.
4. Keep cue IDs generic and document-local as returned by Subtitler. Keep
   `subtitle_stream_index` only in report metadata. ASS-to-SRT conversion may
   add markup such as `<font>`; preserve it in report text as data. Any later
   HTML presentation must escape cue text and never mark it safe.

## Step 3 — call the private Speaches transcription API

1. Add a `TranscriptReview.Adapter` behaviour and a Speaches implementation.
   Keep Req calls and provider-response parsing inside that adapter. The cue
   HTTP client is a separate transport module; do not add a cue parser or a
   second generic behaviour.
2. Post a multipart request to
   `#{base_url}/v1/audio/transcriptions` with fields `file`, `model`,
   `language`, `response_format=verbose_json`, and repeated
   `timestamp_granularities[]=word`. Stream the WAV instead of copying the
   complete file into a binary. Req `0.7.4` accepts a `File.Stream` as a
   multipart value and accepts `{value, options}` where options include
   `filename`; the pinned source is listed in `00-conventions.md`.
3. Normalize response `words` entries (`word`, `start`, `end`) and require
   numeric values where `0 <= start <= end`. If no word entries arrive, return
   `:word_timestamps_missing`; do not fall back to sentence-level timing.
   Return tagged errors for unavailable service, timeout, non-success HTTP,
   unauthorized response, malformed JSON, and malformed word entries. Do not
   include an HTTP body or configured base URL in error text.
4. Read endpoint, model, and timeout from KoeFrame application configuration
   with `Application.get_env/3`; adapters must not read environment variables
   directly. `config/dev.exs` reads `KOE_FRAME_SPEACHES_BASE_URL`,
   `KOE_FRAME_SPEACHES_MODEL`, `KOE_FRAME_SPEACHES_TIMEOUT_MS`,
   `KOE_FRAME_SUBTITLER_BASE_URL`, and `KOE_FRAME_SUBTITLER_TIMEOUT_MS` for Mix
   commands. `config/runtime.exs` reads the same values for release boot, and
   `config/test.exs` installs deterministic fake adapters and Req test plugs.
   Validate both timeouts as positive bounded integers and return a tagged
   configuration error when either private base URL is missing. Mix tasks use
   dev config; `runtime.exs` is not loaded by Mix.
   Default the model to NAS-tested
   `deepdml/faster-whisper-large-v3-turbo-ct2`. The endpoint is not a
   user-supplied URL. Bound both Req `request_timeout` and `receive_timeout`
   using `KOE_FRAME_SPEACHES_TIMEOUT_MS` (default 180,000 ms), set
   `max_retries: 0`, and keep the adapter replaceable through application
   config. Configure the cue client's timeout with
   `KOE_FRAME_SUBTITLER_TIMEOUT_MS` (default 30,000 ms), set both Req timeouts
   to it, and set `max_retries: 0` for that client as well.
   The NAS pilot does not require an API key. If the service returns 401/403,
   report unauthorized; do not add a plaintext token or disable auth.

Speaches documents `POST /v1/audio/transcriptions` with multipart `file` and
`model`. The NAS pilot verified `language`, `response_format`, and word
timestamp fields against its installed service; each returned word carries
`word`, `start`, and `end`. Do not send the original media or subtitle text to
Speaches.

## Step 4 — provide a safe local operator command

1. Add `mix koe_frame.transcript_review --file PATH --list-streams` to call
   `MediaAnalysis.probe/1` and print media duration plus each stream's global
   index, type, codec, language, and disposition as JSON. The operator selects
   tracks from this result; do not call `ffprobe` directly from the Mix task.
   Its public function `stream_inventory(path)` returns `{:ok, inventory}` or
   `{:error, tagged_reason}` and is also callable from a running release.
2. Add preview switches `--audio-stream`, `--subtitle-stream`,
   `--source-language`, `--start-ms`, and `--duration-ms`. Require every
   switch; validate an absolute regular file, audio/subtitle stream kinds,
   supported subtitle text codec, a two-letter source-language code,
   non-negative start, positive duration, and the 60,000 ms maximum before
   extraction. Require a finite, non-negative probed media duration. Convert
   FFprobe seconds to milliseconds with `floor(duration_seconds * 1000)` and
   reject a clip whose end exceeds that conservative value. Compare raw
   `codec_name` values against exactly `"ass"`, `"ssa"`, and `"subrip"`; do
   not assume the probe layer normalizes them. The endpoint and model remain
   application configuration.
3. Extract a 16 kHz mono WAV and selected subtitle SRT into a unique temporary
   directory. Run Speaches, request normalized cues from Subtitler, shift word
   times to the source timeline, then print one JSON report to stdout. Remove
   the directory in an `after` block on success and every error path. Report
   errors to stderr and return non-zero without printing a partial report.
   Provide public `TranscriptReview.stream_inventory/1` and `preview/1`
   functions. `preview/1` accepts a map with keys `path`, `audio_stream`,
   `subtitle_stream`, `source_language`, `start_ms`, and `duration_ms`, and
   returns `{:ok, report}` or `{:error, tagged_reason}`. The Mix task is only a
   development wrapper and must not run the `app.start` Mix requirement, Repo,
   or Oban. The release image has no Mix, so the NAS smoke invokes these
   functions through `bin/koe_frame rpc`.
4. Do not persist transcripts/cues or add a schema, migration, Oban worker,
   order, network route, or frontend in this pilot.

The report contains `source_language`, `model`, selected audio/subtitle stream
indexes, the source clip range, ordered words with absolute source
`start_ms`/`end_ms` and `cue_ids`, and ordered cues with `id`, `start_ms`,
`end_ms`, and `text` that overlap the selected clip. Keep
`subtitle_stream_index` as report metadata; generic cue IDs contain only a cue
ordinal, not a media stream index.

## Step 5 — document the implemented capability

Update `README.md` with the development `mix koe_frame.transcript_review`
entry point, and `.ai/capabilities.md` with the public inventory/preview
functions, the Subtitler cue API dependency, runtime configuration names, and
the fact that this pilot does not persist results. Remove the stale claim that
KoeFrame does not provide ASR or cue alignment. Keep capability claims limited
to behavior proven by the implementation and verification below.

## Tests

- `MediaAnalysis.FfmpexAdapterTest` — the new SRT case proves ASS conversion
  selects the requested stream and will not overwrite output; the corrected
  nil-format case proves codec-copy behavior.
- `TranscriptReviewTest` — fake extraction, HTTP cue response, and ASR prove
  stream selection, cue filtering, source-time offset, overlap IDs, unmatched
  words, and cleanup after success and adapter failure.
- `TranscriptReviewTest` — Subtitler errors, malformed cue JSON, duplicate cue
  IDs, and invalid cue ranges return tagged errors without a partial report.
- `TranscriptReviewTest` — zero-duration words match a containing cue as a
  point event; cues touching but not entering a half-open clip window are
  excluded.
- `TranscriptReviewTest` — invalid path/index/language/range, a clip past the
  probed media duration, and durations above 60,000 ms fail before extraction
  or ASR is called.
- `TranscriptReviewTest` — bitmap/unknown subtitle codecs return
  `:unsupported_subtitle_codec` before FFmpeg is called.
- `TranscriptReview.SpeachesAdapterTest` — local Req stub asserts multipart
  fields, file streaming, model/language, verbose JSON, word granularity,
  normalized millisecond times, and tagged timeout/status/schema errors.
- `TranscriptReview.SpeachesAdapterTest` — millisecond rounding is exact, and
  negative, reversed, or out-of-clip word timestamps (including a point at the
  clip end) return `:word_timestamp_outside_clip`.
- `TranscriptReview.SubtitlerClientTest` — a local Req plug proves the request
  shape, cue response validation, 4xx/5xx handling, and that response bodies
  are not copied into errors.
- `Mix.Tasks.KoeFrame.TranscriptReviewTest` — `--list-streams` includes media
  duration and global indexes; preview prints valid JSON; missing
  flags/provider failures return non-zero and no partial report.
- `mix test` — the full suite stays green with synthetic data only; no NAS,
  Speaches, or Aoyama media is needed.

## Verification

```sh
mix compile --warnings-as-errors
grep -qF 'transcript-review preview' .ai/capabilities.md
grep -qF 'converts ASS subtitle streams to SRT for cue parsing' test/koe_frame/media_analysis/ffmpex_adapter_test.exs
grep -qF 'defmodule Defdo.KoeFrame.TranscriptReview do' lib/koe_frame/transcript_review.ex
grep -qF 'timestamp_granularities[]' lib/koe_frame/transcript_review/speaches_adapter.ex
grep -qF 'defmodule Defdo.KoeFrame.TranscriptReview.SubtitlerClient do' lib/koe_frame/transcript_review/subtitler_client.ex
grep -qF 'def stream_inventory(' lib/koe_frame/transcript_review.ex
grep -qF 'mix koe_frame.transcript_review' README.md
grep -qF 'KOE_FRAME_SUBTITLER_BASE_URL' config/dev.exs
grep -qF 'KOE_FRAME_SUBTITLER_BASE_URL' config/runtime.exs
grep -qF 'KOE_FRAME_SUBTITLER_BASE_URL' config/test.exs
grep -qF 'defmodule Mix.Tasks.KoeFrame.TranscriptReview do' lib/mix/tasks/koe_frame.transcript_review.ex
test -f lib/koe_frame/transcript_review.ex
test -f lib/koe_frame/transcript_review/adapter.ex
test -f lib/koe_frame/transcript_review/speaches_adapter.ex
test -f lib/koe_frame/transcript_review/subtitler_client.ex
test -f lib/koe_frame/transcript_review/alignment.ex
test -f lib/mix/tasks/koe_frame.transcript_review.ex
test -f test/koe_frame/transcript_review_test.exs
mix test test/koe_frame/transcript_review_test.exs
test -f test/koe_frame/transcript_review/speaches_adapter_test.exs
mix test test/koe_frame/transcript_review/speaches_adapter_test.exs
test -f test/koe_frame/transcript_review/subtitler_client_test.exs
mix test test/koe_frame/transcript_review/subtitler_client_test.exs
test -f test/mix/tasks/koe_frame.transcript_review_test.exs
mix test test/mix/tasks/koe_frame.transcript_review_test.exs
mix test test/koe_frame/media_analysis/ffmpex_adapter_test.exs
mix test
mix format --check-formatted
git diff --check
```

## Manual NAS smoke

After automated gates pass, deploy a candidate release with both the configured
private Speaches endpoint and private Subtitler service address. The Aoyama file
must be mounted and readable inside the running KoeFrame release container;
KoeFrame's runtime image has no Mix. Do not copy media into the repository.
First inspect that file's own stream indexes through release RPC:

```sh
bin/koe_frame rpc 'case Defdo.KoeFrame.TranscriptReview.stream_inventory(System.fetch_env!("KOEFRAME_VIDEO")) do {:ok, inventory} -> IO.puts(Jason.encode!(inventory)); {:error, reason} -> IO.puts(:stderr, inspect(reason)) end'
```

Inject `KOEFRAME_VIDEO` into the release container environment before starting
or restarting the release. The RPC expression runs inside the already-running
BEAM; exporting a variable in a later `exec` shell does not change the BEAM's
environment. Select the audio and subtitle global indexes from the inventory
output, substitute those numbers as integer literals in the preview expression,
then run it through RPC:

```sh
bin/koe_frame rpc 'case Defdo.KoeFrame.TranscriptReview.preview(%{path: System.fetch_env!("KOEFRAME_VIDEO"), audio_stream: 1, subtitle_stream: 3, source_language: "ja", start_ms: 0, duration_ms: 30000}) do {:ok, report} -> IO.puts(Jason.encode!(report)); {:error, reason} -> IO.puts(:stderr, inspect(reason)) end'
```

Replace `1` and `3` with the selected global stream indexes from the inventory;
these example values are not defaults.

Using the default `deepdml/faster-whisper-large-v3-turbo-ct2` model, the binary
manual gate is: for each known Spanish cue range (5,910–9,480 ms and
13,190–18,490 ms), the report contains that cue and at least one ASR word
inside its corresponding speech passage (6,000–9,060 ms and 13,280–17,820 ms)
whose `cue_ids` contains that cue's returned `id`. A report with empty
`cue_ids` fails even if all words and cues are present. Review transcript
wording manually; this gate validates stream and timing association, not ASR
accuracy. Confirm the temporary directory is removed after the RPC call.

## Ecosystem

- uses: `Defdo.KoeFrame.MediaAnalysis@0.1.0-dev.3` — FFprobe global stream
  indexes and Ffmpex extraction; `output_format: "srt"` is extended in this
  slice to transcode subtitle streams.
- uses: `Req@0.7.4` — already locked; Speaches multipart transport.
- uses: Subtitler cue API — `POST /api/cues/parse`, HTTP JSON contract; this
  slice requires a released endpoint reachable on a private service address.
- uses: Speaches STT API — private endpoint; NAS-tested model is
  `deepdml/faster-whisper-large-v3-turbo-ct2`, configurable at runtime.
- boundary: Subtitler owns cue parsing, document-local IDs, integer timecodes,
  and normalized cue text; KoeFrame filters cues to the selected clip and owns
  media stream indexes and audio/source-time alignment.
- gap: Hub translation tasks — deferred until `defdo_memory_hub` task-job and
  callback releases are verified, as accepted in the root product boundary.
  This slice sends no task payload outside KoeFrame.

## Acceptance criteria

- [ ] `--list-streams` reports global FFprobe indexes and does not infer a
  preferred audio/subtitle stream.
- [ ] An ASS stream converts to SRT without changing existing subtitle-copy
  behavior.
- [ ] A 30-second preview returns word timestamps and overlapping cue IDs on
  the source-video timeline.
- [ ] KoeFrame obtains cues through the Subtitler HTTP contract and does not
  parse SRT or generate cue IDs itself.
- [ ] Invalid input, unsupported subtitle codec, malformed Speaches output,
  missing word timestamps, timeout, and HTTP failure return tagged errors and
  remove temporary files.
- [ ] Cue output contains only cues overlapping the clip; half-open interval
  boundary and zero-duration word behavior matches the documented rules.
- [ ] FFprobe duration is conservatively floored to milliseconds, Speaches
  timestamps are rounded once, and invalid/out-of-clip words return the
  documented tagged error.
- [ ] The CLI prints one valid JSON report on success and no partial report on
  failure; source video/subtitle bytes remain unchanged.
- [ ] No real Aoyama media/transcript, schema, Hub call, or secret is added to
  the diff.
- [ ] All verification commands pass and the manual NAS smoke confirms the
  selected streams and source-time windows after selecting indexes from the
  file's own probe output.
