---
kind: implementation
serves: []
skills: [defdo-runtime-readiness, defdo-docs-evidence-maintainer]
---

## Ecosystem

- `uses: defdo_migrator@0.4.1` — check the generated wrapper and pinned version.
- `uses: defdo_tenant@0.17.0` — tenant-table scope is exercised by intake tests.
- `gap: authenticated network transfer — cannot be gated until slice 02 and the Mac client exist.`

# Verification gate — media intake

This is the durable gate for P-01 as its implementation slices land. Run from
the KoeFrame repository root.

## Commands

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test test/koe_frame/media_intake/uploads_test.exs
mix test
git diff --check
```

## Current evidence

- On 2026-09-29, the current local working tree passed `mix format
  --check-formatted`, `mix compile --warnings-as-errors`, `mix test` (25 tests,
  0 failures), and `git diff --check`. The full suite started the local test
  database and exercised the tenant-scoped upload persistence and staging path.
- The first full test run exposed a test-only tuple access error in the owner
  assertion. It was corrected to read the GID from the `{uid, gid}` tuple, and
  the complete suite then passed.
- A separate synthetic two-second MKV smoke through KoeFrame's FFmpex adapter
  found global streams 0/1/2, extracted the SRT subtitle, and produced a
  0.5-second WAV segment (16,078 bytes, consistent with a mono 16 kHz PCM WAV).
- An independent review used an isolated copy: its fresh test-env compile and
  four FFmpex adapter tests passed. It found the same tuple assertion failure
  in the then-current copy. The fix is covered by the 25-test local run; the
  reviewer has not re-reviewed the post-fix tree.
- Earlier filesystem-adapter checks rejected symlinked and group-writable
  parents and confirmed file/directory modes 0640/0750. Those checks were made
  before the latest root-boundary changes; the current complete suite covers
  those cases locally.
- `mix deps.get` previously resolved `defdo_uploader@0.3.0` and
  `defdo_s3@0.2.1` in this checkout. A fresh-clone dependency fetch has not been
  verified.
- A fresh temporary schema migration installed Tenant v7 and KoeFrame v1/v2
  through an Ecto migration runner, confirmed the media upload table existed,
  and rolled the schema back cleanly. The temporary schema was dropped after
  verification. This exercises the package migrators and the v2 empty-table
  rollback guard; it does not execute the repository's exact full bootstrap
  migration (including Vault) against a newly created database or test refusal
  to roll back while upload rows exist.
- The authenticated API still depends on resolving private `defdo_auth_client`
  and registering the narrow tenant scope; no upload route or Mac client exists
  yet. A clean-clone full test, real HTTP/Tus transfer, interrupted
  multi-gigabyte directory transfer, and the configured NAS UID/GID have not
  been verified. P-01 remains incomplete.
- The Hub task-jobs callback contract for P-03 is independently blocked on
  task-jobs 01 (#110): its second review found an open P1 and three P2 findings.
  This does not block P-01; KoeFrame must wait for fixes, a third review, and a
  merged Hub change before implementing callback delivery.
