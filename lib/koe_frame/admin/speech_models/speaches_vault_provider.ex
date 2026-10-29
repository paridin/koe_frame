defmodule Defdo.KoeFrame.Admin.SpeechModels.SpeachesVaultProvider do
  @moduledoc "Resolves Speaches connection details from the current tenant's Vault."

  alias Defdo.Tenant.Context
  alias Defdo.Vault.SDK

  @project_key "koe_frame"
  @secret_code "speaches_asr"

  @spec fetch(keyword()) ::
          {:ok, %{base_url: String.t(), api_key: String.t() | nil}} | {:error, atom()}
  def fetch(opts \\ []) do
    resolver = Keyword.get(opts, :resolver, SDK)

    with tenant_id when is_binary(tenant_id) and tenant_id != "" <- Context.tenant_id(),
         {:ok, reference} <- secret_reference(resolver),
         {:ok, content} <- resolver.resolve_value_from(reference),
         {:ok, connection} <- validate_content(content) do
      {:ok, connection}
    else
      nil -> {:error, :missing_tenant_context}
      "" -> {:error, :missing_tenant_context}
      {:error, _reason} -> {:error, :speaches_credentials_unavailable}
      _other -> {:error, :speaches_credentials_unavailable}
    end
  rescue
    _error -> {:error, :speaches_credentials_unavailable}
  catch
    :exit, _reason -> {:error, :speaches_credentials_unavailable}
  end

  defp secret_reference(resolver) do
    resolver.build_uri(:secret, @project_key, @secret_code,
      query: %{
        otp_app: "koe_frame",
        env: Atom.to_string(vault_env())
      }
    )
  end

  defp validate_content(content) when is_map(content) do
    base_url = Map.get(content, "base_url") || Map.get(content, :base_url)
    api_key = Map.get(content, "api_key") || Map.get(content, :api_key)

    if valid_base_url?(base_url) and valid_api_key?(api_key) do
      {:ok, %{base_url: String.trim_trailing(base_url, "/"), api_key: blank_to_nil(api_key)}}
    else
      {:error, :invalid_speaches_credentials}
    end
  end

  defp validate_content(_content), do: {:error, :invalid_speaches_credentials}

  defp valid_base_url?(url) when is_binary(url) and url != "" do
    uri = URI.parse(url)

    uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" and
      is_nil(uri.userinfo) and is_nil(uri.query) and is_nil(uri.fragment) and
      uri.path in [nil, "", "/"]
  end

  defp valid_base_url?(_url), do: false

  defp valid_api_key?(nil), do: true

  defp valid_api_key?(key) when is_binary(key),
    do: String.trim(key) == "" or key == String.trim(key)

  defp valid_api_key?(_key), do: false

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end

  defp vault_env do
    case Application.get_env(:koe_frame, :environment, :prod) do
      env when env in [:dev, :stage, :prod, :test] -> env
      :development -> :dev
      :staging -> :stage
      :production -> :prod
      "development" -> :dev
      "staging" -> :stage
      "production" -> :prod
      "test" -> :test
      _ -> :prod
    end
  end
end
