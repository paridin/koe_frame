# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :koe_frame,
  namespace: Defdo.KoeFrame,
  ecto_repos: [Defdo.KoeFrame.Repo],
  generators: [timestamp_type: :utc_datetime_usec]

config :koe_frame, Defdo.KoeFrame.Repo,
  migration_default_prefix: "defdo_koe_frame",
  after_connect: {Postgrex, :query!, ["SET search_path TO defdo_koe_frame,public", []]}

config :defdo_migrator, repo: Defdo.KoeFrame.Repo

config :defdo_order,
  repo: Defdo.KoeFrame.Repo,
  migration_module: Defdo.Order.Migrations,
  ecto_repos: [Defdo.KoeFrame.Repo],
  start_repo?: false

config :defdo_order, Oban,
  notifier: Oban.Notifiers.Postgres,
  repo: Defdo.KoeFrame.Repo,
  prefix: "defdo_koe_frame",
  plugins: [Oban.Plugins.Pruner, Defdo.Order.Plugin.Monitor],
  queues: [tasks: 10, events: 10]

config :defdo_tenant,
  repo: Defdo.KoeFrame.Repo,
  enforcement: :strict,
  tenant_key: :tenant_id,
  timestamp_type: :utc_datetime_usec,
  tenant_code_error_key: :code

config :defdo_tenant, Defdo.Tenant.Adapters, skip_query_module: Defdo.KoeFrame.Repo

config :defdo_vault,
  repo: Defdo.KoeFrame.Repo,
  caller_otp_app: :koe_frame,
  manage_tenant_tables: false,
  start_repo: false,
  start_pubsub: false

# Configure the endpoint
config :koe_frame, Defdo.KoeFrameWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: Defdo.KoeFrameWeb.ErrorHTML, json: Defdo.KoeFrameWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Defdo.KoeFrame.PubSub,
  live_view: [signing_salt: "alZhpNiA"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :koe_frame, Defdo.KoeFrame.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  koe_frame: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.3",
  path: Path.expand("../priv/bin/tailwindcss", __DIR__),
  koe_frame: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
