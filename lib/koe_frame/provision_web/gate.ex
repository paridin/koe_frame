defmodule Defdo.KoeFrame.ProvisionWeb.Gate do
  @moduledoc false

  @behaviour Defdo.Tenant.Provision.Gate

  alias Defdo.KoeFrame.ProvisionWeb.CredentialStore
  alias Defdo.KoeFrame.ProvisionWebAdapter
  alias Defdo.Tenant.Provision.Gate, as: Verdict
  alias Defdo.Tenant.Schema.Profile

  require Logger

  @impl true
  def tenant_for(params, _opts) do
    case ProvisionWebAdapter.profile_for_host(host(params)) do
      %Profile{} = profile -> {:ok, profile}
      nil -> :none
    end
  end

  @impl true
  def live?(%Profile{} = profile),
    do: profile.is_deleted != true and is_nil(profile.deleted_at)

  def live?(_), do: false

  @impl true
  def owner?(%Profile{tenant_id: tenant_id}) when is_binary(tenant_id) do
    case CredentialStore.fetch(tenant_id) do
      {:ok, credential} when is_map(credential) -> true
      {:error, reason} when reason in [:not_found, :unknown_project] -> false
      {:error, _reason} -> true
      _ -> true
    end
  rescue
    exception ->
      Logger.error("installer gate lookup failed: #{inspect(exception.__struct__)}")
      true
  end

  def owner?(_), do: false

  def verdict(params \\ %{}), do: Verdict.check(params, gate: __MODULE__)
  def installed?, do: match?({:closed, :installed}, verdict())

  defp host(params) do
    Map.get(params, :host) || Map.get(params, "host") || ""
  end
end
