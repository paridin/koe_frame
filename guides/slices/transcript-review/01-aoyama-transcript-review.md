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
- Base commit includes KoeFrame `0.1.0-dev.2` MediaAnalysis from
  `9cee0baa070041d9d7c00e8c1c92d49b4e7ba2ba`.
- `ffmpeg` and `ffprobe` must be on the operator's `PATH`.
- Set `KOE_FRAME_SPEACHES_BASE_URL` to a private Speaches endpoint and
  `KOE_FRAME_SPEACHES_MODEL` to an installed model. Do not put an endpoint or
  secret in CLI arguments or source control.
- This slice does not depend on the Hub task-job API or `defdo_order` and does
  not submit a translation task.

## Targets

Verified at 0.1.0-dev.2 / `9cee0ba` — re-locate with grep before editing;
line numbers move, anchors do not.

- `lib/koe_frame/media_analysis.ex` — 212 lines, first definition at :1 — defmodule Defdo.KoeFrame.MediaAnalysis do
- `lib/koe_frame/media_analysis/ffmpex_adapter.ex` — 233 lines, first definition at :1 — defmodule Defdo.KoeFrame.MediaAnalysis.FfmpexAdapter do
- `.ai/capabilities.md` — 49 lines, `# KoeFrame capabilities`
- `test/koe_frame/media_analysis/ffmpex_adapter_test.exs` — 174 lines, subtitle command test at :88
- `lib/koe_frame/transcript_review.ex` — NEW
- `lib/koe_frame/transcript_review/adapter.ex` — NEW
- `lib/koe_frame/transcript_review/speaches_adapter.ex` — NEW
- `lib/koe_frame/transcript_review/cue_parser.ex` — NEW
- `lib/koe_frame/transcript_review/alignment.ex` — NEW
- `lib/mix/tasks/koe_frame.transcript_review.ex` — NEW
- `test/koe_frame/transcript_review_test.exs` — NEW
- `test/koe_frame/transcript_review/speaches_adapter_test.exs` — NEW
- `test/mix/tasks/koe_frame.transcript_review_test.exs` — NEW

## Step 1 — convert the selected subtitle stream to SRT

1. Extend `MediaAnalysis.extract_subtitle/4` and its Ffmpex adapter so
   `output_format: "srt"` transcodes the selected subtitle stream to SRT;
   retain codec-copy behavior for existing `nil`/same-format use. ASS-to-SRT
   needs the SRT muxer (`-f srt`) and subtitle codec (`-c:s srt`). Preserve
   global stream mapping, no-overwrite behavior, and tagged extraction errors.
2. Add an adapter test named
   `converts ASS subtitle streams to SRT for cue parsing`. Assert the selected
   global stream index, SRT codec/muxer, and no-overwrite behavior. Existing
   copy-mode tests must continue to pass.

## Step 2 — normalize cues and transcript words

1. Add an SRT parser for the extracted output. Return ordered maps with `id`,
   `start_ms`, `end_ms`, and `text`. Derive each cue ID from subtitle stream
   index plus cue ordinal. Preserve multiline text and reject malformed,
   negative, or end-before-start timestamps with a tagged error.
2. Define transcript words with `text`, `start_ms`, and `end_ms` relative to
   the extracted WAV at the adapter boundary. Convert Speaches seconds to
   integer milliseconds once. The context adds the source clip offset once
   before matching; do not modify adapter-relative times.
3. Add a pure interval-overlap aligner. Attach zero, one, or multiple cue IDs
   to each word based on time overlap. Keep unmatched words/cues in the report;
   do not infer semantic matches from text similarity.

## Step 3 — call the private Speaches transcription API

1. Add a `TranscriptReview.Adapter` behaviour and a Speaches implementation.
   Keep Req calls and provider-response parsing inside that adapter.
