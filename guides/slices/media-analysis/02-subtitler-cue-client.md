---
kind: implementation
serves: [P-03]
skills: [defdo-architecture-boundary-guardian, defdo-tenant-edge-contract, defdo-exunit-quality-tests]
---

# Slice 02 — KoeFrame client for Subtitler cue normalization

## Goal

KoeFrame can send an extracted SRT document to Subtitler and receive generic,
ordered cue IDs with integer millisecond ranges. The request is transient and
contains subtitle text only; video and audio bytes stay in KoeFrame.

## Contract

- Public application entry point: `Defdo.KoeFrame.Subtitler.normalize_srt/1`.
- Request: `POST /api/cues/parse`, JSON `{"format":"srt","content":"..."}`.
- Authentication: bearer token resolved from `defdo_vault` under the
  `:koe_frame` OTP namespace. `SUBTITLER_CUE_TOKEN_REF` is a non-secret Vault
  reference; the value is read only when tenant context is present in the
  current process.
- Response: non-empty ordered cues with exact IDs `cue-1`, `cue-2`, ...,
  non-negative integer starts, greater ends, and non-empty UTF-8 text. The
  adapter returns atom-keyed cue maps after validating the HTTP response.
- Input is capped at 1,000,000 bytes and the response at 20,000 cues, matching
  the service contract. The raw response body is separately capped at 8 MiB
  while streaming, before JSON decoding.
- Credentials are never sent across redirects. Production requests require
  HTTPS. Development and tests may use HTTP; a production private-network
  exception must wait for positive NAS boundary evidence.
- Transport and service errors are reduced to stable atoms. Response bodies,
  credentials, paths, and subtitle text are not returned in errors or logged.

## Configuration

- `SUBTITLER_CUE_BASE_URL` — service origin, with no path or query string.
- `SUBTITLER_CUE_TOKEN_REF` — Vault URI for the KoeFrame client's copy of the
  cue API bearer token. The reference must resolve within the active tenant,
  `project_key`, `otp_app=koe_frame`, and environment.
- `SUBTITLER_CUE_TIMEOUT_MS` — request and connection timeout; defaults to
  30,000 ms.
- The target server contract uses a read-only mounted secret file at
  `/run/secrets/subtitler_cue_api_token`, provisioned by the deployment secret
  provider from `defdo_vault`. This comes from the pending Subtitler auth fix
  and is not present in released `0.1.11`; do not use this client until an
  auth-enabled Subtitler image is deployed. Do not pass the server token through
  a process environment variable or commit or print either copy. The provider
  must also supply Vault's keyring material to KoeFrame at runtime.

## Boundaries

- `Defdo.KoeFrame.Subtitler` owns the application-facing contract.
- `HTTPAdapter` owns Req, endpoint security, request shape, and response
  validation.
- `VaultTokenProvider` resolves credentials through the shared Vault SDK and
  reads tenant identity from `Defdo.Tenant.Context`; no `tenant_id` argument is
  threaded through the client.
- Subtitler stays an independent generic service. KoeFrame has no Subtitler
  compile-time dependency and does not share its database.
- The client does not extract media, run ASR, translate cues, create Hub jobs,
  or persist the SRT payload.

## Verification

Run from the repository root:

```sh
MIX_ENV=test mix test test/koe_frame/subtitler
MIX_ENV=test mix compile --warnings-as-errors
mix format --check-formatted
git diff --check
```

The local contract tests use synthetic subtitles and `Req.Test`; they do not
call a live Subtitler service or prove production credential provisioning,
network privacy, or release boot.
