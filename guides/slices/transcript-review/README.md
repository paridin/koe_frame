---
kind: operational
topic: koe-frame-transcript-review
---

# Transcript review pilot

This set validates one narrow step in KoeFrame's subtitle-localization flow:
compare a short, local Japanese speech transcript with cues from a selected
subtitle track before asking a model to translate anything.

## Slice order

1. Release Subtitler's cue-normalization API slice first so the private service
   exposes `POST /api/cues/parse`.
2. `01-aoyama-transcript-review.md` adds a bounded Mix command and public
   KoeFrame functions that probe a media file, extract one audio segment and
   one subtitle stream, transcribe through NAS Speaches, obtain normalized
   cues from Subtitler, and print a JSON alignment report. It does not persist
   media or call the Hub. The NAS smoke uses release RPC because the runtime
   image has no Mix executable.

## Follow-up candidates

- A review screen backed by saved localization context, after the operator
  validates the report shape on real media.
- Full-track transcription as bounded durable work using `defdo_order`.
- Translation batches submitted through the Hub's task API after its task-job
  contract and callback lifecycle are released and verified.

Those are not preconditions for the one-segment experiment in slice 01.
