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
