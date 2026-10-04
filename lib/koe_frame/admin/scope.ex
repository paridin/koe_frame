defmodule Defdo.KoeFrame.Admin.Scope do
  @moduledoc """
  Authenticated administrator session scope for the KoeFrame admin workspace.

  The PKCE session value is an opaque cache key. `SessionAuthenticator` resolves
  it through the SDK-owned cache, validates the actual access token, and returns
  a normalized principal. Authorization always requires the configured
  KoeFrame admin scope from that validated token.
  """

  defstruct user: nil, tenant_id: nil, host: nil

  @type t :: %__MODULE__{
          user: %{
            id: String.t(),
            email: String.t() | nil,
            name: String.t() | nil,
            scopes: [String.t()]
          },
          tenant_id: String.t(),
          host: String.t() | nil
        }

  @spec for_session(map()) :: {:ok, t()} | {:error, atom()}
  def for_session(session) when is_map(session) do
    with {:ok, cache_key} <- session_user_token(session),
         {:ok, tenant_id} <- session_tenant_id(session),
         {:ok, user} <- authenticator().authenticate(cache_key, tenant_id) do
      {:ok,
       %__MODULE__{
         user: user,
         tenant_id: tenant_id,
         host: session_host(session)
       }}
    end
  rescue
    _exception -> {:error, :auth_cache_unavailable}
  catch
    :exit, _reason -> {:error, :auth_cache_unavailable}
  end

  def for_session(_session), do: {:error, :no_session_token}

  defp session_user_token(session) do
    case Map.get(session, "user_token") || Map.get(session, :user_token) do
      token when is_binary(token) and token != "" -> {:ok, token}
      _other -> {:error, :no_session_token}
    end
  end

  defp session_tenant_id(session) do
    case Map.get(session, "tenant_id") || Map.get(session, :tenant_id) do
      tenant_id when is_binary(tenant_id) and tenant_id != "" -> {:ok, tenant_id}
      _other -> {:error, :tenant_not_found}
    end
  end

  defp session_host(session) do
    case Map.get(session, "tenant_provision_host") || Map.get(session, :tenant_provision_host) do
      host when is_binary(host) and host != "" -> host
      _other -> nil
    end
  end

  defp authenticator do
    Application.get_env(
      :koe_frame,
      :admin_session_authenticator,
      Defdo.KoeFrame.Admin.PKCESessionAuthenticator
    )
  end
end
