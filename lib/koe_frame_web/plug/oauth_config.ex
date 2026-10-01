defmodule Defdo.KoeFrameWeb.Plug.OAuthConfig do
  @moduledoc false
  @behaviour Plug

  alias Defdo.DefdoAuth.Plug.AuthorizeCodeWithPKCE
  alias Defdo.KoeFrame.Auth.OAuthApp
  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case OAuthApp.config(conn) do
      %{client_id: _client_id, client_secret: _secret} = config ->
        AuthorizeCodeWithPKCE.put_config(config)
        put_connection_id(conn, config)

      _ ->
        conn |> send_resp(:service_unavailable, "Login is not configured") |> halt()
    end
  end

  defp put_connection_id(conn, %{connection: id}) when is_binary(id) and id != "" do
    conn = fetch_query_params(conn)

    if Map.has_key?(conn.query_params, "connection_id") do
      conn
    else
      %{conn | query_params: Map.put(conn.query_params, "connection_id", id)}
    end
  end

  defp put_connection_id(conn, _config), do: conn
end
