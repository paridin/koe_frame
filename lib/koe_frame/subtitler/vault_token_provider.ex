defmodule Defdo.KoeFrame.Subtitler.VaultTokenProvider do
  @moduledoc """
  Resolves KoeFrame's own Subtitler API credential from defdo_vault.

  The Vault reference contains no secret. Resolution uses the tenant already
  established in the current process and the `:koe_frame` OTP namespace.
  """

  alias Defdo.Tenant.Context
  alias Defdo.Vault.SDK

  @min_token_bytes 32

  @spec fetch_token() :: {:ok, String.t()} | {:error, atom()}
  def fetch_token do
    reference = Application.get_env(:koe_frame, :subtitler_cue_token_ref)

    fetch_token(reference, [])
  end

  @doc false
  def fetch_token(reference, opts) when is_list(opts) do
    cond do
      not is_binary(reference) or reference == "" ->
        {:error, :credential_not_configured}

      not is_binary(Context.tenant_id()) or Context.tenant_id() == "" ->
        {:error, :missing_tenant_context}

      true ->
        resolve(reference, Keyword.get(opts, :resolver, SDK))
    end
  end

  defp resolve(reference, resolver) do
    case resolver.resolve_value_from(reference) do
      {:ok, content} -> extract_token(content)
      {:error, :missing_tenant} -> {:error, :missing_tenant_context}
      {:error, _reason} -> {:error, :credential_unavailable}
      _other -> {:error, :credential_unavailable}
    end
  rescue
    _error -> {:error, :credential_unavailable}
  end

  defp extract_token(%{"token" => token}), do: validate_token(token)
  defp extract_token(%{token: token}), do: validate_token(token)
  defp extract_token(_content), do: {:error, :credential_unavailable}

  defp validate_token(token) when is_binary(token) and byte_size(token) >= @min_token_bytes,
    do: {:ok, token}

  defp validate_token(_token), do: {:error, :credential_unavailable}
end
