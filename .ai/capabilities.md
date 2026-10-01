# KoeFrame capabilities

## Current capabilities

- `Defdo.KoeFrame.MediaIntake.Uploads` creates tenant-scoped upload sessions,
  reports committed offsets, appends bounded chunks, lists an intake in stable
  path order, and finalizes only after whole-file SHA-256 verification.
- `Defdo.KoeFrame.MediaIntake.Staging` writes into a configured local staging
  root. Temporary files use mode `0600` inside `0700` owner-only directories.
  Completed files use `0640`; KoeFrame-owned intake directories use `0750` and
  the configured media group. Final publication goes through the
  `Defdo.Uploader.Adapter` contract implemented by KoeFrame's filesystem
  adapter.
- `Defdo.KoeFrame.MediaIntake.RelativePath` accepts only safe paths relative to
  one generated intake directory. It does not choose a Sonarr root or final
  library destination.
- KoeFrame's versioned migrator owns the upload-session schema. `defdo_tenant`
  owns tenant identity and supplies the process-context boundary.

## Use when

- A KoeFrame server-side caller has already authenticated and restored the
  tenant context, and needs to persist a file upload session or stage verified
  chunks.
- A future HTTP/Tus controller needs an application-owned session and staging
  API.

## Not provided yet

- No upload HTTP route is registered. These modules must not be called from an
  unauthenticated client boundary.
- There is no Mac directory scanner/client, Tus endpoint, batch-completion
  action, retention worker, or Sonarr import planner yet.
- There is no route for final media-library placement. The current destination
  is a review staging tree only.

## Replaces

- Nothing in the operator workflow yet. Existing `rsync` usage remains the
  practical transfer path until an authenticated API and client are delivered.
- `defdo_uploader` does not provide the resumable session protocol; KoeFrame
  uses its adapter boundary for the NAS write and owns the media workflow.

## Integration boundary

Call `Uploads` only after an HTTP or task edge establishes
`Defdo.Tenant.Context`. The context reads tenant identity from process state;
callers cannot choose `tenant_id`, file modes, owner/group, or absolute paths
through upload attributes.
