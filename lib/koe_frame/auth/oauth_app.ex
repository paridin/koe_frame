defmodule Defdo.KoeFrame.Auth.OAuthApp do
  @moduledoc false

  alias Defdo.KoeFrame.ProvisionWeb.CredentialStore
  alias Defdo.KoeFrame.ProvisionWebAdapter
  alias Defdo.Tenant.Schema.Profile

  @required ~w(site client_id client_secret redirect_uri)

  def config(%Plug.Conn{host: host}) do
    with %Profile{tenant_id: tenant_id} <- ProvisionWebAdapter.profile_for_host(host),
         {:ok, credentials} <- CredentialStore.fetch(tenant_id),
         true <- valid?(credentials) do
      credentials
      |> atomize_known_fields()
      |> Map.put(:tenant_id, tenant_id)
    else
      _ -> nil
    end
  end

  def config(_), do: nil

  defp valid?(credentials) do
    Enum.all?(@required, fn key ->
      value = Map.get(credentials, key) || Map.get(credentials, String.to_existing_atom(key))
      is_binary(value) and String.trim(value) != ""
    end)
  rescue
    ArgumentError -> false
  end

  defp atomize_known_fields(credentials) do
    for key <- ~w(site client_id client_secret redirect_uri connection), into: %{} do
      value = Map.get(credentials, key) || Map.get(credentials, String.to_existing_atom(key))
      {String.to_existing_atom(key), value}
    end
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end
end
