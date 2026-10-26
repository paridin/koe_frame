defmodule Defdo.KoeFrameWeb.Plug.OAuthConfigTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias Defdo.KoeFrameWeb.Plug.OAuthConfig

  test "pins authorization to the connection stored for this tenant" do
    conn = conn(:get, "/auth/callback?connection_id=attacker-selected")

    conn = OAuthConfig.pin_connection_id(conn, %{connection: "tenant-configured"})

    assert conn.query_params["connection_id"] == "tenant-configured"
  end

  test "removes a caller-selected connection when no tenant connection is configured" do
    conn = conn(:get, "/auth/callback?connection_id=attacker-selected")

    conn = OAuthConfig.pin_connection_id(conn, %{})

    refute Map.has_key?(conn.query_params, "connection_id")
  end

  test "adds the configured KoeFrame admin scope to the PKCE authorization request" do
    conn = conn(:get, "/auth/callback")

    params = OAuthConfig.authorize_params([nonce: "nonce"], conn)

    assert params[:scope] == "email openid profile koe-frame:admin"
  end
end
