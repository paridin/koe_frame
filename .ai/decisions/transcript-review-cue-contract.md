---
kind: architecture
topic: koe-frame-transcript-review
---

# Keep the transcript-review pilot independent of Subtitler's app runtime

**Status:** accepted for the one-segment pilot, 2026-09-29.

## Decision

KoeFrame normalizes the extracted SRT cues into a small generic cue shape for
the transcript-review report. It does not add a compile-time dependency on
Subtitler or call Subtitler's private `Subtitler.SRT` module.

## Why

Subtitler `0.1.10` is a standalone Phoenix application. Its parser is marked
`@moduledoc false`, returns a parser-specific `%{index, timing, lines}` shape,
and its HTTP API accepts translation jobs rather than generic cue-parse
requests. Calling it would either couple KoeFrame to an unsupported module or
add a service hop just to parse text already extracted by KoeFrame.

KoeFrame owns the media stream selection and extraction. For this pilot, it
needs to preserve the FFprobe stream index as report metadata and move word
timings from the extracted-segment origin back to the video's source timeline.
The cue parser therefore stays at that app boundary and emits generic ordinal
IDs, integer millisecond ranges, and text. A media stream index is never part
of the cue ID or cue fields.

## Consequences

- The parser accepts the SRT output produced by KoeFrame's FFmpeg extraction;
  it does not parse containers or ASS directly.
- The Speaches adapter and cue parser are separate modules and behaviours so
  each can be replaced without changing the report contract.
- Before Subtitler or another consumer uses the cue type, extract the shared
  contract/parser into a package or publish a supported Subtitler API and
  migrate both consumers. This pilot is not permission to duplicate an
  app-private parser.
- The pilot stores no cue records and adds no migration.
- This slice stops at a synchronous segment of at most 60 seconds. The
  existing root product decision in `product.md` P-03/P-04 assigns durable
  full-track localization to `defdo_order` and bounded translation execution
  to the Hub. Those later workflows require the Hub task-job/callback release
  and a tested `pause_mode`/resume path; this pilot must not emulate them with
  polling, an Oban worker, or raw-media Hub requests.
