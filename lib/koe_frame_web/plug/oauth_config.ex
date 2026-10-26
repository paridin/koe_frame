defmodule Defdo.KoeFrameWeb.Plug.OAuthConfig do
  @moduledoc false
  @behaviour Plug

  alias Defdo.DefdoAuth.Plug.AuthorizeCodeWithPKCE
  alias Defdo.KoeFrame.Admin.Authorization
  alias Defdo.KoeFrame.Auth.OAuthApp
  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if Authorization.configured?() do
      case OAuthApp.config(conn) do
        %{client_id: _client_id, client_secret: _secret} = config ->
          AuthorizeCodeWithPKCE.put_config(config)
          pin_connection_id(conn, config)

        _ ->
          conn |> send_resp(:service_unavailable, "Login is not configured") |> halt()
      end
    else
      conn
      |> send_resp(:service_unavailable, "Admin login authorization is not configured")
      |> halt()
    end
  end

  @doc false
  def authorize_params(params, conn), do: Authorization.authorize_params(params, conn)

  @doc false
  def pin_connection_id(conn, %{connection: id}) when is_binary(id) and id != "" do
    conn = fetch_query_params(conn)

    %{conn | query_params: Map.put(conn.query_params, "connection_id", id)}
  end

  def pin_connection_id(conn, _config) do
    conn = fetch_query_params(conn)
    %{conn | query_params: Map.delete(conn.query_params, "connection_id")}
  end
end
