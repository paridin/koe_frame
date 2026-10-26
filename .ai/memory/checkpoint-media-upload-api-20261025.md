---
name: checkpoint-media-upload-api-20261025
description: KoeFrame dev.9 admin UI candidate committed, published, and pinned in dev GitOps; actual cluster rollout and authenticated browser validation remain blocked on dev access.
metadata:
  type: project
  checkpoint: true
---

**Task**: Commit the admin layout/LiveView state refactor, publish a unique dev image, pin it in dev GitOps, and validate without touching production. Authenticated Tus/NAS validation remains part of larger task.
**State**: partially complete — app branch `deploy/koe-frame-media-api-dev8-20261026` is at documentation checkpoint commit `31fce369d2bf332aac7abaec9874d78cabc325c8`; code commit/tag `0954dc2455f9aa05241144080c147ec4507bdbd8`/`0.1.0-dev.9` is the published candidate. GitOps dev pin is commit `2615349` on `defdo_apps_deployment/main`, worktree clean. Image `hub.defdo.ninja/defdo/koe_frame:0.1.0-dev.9` exists at `sha256:f42c8ca4af48fe1ec9c4b95bab2b329872ab92f1258b0c7336bff3d9dcaaa12b`. GitOps render passed; actual Argo/Kubernetes rollout and authenticated UI validation are unverified because only local Kubernetes context is `defdo-prod`, which was not used. No production workloads were touched.
**Decisions**:
- Reconcile the media API atop dev.7 so the candidate does not regress the admin/IdP tenant-session fixes; retain Decimal 3.2.0 dependency refresh.
- Add authenticated Tus `OPTIONS` capability discovery because independent review found it missing and Tus clients need it.
- Bound Hex requests and install CMake in CI/build because clean Woodpecker jobs had registry fetch failures and NIF source-fallback risk; preserve unique tag and never retag a published image.
- Keep selector UI separate from Tus delivery; translation through Hub remains pending.
- Use the shared `admin_page_shell` and `nav_group` for consistent responsive admin chrome; use one `%Model{}` assign, closed message parsing, pure `update/2`, and explicit effect commands in both existing admin LiveViews. Keep provider/diagnostic behavior outside UI-state transition logic.
- Import `tw-animate-css` because the shared shell/drawer references its motion-safe utilities; the host's Tailwind source scan alone does not emit those animations.
- Do not use the only local Kubernetes context (`defdo-prod`) to inspect or mutate dev. Continue only with an explicitly authorized dev access path.
- Upgrade Bandit from 1.13.1 to 1.14.0 because `mix hex.audit` reported multiple HIGH advisories in 1.13.1; compatible project constraints allowed update without widening `mix.exs`.
**Discoveries**:
- App commit `0954dc2` was pushed to branch and CI pipeline #52 passed on Woodpecker's clean clone. Tag pipeline #53 passed preflight, release verification, and AMD64 image build. Local gates: locked deps, format, warnings-as-errors compile, 155 tests, clean `mix hex.audit`, production assets, release, and `git diff --check`.
- `mix deps.update bandit` resolved Bandit 1.13.1 → 1.14.0; `mix hex.audit` then reported no retired/security-advisory packages.
- Git tag `0.1.0-dev.9` was absent locally/remotely before publication and was created once, annotated, then pushed. Registry inspection reported image digest `sha256:f42c8ca4af48fe1ec9c4b95bab2b329872ab92f1258b0c7336bff3d9dcaaa12b`.
- Tanka `jb install && tk eval environments/defdo-rpi4/dev` succeeded in isolated GitOps worktree; rendered manifest contains image `dev.9`, namespace `defdo-apps-dev`, and host `koe-frame-dev.defdo.ninja`. Pin commit `2615349` was fast-forwarded to GitOps `main`.
- Public probes: `GET /` → 200; unauthenticated `GET /admin` and `/admin/speech-models` → 302 to `/auth/callback`. These do not prove Argo applied the new image or render authenticated UI. `kubectl config get-contexts -o name` lists only `defdo-prod`; no production context was used.
- Registry inspection confirmed `hub.defdo.ninja/defdo/koe_frame:0.1.0-dev.8` digest `sha256:8ffcf25e9ce08928d18ff9d4c6a044c970647d1696938634e647863ea22f40c4`.
- GitOps Tanka render at pin candidate shows namespace `defdo-apps-dev`, staging `/media/staging`, UID/GID `568`, dev image `0.1.0-dev.8`, and secret ref `koe-frame-dev-secret`.
- After pin commit `fa544c3`, public `GET /` returns 200 but Tus `OPTIONS` still returns 404 (including unique query string). This proves rollout is not visible at the public route, not that application code is absent.
- `argocd app get koe-frame-dev --server argocd.defdo.ninja --grpc-web` returned unauthenticated; `kubectl config get-contexts -o name` listed only `defdo-prod`. Do not fall back to prod. Internal auth token and exact media-write grant also remain unverified; never print secrets.
- Adversarial review verdict was `READY_WITH_FOLLOWUPS`; real IdP introspection/scope, deployed release boot, NAS storage, and real Tus client interoperability remain unverified.
**Next step**: Obtain authorized read-only Argo access or an explicitly scoped dev Kubernetes context; verify `koe-frame-dev` sync revision `2615349`, running image digest, and rollout. Then authenticate to dev and visually validate `/admin` and `/admin/speech-models` at 320/375/390px plus desktop in light/dark themes. Continue authenticated Tus create → partial PATCH → HEAD → resume/finalize and auth/tenant negative cases; inspect NAS staging ownership/mode. Do not use `defdo-prod`. The user-requested code commit and dev image/GitOps pin are complete; external runtime validation is the remaining blocker.
**Verification**: App commit/tag `0954dc2`/`0.1.0-dev.9`, GitOps `main` commit `2615349`; app CI #52 and image CI #53 succeeded. Local macOS `mix deps.get --check-locked`, `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix test` (155, 0 failures), `mix hex.audit`, `MIX_ENV=prod mix assets.deploy`, and `MIX_ENV=prod mix release` passed. Tanka render verified dev image/namespace/host. Registry digest recorded above. Public route checks returned `/` 200, admin routes 302 to auth callback. No Argo sync, authenticated browser, Tus, or NAS runtime proof was available; only `defdo-prod` Kubernetes context existed and remained unused.
**Cache user**: `defdo/koe-frame-media-api-20261025`
