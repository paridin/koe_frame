defmodule Defdo.KoeFrame.Admin.Authorization do
  @moduledoc """
  Product-specific authorization for KoeFrame's standalone admin.

  The same configured scope is requested during PKCE login and required after
  token introspection. Authentication alone never grants access to `/admin`.
  """

  @default_admin_scope "koe-frame:admin"
  @base_scopes ~w(email openid profile)

  @spec admin_scope() :: String.t() | nil
  def admin_scope do
    case Application.get_env(:koe_frame, :admin_scope, @default_admin_scope) do
      scope when is_binary(scope) ->
        scope = String.trim(scope)
        if valid_scope?(scope), do: scope, else: nil

      _other ->
        nil
    end
  end

  @spec configured?() :: boolean()
  def configured?, do: is_binary(admin_scope())

  @spec authorized?(map()) :: boolean()
  def authorized?(%{scopes: scopes}) when is_list(scopes) do
    case admin_scope() do
      scope when is_binary(scope) and scope != "" -> scope in scopes
      _other -> false
    end
  end

  def authorized?(_user), do: false

  @doc "Adds the configured admin audience to the authorization request."
  @spec authorize_params(keyword(), Plug.Conn.t()) :: keyword()
  def authorize_params(params, _conn) when is_list(params) do
    scope = admin_scope()

    if is_binary(scope) do
      scopes =
        params
        |> Keyword.get(:scope, Enum.join(@base_scopes, " "))
        |> String.split(~r/\s+/, trim: true)
        |> Kernel.++([scope])
        |> Enum.uniq()

      Keyword.put(params, :scope, Enum.join(scopes, " "))
    else
      raise ArgumentError, "KoeFrame admin OAuth scope is not configured"
    end
  end

  defp valid_scope?(scope) when is_binary(scope),
    do: String.match?(scope, ~r/\A[a-zA-Z0-9][a-zA-Z0-9:._-]*\z/)

  defp valid_scope?(_scope), do: false
end
