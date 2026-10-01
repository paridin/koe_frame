---
kind: architecture
topic: koe-frame-transcript-review
---

# Use Subtitler's supported cue contract from the transcript-review pilot

**Status:** accepted for the one-segment pilot, 2026-09-29; implemented against
the released Subtitler 0.1.11 cue API.

## Decision

Subtitler owns normalized cue IDs, times, and text. KoeFrame posts the extracted
SRT text to Subtitler's supported `POST /api/cues/parse` endpoint and consumes
its generic cue response. KoeFrame does not add a compile-time dependency on
Subtitler or call its private `Subtitler.SRT` module.

## Why

Subtitler `0.1.10` is a standalone Phoenix application. Its parser is marked
`@moduledoc false` and returns a parser-specific `%{index, timing, lines}`
shape; its current HTTP API has no generic cue-parse request. The new additive
cue API makes that capability reusable without coupling KoeFrame to the
private parser module or database.

KoeFrame owns media stream selection and extraction. It preserves the FFprobe
stream index as report metadata and moves word timings from the extracted
segment origin back to the video's source timeline. Subtitler emits generic
document-local cue IDs, integer millisecond ranges, and text. A media stream
index is never part of the cue ID or cue fields.

## Consequences

- KoeFrame converts selected embedded subtitles to SRT with FFmpeg and sends
  that text to Subtitler; Subtitler does not parse containers or ASS directly.
- The Speaches adapter owns its provider behavior. KoeFrame's Subtitler client
  is an HTTP transport module tested with a local Req plug; the pure alignment
  module has no behavior or external-service responsibility.
- Subtitler's cue API is reusable independently of anime, media stream indexes,
  or KoeFrame's report. A future package extraction can preserve this HTTP
  contract.
- The pilot stores no cue records and adds no migration.
- This slice stops at a synchronous segment of at most 60 seconds. The
  existing root product decision in `product.md` P-03/P-04 assigns durable
  full-track localization to `defdo_order` and bounded translation execution
  to the Hub. Those later workflows require the Hub task-job/callback release
  and a tested `pause_mode`/resume path; this pilot must not emulate them with
  polling, an Oban worker, or raw-media Hub requests.
