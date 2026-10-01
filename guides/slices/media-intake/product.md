---
kind: product
topic: media-intake
approved: 2026-09-27 by owner in conversation
---

# Media intake — product slice

This file extracts P-01 from the approved root [`product.md`](../../../product.md).

## Who and why

The operator selects local video directories in the Mac client and wants them
on the NAS without restarting a multi-gigabyte transfer or repairing macOS
ownership and modes by hand.

## P-01 — Send local folders to the NAS

1. Opens the Mac client and selects one or more source directories.
2. Reviews file names, sizes, basic media metadata, and transfer progress.
3. If the network drops, resumes each file at the server's committed offset.
4. Sees the server verify each source digest and place the directory tree in
   NAS staging with the configured media UID/GID and file/directory modes.

**Done when:** an interrupted multi-gigabyte transfer resumes without
restarting the file, and a staged directory tree passes checksum and
permission checks.

## Out of scope

- Choosing final series or episode paths. Sonarr-backed import planning is P-02.
- Preserving client filesystem ownership, ACLs, or arbitrary modes.
- Public SaaS upload or unauthenticated file access.
- Subtitle translation, voice conversion, or Hub task execution.

## Ecosystem

- `uses: defdo_tenant@0.17.0` — process tenant context and tenant-owned schema.
- `uses: defdo_migrator@0.4.1` — KoeFrame's versioned schema migrator.
- `uses: defdo_uploader@0.3.0` — shared adapter contract for verified local
  publication; KoeFrame supplies its NAS filesystem adapter.
- `gap: authenticated HTTP upload — use defdo_auth_client; local endpoint
  implementation is pending package resolution and IdP scope registration.`
- `partial: resumable local staging — session/chunk/finalize foundation exists;
  authenticated HTTP and the Mac client remain pending.`
