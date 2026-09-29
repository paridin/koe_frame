---
kind: operational
topic: koe-frame-transcript-review
---

# Transcript-review conventions

Read this before implementing any slice in this set. Work only in the
`koe_frame` repository; do not require sibling-repository files at runtime.

## Environment and build

- Base commit: KoeFrame `0.1.0-dev.2`, commit `9cee0baa070041d9d7c00e8c1c92d49b4e7ba2ba`.
- Run Mix commands from the repository root. The app targets Elixir `~> 1.19`
  and Phoenix `~> 1.8.15`.
- Req is already in `mix.exs`; the checked-in lock resolves Req `0.7.4`. Do not
  add another HTTP client or update dependencies in the pilot slice.
- Ffmpex `0.11.1` and Rambo `0.3.4` are already pinned. FFmpeg and FFprobe
  executables are supplied by the deployment environment; neither dependency
  bundles those executables.
- `mix test` creates the tenant schema and runs the wrapper migrations. A
  working PostgreSQL service is required.
- The preview needs `KOE_FRAME_SPEACHES_BASE_URL` and
  `KOE_FRAME_SPEACHES_MODEL`. The model defaults to the NAS pilot's
  `deepdml/faster-whisper-large-v3-turbo-ct2`. The base URL has no safe
  universal default; return a clear configuration error if it is absent.
- Bound both Req `request_timeout` and `receive_timeout` using
  `KOE_FRAME_SPEACHES_TIMEOUT_MS` (default 180,000 ms) and set `max_retries: 0`
  so a streamed inference request cannot hang or be silently repeated.
- The NAS pilot Speaches service is reachable on the private network without
  an API key. If authentication is enabled, return an unauthorized error and
  add a Vault-backed credential reference in a separate slice; do not add a
  plaintext key environment variable or embed credentials in the base URL.

## Ownership rules

- `Defdo.KoeFrame.MediaAnalysis` owns FFprobe inventory, global stream indexes,
  and FFmpeg extraction. Do not build FFmpeg command strings in the Mix task,
  transcript context, or tests.
- The transcript-review context owns input validation, temporary-file
  lifecycle, ASR adapter routing, normalized word timestamps, and cue overlap
  reporting. The Speaches URL/model are server configuration, never CLI input.
- The first pilot accepts a local absolute path only through the operator's
  `mix` command. Do not add an HTTP endpoint that accepts a server path.
- Speaches receives only the extracted WAV segment. Neither the original
  video nor subtitle text is sent to the Hub or another internet service.
- No transcript, audio, subtitle, or sample media belongs in source control.
  The task prints a report; it does not persist one unless the operator
  explicitly redirects stdout.
- Use stable tagged errors for invalid paths, unsupported streams, ASR
  transport failures, malformed JSON, and missing word timestamps. Do not
  leak Req or FFmpeg exceptions to callers.
- Keep the cue fields generic (`id`, `start_ms`, `end_ms`, `text`); do not add
  anime, episode, Sonarr, or NAS-library fields to the reusable cue shape.

## Language and framework rules

- Runtime modules use the `Defdo.KoeFrame` namespace; Mix tasks live under
  `Mix.Tasks.KoeFrame.*`.
- Validate the requested clip as positive integers and reject durations over
  60,000 ms before calling `MediaAnalysis.extract_audio_segment/6`.
- Select audio and subtitle streams only by the explicit FFprobe global index
  supplied by the operator. Never assume index 0 or 1 is the desired track.
- ASR timestamps are relative to the extracted WAV. Add the requested source
  start time exactly once, in integer milliseconds, before matching cues.
- Pair by interval overlap only. This is a timing aid, not semantic alignment;
  report zero matches and multiple matches honestly.
- Always remove generated files in an `after` block, including when Req or
  parsing fails. Use a unique temporary directory and never overwrite source
  media.
