---
name: checkpoint-media-upload-api-20261025
description: KoeFrame dev.8 is pinned in dev GitOps; admin UI now adopts shared shell and Elm-style LiveView state, but changes remain uncommitted and rollout is unverified.
metadata:
  type: project
  checkpoint: true
---

**Task**: Deploy and test KoeFrame's authenticated resumable Tus API in dev/NAS without touching production. On review of the current admin screens, first standardize their layout with `defdo_theme_components` and adopt Elm-style LiveView state before continuing the media-operation selector.
**State**: in-progress — app branch `deploy/koe-frame-media-api-dev8-20261026` at `304fd4f2277dd27d64755b9f7d9d99feb2051a15`; annotated tag `0.1.0-dev.8` points to it. New admin UI changes are uncommitted in `assets/css/app.css`, `lib/koe_frame_web/{admin/system_live.ex,admin/speech_models_live.ex,components/layouts.ex}`, and their two LiveView tests. Prior GitOps pin commit `fa544c3` is pushed to `defdo_apps_deployment/main`; no evidence yet that Argo applied it. No production context or workloads were used.
**Decisions**:
- Reconcile the media API atop dev.7 so the candidate does not regress the admin/IdP tenant-session fixes; retain Decimal 3.2.0 dependency refresh.
- Add authenticated Tus `OPTIONS` capability discovery because independent review found it missing and Tus clients need it.
- Bound Hex requests and install CMake in CI/build because clean Woodpecker jobs had registry fetch failures and NIF source-fallback risk; preserve unique tag and never retag a published image.
- Keep selector UI separate from Tus delivery; translation through Hub remains pending.
- Use the shared `admin_page_shell` and `nav_group` for consistent responsive admin chrome; use one `%Model{}` assign, closed message parsing, pure `update/2`, and explicit effect commands in both existing admin LiveViews. Keep provider/diagnostic behavior outside UI-state transition logic.
- Import `tw-animate-css` because the shared shell/drawer references its motion-safe utilities; the host's Tailwind source scan alone does not emit those animations.
- Do not use the only local Kubernetes context (`defdo-prod`) to inspect or mutate dev. Continue only with an explicitly authorized dev access path.
**Discoveries**:
- Woodpecker pipeline #50 passed all verification on `304fd4f`; fresh isolated worktree gates passed: locked dependencies, formatting, compile, 153 tests, and Hex audit. Tag pipeline #51 passed preflight, release verification, and AMD64 image build.
- Registry inspection confirmed `hub.defdo.ninja/defdo/koe_frame:0.1.0-dev.8` digest `sha256:8ffcf25e9ce08928d18ff9d4c6a044c970647d1696938634e647863ea22f40c4`.
- GitOps Tanka render at pin candidate shows namespace `defdo-apps-dev`, staging `/media/staging`, UID/GID `568`, dev image `0.1.0-dev.8`, and secret ref `koe-frame-dev-secret`.
- After pin commit `fa544c3`, public `GET /` returns 200 but Tus `OPTIONS` still returns 404 (including unique query string). This proves rollout is not visible at the public route, not that application code is absent.
- `argocd app get koe-frame-dev --server argocd.defdo.ninja --grpc-web` returned unauthenticated; `kubectl config get-contexts -o name` listed only `defdo-prod`. Do not fall back to prod. Internal auth token and exact media-write grant also remain unverified; never print secrets.
- Adversarial review verdict was `READY_WITH_FOLLOWUPS`; real IdP introspection/scope, deployed release boot, NAS storage, and real Tus client interoperability remain unverified.
**Next step**: Review changed LiveViews for interaction edge cases, then visually inspect admin shell at 320/375/390px and desktop in light/dark themes; this session verified compile/tests/CSS build but did not run a browser against an authenticated instance. Commit the UI-only slice after that gate, without changing the published `dev.8` tag. Separately obtain approved Argo read-only or explicitly scoped dev access; verify `koe-frame-dev` applied revision `fa544c3` and image/digest before retrying public Tus `OPTIONS`. Provision/verify internal Auth token and exact scope only through approved secret/IdP channels, then run authenticated Tus upload/resume/finalize plus auth/tenant negatives and inspect NAS staging. Selector workflow follows the admin UX foundation; translation through Hub remains pending.
**Verification**: macOS worktree at app HEAD `304fd4f` with the UI diff uncommitted: `mix format --check-formatted`, `mix compile --warnings-as-errors`, full `mix test` (155 tests, 0 failures), `mix assets.build`, and `git diff --check` passed. Built CSS contains `animate-in`, `fade-in-0`, drawer transforms, and nav-group utilities. Earlier clean isolated worktree at `304fd4f` passed locked deps, format, compile, 153 tests, and Hex audit; Woodpecker CI #50 and tag/image pipeline #51 passed. Registry digest is `sha256:8ffcf25e9ce08928d18ff9d4c6a044c970647d1696938634e647863ea22f40c4`. Tanka render verified dev namespace/staging/UID/GID. Public `/` was HTTP 200 and unauthenticated Tus `OPTIONS` HTTP 404. Argo read-only call had no session; local kubectl only lists `defdo-prod`, unused. No authenticated Tus or browser-width/theme verification was performed.
**Cache user**: `defdo/koe-frame-media-api-20261025`
