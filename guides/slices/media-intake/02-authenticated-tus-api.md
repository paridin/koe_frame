---
kind: implementation
serves: [P-01]
skills: [defdo-tenant-edge-contract, defdo-auth-ecosystem-patterns, defdo-exunit-quality-tests]
---

## Ecosystem

- `uses: defdo_auth_client@0.12.0` — `Defdo.AuthClient.SDK.introspect_credential/3` validates Defdo credentials; app API calls require the SDK's internal introspection token.
- `uses: defdo_tenant@0.18.0` — `Defdo.Tenant.Context.with_context/2` restores the tenant only around tenant-aware controller work.
- `uses: Defdo.KoeFrame.MediaIntake.Uploads` — existing session, committed-offset, checksum, and staging contract.
- `gap: Mac folder client — remains slice 03; this slice exposes only authenticated HTTP/Tus.

# Slice MI-02 — authenticated Tus upload API

## Goal

An authenticated KoeFrame client can create an idempotent upload session, query its committed offset, append one bounded Tus chunk, and explicitly finalize a checksum-verified staged file. Requests without the exact write scope fail before any tenant data or filesystem operation.

## Preconditions

- Read `00-conventions.md` and `01-session-and-local-staging.md`.
- The approved product scenario P-01 and the versioned upload schema are present.
- `defdo_auth_client` is declared and locked at 0.12.0. Do not fetch dependencies from the slice.
- Deployment registers `koe_frame:media:write` and configures `DEFDO_AUTH_INTERNAL_TOKEN`; no credential or scope is committed here.

## Targets

- `mix.exs` dependency `defdo_auth_client` — verified at `origin/main` `b58ed9b`; re-locate before editing. Preserve existing `~> 0.9` compatibility range and lock at 0.12.0.
- `lib/koe_frame_web/router.ex` API pipeline and commented API scope — verified at `origin/main` `b58ed9b`; re-locate before editing.
- `lib/koe_frame/media_intake/uploads.ex` public `create_upload/1`, `get_upload/1`, `append_chunk/3`, `finalize_upload/1` — verified at `origin/main` `b58ed9b`; re-locate before editing.
- `lib/koe_frame_web/controllers/` — add the credential plug and Tus controller; no absolute filesystem path may enter these modules.
- `config/runtime.exs` — add only runtime Auth SDK configuration; internal token resolves from `DEFDO_AUTH_INTERNAL_TOKEN` and is never logged.
- `test/koe_frame_web/` — add authenticated HTTP tests using a fake introspection result; no real credentials or media fixtures.
- `guides/slices/media-intake/README.md`, `.ai/capabilities.md`, `README.md`, `product.md` — update status from implementation evidence.

## Step 1 — authenticate and establish tenant at the HTTP edge

1. Add a small `Plug` that requires exactly one `Authorization: Bearer <credential>` header and calls the configured introspector. The production implementation delegates to `Defdo.AuthClient.SDK.introspect_credential(credential)` (verified against `defdo_auth_client` 0.12.0 source).
2. Accept only `%{"active" => true, "scopes" => scopes, "tenant" => %{"id" => tenant_id}}` where `scopes` contains the exact string `koe_frame:media:write` and tenant ID is a non-empty binary. Reject missing/malformed/inactive credentials with 401, insufficient scope with 403, and introspection transport errors with 503. Never log or echo the credential or raw introspection response.
3. Assign the validated tenant ID to the connection. Each controller action must wrap its call to `Uploads` in `Defdo.Tenant.Context.with_context(tenant_id, fn -> ... end)`, which restores the previous process context even on exceptions. Do not set a parallel tenant store and do not add `skip_tenant_id`.
4. Configure Auth SDK `site` from existing `DEFDO_AUTH_SITE` and `internal_api_token: {:system, "DEFDO_AUTH_INTERNAL_TOKEN"}`, with HMAC enabled. Missing configuration must fail closed. The token is a server-side introspection credential, not the user's bearer credential.

## Step 2 — expose bounded Tus lifecycle

1. Register authenticated routes under `/api/v1/media`: `POST /intakes/:intake_id/uploads`, `HEAD /uploads/:id`, `PATCH /uploads/:id`, and `POST /uploads/:id/finalize`.
2. Require `Tus-Resumable: 1.0.0`. Creation takes `Upload-Length` and Tus `Upload-Metadata` keys `relative_path` and `sha256`; both metadata values are strict base64 UTF-8. Client chooses only stable intake UUID, safe relative path, size, digest, and bytes. Ignore/reject unknown metadata. Never accept tenant ID, absolute path, ownership, or mode.
3. Creation calls `Uploads.create_upload/1` and returns 201 with `Location`, `Upload-Length`, `Upload-Offset: 0`, and Tus version. Repeated creation for same tenant/intake/path and matching length/digest returns same session; mismatched idempotent parameters return 409.
4. HEAD returns 200 with committed `Upload-Offset` and `Upload-Length`, no body, and `Cache-Control: no-store`. A different tenant must receive the same not-found response as an unknown ID.
5. PATCH requires `Content-Type: application/offset+octet-stream`, a decimal `Upload-Offset`, and a non-empty body no larger than 8 MiB. Read at most 8 MiB plus one byte; reject oversize before calling `Uploads.append_chunk/3`. On offset mismatch return 409 and current `Upload-Offset`; on success return 204 and the new offset.
6. Explicit finalize calls `Uploads.finalize_upload/1`. Return 200 with staged status only after digest verification; incomplete uploads return 409 and checksum mismatch returns 422. Responses contain IDs, status, and offsets only—not storage paths or digest values.
7. Add a production route test from request creation through PATCH, HEAD, and finalize, plus unauthorized, inactive, missing-scope, introspection-outage, tenant-isolation, invalid Tus headers/metadata, oversize body, offset mismatch, and checksum mismatch cases.

## Process map

No long-lived activity added or changed. HTTP request owns each operation; no worker or polling process is introduced.

## Tests

- Credential plug tests prove missing, duplicate, malformed, inactive, wrong-scope, malformed-tenant, and introspection-error handling; none may invoke `Uploads`.
- Controller tests prove a valid bearer maps to the introspected tenant, tenant context is restored after the request, cross-tenant IDs are indistinguishable from absent IDs, and all Tus headers/status codes match the contract.
- Chunk tests prove no partial append occurs for a body over 8 MiB and offset conflict reports committed offset.
- Finalize tests prove checksum mismatch is not reported as staged and storage paths never appear in JSON.

## Verification

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test test/koe_frame_web/controllers/media_uploads_controller_test.exs
mix test
git diff --check
```

