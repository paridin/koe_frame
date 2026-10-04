# KoeFrame

KoeFrame is a Phoenix application for private video intake, localization, and
library management. Its first catalog is anime on a NAS, while the subtitle
translation contract stays generic enough for other video collections.

The Mac client is planned to select local folders and resume transfers. The
server will stage and verify files, propose catalog matches, and ask the
operator to review an import plan before applying it. Sonarr remains the source
of truth for existing series IDs and library paths. `defdo_order` will own
durable media workflows; each subtitle batch can pause for a Hub result and
resume from a signed callback. KoeFrame and the independent Subtitler service
will submit the same bounded subtitle task type to the Hub API, using their own
workflows and signed callbacks. KoeFrame will consume Subtitler through its
service boundary when it needs subtitle-specific capabilities; it will not
compile against Subtitler's private repository, embed its Phoenix runtime, or
share its database.

See [`product.md`](product.md) for the approved product scope and transfer
decision. The first intake foundation now persists tenant-scoped upload
sessions, resumes bounded chunks from the committed offset, verifies the
whole-file SHA-256, and finalizes into a server-owned staging tree with
configured modes and owner/group. Published files use `0640`; directories use
`0750` and retain KoeFrame ownership for new uploads while the configured media
group can read and traverse them. Partial upload files are private (`0600`).
The final publish uses the
`Defdo.Uploader.Adapter` contract from `defdo_uploader`; KoeFrame supplies the
filesystem adapter because it owns the NAS path and permission policy.

The HTTP/Tus endpoint, authentication edge, and Mac client are still pending;
the current context is not exposed as an unauthenticated route. P-01 is not
complete until a client can transfer and resume a real large directory tree.

## Development

Run Mix commands from this directory:

```sh
mix deps.get
mix phx.server
```

Generate schema wrappers with `mix ecto.gen.migration <name>` and route the
schema change through the configured `defdo_migrator` versioned migrator.

The initial schema wrapper installs `defdo_tenant`, `defdo_vault`, Oban,
`defdo_order`, and KoeFrame's versioned schema into `defdo_koe_frame`.
Integration credentials belong in Vault; the app stores references only.
Production config must inject `DEFDO_VAULT_PRIMARY_KEY_ID` and
`DEFDO_VAULT_KEYS_JSON` through its secret provider.

The intake finalizer also requires `KOE_FRAME_STAGING_ROOT`,
`KOE_FRAME_MEDIA_UID`, and `KOE_FRAME_MEDIA_GID` in production. Run KoeFrame
with a service identity permitted to assign that UID/GID and write the staging
filesystem. The staging root cannot be `/`, `/tmp`, a symlink, a sticky
directory, or an existing directory with group/world write permission. Its
parent chain must also have no group/world-writable directories, even when a
directory has the sticky bit. KoeFrame may create only the final root directory
when it is absent; its parent must already exist. An existing root must already
have mode `0750` and the configured media group. KoeFrame rejects an
unprovisioned root without changing its permissions. Use a dedicated staging
directory, separate from the shared writable media-library directory.

## Transcript review preview

The local operator pilot can list a media file's global stream indexes, then
compare a short word-level Speaches transcript against cues normalized by
Subtitler:

    mix koe_frame.transcript_review --file /absolute/path/episode.mkv --list-streams
    mix koe_frame.transcript_review --file /absolute/path/episode.mkv \
      --audio-stream 1 --subtitle-stream 3 --source-language ja \
      --start-ms 5000 --duration-ms 30000

Mix configuration reads KOE_FRAME_TENANT_ID,
KOE_FRAME_SPEACHES_BASE_URL, KOE_FRAME_SPEACHES_MODEL, and
KOE_FRAME_SPEACHES_TIMEOUT_MS. Subtitler uses SUBTITLER_CUE_BASE_URL and the
Vault reference SUBTITLER_CUE_TOKEN_REF. In production, that reference defaults
to `vault://secret/subtitler/koe_frame_cue_api_token?otp_app=koe_frame&env=prod`;
an explicit `SUBTITLER_CUE_TOKEN_REF` value overrides it. The reference does
not create the Vault credential: that secret still needs to be provisioned,
and the preview still requires an auth-enabled Subtitler image to be deployed.
Configure private service addresses and the KoeFrame tenant before running a
preview. Released `0.1.11` predates cue endpoint authentication. The preview
streams only the extracted WAV to Speaches and sends only the extracted SRT
text through KoeFrame's Vault-backed Subtitler client. It
starts the KoeFrame application so Vault can use the Repo, prints a transient
JSON report, and removes temporary media files on success or failure; it does
not persist transcripts, edit subtitle files, or call the Hub. Stream listing
does not start the application or require Vault credentials.

