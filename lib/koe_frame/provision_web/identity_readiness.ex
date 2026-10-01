defmodule Defdo.KoeFrame.ProvisionWeb.IdentityReadiness do
  @moduledoc false

  alias Defdo.AuthClient.SDK

  @timeout 3_000
  @required_scopes ["openid", "profile"]

  @spec preflight(map()) :: :ok | {:error, atom()}
  def preflight(context) when is_map(context) do
    with {:ok, config} <- config(context),
         {:ok, discovery} <-
           fetch_json(config, config.site <> "/.well-known/openid-configuration"),
         :ok <- validate_discovery(discovery, config.site),
         {:ok, jwks} <- fetch_json(config, discovery["jwks_uri"]),
         :ok <- validate_jwks(jwks),
         {:ok, contract} <- fetch_contract(config, context),
         :ok <- validate_contract(contract, config.redirect_uri) do
      :ok
    end
  rescue
    _exception -> {:error, :identity_provider_unavailable}
  catch
    :exit, _reason -> {:error, :identity_provider_unavailable}
  end

  def preflight(_context), do: {:error, :identity_provider_unavailable}

  defp config(context) do
    site = context_value(context, :site)
    client_id = context_value(context, :setup_client_id)
    redirect_uri = context_value(context, :setup_redirect_uri)

    with {:ok, site} <- https_origin(site),
         true <- present?(client_id),
         true <- valid_redirect_uri?(redirect_uri) do
      {:ok,
       %{
         site: site,
         client_id: client_id,
         redirect_uri: redirect_uri,
         identity_request: context_value(context, :identity_request)
       }}
    else
      _other -> {:error, :identity_provider_not_configured}
    end
  end

  defp fetch_json(config, url) when is_binary(url) do
    if same_origin?(config.site, url) do
      options = [
        headers: [{"accept", "application/json"}],
        receive_timeout: @timeout,
        connect_options: [timeout: @timeout],
        retry: false
      ]

      case identity_request(config, :get, url, options) do
        {:ok, %{status: 200, body: body}} when is_map(body) -> {:ok, body}
        _other -> {:error, :identity_provider_unavailable}
      end
    else
      {:error, :identity_provider_unavailable}
    end
  end

  defp fetch_json(_config, _url), do: {:error, :identity_provider_unavailable}

  defp identity_request(config, method, url, options) do
    case context_value(config, :identity_request) do
      request when is_function(request, 3) -> request.(method, url, options)
      _other -> Req.request(Keyword.merge(options, method: method, url: url))
    end
  end

  defp validate_discovery(
         %{
           "issuer" => issuer,
           "authorization_endpoint" => authorize_url,
           "token_endpoint" => token_url,
           "jwks_uri" => jwks_uri
         },
         site
       ) do
    if issuer == site and Enum.all?([authorize_url, token_url, jwks_uri], &same_origin?(site, &1)),
      do: :ok,
      else: {:error, :identity_provider_unavailable}
  end

  defp validate_discovery(_discovery, _site), do: {:error, :identity_provider_unavailable}

  defp validate_jwks(%{"keys" => keys}) when is_list(keys) and keys != [] do
    if Enum.all?(keys, &valid_public_key?/1),
      do: :ok,
      else: {:error, :identity_provider_unavailable}
  end

  defp validate_jwks(_jwks), do: {:error, :identity_provider_unavailable}

  defp valid_public_key?(%{"kid" => kid, "kty" => "RSA", "n" => modulus, "e" => exponent}) do
    present?(kid) and present?(modulus) and present?(exponent)
  end

  defp valid_public_key?(%{"kid" => kid, "kty" => "EC", "crv" => curve, "x" => x, "y" => y}) do
    present?(kid) and present?(curve) and present?(x) and present?(y)
  end

  defp valid_public_key?(_key), do: false

  defp fetch_contract(config, context) do
    client_config = %{
      site: config.site,
      client_id: config.client_id,
      # This is a public PKCE client. Never inherit a host's confidential client
      # secret while checking its public registration.
      client_secret: nil,
      timeout: @timeout
    }

    case context_value(context, :contract_fetcher) do
      fetcher when is_function(fetcher, 1) -> fetcher.(client_config)
      _other -> SDK.fetch_app_contract(client_config)
    end
  end

  defp validate_contract(
         %{
           "application_type" => "spa",
           "login_ready" => true,
           "expected_scopes" => @required_scopes,
           "grant_types" => ["authorization_code"],
           "redirect_uris" => redirect_uris,
           "pkce" => true
         },
         redirect_uri
       )
       when is_list(redirect_uris) do
    if redirect_uri in redirect_uris, do: :ok, else: {:error, :setup_client_mismatch}
  end

  defp validate_contract(
         %{"application_type" => "spa", "login_ready" => false},
         _redirect_uri
       ),
       do: {:error, :setup_client_disconnected}

  defp validate_contract(%{"application_type" => "spa"}, _redirect_uri),
    do: {:error, :setup_client_mismatch}

  defp validate_contract(_contract, _redirect_uri), do: {:error, :setup_client_unavailable}

  defp https_origin(value) when is_binary(value) do
    value = String.trim_trailing(value, "/")
    uri = URI.parse(value)

    if uri.scheme == "https" and is_binary(uri.host) and uri.path in [nil, ""] and
         is_nil(uri.query) and is_nil(uri.fragment) do
      {:ok, value}
    else
      {:error, :identity_provider_not_configured}
    end
  end

  defp https_origin(_value), do: {:error, :identity_provider_not_configured}

  defp valid_redirect_uri?(value) when is_binary(value) do
    uri = URI.parse(value)
    uri.scheme == "https" and is_binary(uri.host) and is_nil(uri.fragment)
  end

  defp valid_redirect_uri?(_value), do: false

  defp same_origin?(site, endpoint) when is_binary(site) and is_binary(endpoint) do
    base = URI.parse(site)
    target = URI.parse(endpoint)

    target.scheme == "https" and target.scheme == base.scheme and target.host == base.host and
      target.port == base.port and is_nil(target.userinfo)
  end

  defp same_origin?(_site, _endpoint), do: false

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp context_value(context, key) do
    Map.get(context, key) || Map.get(context, Atom.to_string(key))
  end
end
