---
kind: product
topic: koe-frame-transcript-review
approved: 2026-09-29 by owner, who said "hagámoslo" in conversation
---

# KoeFrame transcript review pilot — product

## Who and why

The private-library operator wants to know what the Japanese audio actually
says before judging or replacing an existing subtitle translation. Today the
operator extracts audio and subtitles separately, then compares them by hand.
This pilot makes that comparison repeatable on one short passage.

## Scenario

### P-06 — Compare spoken words with an existing subtitle

1. The operator probes a local media file and chooses its Japanese audio stream
   and the subtitle stream to compare by their FFprobe global indexes.
2. The operator runs a transcript-review preview for a start time and a clip
   between 1 and 60 seconds, with an explicit source-language code.
3. KoeFrame extracts only that audio segment, sends it to the configured
   private Speaches service, and converts the selected subtitle stream to SRT
   for cue parsing.
4. The operator receives JSON containing the selected stream indexes, model
   and language, word-level transcript with source-media times, all subtitle
   cues overlapping the selected clip, and the cue IDs matched to each word.
   Unmatched words and cues within the clip remain visible.
5. The operator checks the spoken Japanese against the existing Spanish cue
   and decides whether translation needs correction. The media and subtitle
   source files remain unchanged; extracted audio and subtitle files are
   temporary and removed after the command finishes.

Done when: on the Aoyama pilot file, the 30-second sample returns word
timestamps around the two previously observed speech passages and pairs them
with the Spanish cues around 5.91–9.48 s and 13.19–18.49 s. Unit tests prove
the offset and overlap calculations without requiring that copyrighted file or
the live NAS.

## Product boundaries

- This is a one-segment operator experiment, not a full-episode workflow or a
  persistent review UI.
- KoeFrame chooses media streams and owns extraction. Speaches receives only
  the extracted audio segment over the configured private service endpoint.
- Speech recognition is evidence for subtitle review, not a translation and
  not a claim that ASR is authoritative. The report preserves the model's
  returned words and timings so the operator can identify recognition errors.
- This slice does not create or overwrite subtitle files, edit the video, save
  transcripts, or submit content to ACP/the Hub.
- A later slice can submit reviewed, bounded text batches through the Hub and
  orchestrate them with `defdo_order`; it must not send raw media to the Hub.
- Voice conversion, dubbing, recap generation, and course/LMS authoring remain
  later work.

## Ecosystem

- uses: `Defdo.KoeFrame.MediaAnalysis` at `0.1.0-dev.2` — probes streams and
  creates bounded audio/subtitle extraction files; keep FFmpeg behind this
  context.
- uses: Speaches OpenAI-compatible STT API — local NAS service; the pilot has
  `deepdml/faster-whisper-large-v3-turbo-ct2` and
  `Systran/faster-whisper-medium` available. The model remains runtime
  configurable.
- uses: Req `0.7.4` — already locked by KoeFrame for multipart HTTP.
- gap: reusable subtitle cue parser — local in this pilot because Subtitler
  `0.1.10` is a standalone application whose parser is not exposed as a package
  or parse endpoint, while KoeFrame needs to attach the selected media stream
  and source-time offset. The normalized cue shape stays generic. Before
  multiple consumers depend on it, extract that shape/parser into a shared
  Subtitler capability or add a supported service contract; do not copy
  Subtitler's application runtime into KoeFrame.
- gap: durable full-track transcription — defer to a later KoeFrame slice
  using `defdo_order` after chunk limits, resume behavior, and storage
  retention are defined, as recorded in
  `.ai/decisions/transcript-review-cue-contract.md` and root `product.md`
  P-03/P-04. The 60-second synchronous pilot does not need an order, Oban
  worker, schema, or migration.
- gap: ACP translation of transcript/cue batches — defer until the Hub's
  task-job API and signed callback path are available to both KoeFrame and
  Subtitler, as recorded in root `product.md` P-03/P-04. The local pilot sends
  no content to ACP/the Hub.
