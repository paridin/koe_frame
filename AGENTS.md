# KoeFrame — project instructions

- Keep the serving application modules under the `Defdo.KoeFrame` namespace
  and its Phoenix web modules under `Defdo.KoeFrameWeb`.
- Keep media intake, catalog planning, and subtitle translation behind
  application-owned contexts. Sonarr is authoritative for existing series
  identity and library paths; model output is a proposal that requires a
  reviewable import plan.
- Keep Subtitler generic: cue IDs, timecodes, language, glossary, and context
  belong in its contract; anime entities, Sonarr, NAS paths, and lore do not.
- Use `defdo_order` for KoeFrame's durable localization workflows. Model each
  translation batch as its own task so only failed batches need retrying. A
  Hub result returns through an authenticated, idempotent callback that
  restores tenant context before resuming the matching order step.
- For an external wait, declare `pause_mode` and `input_config` on the step.
  Do not use `Defdo.Order.pause/2` to prepare a step for resume; the current
  `defdo_order` flow contract documents that path as unable to persist the
  resumable step/context. Do not block an Oban worker polling the Hub.
- Use `defdo_migrator` for versioned schema changes. Generate the Ecto wrapper
  with `mix ecto.gen.migration <name>` from this app directory, then have that
  wrapper invoke `Defdo.KoeFrame.Migrator` for the app's versioned migrations.
  Do not hand-create timestamped migration files.
- The server finalizes NAS ownership and modes after checksum validation. A
  client-supplied path or macOS ownership must never choose a final library
  destination or NAS service owner.
- Store Sonarr, Jellyfin, Hub, and SSH credentials in `defdo_vault`; persist
  only opaque credential references in KoeFrame tables. Inject Vault keyring
  material at runtime through the deployment secret provider, never source
  control.
