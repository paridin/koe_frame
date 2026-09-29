---
kind: product
topic: koe-frame
approved: P-01–P-05 on 2026-09-27; P-06 on 2026-09-29 by owner in conversation
---

# KoeFrame — product

## Who and why

This is the owner’s private video intake, localization, and library-management
platform. Its first catalog is anime on a NAS. The shape should remain useful
for other video collections and potentially for course libraries later.
“LMS” is a useful reference for lessons, notes, subtitles, and metadata; the
first product is a media localization studio, not a course authoring system.

The operator currently chooses folders by hand, runs rsync, and fixes naming
and permissions when the media server does not recognize the files. Subtitle
translation also lives in a separate app with a fixed Ollama path and anime
specific prompt. The platform should make intake reviewable, preserve the
operator’s context, and reuse generic subtitle capabilities from Subtitler
while sending bounded ACP translation tasks through the Hub.

## Scenarios

### P-01 — Send a local folder to the NAS

1. Opens the Mac client and selects one or more source directories.
2. The client shows the file list, size, basic media metadata, and transfer
   progress before and during upload.
3. An interrupted upload resumes from the server’s committed offset; completed
   files are checked against their source digest.
4. Files land in NAS staging, where the server—not macOS—assigns the media
   service owner/group and file/directory modes.

Done when: an interrupted multi-gigabyte transfer resumes without restarting
the file and the completed staging tree passes checksum and permission checks.

### P-02 — Match a batch to the right series and season

1. The NAS intake job reads filenames and safe media metadata from staging.
2. The model proposes title, season, episode numbers, language, and existing
   catalog match, with cited evidence and confidence.
3. The operator reviews uncertain matches. A known alias resolves to the
   existing Sonarr series record; season 2 appends under it rather than
   creating a duplicate series folder.
4. The app builds a dry-run import plan and the operator applies it.

Done when: the final path comes from the chosen Sonarr series record and its
root path; the model cannot write an arbitrary destination path.

### P-03 — Translate and edit subtitle cues with context

1. Opens an episode and selects embedded or external subtitle cues.
2. Chooses source/target languages, audience style, glossary, and a context
   profile. The app can request story research through the Hub and review the
   source citations before using them.
3. KoeFrame uses a `defdo_order` workflow for the media-level order. KoeFrame
   and the standalone Subtitler service send the same bounded subtitle task
   type to the Hub; Subtitler keeps its own subtitle-job lifecycle.
4. Each task keeps cue IDs, timestamps, and order unchanged. The Hub validates
   the result and sends a signed callback to the registered consumer. KoeFrame
   resumes its matching order step; Subtitler updates its matching job. Each
   consumer retries only its failed batch.
5. Reviews and edits the output through the subtitle workflow, then exports a
   sidecar subtitle or prepares an external track for playback.

Done when: cue IDs and time ranges are unchanged, translation is editable,
and the result remains linked to the episode and the context revision used.

### P-04 — Keep a localization order alive

1. Starts an order for a show, season, episode, or subtitle track.
2. Adds a correction, glossary decision, episode summary, or source after the
   first model response.
3. The order pauses at the Hub handoff without holding an Oban worker, then
   resumes when the matching signed callback arrives, even if the model runner
   has restarted.
4. Sees the KoeFrame context revision and source provenance used by each
   batch.

Done when: no previous translation or evidence is silently overwritten when
the direction changes.

### P-05 — Prepare a dub experiment

1. Selects a translated subtitle track and a short audio segment.
2. Requests speech translation or voice-conversion experiments as a separate
   task, with a clear preview and source/target track references.
3. Reviews generated audio before attaching it to the episode.

Done when: generated audio is a new reviewable track; the source video/audio is
never overwritten.

### P-06 — Compare spoken words with an existing subtitle

1. Select a local media file and choose audio and subtitle streams by their
   FFprobe global indexes.
2. Request a 1–60 second transcript preview in an explicit source language.
3. KoeFrame extracts the audio segment for its private Speaches service,
   converts the selected text subtitle stream to SRT, and asks Subtitler's
   private cue API for normalized cue IDs and time ranges.
4. Review word-level source-media timestamps alongside overlapping subtitle
   cues, including unmatched words and cues, before choosing corrections for a
   later translation workflow.

Done when: the Aoyama 30-second sample can align recognized words with the
selected Spanish cues, while source media stays unchanged and temporary
extractions are removed.

## Product boundaries

- The Mac client reads local directories and handles transfer. The server owns
  NAS staging, checksum verification, media analysis, catalog matching, import
  planning, and permission finalization.
- The media catalog and Sonarr API are authoritative for existing series IDs,
  root folders, and season paths. The model proposes a match; it never invents
  the final path or silently creates a duplicate.
