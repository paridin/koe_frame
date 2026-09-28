# KoeFrame media-analysis slices

This set implements the first internal step of approved product scenario
[`P-03`](../../../product.md#p-03--translate-and-edit-subtitle-cues-with-context):
inventory the media streams and extract bounded subtitle/audio material so a
later localization step can work with text and timings.

## Order

1. `01-ffmpex-extraction.md` — KoeFrame-owned FFprobe inventory and bounded
   extraction through Ffmpex. It does not call the Hub or modify the source
   media.
2. Later slice: normalize extracted subtitle cues against the generic
   Subtitler cue contract.
3. Later slice: run the Aoyama ASR/reference comparison and produce a reviewed
   first Spanish draft.
4. Later slice: compare translation candidates through the Hub only after
   task-jobs 01 is corrected, third-reviewed, and merged.

The current runner should receive only slice 01. The later items are ordered
follow-ups, not hidden acceptance criteria for it.

## Product and architecture

- `product.md` is the approved P-03 scenario excerpt; the approval is recorded
  in KoeFrame's root `product.md`.
- `../../../.ai/decisions/media-analysis-boundary.md` records the
  application/package and runtime-binary decisions.
- `00-conventions.md` is mandatory before implementing a slice.
