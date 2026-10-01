defmodule Defdo.KoeFrame.MixProject do
  use Mix.Project

  def project do
    [
      app: :koe_frame,
      version: File.read!("VERSION") |> String.trim(),
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Defdo.KoeFrame.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.15"},
      {:phoenix_ecto, "~> 4.7"},
      {:ecto_sql, "~> 3.14"},
      {:postgrex, "~> 0.22.0"},
      {:phoenix_html, "~> 4.3"},
      {:phoenix_live_reload, "~> 1.7", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, "~> 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:daisyui,
       github: "saadeghi/daisyui",
       tag: "v5.5.20",
       sparse: "packages/bundle",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.28"},
      {:req, "~> 0.7.0"},
      {:telemetry_metrics, "~> 1.2"},
      {:telemetry_poller, "~> 1.3"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:dns_cluster, "~> 0.2.0"},
      {:defdo_migrator, "~> 0.4", organization: "defdo"},
      {:defdo_tasks, "~> 0.7", organization: "defdo"},
      {:defdo_order, "~> 0.7", organization: "defdo"},
      {:defdo_tenant, "~> 0.17.0", organization: "defdo"},
      {:defdo_tenant_provision, "~> 0.3",
       defdo_dep_opts("DEFDO_TENANT_PROVISION_PATH", "../defdo_tenant_provision")},
      {:defdo_tenant_provision_web, "~> 0.2",
       defdo_dep_opts("DEFDO_TENANT_PROVISION_WEB_PATH", "../defdo_tenant_provision_web")},
      {:defdo_vault, "~> 0.16", organization: "defdo"},
      {:defdo_auth_client, "~> 0.9",
       defdo_dep_opts("DEFDO_AUTH_CLIENT_PATH", "../defdo_auth_client")},
      {:defdo_uploader, "~> 0.3", organization: "defdo"},
      {:ffmpex, "~> 0.11.1"},
      {:bandit, "~> 1.12"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build", "compile.rambo"],
      "ecto.koe_frame_schema":
        "defdo.repo.pg.ensure_schema --repo Defdo.KoeFrame.Repo --schema defdo_koe_frame",
      "ecto.setup": [
        "ecto.create",
        "ecto.koe_frame_schema",
        "ecto.migrate",
        "run priv/repo/seeds.exs"
      ],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      release: ["compile.rambo", "release"],
      test: [
        "ecto.create --quiet",
        "ecto.koe_frame_schema",
        "ecto.migrate --quiet",
        "compile.rambo",
        "test"
      ],
      "assets.setup": [
        "tailwind.install 'https://storage.defdo.de/tailwind_cli_daisyui/v$version/tailwindcss-$target'",
        "esbuild.install --if-missing"
      ],
      "assets.build": ["compile", "tailwind koe_frame", "esbuild koe_frame"],
      "assets.deploy": [
        "compile",
        "tailwind koe_frame --minify",
        "esbuild koe_frame --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end

  defp defdo_dep_opts(env_var, default_path) do
    path = System.get_env(env_var) || Path.expand(default_path, __DIR__)

    if Mix.env() in [:dev, :test] and File.dir?(path) do
      [path: path, override: true]
    else
      [organization: "defdo"]
    end
  end
end
