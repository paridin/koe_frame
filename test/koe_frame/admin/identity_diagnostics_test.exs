defmodule Defdo.KoeFrame.Admin.IdentityDiagnosticsTest do
  use ExUnit.Case, async: true

  alias Defdo.KoeFrame.Admin.IdentityDiagnostics

  @site "https://idp.example.test"
  @redirect_uri "https://koe-frame.example.test/auth/callback"
  @client_id "public-setup-client"
  @tenant_id "tenant-test"
  @private_value "never-render-this-test-credential"
  @rsa_modulus Base.url_encode64(:binary.copy(<<0xA5>>, 256), padding: false)

  @discovery %{
    "issuer" => @site,
    "authorization_endpoint" => @site <> "/oauth/authorize",
    "token_endpoint" => @site <> "/oauth/token",
    "jwks_uri" => @site <> "/oauth/jwks"
  }

  @jwks %{
    "keys" => [
      %{"kid" => "test-key", "kty" => "RSA", "n" => @rsa_modulus, "e" => "AQAB"}
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

  test "checks the public PKCE app and first-admin preflight without creating users or returning credentials" do
    result = IdentityDiagnostics.run(context(), @tenant_id)

    assert Enum.map(result.checks, &{&1.id, &1.status}) == [
             configuration: :ok,
             discovery: :ok,
             signing_keys: :ok,
             setup_client: :ok,
             bootstrap_preflight: :ok,
             admin_login_credential: :ok
           ]

    assert DateTime.diff(DateTime.utc_now(), result.checked_at, :second) in 0..2
    assert_received {:contract_fetch, %{client_secret: nil, client_id: @client_id}}
    assert_received {:bootstrap_request, :post, @site <> "/api/v1/bootstrap/preflight", _body}
    refute_received {:bootstrap_request, :post, @site <> "/api/v1/bootstrap/admin-access", _body}
    assert_received {:credential_lookup, @tenant_id}

    rendered = inspect(result)
    refute rendered =~ @private_value
    refute rendered =~ "server-side-bootstrap-test-token"
  end

  test "normalizes bootstrap and admin-registration failures without rendering response bodies or secrets" do
    result =
      context(%{
        bootstrap_response: {:ok, %{status: 401, body: %{"token" => @private_value}}},
        credential: {:ok, %{"client_secret" => @private_value, "connection" => "external"}}
      })
      |> IdentityDiagnostics.run(@tenant_id)

    bootstrap = Enum.find(result.checks, &(&1.id == :bootstrap_preflight))
    credential = Enum.find(result.checks, &(&1.id == :admin_login_credential))

    assert bootstrap.status == :error
    assert bootstrap.message == "Auth rejected the server-side bootstrap credential."
    assert credential.status == :error
    refute inspect(result) =~ @private_value
  end

  defp context(overrides \\ %{}) do
    values =
      Map.merge(
        %{
          site: @site,
          setup_client_id: @client_id,
          setup_redirect_uri: @redirect_uri,
          token: "server-side-bootstrap-test-token",
          redirect_host: "koe-frame.example.test",
          environment: "test",
          bootstrap_response: {:ok, %{status: 204, body: %{}}},
          credential:
            {:ok,
             %{
               "site" => @site,
               "client_id" => "admin-login-client",
               "client_secret" => @private_value,
               "redirect_uri" => @redirect_uri,
               "connection" => "internal_admin"
             }}
        },
        overrides
      )

    values
    |> Map.put(:identity_request, fn :get, url, _options ->
      send(self(), {:identity_request, url})

      body =
        case url do
          @site <> "/.well-known/openid-configuration" -> Map.get(values, :discovery, @discovery)
          @site <> "/oauth/jwks" -> Map.get(values, :jwks, @jwks)
          _other -> %{}
        end

      {:ok, %{status: 200, body: body}}
    end)
    |> Map.put(:contract_fetcher, fn config ->
      send(self(), {:contract_fetch, config})
      Map.get(values, :contract, {:ok, @contract})
    end)
    |> Map.put(:request, fn method, url, _options, body ->
      send(self(), {:bootstrap_request, method, url, body})
      values.bootstrap_response
    end)
    |> Map.put(:credential_fetcher, fn tenant_id ->
      send(self(), {:credential_lookup, tenant_id})
      values.credential
    end)
  end
end