Do not run `mix deps.get` from this slice. If required deps are unavailable, stop and report the missing packages; do not claim the slice verified.

## Acceptance criteria

- [ ] Only an active credential with exact `koe_frame:media:write` scope can call media upload routes.
- [ ] Authenticated tenant is sourced only from introspection and restored through `Context.with_context/2` around every tenant-aware call.
- [ ] Tus create, HEAD, PATCH, and explicit finalize route through existing `Uploads`; request params cannot choose server paths or permissions.
- [ ] PATCH rejects bodies over 8 MiB before any append.
- [x] Focused HTTP tests (8) and full suite (101) pass in the clean worktree with locked dependencies.
- [x] Docs say authenticated API is implemented but P-01 remains incomplete pending Mac client and real interrupted directory transfer.

## Evidence

- 2026-10-25: `mix deps.get --check-locked` passed with the documented sibling-path overrides; `mix.lock` unchanged.
- 2026-10-25: `mix format --check-formatted`, `mix compile --warnings-as-errors`, focused HTTP tests (8, 0 failures), full suite (101, 0 failures), and `git diff --check` passed.
- Not proven: production IdP scope grant, runtime secret injection, authenticated request against the real IdP, Mac client, or interrupted multi-gigabyte directory resume. P-01 remains incomplete.