The release image has no Mix executable. A NAS preview runs through release RPC
after confirming the configured Speaches and Subtitler services and tenant:

    bin/koe_frame rpc 'Defdo.Tenant.Context.with_context(Application.fetch_env!(:koe_frame, :transcript_review_tenant_id), fn -> IO.inspect(Defdo.KoeFrame.TranscriptReview.preview(%{path: "/media/anime/episode.mkv", audio_stream: 1, subtitle_stream: 3, source_language: "ja", start_ms: 5000, duration_ms: 30000})) end)'

## First-run installer identity checks

Before the installer asks for the instance name, canonical domain, or first
administrator credentials, it verifies the configured IdP's OIDC discovery
document and signing keys. It also reads the configured public PKCE app
contract through `defdo_auth_client` and requires the registered app to have
an enabled login connection, the exact callback URI, PKCE, and only the
`openid profile` scopes. The Auth bootstrap preflight then checks the selected
host and backend dependencies. A missing or unavailable IdP, signing key set,
app registration, login connection, or bootstrap consumer keeps the instance
and administrator forms hidden.

Configure `DEFDO_AUTH_SITE`, `DEFDO_AUTH_SETUP_CLIENT_ID`, and
`DEFDO_AUTH_SETUP_REDIRECT_URI` for the setup client. The setup client is
public and has no client secret; its minimum contract is an SPA client using
authorization code with PKCE and the `openid profile` scopes. The separate
server-only `DEFDO_AUTH_BOOTSTRAP_TOKEN` is used only for the trusted Auth
bootstrap API.

## Admin identity diagnostics

After signing in, open `/admin` to inspect the current identity path. The page
checks OIDC discovery, signing keys, the public PKCE setup-client contract, the
read-only Auth first-admin preflight, and the tenant's stored admin login
registration. Admin access also requires an active token introspected through
`defdo_auth_client`, a matching tenant and login client, and the configured
`koe-frame:admin` scope. The PKCE session's opaque cache key is never treated as
an access token. Authenticated users without the admin scope receive a 403 page.
The diagnostics never display OAuth credentials.

The administrator login registration in Auth must allow `koe-frame:admin` and
the intended administrator must be granted that scope. Set
`KOE_FRAME_ADMIN_SCOPE` only when the IdP uses a different, deliberately
provisioned KoeFrame admin scope; the same configured scope is requested during
login and required by the admin gate.

The Auth first-admin preflight does **not** create an IAM user. A passing
preflight proves the endpoint and its current prerequisites accepted a
read-only check; an actual user-creation test still requires a disposable
instance setup flow.

## Admin speech model lab

Administrators with the configured KoeFrame admin scope can open
`/admin/speech-models` to inspect models from the configured Speaches service.
The catalog shows Japanese automatic-speech-recognition models only. A model
download is rechecked against the current registry, then against the installed
inventory; this action does not change `KOE_FRAME_SPEACHES_MODEL`, which remains
the transcription default.

The comparison accepts one WAV clip up to 25 MB and 30 seconds and runs two to
four installed models against the same temporary file. KoeFrame removes the
temporary copy when comparison finishes. A reference transcript is optional;
when supplied, the panel reports character error rate after Unicode NFKC
normalization and removing whitespace, punctuation, and symbols.

The Speaches catalog includes Japanese ASR candidates and installs through the
configured Speaches API. Cactus Whistle appears as an experimental candidate
through its own Elixir adapter, which invokes the configured native `needle`
runner and downloader. Configure `KOE_FRAME_CACTUS_WHISTLE_RUNNER`,
`KOE_FRAME_CACTUS_WHISTLE_DOWNLOADER`, and
`KOE_FRAME_CACTUS_WHISTLE_MODEL_DIR`; keep the model directory on persistent
storage if downloads should survive container replacement. The runner converts
the uploaded WAV to 16 kHz mono PCM when needed. The panel permits comparing
Whistle on Japanese audio so its actual failure rate can be measured, while its
published language list currently excludes Japanese.

This comparison is exploratory evidence. The lifecycle is exploration, a
representative Japanese benchmark, repeatable quality and latency evaluation,
then human review. Promotion is blocked until every stage has evidence; a single
clip cannot meet that gate. The admin cannot promote or activate models. The
Speaches install and comparison requests use
`KOE_FRAME_SPEACHES_ADMIN_TIMEOUT_MS` (default 30 minutes), and Cactus commands
use `KOE_FRAME_CACTUS_WHISTLE_TIMEOUT_MS` (default 30 minutes). A real Cactus
download or Japanese audio run has not yet been executed in the NAS environment.