2. Post a multipart request to
   `#{base_url}/v1/audio/transcriptions` with fields `file`, `model`,
   `language`, `response_format=verbose_json`, and repeated
   `timestamp_granularities[]=word`. Stream the WAV instead of copying the
   complete file into a binary. Req `0.7.4` accepts a `File.Stream` as a
   multipart value and accepts `{value, options}` where options include
   `filename`; the pinned source is listed in `00-conventions.md`.
3. Normalize response `words` entries (`word`, `start`, `end`) and require
   numeric values where `0 <= start < end`. If no word entries arrive, return
   `:word_timestamps_missing`; do not fall back to sentence-level timing.
   Return tagged errors for unavailable service, timeout, non-success HTTP,
   unauthorized response, malformed JSON, and malformed word entries. Do not
   include an HTTP body or configured base URL in error text.
4. Read endpoint, model, and timeout from KoeFrame runtime configuration.
   Default the model to NAS-tested
   `deepdml/faster-whisper-large-v3-turbo-ct2`. The endpoint is not a
   user-supplied URL. Bound both Req `request_timeout` and `receive_timeout`
   using `KOE_FRAME_SPEACHES_TIMEOUT_MS` (default 180,000 ms), set
   `max_retries: 0`, and keep the adapter replaceable through application
   config.
   The NAS pilot does not require an API key. If the service returns 401/403,
   report unauthorized; do not add a plaintext token or disable auth.

Speaches documents `POST /v1/audio/transcriptions` with multipart `file` and
`model`. The NAS pilot verified `language`, `response_format`, and word
timestamp fields against its installed service; each returned word carries
`word`, `start`, and `end`. Do not send the original media or subtitle text to
Speaches.

## Step 4 — provide a safe local operator command

1. Add `mix koe_frame.transcript_review --file PATH --list-streams` to call
   `MediaAnalysis.probe/1` and print stream index, type, codec, language, and
   disposition as JSON. The operator selects tracks from this result; do not
   call `ffprobe` directly from the Mix task.
2. Add preview switches `--audio-stream`, `--subtitle-stream`,
   `--source-language`, `--start-ms`, and `--duration-ms`. Require every
   switch; validate an absolute regular file, audio/subtitle stream kinds,
   non-negative start, positive duration, and the 60,000 ms maximum before
   extraction. The endpoint and model remain server configuration.
3. Extract a 16 kHz mono WAV and selected subtitle SRT into a unique temporary
   directory. Run Speaches, parse cues, shift word times to the source
   timeline, then print one JSON report to stdout. Remove the directory in an
   `after` block on success and every error path. Report errors to stderr and
   return non-zero without printing a partial report.
4. Do not persist transcripts/cues or add a schema, migration, Oban worker,
   order, network route, or frontend in this pilot.

The report contains `source_language`, `model`, selected audio/subtitle stream
indexes, the source clip range, ordered words with absolute source
`start_ms`/`end_ms` and `cue_ids`, and ordered cues with `id`, `start_ms`,
`end_ms`, and `text`.

## Tests

- `MediaAnalysis.FfmpexAdapterTest` — the new SRT case proves ASS conversion
  selects the requested stream and will not overwrite output; current
  codec-copy tests prove no regression.
- `TranscriptReviewTest` — fake extraction/ASR proves stream selection, cue
  parsing, source-time offset, overlap IDs, unmatched words, and cleanup after
  success and adapter failure.
- `TranscriptReviewTest` — invalid path/index/range and durations above
  60,000 ms fail before extraction or ASR is called.
- `TranscriptReview.SpeachesAdapterTest` — local Req stub asserts multipart
  fields, file streaming, model/language, verbose JSON, word granularity,
  normalized millisecond times, and tagged timeout/status/schema errors.
- `Mix.Tasks.KoeFrame.TranscriptReviewTest` — `--list-streams` and preview
  print valid JSON; missing flags/provider failures return non-zero and no
  partial report.
- `mix test` — the full suite stays green with synthetic data only; no NAS,
  Speaches, or Aoyama media is needed.

## Verification

