defmodule Defdo.KoeFrame.Admin.SessionAuthenticator do
  @moduledoc "Boundary for resolving a PKCE session key to a validated user."

  @callback authenticate(cache_key :: String.t(), tenant_id :: String.t()) ::
              {:ok,
               %{
                 id: String.t(),
                 email: String.t() | nil,
                 name: String.t() | nil,
                 scopes: [String.t()]
               }}
              | {:error, atom()}
end

defmodule Defdo.KoeFrame.Admin.TokenVerifier do
  @moduledoc "Boundary for validating a browser access token with Defdo Auth."

  @callback introspect(token :: String.t(), config :: map()) :: {:ok, map()} | {:error, term()}
end

defmodule Defdo.KoeFrame.Admin.DefdoAuthTokenVerifier do
  @moduledoc false

  @behaviour Defdo.KoeFrame.Admin.TokenVerifier

  @impl true
  @doc false
  def introspect(token, config) when is_binary(token) and is_map(config) do
    manager = Defdo.AuthClient.TokenManager.new(config)
    Defdo.AuthClient.TokenManager.validate_token(manager, token)
  end
end

defmodule Defdo.KoeFrame.Admin.PKCESessionAuthenticator do
  @moduledoc """
  Resolves the PKCE plug's opaque session key using its server-side caches and
  verifies the cached access token with Defdo Auth before returning any claims.
  """

  @behaviour Defdo.KoeFrame.Admin.SessionAuthenticator

  alias Defdo.KoeFrame.ProvisionWeb.CredentialStore

  @impl true
  def authenticate(cache_key, tenant_id)
      when is_binary(cache_key) and cache_key != "" and is_binary(tenant_id) and tenant_id != "" do
    with {:ok, profile} <- cached_value(:defdo_auth_user_profile, cache_key),
         {:ok, client} <- cached_value(:defdo_auth_user_client, cache_key),
         {:ok, credentials} <- credential_fetcher().(tenant_id),
         :ok <- matching_login_client(client, credentials),
         {:ok, access_token} <- cached_access_token(client),
         {:ok, token_info} <-
           token_verifier().introspect(access_token, verifier_config(credentials, tenant_id)),
         :ok <- active_token(token_info),
         :ok <- matching_client(token_info, value(credentials, :client_id)),
         :ok <- matching_subject(profile, token_info),
         :ok <- matching_tenant(token_info, tenant_id) do
      {:ok,
       %{
         id: claim(profile, "sub"),
         email: claim(profile, "email"),
         name: claim(profile, "name"),
         scopes: scopes(token_info)
       }}
    else
      {:error, reason} when is_atom(reason) -> {:error, reason}
      _other -> {:error, :identity_session_unavailable}
    end
  rescue
    _exception -> {:error, :identity_session_unavailable}
  catch
    :exit, _reason -> {:error, :identity_session_unavailable}
  end

  def authenticate(_cache_key, _tenant_id), do: {:error, :identity_session_unavailable}

  defp cached_value(cache_name, key) do
    case Cachex.get(cache_name, key) do
      {:ok, %{} = value} -> {:ok, value}
      _other -> {:error, :identity_session_unavailable}
    end
  end

  defp credential_fetcher do
    Application.get_env(:koe_frame, :admin_credential_fetcher, &CredentialStore.fetch/1)
  end

  defp token_verifier do
    Application.get_env(
      :koe_frame,
      :admin_token_verifier,
      Defdo.KoeFrame.Admin.DefdoAuthTokenVerifier
    )
  end

  defp matching_login_client(client, credentials) do
    client_id = value(credentials, :client_id)

    if CredentialStore.valid_admin_access?(credentials) and is_binary(client_id) and
         value(client, :client_id) == client_id do
      :ok
    else
      {:error, :identity_session_unavailable}
    end
  end

  defp cached_access_token(client) do
    case value(value(client, :token), :access_token) do
      token when is_binary(token) and token != "" -> {:ok, token}
      _other -> {:error, :identity_session_unavailable}
    end
  end

  defp verifier_config(credentials, tenant_id) do
    %{
      site: value(credentials, :site),
      client_id: value(credentials, :client_id),
      client_secret: value(credentials, :client_secret),
      tenant_id: tenant_id,
      timeout: 5_000
    }
  end

  defp active_token(%{"active" => true}), do: :ok
  defp active_token(_token_info), do: {:error, :identity_session_unavailable}

  defp matching_client(token_info, expected_client_id) when is_binary(expected_client_id) do
    if value(token_info, :client_id) == expected_client_id do
      :ok
    else
      {:error, :identity_session_unavailable}
    end
  end

  defp matching_client(_token_info, _expected_client_id),
    do: {:error, :identity_session_unavailable}

  defp matching_subject(profile, token_info) do
    case {claim(profile, "sub"), token_subject(token_info)} do
      {subject, subject} when is_binary(subject) and subject != "" -> :ok
      _other -> {:error, :identity_session_unavailable}
    end
  end

  defp token_subject(token_info) do
    Map.get(token_info, "sub") || Map.get(token_info, "subject") ||
      Map.get(token_info, "user_id") || Map.get(token_info, "username")
  end

  defp matching_tenant(token_info, tenant_id) do
    case token_tenant_id(token_info) do
      ^tenant_id -> :ok
      _other -> {:error, :identity_session_unavailable}
    end
  end

  defp token_tenant_id(%{"tenant" => %{"id" => tenant_id}}), do: tenant_id
  defp token_tenant_id(%{"tenant" => tenant_id}) when is_binary(tenant_id), do: tenant_id
  defp token_tenant_id(token_info), do: Map.get(token_info, "tenant_id")

  defp scopes(token_info) do
    case Map.get(token_info, "scopes") || Map.get(token_info, "scope") || [] do
      value when is_binary(value) -> String.split(value, ~r/\s+/, trim: true)
      value when is_list(value) -> Enum.filter(value, &is_binary/1)
      _other -> []
    end
  end

  defp claim(map, key) do
    Map.get(map, key) || Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(map, key)
  end

  defp value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp value(_map, _key), do: nil
end