- Use `Req` (`0.7.4`) for HTTP. For the multipart file field, `Req` accepts a
  `File.Stream` as a form value and supports `:filename`/`:content_type` options
  (`Req.Steps.encode_body/1`, v0.7.4). Its request options include
  `request_timeout`, `receive_timeout`, and `max_retries` (`Req.new/1` docs,
  v0.7.4). Keep timeouts finite and bound the clip before streaming it.
- Do not use `String.to_atom/1` on user input.

## i18n

Slice 01 is a Mix command and adds no UI strings. If a later slice adds UI,
run `mix gettext.extract --merge` and remove `, fuzzy` from translations that
must be served at runtime.

## Tests

- Context, parser, alignment, and CLI tests live under
  `test/koe_frame/transcript_review*` and `test/mix/tasks/`.
- Use fake MediaAnalysis/ASR adapters and temporary generated SRT/WAV files.
  CI must not call the NAS, Speaches, or copyrighted media.
- The Speaches adapter test must exercise the multipart request/response
  contract through Req's test plug or an equivalent local stub; never depend
  on the private NAS service for unit tests.
- A real Aoyama 30-second smoke is an operator-run release check, not a CI
  gate. Verify that temporary outputs are removed after both success and
  failure.

## Ecosystem

KoeFrame's checked-in dependency set includes `defdo_migrator 0.4.1`,
`defdo_order 0.7.1`, `defdo_tenant 0.17.0`, and `defdo_vault 0.16.0`. Their
current capabilities are recorded in `.ai/capabilities.md` and in each
dependency's published package documentation. Slice 01 uses the existing
`MediaAnalysis` context and does not invoke the other Defdo packages.

## Ecosystem reference

The following exact APIs were read at the base commit; re-locate anchors before
editing because line numbers can move.

| Need | Existing API / source |
|---|---|
| Probe and preserve global stream indexes | `Defdo.KoeFrame.MediaAnalysis.probe/1` and `MediaInfo` in `lib/koe_frame/media_analysis.ex` and `media_info.ex` |
| Extract subtitle | `Defdo.KoeFrame.MediaAnalysis.extract_subtitle/4` in `lib/koe_frame/media_analysis.ex`; adapter uses output muxer `-f` and currently copies the codec |
| Extract ≤60s WAV | `Defdo.KoeFrame.MediaAnalysis.extract_audio_segment/6`; accepts `sample_rate` and `channels`, defaults to 16 kHz mono |
| Ffmpex command boundary | `Defdo.KoeFrame.MediaAnalysis.FfmpexAdapter.subtitle_command/4` and `audio_command/6`; both are `@doc false` testable command builders |
| Speaches STT | `POST {base_url}/v1/audio/transcriptions`, multipart `file` and `model`; NAS pilot also verified `language=ja`, `response_format=verbose_json`, `timestamp_granularities[]=word` |
| Req multipart | Req `0.7.4` `form_multipart` accepts `File.Stream` values and `{value, options}` with `filename`, `content_type`, `size`; verified from Req's v0.7.4 docs/source |
| Existing generic subtitle parser | Subtitler `0.1.10` `Subtitler.SRT.parse/1` returns `%{index, timing, lines}` but is `@moduledoc false` and not a dependency/API; do not compile against it in KoeFrame |

Speaches source reference: `https://github.com/speaches-ai/speaches/blob/master/docs/usage/speech-to-text.md`.
Req source reference: `https://req.hexdocs.pm/Req.Steps.html` (Req `0.7.4`).

## Verification loop

Run these commands in order from the app directory:

```sh
mix compile --warnings-as-errors
mix test test/koe_frame/transcript_review_test.exs
mix test test/koe_frame/transcript_review/speaches_adapter_test.exs
mix test test/koe_frame/media_analysis/ffmpex_adapter_test.exs
mix test
mix format --check-formatted
git diff --check
```

The actual-media smoke is documented in slice 01 and must never be substituted
for the fake-adapter suite.

## Git

- Implement one slice per branch/job and do not edit its committed document
  while the job is running.
- Never commit a video, audio segment, transcript, local endpoint config, or
  report generated from real media.
- Use one shell command per verification line; the slice runner executes lines
  individually, so do not use backslash continuations.
