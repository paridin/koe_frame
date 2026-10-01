---
name: checkpoint-mf01-gate-20260930
description: MF-01 local gate results and KoeFrame branch state as of 2026-09-30.
metadata:
  type: project
  checkpoint: true
---

**Task**: Continue the KoeFrame pending-work review by reconciling the apparent branch divergence and running the MF-01 verification gate.

**State**: done — current checkout `main` is dirty/uncommitted and two commits behind `origin/main`. `feat/media-pilot-20260930` is at `4977869`, 19 commits ahead of local `main` and two commits behind `origin/main`; the branches have diverged. Nothing deployed.

**Decisions**:
- Leave the checked-out `main` tree intact because it contains uncommitted changes and the workspace permission exposes `.git` read-only. Inspect the existing feature branch in a temporary clone instead of switching or overwriting files.
- Reconcile `feat/media-pilot-20260930` with `origin/main` before adding slice 02, so the API does not land on top of a diverged release baseline.
- Treat local test/compile/format results as evidence for the current `main` worktree only. The feature branch has newer source and its recorded CI/independent-review evidence should not be attributed to this older working tree.
- Keep P-01 open until the authenticated Tus API, Mac client, and real interrupted directory transfer are complete.

**Discoveries**:
- Current working tree passed `mix format --check-formatted`, `mix compile --warnings-as-errors`, focused upload tests (9 tests, 0 failures), full suite (25 tests, 0 failures), and `git diff --check` on the local macOS checkout. The suite used the local test database; no clean dependency fetch was possible in the isolated clone.
- Temporary clean clone of `feat/media-pilot-20260930` reached HEAD `4977869`. Its guide records 62 tests, CI pipeline #15, release assembly, and an independent clean-checkout review at `4ff2f2e`; those checks were not rerun here.
- In the isolated clone, `mix deps.get` failed opening a local TCP socket with `:eperm`; `mix format --check-formatted` then lacked dependencies. This is an environment limitation, not a demonstrated source failure.
- `defdo_auth_client` 0.11.1 is present in the local Hex package cache and a local source checkout. KoeFrame's current `mix.exs`/lock do not include it, and the authenticated upload route and IdP scope are still absent.
- **DETOUR filed, not followed**: Hypothesis — the documented `Defdo.AuthPlug.ApiKey` + `Defdo.AuthPlug.RequireScopes` chain may reject API-key requests because `ApiKey` assigns `current_credential`, `token_info`, and `current_tenant_id`, while `RequireScopes` reads `current_token` and `token_manager`. Source inspection supports the mismatch; no runtime reproduction was run. Verify with a focused Plug test when slice 02 starts.

**Next step**: In a writable checkout, reconcile `feat/media-pilot-20260930` with `origin/main`, then start media-intake slice 02: add the cached `defdo_auth_client` 0.11.1 dependency, establish credential introspection and exact `koe_frame:media:write` scope checks at the Phoenix edge, restore tenant process context before calling `Uploads`, and cover missing/invalid credential, insufficient scope, tenant restoration, and Tus create/head/patch/finalize behavior. Keep the external IdP scope registration as a deployment prerequisite.

**Verification**: Local macOS checkout `/Users/paridin/Devel/defdo_projects/koe_frame`: `mix format --check-formatted` — exit 0; `mix compile --warnings-as-errors` — exit 0; `mix test test/koe_frame/media_intake/uploads_test.exs` — 9 tests, 0 failures; `mix test` — 25 tests, 0 failures; `git diff --check` — exit 0. These used the existing local build/dependencies, not a clean dependency checkout. In the temporary clone of `feat/media-pilot-20260930`, `mix deps.get` was blocked by `:eperm` opening a TCP socket. The feature branch guide records 62 tests and CI at code HEAD `4ff2f2e`; those results were not rerun in this turn.
