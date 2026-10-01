defmodule Defdo.KoeFrame.ProvisionWeb.AdminAccess do
  @moduledoc false

  @behaviour Defdo.Tenant.Provision.AdminAccess

  alias Defdo.Tenant.Provision.AdminAccess.Reference
  alias Defdo.Tenant.ProvisionWeb.AdminAccess.Remote
  alias Defdo.KoeFrame.ProvisionWeb.IdentityReadiness

  @impl true
  def preflight(context) do
    with :ok <- IdentityReadiness.preflight(context),
         :ok <- Remote.preflight(context) do
      :ok
    end
  end

  @impl true
  def ensure(tenant, attrs, context) do
    attrs =
      case Application.get_env(:koe_frame, :auth_callback_redirect_host) do
        host when is_binary(host) and host != "" -> Map.put(attrs, :redirect_host, host)
        _ -> attrs
      end

    Remote.ensure(tenant, attrs, context)
  end

  @impl true
  def revoke(%Reference{} = reference, context), do: Remote.revoke(reference, context)
end
