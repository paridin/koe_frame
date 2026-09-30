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

- At HEAD `4ff2f2e` on 2026-09-30, the isolated worktree passed
  `mix format --check-formatted`, test and production compilation with
  `--warnings-as-errors`, `MIX_ENV=test mix test` (62 tests, 0 failures),
  production release assembly, `mix deps.unlock --check-unused`, and
  `git diff --check`. Tests cover tenant-bound uploads, unsafe paths and
  symlinks, permissions, bounded FFmpeg calls, and redacted failures. A
  synthetic MKV smoke found global streams and extracted an SRT plus a 500 ms
  WAV segment.
- An independent clean-checkout review at the same HEAD reproduced the 62/0
  suite, compile checks, release assembly, and `Release.migrate/0` on a fresh
  test database. It confirmed a second migration pass was idempotent and found
  no active code findings (`READY_WITH_FOLLOWUPS`). The review did not verify a
  production release boot.
- [Woodpecker pipeline #15](https://woodpecker.defdo.ninja/repos/79/pipeline/15/1)
  for `4ff2f2e` passed. Its CI job resolved the
  locked dependencies, ran formatting, compilation and all tests, installed
  Tailwind, deployed production assets, and assembled the release. The
  independent reviewer could not download Tailwind from `storage.defdo.de`
  because its connection closed; the successful CI job verified that build
  path. The Docker image has not been built yet.
- P-01 remains incomplete. This slice has no authenticated upload route or Mac
  client. No real HTTP/Tus transfer, interrupted multi-gigabyte upload,
  production release startup with staging settings, or configured NAS UID/GID
  has been verified.
- The Hub task-jobs API is outside this slice. KoeFrame must verify the Hub
  contract before implementing subtitle-translation callback delivery.
