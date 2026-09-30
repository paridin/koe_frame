# KoeFrame media-analysis slices

This set implements the first internal step of approved product scenario
[`P-03`](../../../product.md#p-03--translate-and-edit-subtitle-cues-with-context):
inventory the media streams and extract bounded subtitle/audio material so a
later localization step can work with text and timings.

## Order

1. `01-ffmpex-extraction.md` — KoeFrame-owned FFprobe inventory and bounded
   extraction through Ffmpex. It does not call the Hub or modify the source
   media.
2. `02-subtitler-cue-client.md` — send bounded SRT text to Subtitler's
   authenticated generic cue endpoint and validate the returned cue contract.
3. Later slice: run the Aoyama ASR/reference comparison and produce a reviewed
   first Spanish draft.
4. Later slice: compare translation candidates through the Hub only after
   task-jobs 01 is corrected, third-reviewed, and merged.

Slices 01 and 02 are implemented locally on the media-pilot branch. The
remaining items are ordered follow-ups, not hidden acceptance criteria for
those slices.

## Product and architecture

- `product.md` is the approved P-03 scenario excerpt; the approval is recorded
  in KoeFrame's root `product.md`.
- `../../../.ai/decisions/media-analysis-boundary.md` records the
  application/package and runtime-binary decisions.
- `00-conventions.md` is mandatory before implementing a slice.
