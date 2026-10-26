defmodule Defdo.KoeFrameWeb.Plug.OAuthCallback do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias Defdo.KoeFrame.ProvisionWebAdapter
  alias Defdo.Tenant.Schema.Profile

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{halted: true} = conn, _opts), do: conn

  def call(%Plug.Conn{state: :unset} = conn, _opts) do
    case ProvisionWebAdapter.profile_for_host(conn.host) do
      %Profile{tenant_id: tenant_id} ->
        conn
        |> put_session("tenant_id", tenant_id)
        |> put_session(:tenant_id, tenant_id)
        |> put_session("tenant_provision_host", conn.host)
        |> put_session(:tenant_provision_host, conn.host)
        |> redirect_home()

      _ ->
        conn |> send_resp(:service_unavailable, "Tenant is not configured") |> halt()
    end
  end

  def call(conn, _opts), do: conn

  defp redirect_home(conn) do
    body = "<html><body>You are being <a href=\"/\">redirected</a>.</body></html>"

    conn
    |> put_resp_header("location", "/")
    |> put_resp_content_type("text/html")
    |> send_resp(302, body)
    |> halt()
  end
end
