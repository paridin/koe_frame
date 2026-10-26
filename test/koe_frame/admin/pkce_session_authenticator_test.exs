defmodule Defdo.KoeFrame.Admin.PKCESessionAuthenticatorTest do
  use ExUnit.Case, async: false

  alias Defdo.KoeFrame.Admin.PKCESessionAuthenticator
  alias Defdo.KoeFrame.Admin.TokenVerifierFake

  @cache_key "opaque-pkce-cache-key"
  @access_token "real-access-token-fixture"
  @tenant_id "tenant-1"

  setup do
    keys = [
      :admin_credential_fetcher,
      :admin_token_verifier,
      :admin_token_verifier_test_pid,
      :admin_token_verifier_test_result
    ]

    previous = Map.new(keys, &{&1, Application.get_env(:koe_frame, &1)})

    Application.put_env(:koe_frame, :admin_token_verifier, TokenVerifierFake)
    Application.put_env(:koe_frame, :admin_token_verifier_test_pid, self())

    Application.put_env(:koe_frame, :admin_credential_fetcher, fn _tenant_id ->
      {:ok, credentials()}
    end)

    Cachex.del(:defdo_auth_user_profile, @cache_key)
    Cachex.del(:defdo_auth_user_client, @cache_key)

    on_exit(fn ->
      Cachex.del(:defdo_auth_user_profile, @cache_key)
      Cachex.del(:defdo_auth_user_client, @cache_key)
      Enum.each(previous, fn {key, value} -> restore_env(key, value) end)
    end)

    :ok
  end

  test "accepts an IdP tenant distinct from the KoeFrame tenant and returns normalized claims" do
    cache_pkce_session()

    Application.put_env(
      :koe_frame,
      :admin_token_verifier_test_result,
      {:ok,
       %{
         "active" => true,
         "sub" => "user-1",
         "client_id" => "koe-frame-login",
         "tenant_id" => "idp-tenant-1",
         "scope" => "openid profile koe-frame:admin",
         "private_claim" => "never-return-this"
       }}
    )

    assert {:ok, user} = PKCESessionAuthenticator.authenticate(@cache_key, @tenant_id)

    assert user == %{
             id: "user-1",
             email: "admin@example.test",
             name: "KoeFrame Admin",
             scopes: ["openid", "profile", "koe-frame:admin"]
           }

    assert_received {:token_introspection_requested, @access_token,
                     %{
                       site: "https://idp.example.test",
                       client_id: "koe-frame-login",
                       tenant_id: @tenant_id
                     }}

    refute_received {:token_introspection_requested, @cache_key, _config}
    refute inspect(user) =~ "never-return-this"
  end

  test "refuses a cached PKCE client that does not match this tenant's Vault login registration" do
    cache_pkce_session(%{client_id: "different-client"})

    assert {:error, :identity_session_unavailable} =
             PKCESessionAuthenticator.authenticate(@cache_key, @tenant_id)

    refute_received {:token_introspection_requested, _, _}
  end

  test "rejects inactive, subject-mismatched, and client-mismatched introspection results" do
    cache_pkce_session()

    for token_info <- [
          %{
            "active" => false,
            "sub" => "user-1",
            "client_id" => "koe-frame-login",
            "tenant_id" => @tenant_id
          },
          %{
            "active" => true,
            "sub" => "other-user",
            "client_id" => "koe-frame-login",
            "tenant_id" => "idp-tenant-1"
          },
          %{
            "active" => true,
            "sub" => "user-1",
            "client_id" => "different-client",
            "tenant_id" => "idp-tenant-1"
          },
          %{"active" => true, "sub" => "user-1", "tenant_id" => "idp-tenant-1"}
        ] do
      Application.put_env(:koe_frame, :admin_token_verifier_test_result, {:ok, token_info})

      assert {:error, :identity_session_unavailable} =
               PKCESessionAuthenticator.authenticate(@cache_key, @tenant_id)
    end
  end

  defp cache_pkce_session(client_overrides \\ %{}) do
    profile = %{"sub" => "user-1", "email" => "admin@example.test", "name" => "KoeFrame Admin"}

    client =
      Map.merge(
        %{client_id: "koe-frame-login", token: %{access_token: @access_token}},
        client_overrides
      )

    assert {:ok, true} = Cachex.put(:defdo_auth_user_profile, @cache_key, profile)
    assert {:ok, true} = Cachex.put(:defdo_auth_user_client, @cache_key, client)
  end

  defp credentials do
    %{
      site: "https://idp.example.test",
      client_id: "koe-frame-login",
      client_secret: "fixture-secret-do-not-render",
      redirect_uri: "https://koe-frame.example.test/auth/callback",
      connection: "internal_admin"
    }
  end

  defp restore_env(key, nil), do: Application.delete_env(:koe_frame, key)
  defp restore_env(key, value), do: Application.put_env(:koe_frame, key, value)
end
