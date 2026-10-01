import Config

config :defdo_vault, config_env: config_env()
config :koe_frame, :runtime_env, config_env()

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/koe_frame start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") in ~w(true 1) do
  config :koe_frame, Defdo.KoeFrameWeb.Endpoint, server: true
end

config :koe_frame, Defdo.KoeFrameWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

subtitler_cue_token_ref =
  System.get_env("SUBTITLER_CUE_TOKEN_REF") ||
    if config_env() == :prod do
      "vault://secret/subtitler/koe_frame_cue_api_token?otp_app=koe_frame&env=prod"
    end

config :koe_frame,
  subtitler_cue_base_url: System.get_env("SUBTITLER_CUE_BASE_URL"),
  subtitler_cue_token_ref: subtitler_cue_token_ref,
  subtitler_cue_timeout_ms:
    String.to_integer(System.get_env("SUBTITLER_CUE_TIMEOUT_MS", "30000")),
  transcript_review_tenant_id: System.get_env("KOE_FRAME_TENANT_ID"),
  speaches_base_url: System.get_env("KOE_FRAME_SPEACHES_BASE_URL"),
  speaches_model:
    System.get_env("KOE_FRAME_SPEACHES_MODEL", "deepdml/faster-whisper-large-v3-turbo-ct2"),
  speaches_timeout_ms: System.get_env("KOE_FRAME_SPEACHES_TIMEOUT_MS", "180000")

config :koe_frame,
  setup_token: System.get_env("SETUP_TOKEN"),
  auth_site: System.get_env("DEFDO_AUTH_SITE"),
  auth_bootstrap_token: System.get_env("DEFDO_AUTH_BOOTSTRAP_TOKEN"),
  auth_setup_client_id: System.get_env("DEFDO_AUTH_SETUP_CLIENT_ID"),
  auth_setup_redirect_uri: System.get_env("DEFDO_AUTH_SETUP_REDIRECT_URI"),
  auth_environment: System.get_env("KOE_FRAME_AUTH_ENVIRONMENT", Atom.to_string(config_env())),
  auth_callback_redirect_host: System.get_env("KOE_FRAME_AUTH_CALLBACK_REDIRECT_HOST"),
  start_oban?: System.get_env("KOE_FRAME_START_OBAN", "false") in ["true", "1"],
  tenant_region: System.get_env("KOE_FRAME_TENANT_REGION", "mx"),
  tenant_environment:
    System.get_env("KOE_FRAME_TENANT_ENVIRONMENT") ||
      if(config_env() == :prod, do: "production", else: "development"),
  environment: config_env()

if config_env() == :dev and System.get_env("KOE_FRAME_DEV_TLS") in ["true", "1"] do
  port = String.to_integer(System.get_env("PORT", "4000"))
  certfile = System.fetch_env!("KOE_FRAME_DEV_TLS_CERT")
  keyfile = System.fetch_env!("KOE_FRAME_DEV_TLS_KEY")

  config :koe_frame, Defdo.KoeFrameWeb.Endpoint,
    url: [scheme: "https", host: "localhost", port: port],
    http: false,
    https: [
      ip: {127, 0, 0, 1},
      port: port,
      certfile: certfile,
      keyfile: keyfile
    ]
end

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :koe_frame, Defdo.KoeFrameWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Gettext translations
        ~r"priv/gettext/.*\.po$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/koe_frame_web/router\.ex$"E,
        ~r"lib/koe_frame_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  media_staging_root =
    System.get_env("KOE_FRAME_STAGING_ROOT") ||
      raise "environment variable KOE_FRAME_STAGING_ROOT is missing"

  media_owner_uid =
    System.get_env("KOE_FRAME_MEDIA_UID") ||
      raise "environment variable KOE_FRAME_MEDIA_UID is missing"

  media_owner_gid =
    System.get_env("KOE_FRAME_MEDIA_GID") ||
      raise "environment variable KOE_FRAME_MEDIA_GID is missing"

  config :koe_frame,
    media_staging_root: Path.expand(media_staging_root),
    media_staging_owner: {String.to_integer(media_owner_uid), String.to_integer(media_owner_gid)}

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :koe_frame, Defdo.KoeFrame.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :koe_frame, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :koe_frame, Defdo.KoeFrameWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :koe_frame, Defdo.KoeFrameWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :koe_frame, Defdo.KoeFrameWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :koe_frame, Defdo.KoeFrame.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://swoosh.hexdocs.pm/Swoosh.html#module-installation for details.
end
