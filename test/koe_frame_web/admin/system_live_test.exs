defmodule Defdo.KoeFrameWeb.Admin.SystemLiveTest do
  use Defdo.KoeFrameWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Defdo.KoeFrame.Admin.SessionAuthenticatorFake

  @user_token "admin-liveview-test-key"

  setup do
    original_runner = Application.get_env(:koe_frame, :identity_diagnostics_runner)
    original_test_pid = Application.get_env(:koe_frame, :identity_diagnostics_test_pid)
    original_authenticator = Application.get_env(:koe_frame, :admin_session_authenticator)

    original_auth_result =
      Application.get_env(:koe_frame, :admin_session_authenticator_test_result)

    original_auth_pid = Application.get_env(:koe_frame, :admin_session_authenticator_test_pid)
    original_admin_scope = Application.get_env(:koe_frame, :admin_scope)

    Application.put_env(
      :koe_frame,
      :identity_diagnostics_runner,
      Defdo.KoeFrameWeb.Admin.DiagnosticsFake
    )

    Application.put_env(:koe_frame, :identity_diagnostics_test_pid, self())
    Application.put_env(:koe_frame, :admin_session_authenticator, SessionAuthenticatorFake)
    Application.put_env(:koe_frame, :admin_session_authenticator_test_pid, self())
    Application.put_env(:koe_frame, :admin_scope, "koe-frame:admin")

    Application.put_env(
      :koe_frame,
      :admin_session_authenticator_test_result,
      {:ok,
       %{
         id: "user-1",
         email: "admin@example.test",
         name: "KoeFrame Admin",
         scopes: ["openid", "profile", "koe-frame:admin"]
       }}
    )

    on_exit(fn ->
      restore_env(:identity_diagnostics_runner, original_runner)
      restore_env(:identity_diagnostics_test_pid, original_test_pid)
      restore_env(:admin_session_authenticator, original_authenticator)
      restore_env(:admin_session_authenticator_test_result, original_auth_result)
      restore_env(:admin_session_authenticator_test_pid, original_auth_pid)
      restore_env(:admin_scope, original_admin_scope)
    end)

    :ok
  end

  test "redirects a request without an authenticated PKCE session to the login route", %{
    conn: conn
  } do
    conn = get(conn, "/admin")

    assert redirected_to(conn) == "/auth/callback"
  end

  test "shows read-only status checks to the signed-in administrator and supports refresh", %{
    conn: conn
  } do
    conn =
      init_test_session(conn, %{
        "user_token" => @user_token,
        "tenant_id" => "tenant-test",
        "tenant_provision_host" => "koe-frame.example.test"
      })

    {:ok, view, _html} = live(conn, "/admin")
    html = render_async(view)

    assert html =~ "KoeFrame Admin"
    assert html =~ "Admin access verified"
    assert html =~ "koe-frame:admin"
    assert html =~ "Test identity connection"
    assert html =~ "All checks passed"
    assert_received {:identity_diagnostics_ran, "tenant-test", "koe-frame.example.test"}

    view
    |> element("#refresh-identity-diagnostics")
    |> render_click()

    assert render_async(view) =~ "The test runner completed."
    assert_received {:identity_diagnostics_ran, "tenant-test", "koe-frame.example.test"}
  end

  test "redirects an authenticated user without the KoeFrame admin scope to a forbidden page", %{
    conn: conn
  } do
    Application.put_env(
      :koe_frame,
      :admin_session_authenticator_test_result,
      {:ok,
       %{
         id: "user-2",
         email: "member@example.test",
         name: "KoeFrame Member",
         scopes: ["openid", "profile"]
       }}
    )

    conn =
      init_test_session(conn, %{
        "user_token" => @user_token,
        "tenant_id" => "tenant-test",
        "tenant_provision_host" => "koe-frame.example.test"
      })

    assert {:error, {:redirect, %{to: "/admin/forbidden"}}} = live(conn, "/admin")
  end

  defp restore_env(key, nil), do: Application.delete_env(:koe_frame, key)
  defp restore_env(key, value), do: Application.put_env(:koe_frame, key, value)
end
