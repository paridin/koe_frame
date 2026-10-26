defmodule Defdo.KoeFrameWeb.Plug.MediaCredential do
  @moduledoc """
  Authenticates media API credentials and authorizes the media-write scope.

  This plug assigns the tenant ID from Defdo Auth introspection. Controller
  actions establish process tenant context only around tenant-aware work.
  """

  @behaviour Plug

  import Plug.Conn

  @required_scope "koe_frame:media:write"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    with {:ok, credential} <- bearer_credential(conn),
         {:ok, info} <- introspect(credential),
         {:ok, tenant_id} <- authorize(info) do
      assign(conn, :media_tenant_id, tenant_id)
    else
      {:error, :unauthorized} -> reject(conn, 401, "unauthorized")
      {:error, :forbidden} -> reject(conn, 403, "insufficient_scope")
      {:error, :unavailable} -> reject(conn, 503, "authentication_unavailable")
    end
  end

  defp bearer_credential(conn) do
    case get_req_header(conn, "authorization") do
      [header] ->
        case String.split(header, " ", parts: 2) do
          [scheme, credential] when credential != "" ->
            if String.downcase(scheme) == "bearer" and
                 not String.contains?(credential, [" ", "\t", "\r", "\n"]) do
              {:ok, credential}
            else
              {:error, :unauthorized}
            end

          _ ->
            {:error, :unauthorized}
        end

      _ ->
        {:error, :unauthorized}
    end
  end

  defp introspect(credential) do
    introspector =
      Application.get_env(
        :koe_frame,
        :media_credential_introspector,
        Defdo.KoeFrameWeb.MediaCredentialIntrospector
      )

    case introspector.introspect_credential(credential) do
      {:ok, info} when is_map(info) -> {:ok, info}
      {:ok, _malformed} -> {:error, :unauthorized}
      {:error, _reason} -> {:error, :unavailable}
      _unexpected -> {:error, :unavailable}
    end
  rescue
    _exception -> {:error, :unavailable}
  end

  defp authorize(%{"active" => true} = info) do
    with %{"id" => tenant_id} when is_binary(tenant_id) <- Map.get(info, "tenant"),
         {:ok, tenant_uuid} <- Ecto.UUID.cast(tenant_id),
         true <- has_required_scope?(info) do
      {:ok, tenant_uuid}
    else
      false -> {:error, :forbidden}
      _ -> {:error, :unauthorized}
    end
  end

  defp authorize(%{"active" => false}), do: {:error, :unauthorized}
  defp authorize(_info), do: {:error, :unauthorized}

  defp has_required_scope?(info) do
    scopes = Map.get(info, "scopes", [])
    scope = Map.get(info, "scope", "")

    (is_list(scopes) and @required_scope in scopes) or
      (is_binary(scope) and @required_scope in String.split(scope))
  end

  defp reject(conn, status, code) do
    conn =
      conn
      |> put_resp_content_type("application/json")
      |> maybe_challenge(status)

    conn
    |> send_resp(status, Jason.encode!(%{errors: %{code: code}}))
    |> halt()
  end

  defp maybe_challenge(conn, 401),
    do: put_resp_header(conn, "www-authenticate", "Bearer realm=\"koe-frame-media\"")

  defp maybe_challenge(conn, _status), do: conn
end

defmodule Defdo.KoeFrameWeb.MediaCredentialIntrospector do
  @moduledoc "Production adapter for Defdo Auth credential introspection."

  @doc false
  def introspect_credential(credential) do
    if internal_token_configured?() do
      Defdo.AuthClient.SDK.introspect_credential(credential)
    else
      {:error, :internal_api_token_missing}
    end
  end

  defp internal_token_configured? do
    case System.get_env("DEFDO_AUTH_INTERNAL_TOKEN") do
      token when is_binary(token) and token != "" -> true
      _missing -> false
    end
  end
end
