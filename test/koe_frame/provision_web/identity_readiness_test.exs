defmodule Defdo.KoeFrame.ProvisionWeb.IdentityReadinessTest do
  use ExUnit.Case, async: true

  alias Defdo.KoeFrame.ProvisionWeb.IdentityReadiness

  @site "https://idp.example.test"
  @client_id "koe-frame-public-client"
  @redirect_uri "https://localhost:4000/auth/callback"
  @rsa_modulus Base.url_encode64(:binary.copy(<<0xA5>>, 256), padding: false)

  @discovery %{
    "issuer" => @site,
    "authorization_endpoint" => @site <> "/openid/authorize",
    "token_endpoint" => @site <> "/oauth/token",
    "jwks_uri" => @site <> "/openid/jwks"
  }

  @jwks %{
    "keys" => [
      %{
        "kid" => "test-key",
        "kty" => "RSA",
        "n" => @rsa_modulus,
        "e" => "AQAB"
      }
    ]
  }

  @contract %{
    "application_type" => "spa",
    "login_ready" => true,
    "expected_scopes" => ["openid", "profile"],
    "grant_types" => ["authorization_code"],
    "redirect_uris" => [@redirect_uri],
    "pkce" => true
  }

  test "requires discovery, signing keys, and the registered least-privilege PKCE app" do
    context = context()

    assert :ok = IdentityReadiness.preflight(context)
    assert_received {:identity_request, :get, @site <> "/.well-known/openid-configuration"}
    assert_received {:identity_request, :get, @site <> "/openid/jwks"}
    assert_received {:contract_fetch, %{site: @site, client_id: @client_id, client_secret: nil}}
  end

  test "does not call discovery when the app registration is missing" do
    context = context(%{setup_client_id: nil})

    assert {:error, :identity_provider_not_configured} = IdentityReadiness.preflight(context)
    refute_received {:identity_request, _, _}
  end

  test "fails closed when discovery points at another issuer or origin" do
    context = context(%{discovery: Map.put(@discovery, "issuer", "https://other.example.test")})

    assert {:error, :identity_provider_unavailable} = IdentityReadiness.preflight(context)
    refute_received {:identity_request, :get, @site <> "/openid/jwks"}
    refute_received {:contract_fetch, _}
  end

  test "fails closed when JWKS has no usable signing keys" do
    context = context(%{jwks: %{"keys" => []}})

    assert {:error, :identity_provider_unavailable} = IdentityReadiness.preflight(context)
    refute_received {:contract_fetch, _}
  end

  test "rejects malformed RSA key material instead of reporting usable signing keys" do
    context =
      context(%{
        jwks: %{"keys" => [%{"kid" => "bad", "kty" => "RSA", "n" => "garbage", "e" => "AQAB"}]}
      })

    assert {:error, :identity_provider_unavailable} = IdentityReadiness.preflight(context)
    refute_received {:contract_fetch, _}

    diagnosis = IdentityReadiness.diagnose(context)
    assert diagnosis.result == {:error, :identity_provider_unavailable}
    assert Enum.find(diagnosis.checks, &(&1.id == :signing_keys)).status == :error
  end

  test "rejects encryption-only keys and keys without verification usage" do
    encryption_only = Map.put(hd(@jwks["keys"]), "use", "enc")
    encryption_operation_only = Map.put(hd(@jwks["keys"]), "key_ops", ["encrypt", "unwrapKey"])
    encryption_algorithm = Map.put(hd(@jwks["keys"]), "alg", "RSA-OAEP-256")

    for key <- [encryption_only, encryption_operation_only, encryption_algorithm] do
      assert {:error, :identity_provider_unavailable} =
               context(%{jwks: %{"keys" => [key]}})
               |> IdentityReadiness.preflight()
    end
  end

  test "accepts a valid signing key alongside unrelated encryption keys" do
    encryption_only = Map.put(hd(@jwks["keys"]), "use", "enc")
    jwks = %{"keys" => [encryption_only | @jwks["keys"]]}

    assert :ok = context(%{jwks: jwks}) |> IdentityReadiness.preflight()
  end

  test "requires an existing app with the exact callback, PKCE, and only OIDC scopes" do
    context = context(%{contract: {:error, :application_not_found}})

    assert {:error, :application_not_found} = IdentityReadiness.preflight(context)

    context = context(%{contract: {:ok, Map.put(@contract, "redirect_uris", [])}})
    assert {:error, :setup_client_mismatch} = IdentityReadiness.preflight(context)

    context =
      context(%{
        contract:
          {:ok, Map.put(@contract, "expected_scopes", ["openid", "profile", "admin:users"])}
      })

    assert {:error, :setup_client_mismatch} = IdentityReadiness.preflight(context)
  end

  test "requires the setup app to have an enabled login connection" do
    context = context(%{contract: {:ok, Map.put(@contract, "login_ready", false)}})

    assert {:error, :setup_client_disconnected} = IdentityReadiness.preflight(context)
  end

  test "diagnose reports discovery, signing keys, and the public client contract separately" do
    diagnosis = IdentityReadiness.diagnose(context())

    assert diagnosis.result == :ok

    assert Enum.map(diagnosis.checks, &{&1.id, &1.status}) == [
             configuration: :ok,
             discovery: :ok,
             signing_keys: :ok,
             setup_client: :ok
           ]

    assert_received {:contract_fetch, %{client_secret: nil}}
  end

  test "diagnose still checks the public client when discovery fails and marks signing keys skipped" do
    diagnosis =
      context(%{discovery: Map.put(@discovery, "issuer", "https://other.example.test")})
      |> IdentityReadiness.diagnose()

    assert diagnosis.result == {:error, :identity_provider_unavailable}

    assert Enum.map(diagnosis.checks, &{&1.id, &1.status}) == [
             configuration: :ok,
             discovery: :error,
             signing_keys: :skipped,
             setup_client: :ok
           ]

    assert_received {:contract_fetch, %{client_secret: nil}}
    refute_received {:identity_request, :get, @site <> "/openid/jwks"}
  end

  defp context(overrides \\ %{}) do
    values =
      Map.merge(
        %{
          site: @site,
          setup_client_id: @client_id,
          setup_redirect_uri: @redirect_uri,
          discovery: @discovery,
          jwks: @jwks,
          contract: {:ok, @contract}
        },
        overrides
      )

    values
    |> Map.put(:identity_request, fn :get, url, _options ->
      send(self(), {:identity_request, :get, url})

      body =
        case url do
          @site <> "/.well-known/openid-configuration" -> values.discovery
          @site <> "/openid/jwks" -> values.jwks
          _other -> %{}
        end

      {:ok, %{status: 200, body: body}}
    end)
    |> Map.put(:contract_fetcher, fn config ->
      send(self(), {:contract_fetch, config})
      values.contract
    end)
  end
end
