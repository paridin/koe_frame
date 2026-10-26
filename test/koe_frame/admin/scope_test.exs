defmodule Defdo.KoeFrame.Admin.ScopeTest do
  use ExUnit.Case, async: false

  alias Defdo.KoeFrame.Admin.Authorization
  alias Defdo.KoeFrame.Admin.SessionAuthenticatorFake
  alias Defdo.KoeFrame.Admin.Scope

  @user_token "opaque-session-key"
  @admin_scope "koe-frame:admin"

  setup do
    keys = [
      :admin_session_authenticator,
      :admin_session_authenticator_test_pid,
      :admin_session_authenticator_test_result,
      :admin_scope
    ]

    previous = Map.new(keys, &{&1, Application.get_env(:koe_frame, &1)})

    Application.put_env(:koe_frame, :admin_session_authenticator, SessionAuthenticatorFake)
    Application.put_env(:koe_frame, :admin_session_authenticator_test_pid, self())
    Application.put_env(:koe_frame, :admin_scope, @admin_scope)

    on_exit(fn -> Enum.each(previous, fn {key, value} -> restore_env(key, value) end) end)

    :ok
  end

  test "requires the PKCE user token and does not accept an access token" do
    assert {:error, :no_session_token} = Scope.for_session(%{})

    assert {:error, :no_session_token} =
             Scope.for_session(%{"access_token" => "this-is-not-a-session-key"})
  end

  test "requires a tenant context before asking the session adapter" do
    assert {:error, :tenant_not_found} = Scope.for_session(%{"user_token" => @user_token})
    refute_received {:session_authentication_requested, _, _}
  end

  test "builds scope from a validated principal and the signed tenant session" do
    user = %{
      id: "user-1",
      email: "admin@example.test",
      name: "KoeFrame Admin",
      scopes: ["openid", "profile", @admin_scope]
    }

    Application.put_env(:koe_frame, :admin_session_authenticator_test_result, {:ok, user})

    assert {:ok, scope} =
             Scope.for_session(%{
               "user_token" => @user_token,
               "tenant_id" => "tenant-1",
               "tenant_provision_host" => "koe-frame.example.test"
             })

    assert scope.tenant_id == "tenant-1"
    assert scope.host == "koe-frame.example.test"
    assert scope.user == user
    assert Authorization.authorized?(scope.user)
    assert_received {:session_authentication_requested, @user_token, "tenant-1"}
  end

  test "does not authorize an authenticated profile that lacks the exact admin scope" do
    refute Authorization.authorized?(%{scopes: ["openid", "profile"]})
    refute Authorization.authorized?(%{scopes: ["other:admin"]})
    refute Authorization.authorized?(%{})
  end

  test "fails closed if the configured admin scope is blank" do
    Application.put_env(:koe_frame, :admin_scope, " ")

    refute Authorization.configured?()
    assert Authorization.admin_scope() == nil
    refute Authorization.authorized?(%{scopes: [@admin_scope]})
  end

  test "uses the same normalized scope for the login request and authorization" do
    Application.put_env(:koe_frame, :admin_scope, "  #{@admin_scope}  ")

    assert Authorization.admin_scope() == @admin_scope
    assert Authorization.authorized?(%{scopes: [@admin_scope]})
  end

  defp restore_env(key, nil), do: Application.delete_env(:koe_frame, key)
  defp restore_env(key, value), do: Application.put_env(:koe_frame, key, value)
end
