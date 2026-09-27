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
decision. This Phoenix scaffold is the starting server, not a completed intake
or localization workflow.

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
