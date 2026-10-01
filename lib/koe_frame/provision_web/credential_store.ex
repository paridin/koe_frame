defmodule Defdo.KoeFrame.ProvisionWeb.CredentialStore do
  @moduledoc """
  Stores the first-run OAuth client secret in defdo_vault.

  The secret reference is derived from the tenant context, project key and
  code. KoeFrame tables never store the OAuth client secret.
  """

  @behaviour Defdo.Tenant.ProvisionWeb.AdminAccess.CredentialStore

  alias Defdo.Tenant.Context
  alias Defdo.Tenant.Schema.Profile
  alias Defdo.Vault.{Projects, SDK}

  @project_key "koe_frame"
  @secret_code "defdo_auth_admin"
  @required_credential_fields [
    {"site", :site},
    {"client_id", :client_id},
    {"client_secret", :client_secret},
    {"redirect_uri", :redirect_uri},
    {"connection", :connection}
  ]

  @doc "True when a fetched Vault value can complete KoeFrame's admin login."
  def valid_admin_access?(credential) when is_map(credential) do
    Enum.all?(@required_credential_fields, fn {string_key, atom_key} ->
      value = Map.get(credential, string_key) || Map.get(credential, atom_key)
      is_binary(value) and String.trim(value) != ""
    end)
  end

  def valid_admin_access?(_credential), do: false

  @impl true
  def persist_admin_access(%Profile{tenant_id: tenant_id}, _key, credential)
      when is_binary(tenant_id) and is_map(credential) do
    with ^tenant_id <- Context.tenant_id(),
         {:ok, _project} <- Projects.ensure_project(tenant_id, @project_key),
         {:ok, _secret} <- SDK.upsert_secret(secret_attrs(credential)) do
      :ok
    else
      _ -> {:error, :vault_unavailable}
    end
  rescue
    _ -> {:error, :vault_unavailable}
  catch
    :exit, _ -> {:error, :vault_unavailable}
  end

  def persist_admin_access(_tenant, _key, _credential), do: {:error, :vault_unavailable}

  @doc "Fetches the OAuth client data for the tenant at this edge."
  def fetch(tenant_id) when is_binary(tenant_id) do
    reference = secret_reference()

    Context.with_context(tenant_id, fn ->
      case SDK.resolve_value_from(reference) do
        {:ok, credential} when is_map(credential) -> {:ok, credential}
        {:error, reason} -> {:error, reason}
        _ -> {:error, :credential_unavailable}
      end
    end)
  rescue
    _ -> {:error, :credential_unavailable}
  catch
    :exit, _ -> {:error, :credential_unavailable}
  end

  def fetch(_tenant_id), do: {:error, :credential_unavailable}

  defp secret_attrs(credential) do
    %{
      project_key: @project_key,
      code: @secret_code,
      otp_app: :koe_frame,
      env: vault_env(),
      content: %{
        "site" => Map.fetch!(credential, :site),
        "client_id" => Map.fetch!(credential, :client_id),
        "client_secret" => Map.fetch!(credential, :client_secret),
        "redirect_uri" => Map.fetch!(credential, :redirect_uri),
        "connection" => Map.get(credential, :connection)
      }
    }
  end

  defp secret_reference do
    {:ok, reference} =
      SDK.build_uri(:secret, @project_key, @secret_code,
        query: %{otp_app: "koe_frame", env: Atom.to_string(vault_env())}
      )

    reference
  end

  defp vault_env do
    case Application.get_env(:koe_frame, :environment, :prod) do
      env when env in [:dev, :stage, :prod, :test] -> env
      :development -> :dev
      :staging -> :stage
      :production -> :prod
      "development" -> :dev
      "staging" -> :stage
      "production" -> :prod
      "test" -> :test
      _ -> :prod
    end
  end
end
