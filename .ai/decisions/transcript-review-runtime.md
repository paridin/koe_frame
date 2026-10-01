---
kind: architecture
topic: koe-frame-transcript-review
---

# Transcript review uses the existing service boundaries

**Status:** implemented in the 2026-09-30 P-06 pilot.

## Decision

The transcript preview uses KoeFrame's existing Subtitler boundary,
Defdo.KoeFrame.Subtitler.normalize_srt/1. That boundary owns the HTTP request,
tenant-scoped Vault token lookup, response size limit, and generic cue
validation. The preview does not add a second Subtitler client or call
Subtitler's internal parser.

The preview uses a separate ASR adapter for the configured Speaches endpoint.
It streams only the extracted WAV file and returns normalized word text and
millisecond timestamps. The core aligns those words with the generic cue
contract using half-open intervals.

## Tenant context

TranscriptReview.preview/1 requires the caller to establish
Defdo.Tenant.Context. The Mix task is a local operator edge and restores the
tenant from KOE_FRAME_TENANT_ID before calling the context. A release RPC call
uses the runtime-configured KoeFrame tenant in the same way. Core code does
not accept tenant_id in its request map and reads tenant identity from process
context.

## Consequences

- Subtitler receives extracted SRT text only; Speaches receives the extracted
  WAV segment only.
- The preview does not call the Hub, persist media or transcript data, create
  an order, or modify source files.
- The selected audio and subtitle indexes remain metadata in the report. They
  are not encoded into Subtitler cue IDs.
- The caller sees stable tagged errors. Provider response bodies, endpoint
  configuration, and local source paths are not copied into error messages.