```sh
mix compile --warnings-as-errors
grep -qF 'transcript-review preview' .ai/capabilities.md
grep -qF 'converts ASS subtitle streams to SRT for cue parsing' test/koe_frame/media_analysis/ffmpex_adapter_test.exs
grep -qF 'defmodule Defdo.KoeFrame.TranscriptReview do' lib/koe_frame/transcript_review.ex
grep -qF 'timestamp_granularities[]' lib/koe_frame/transcript_review/speaches_adapter.ex
grep -qF 'defmodule Mix.Tasks.KoeFrame.TranscriptReview do' lib/mix/tasks/koe_frame.transcript_review.ex
test -f lib/koe_frame/transcript_review.ex
test -f lib/koe_frame/transcript_review/adapter.ex
test -f lib/koe_frame/transcript_review/speaches_adapter.ex
test -f lib/koe_frame/transcript_review/cue_parser.ex
test -f lib/koe_frame/transcript_review/alignment.ex
test -f lib/mix/tasks/koe_frame.transcript_review.ex
test -f test/koe_frame/transcript_review_test.exs
mix test test/koe_frame/transcript_review_test.exs
test -f test/koe_frame/transcript_review/speaches_adapter_test.exs
mix test test/koe_frame/transcript_review/speaches_adapter_test.exs
test -f test/mix/tasks/koe_frame.transcript_review_test.exs
mix test test/mix/tasks/koe_frame.transcript_review_test.exs
mix test test/koe_frame/media_analysis/ffmpex_adapter_test.exs
mix test
mix format --check-formatted
```

## Manual NAS smoke

After the automated gates pass and KoeFrame can reach the configured NAS
Speaches endpoint, run these commands against the Aoyama source file without
copying media into the repository:

```sh
mix koe_frame.transcript_review --file "$KOEFRAME_VIDEO" --list-streams
mix koe_frame.transcript_review --file "$KOEFRAME_VIDEO" --audio-stream 1 --subtitle-stream 3 --source-language ja --start-ms 0 --duration-ms 30000
```

Confirm the returned words have source times near the speech passages observed
at 6–9 s and 13–18 s, and that cues with ranges 5.91–9.48 s and 13.19–18.49 s
appear in the overlap results. Review transcript wording manually; the gate is
timing/track association, not an assertion that ASR is error-free. Confirm the
temporary directory is removed after the run.

## Ecosystem

- uses: `Defdo.KoeFrame.MediaAnalysis@0.1.0-dev.2` — FFprobe global stream
  indexes and Ffmpex extraction; `output_format: "srt"` is extended in this
  slice to transcode subtitle streams.
- uses: `Req@0.7.4` — already locked; Speaches multipart transport.
- uses: Speaches STT API — private endpoint; NAS-tested model is
  `deepdml/faster-whisper-large-v3-turbo-ct2`, configurable at runtime.
- gap: generic cue parser — local for this pilot as documented in
  `.ai/decisions/transcript-review-cue-contract.md`; move it to a shared
  Subtitler capability before a second consumer adopts it.
- gap: Hub translation tasks — deferred until `defdo_memory_hub` task-job and
  callback releases are verified. This slice sends no task payload outside
  KoeFrame.

## Acceptance criteria

- [ ] `--list-streams` reports global FFprobe indexes and does not infer a
  preferred audio/subtitle stream.
- [ ] An ASS stream converts to SRT without changing existing subtitle-copy
  behavior.
- [ ] A 30-second preview returns word timestamps and overlapping cue IDs on
  the source-video timeline.
- [ ] Invalid input, malformed Speaches output, missing word timestamps,
  timeout, and HTTP failure return tagged errors and remove temporary files.
- [ ] The CLI prints one valid JSON report on success and no partial report on
  failure; source video/subtitle bytes remain unchanged.
- [ ] No real Aoyama media/transcript, schema, Hub call, or secret is added to
  the diff.
- [ ] All verification commands pass and the manual NAS smoke confirms the
  selected streams and source-time windows.
