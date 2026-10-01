import Config

config :koe_frame,
  transcript_review_tenant_id: "tenant-transcript-test",
  speaches_base_url: "http://speaches.test.invalid",
  speaches_model: "test/faster-whisper",
  speaches_timeout_ms: 1_000,
  subtitler_cue_base_url: "https://subtitler.test.invalid",
  subtitler_cue_timeout_ms: 1_000,
  media_staging_root: Path.join(System.user_home!(), ".koe_frame-test-staging")

config :defdo_tenant, enforcement: :test_enforce

config :defdo_order,
  start_oban?: false,
  start_action_mirror?: false,
  start_telemetry_handler?: false

config :koe_frame, start_oban?: false

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :koe_frame, Defdo.KoeFrame.Repo,
  username: "postgres",
  password: "postgres",
  hostname: System.get_env("PGHOST", "localhost"),
  database: "koe_frame_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :koe_frame, Defdo.KoeFrameWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: String.duplicate("0", 64),
  server: false

# In test we don't send emails
config :koe_frame, Defdo.KoeFrame.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