- Sonarr, Jellyfin, Hub, and transfer credentials are stored through
  `defdo_vault`. KoeFrame persists only a Vault reference such as
  `credential_ref`, never the credential value.
- `defdo_order` owns durable workflow execution in KoeFrame: the order DAG,
  step state, pause/resume, and batch-scoped task retries. KoeFrame stores
  title/episode context revisions and research-source provenance.
- The Hub owns fleet execution for bounded AI task jobs. It accepts a batch,
  runs one task turn, validates the response, stores the private input/result
  for up to 30 days, and delivers the result through a signed callback. Task
  payloads and results never enter Hub knowledge, distilled content, or the
  graph. KoeFrame retains the durable history it needs.
- KoeFrame sends only bounded text, the selected context snapshot, and opaque
  media references to the Hub. A callback resumes the exact order step through
  `Defdo.Order.resume(order_id, step_id, result)` after restoring tenant
  context at the callback edge. The step declares `pause_mode` and
  `input_config`; KoeFrame does not hold a worker polling the Hub.
- Subtitler is a generic internal service with stable translation and cue
  contracts. It owns cue IDs, cue timing and text normalization, and
  translation options, not anime catalog entities, Sonarr, NAS paths, or series
  lore. The media app may later extract that module into a separately sellable
  package without changing its API.
- Voice conversion, dub generation, YouTube recaps, LMS courses, and lesson
  authoring are later phases. They must not block the initial intake and
  subtitle workflow.

## Localization order on defdo_order

This section elaborates P-03/P-04 with the shape agreed with the hub's
task-jobs product document (`defdo_memory_hub` `guides/slices/task-jobs/product.md`,
decisions approved by the owner 2026-09-27).

### The DAG

A "localize episode" order is a `defdo_order` flow: extract cues → split into
batches → N parallel translate-batch tasks → merge → QA → write subtitles.
Splitting, merging, QA, and writing the subtitle track run inside KoeFrame's
own steps/actions. Only the translate-batch step calls out to the Hub. Each
batch is one bounded task job on the Hub, not a KoeFrame-side worker loop.

### Per-batch attempt numbering

Each translate-batch task is retried independently, scoped to its own batch,
never to the whole episode. A retry is a new **attempt** on the same
`order_id + step_id`, not a new batch and not a new order. `defdo_order`
decides when to retry (a harness failure, or the Hub's validator rejecting
the shape) and increments the attempt; it does not resubmit the same attempt
to get a different outcome.

### The idempotency key

The submission key sent to the Hub is `order_id + step_id + attempt`.
Re-sending the same attempt (e.g. after a dropped HTTP response) must never
create a second Hub job — the Hub returns the existing one. An intentional
retry increments `attempt`, which creates an independent Hub job for the same
logical batch (`order_id + step_id`). KoeFrame's own retry logic must key off
this triple, not off wall-clock time or a generated request id, so a retried
POST after a timeout cannot double-submit the batch.

### Callback handling

- The Hub POSTs a signed, idempotent callback to KoeFrame when a task job
  reaches a terminal status. **Idempotent** means KoeFrame may receive the
  same callback more than once (at-least-once delivery) and must treat it as
  one — dedupe on `order_id + step_id + attempt` (or the callback's own
  delivery id), independent of whatever idempotency `Defdo.Order.resume/3`
  itself does or does not provide.
- KoeFrame verifies the callback's signature before acting on it.
- The callback body carries the task's outcome (`complete` with the result
  document, or `failed` with a validation-vs-harness-failure distinction —
  see below) plus the identifying triple.
- `GET /api/jobs/:id/result` on the Hub is the fetch/recovery path when a
  callback is lost or KoeFrame needs to reconcile state, not the primary
  delivery mechanism.

### Resume via `pause_mode` — pending a proving test

The translate-batch step is intended to declare `pause_mode`/`input_config`
(the mechanism `defdo_order`'s own `FLOW_ATTACHMENT.md` §3.1 verifies works:
it sets `awaiting_input` and persists a resumable context), and the callback
handler is intended to call `Defdo.Order.resume(order_id, step_id, result)`
after restoring tenant context at the callback edge.

