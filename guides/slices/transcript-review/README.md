---
kind: operational
topic: koe-frame-transcript-review
---

# Transcript review pilot

This set validates one narrow step in KoeFrame's subtitle-localization flow:
compare a short, local Japanese speech transcript with cues from a selected
subtitle track before asking a model to translate anything.

## Slice order

1. `01-aoyama-transcript-review.md` adds a bounded `mix` command that probes a
   media file, extracts one audio segment and one subtitle stream, transcribes
   the audio through the NAS Speaches service, and prints a JSON alignment
   report. It does not persist media or call the Hub.

## Follow-up candidates

- A review screen backed by saved localization context, after the operator
  validates the report shape on real media.
- Full-track transcription as bounded durable work using `defdo_order`.
- Translation batches submitted through the Hub's task API after its task-job
  contract and callback lifecycle are released and verified.

Those are not preconditions for the one-segment experiment in slice 01.
