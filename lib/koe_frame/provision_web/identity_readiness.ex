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

  @doc """
  Checks the OIDC endpoint, signing keys, and public setup-client contract
  independently so an operator can see which part failed. It never returns
  provider payloads or credentials.
  """
  @spec diagnose(map()) :: %{checks: [map()], result: :ok | {:error, atom()}}
  def diagnose(context) when is_map(context) do
    case config(context) do
      {:ok, config} ->
        discovery_result =
          safe_check(fn ->
            with {:ok, discovery} <-
                   fetch_json(config, config.site <> "/.well-known/openid-configuration"),
                 :ok <- validate_discovery(discovery, config.site) do
              {:ok, discovery}
            end
          end)

        signing_keys_result =
          case discovery_result do
            {:ok, discovery} ->
              safe_check(fn ->
                with {:ok, jwks} <- fetch_json(config, discovery["jwks_uri"]),
                     :ok <- validate_jwks(jwks) do
                  :ok
                end
              end)

            {:error, _reason} ->
              {:skip, :discovery_unavailable}
          end

        contract_result =
          safe_check(fn ->
            with {:ok, contract} <- fetch_contract(config, context),
                 :ok <- validate_contract(contract, config.redirect_uri) do
              :ok
            end
          end)

        checks = [
          check(:configuration, :ok),
          check(:discovery, result_for_unit(discovery_result)),
          check(:signing_keys, signing_keys_result),
          check(:setup_client, contract_result)
        ]

        %{checks: checks, result: first_error(checks)}

      {:error, reason} ->
        checks = [
          check(:configuration, {:error, reason}),
          check(:discovery, {:skip, :configuration_unavailable}),
          check(:signing_keys, {:skip, :configuration_unavailable}),
          check(:setup_client, {:skip, :configuration_unavailable})
        ]

        %{checks: checks, result: {:error, reason}}
    end
  rescue
    _exception -> unavailable_diagnostics()
  catch
    :exit, _reason -> unavailable_diagnostics()
  end

  def diagnose(_context), do: unavailable_diagnostics()

  defp unavailable_diagnostics do
    checks = [
      check(:configuration, {:error, :identity_provider_unavailable}),
      check(:discovery, {:skip, :configuration_unavailable}),
      check(:signing_keys, {:skip, :configuration_unavailable}),
      check(:setup_client, {:skip, :configuration_unavailable})
    ]

    %{checks: checks, result: {:error, :identity_provider_unavailable}}
  end

  defp safe_check(fun) do
    fun.()
  rescue
    _exception -> {:error, :identity_provider_unavailable}
  catch
    :exit, _reason -> {:error, :identity_provider_unavailable}
  end

  defp result_for_unit({:ok, _value}), do: :ok
  defp result_for_unit(result), do: result

  defp check(id, :ok), do: %{id: id, status: :ok, reason: nil}
  defp check(id, {:ok, _value}), do: check(id, :ok)
  defp check(id, {:error, reason}), do: %{id: id, status: :error, reason: safe_reason(reason)}
  defp check(id, {:skip, reason}), do: %{id: id, status: :skipped, reason: reason}

  defp first_error(checks) do
    case Enum.find(checks, &(&1.status == :error)) do
      nil -> :ok
      %{reason: reason} -> {:error, reason}
    end
  end

  defp safe_reason(reason)
       when reason in [
              :identity_provider_not_configured,
              :identity_provider_unavailable,
              :setup_client_disconnected,
              :setup_client_mismatch,
              :setup_client_unavailable,
              :unauthorized,
              :application_not_found
            ],
       do: reason

  defp safe_reason(_reason), do: :identity_provider_unavailable

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
    if Enum.any?(keys, &valid_public_key?/1),
      do: :ok,
      else: {:error, :identity_provider_unavailable}
  end

  defp validate_jwks(_jwks), do: {:error, :identity_provider_unavailable}

  defp valid_public_key?(%{"kid" => kid, "kty" => "RSA", "n" => modulus, "e" => exponent} = key) do
    with true <- present?(kid),
         true <- signing_key_metadata?(key, "RSA"),
         {:ok, modulus_bytes} <- decode_jwk_integer(modulus),
         {:ok, exponent_bytes} <- decode_jwk_integer(exponent),
         true <- byte_size(modulus_bytes) in 256..1024,
         true <- byte_size(exponent_bytes) in 1..4,
         modulus <- :binary.decode_unsigned(modulus_bytes),
         exponent <- :binary.decode_unsigned(exponent_bytes),
         true <- bit_size(:binary.encode_unsigned(modulus)) >= 2048,
         true <- rem(modulus, 2) == 1,
         true <- exponent >= 3 and rem(exponent, 2) == 1 and exponent < modulus do
      true
    else
      _other -> false
    end
  end

  defp valid_public_key?(%{"kid" => kid, "kty" => "EC", "crv" => curve, "x" => x, "y" => y} = key) do
    with true <- present?(kid),
         {:ok, curve, coordinate_size} <- ec_curve(curve),
         true <- signing_key_metadata?(key, "EC", curve),
         {:ok, x} <- decode_jwk_bytes(x),
         {:ok, y} <- decode_jwk_bytes(y),
         true <- byte_size(x) == coordinate_size and byte_size(y) == coordinate_size do
      valid_ec_point?(<<4, x::binary, y::binary>>, curve)
    else
      _other -> false
    end
  end

  defp valid_public_key?(_key), do: false

  defp signing_key_metadata?(key, key_type, curve \\ nil) do
    valid_use = Map.get(key, "use") in [nil, "sig"]

    valid_operations =
      case Map.fetch(key, "key_ops") do
        :error -> true
        {:ok, operations} when is_list(operations) -> "verify" in operations
        {:ok, _other} -> false
      end

    valid_algorithm =
      case Map.fetch(key, "alg") do
        :error -> true
        {:ok, algorithm} when key_type == "RSA" -> algorithm in rsa_signing_algorithms()
        {:ok, algorithm} when key_type == "EC" -> algorithm == ec_signing_algorithm(curve)
        {:ok, _other} -> false
      end

    valid_use and valid_operations and valid_algorithm
  end

  defp rsa_signing_algorithms,
    do: ~w(RS256 RS384 RS512 PS256 PS384 PS512)

  defp ec_signing_algorithm("P-256"), do: "ES256"
  defp ec_signing_algorithm("P-384"), do: "ES384"
  defp ec_signing_algorithm("P-521"), do: "ES512"
  defp ec_signing_algorithm(_curve), do: nil

  defp decode_jwk_integer(value)
       when is_binary(value) and value != "" and byte_size(value) <= 1400 do
    case Base.url_decode64(value, padding: false) do
      {:ok, <<first, _rest::binary>> = bytes} when first != 0 -> {:ok, bytes}
      _other -> {:error, :invalid_jwk_integer}
    end
  end

  defp decode_jwk_integer(_value), do: {:error, :invalid_jwk_integer}

  defp decode_jwk_bytes(value)
       when is_binary(value) and value != "" and byte_size(value) <= 1400 do
    case Base.url_decode64(value, padding: false) do
      {:ok, <<_first, _rest::binary>> = bytes} -> {:ok, bytes}
      _other -> {:error, :invalid_jwk_bytes}
    end
  end

  defp decode_jwk_bytes(_value), do: {:error, :invalid_jwk_bytes}

  defp ec_curve("P-256"), do: {:ok, :secp256r1, 32}
  defp ec_curve("P-384"), do: {:ok, :secp384r1, 48}
  defp ec_curve("P-521"), do: {:ok, :secp521r1, 66}
  defp ec_curve(_curve), do: {:error, :unsupported_curve}

  defp valid_ec_point?(point, curve) do
    {_public_key, private_key} = :crypto.generate_key(:ecdh, curve)
    _shared_secret = :crypto.compute_key(:ecdh, point, private_key, curve)
    true
  rescue
    _exception -> false
  catch
    _kind, _reason -> false
  end

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