**This is a precondition, not a settled fact.** `FLOW_ATTACHMENT.md` §3.2
documents `Defdo.Order.pause/2` as a verified defect (it never sets
`awaiting_input` and never persists a paused context, so the resume sequence
printed in `defdo_order`'s own README cannot complete as written), and no
existing `defdo_order` test covers a real pause-then-resume sequence end to
end (the lifecycle tests construct `awaiting_input: true` and the paused
context by hand rather than exercising `pause_mode` through execution).
Before KoeFrame relies on callback-driven resume in production:

1. The translate step must be configured with `pause_mode`/`input_config`,
   never `Defdo.Order.pause/2` or `workflow_control`'s `wait`/`delay`/
   `wait_for_event` (all unusable for an hours-long wait per §3.3).
2. KoeFrame must add its own test that drives a step through pause via
   `pause_mode`, delivers a callback, and proves `Defdo.Order.resume/3`
   resumes that exact step — not a hand-constructed paused context.
3. Until that test exists and passes, treat resume-from-callback as unproven
   in KoeFrame, and do not gate a release on it.

### What the Hub guarantees vs. what KoeFrame owns

| | Owner |
|---|---|
| One bounded ACP turn per attempt, on the fleet (quota, memory floor) | Hub |
| Validating the output shape for `subtitle_translation` (same cue IDs, same timestamps, no cue dropped/added/reordered, valid JSON) and distinguishing that failure from a harness failure | Hub |
| Storing the task's input/output for up to 30 days, then deleting it | Hub |
| Keeping task content out of `defdo_knowledge`, `defdo_distilled`, and any graphify graph (by allowlist, not by filter) | Hub |
| Signed, idempotent callback delivery, plus `GET /api/jobs/:id/result` | Hub |
| The order DAG, step state, batch-scoped retries, and attempt numbering | KoeFrame (`defdo_order`) |
| Deduping a repeated callback delivery | KoeFrame |
| Deciding whether/how to retry a batch after a validation vs. a harness failure | KoeFrame (`defdo_order`) |
| Proving `pause_mode` + callback-driven resume actually resumes the step (see above) | KoeFrame |
| Durable history: context revisions, research-source provenance, prior translations | KoeFrame |

The Hub does not adopt `defdo_order` internally and has no notion of orders,
steps, or a DAG — it only ever sees one bounded task job per attempt.

### Adoption prerequisites

Before the localization order ships, KoeFrame's schema wrapper needs:

- `defdo_tenant` tables installed (tenant context at the callback edge, per
  `defdo_tenant`'s process-context boundary).
- The `defdo_vault` migrator run, so Hub/Sonarr/Jellyfin/transfer credentials
  are stored as Vault references, never inline.
- An Oban prefix configured per `defdo_order`'s `CONSUMER_SETUP` so the
  order's Oban-backed workers do not collide with KoeFrame's other Oban
  usage.

These are already named in this document's Ecosystem section (`defdo_tenant`,
`defdo_vault`, `defdo_order`) and in the README's schema-wrapper description;
this section makes the localization order's specific dependency on them
explicit.

## Transfer decision

Default off-net transport: authenticated HTTPS with Tus resumable uploads,
checksums, a server-side staging ID, and explicit finalize. A configurable
rsync-over-SSH adapter is available for LAN/VPN or operator bulk transfers.
SSH port selection can improve reachability when a network blocks port 22; it
does not increase throughput. Do not expose the rsync daemon directly to the
public internet.

The server finalizer owns permissions. It maps staging content to the NAS
service UID/GID and configured directory/file modes after checksum validation;
the client never asks the NAS to preserve macOS ownership.

## Out of scope for the first release

- Public multi-tenant SaaS or public content distribution.
- Automatic unreviewed model writes to Sonarr or final library paths.
- Replacing Jellyfin playback.
- Dub generation, source audio replacement, voice cloning, or publishing
  recaps to YouTube.
- LMS course, student, assessment, or lesson-authoring features.

## Ecosystem

- app: KoeFrame (`koe_frame` repository) — resumable authenticated NAS intake
  and Mac client are product gaps to implement here.
- uses: defdo_memory_hub — durable contexts and ACP research/agent tasks;
  KoeFrame and Subtitler use the same authenticated task API and signed
  callback contract for bounded subtitle batches. Each app has its own scoped
  client credential and workflow.
- uses: defdo_order — domain-neutral order/task/step/action orchestration and
  Oban-backed durable workflow; each subtitle batch is an independent
  task so retry and requeue remain scoped to that batch.
- planned observer: defdo_order_visor — its repository currently marks the
  live execution screens incomplete, so KoeFrame will not depend on or embed
  it until that surface is complete and its host integration is verified.
- uses: defdo_vault — encrypted integration credentials; secret key material
  is injected per environment and is not committed with the app.
- uses: paridin/subtitler — independent subtitle service. KoeFrame integrates
  over its HTTP boundary where useful; it does not embed Subtitler's Phoenix
  runtime, share its database, or depend on its private Git repository at
  compile time. Both apps will call the Hub's shared task API directly for ACP
  translation batches.
- uses: Sonarr API — authoritative series and root-path catalog for import
  decisions.
- uses: Jellyfin — playback target for final media and subtitle tracks.
- gap: directory permissions/finalization — implement in the NAS-side intake
  finalizer, never in the Mac client.

## Research sources

- Tus protocol: https://tus.io/protocols/resumable-upload (checked 2026-09-27).
- rsync manual: https://rsync.samba.org/ftp/rsync/rsync.1 (checked
  2026-09-27).
