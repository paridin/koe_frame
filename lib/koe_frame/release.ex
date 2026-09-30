defmodule Defdo.KoeFrame.Release do
  @moduledoc """
  Production-only tasks for the standalone KoeFrame release.

  This app owns its private schema and runs its local wrapper migrations before
  the HTTP server starts. The migration ledger is pinned to the same prefix as
  the app tables so first boot cannot silently record migrations in `public`.
  """

  @app :koe_frame

  @spec migrate() :: :ok
  def migrate do
    Application.load(@app)

    schema = Defdo.KoeFrame.RepoConfig.schema()

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _, _versions} =
        Ecto.Migrator.with_repo(repo, fn started_repo ->
          Defdo.Tasks.Repo.Schema.ensure!(started_repo, schema)
          Ecto.Migrator.run(started_repo, :up, all: true, prefix: schema)
        end)
    end

    :ok
  end
end
