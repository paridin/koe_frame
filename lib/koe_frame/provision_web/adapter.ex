defmodule Defdo.KoeFrame.ProvisionWebAdapter do
  @moduledoc "Host adapter for KoeFrame's shared first-run installer."

  @behaviour Defdo.Tenant.ProvisionWeb.Adapter

  import Ecto.Query

  alias Defdo.KoeFrame.Repo
  alias Defdo.KoeFrame.ProvisionWeb.{CredentialStore, Gate}
  alias Defdo.Tenant
  alias Defdo.Tenant.Context
  alias Defdo.Tenant.Schema.Profile

  require Logger

  @impl true
  def endpoint, do: Defdo.KoeFrameWeb.Endpoint

  @impl true
  def repo, do: Repo

  @impl true
  def setup_token, do: Application.get_env(:koe_frame, :setup_token)

  @impl true
  def gate(params), do: Gate.verdict(params)

  @impl true
  def gate_for(tenant), do: Defdo.Tenant.Provision.Gate.check_tenant(tenant, gate: Gate)

  @impl true
  def tenant_key(params), do: "first-run:" <> domain(params)

  @impl true
  def ensure_tenant(params, _opts) do
    domain = domain(params)

    case profile_for_host(domain) do
      %Profile{} = profile ->
        {:ok, profile}

      nil ->
        create_profile(domain, params)
    end
  rescue
    exception ->
      Logger.error("installer tenant creation failed: #{inspect(exception.__struct__)}")
      {:error, :dependency_unavailable}
  end

  @impl true
  def tenant_id(%Profile{tenant_id: tenant_id}), do: tenant_id

  @impl true
  def ensure_defaults(_tenant), do: :ok

  @impl true
  def admin_access do
    Application.get_env(
      :koe_frame,
      :provision_web_admin_access,
      Defdo.KoeFrame.ProvisionWeb.AdminAccess
    )
  end

  @impl true
  def admin_access_context(params) do
    host = domain(params)

    %{
      site: Application.get_env(:koe_frame, :auth_site),
      token: Application.get_env(:koe_frame, :auth_bootstrap_token),
      setup_client_id: Application.get_env(:koe_frame, :auth_setup_client_id),
      setup_redirect_uri: Application.get_env(:koe_frame, :auth_setup_redirect_uri),
      credential_store: CredentialStore,
      registration_key: tenant_key(params),
      redirect_host: host,
      tenant_domain: host,
      instance_name: Map.get(params, "instance_name", "KoeFrame"),
      environment:
        Application.get_env(
          :koe_frame,
          :auth_environment,
          Application.get_env(:koe_frame, :environment, :prod)
        )
        |> to_string()
    }
  end

  @impl true
  def login_path(_tenant), do: "/auth/callback"

  @doc false
  def profile_for_host(host) when is_binary(host) and host != "" do
    host = normalize_domain(host)

    Repo.one(
      from(profile in Profile,
        where:
          profile.domain == ^host and (is_nil(profile.is_deleted) or profile.is_deleted == false) and
            is_nil(profile.deleted_at),
        order_by: profile.inserted_at,
        limit: 1
      ),
      skip_tenant_id: [
        reason: "first-run edge resolves the request host before a tenant context exists"
      ]
    )
  end

  def profile_for_host(_host), do: nil

  defp create_profile(domain, params) do
    tenant_id = Ecto.UUID.generate()
    instance_name = Map.get(params, "instance_name", "KoeFrame")
    region = Application.get_env(:koe_frame, :tenant_region, "mx")
    environment = Application.get_env(:koe_frame, :tenant_environment, "development")

    attrs = %{
      tenant_id: tenant_id,
      name: instance_name,
      code: tenant_code(tenant_id),
      region: region,
      domain: domain,
      environment: environment,
      is_active: true
    }

    Context.with_context(tenant_id, fn ->
      case Tenant.create_profile(attrs) do
        {:ok, %Profile{} = profile} -> {:ok, profile}
        {:error, %Ecto.Changeset{}} -> {:error, :dependency_unavailable}
      end
    end)
  end

  defp tenant_code(tenant_id) do
    suffix =
      :crypto.hash(:sha256, tenant_id)
      |> Base.encode16(case: :lower)
      |> binary_part(0, 12)

    "koe_frame_" <> suffix
  end

  defp domain(params) do
    params
    |> Map.get("domain")
    |> case do
      nil -> Map.get(params, :redirect_host) || Map.get(params, :host) || ""
      value -> value
    end
    |> to_string()
    |> normalize_domain()
  end

  defp normalize_domain(value), do: value |> String.trim() |> String.downcase()
end
