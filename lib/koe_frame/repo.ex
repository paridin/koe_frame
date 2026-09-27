defmodule Defdo.KoeFrame.Repo do
  require Ecto.Query

  use Ecto.Repo,
    otp_app: :koe_frame,
    adapter: Ecto.Adapters.Postgres

  alias Defdo.Tenant.Context
  use Defdo.Tenant.Adapters.SkipTable

  @impl true
  def prepare_query(operation, query, opts) do
    Defdo.Tenant.Repo.Protection.scope_query(__MODULE__, operation, query, opts)
  end

  @impl true
  def default_options(_operation), do: [tenant_id: Context.tenant_id()]

  @impl true
  def skip_table({"tenant_profiles", _schema}), do: true

  def skip_table({table_name, _schema}) when is_binary(table_name),
    do: Defdo.Tenant.SharedTable.skip?(table_name)

  def skip_table(_source), do: false
end
