defmodule Defdo.KoeFrame.Admin.IdentityDiagnostics do
  @moduledoc """
  Read-only checks for the configured identity and first-admin setup paths.

  The bootstrap endpoint check calls its preflight operation only. It does not
  create an IAM user or OAuth registration.
  """

  alias Defdo.KoeFrame.ProvisionWeb.CredentialStore
  alias Defdo.KoeFrame.ProvisionWeb.IdentityReadiness
  alias Defdo.KoeFrame.ProvisionWebAdapter
  alias Defdo.Tenant.ProvisionWeb.AdminAccess.Remote

  @spec run(String.t(), String.t() | nil) :: %{checks: [map()], checked_at: DateTime.t()}
  def run(tenant_id, host) when is_binary(tenant_id) do
    context =
      ProvisionWebAdapter.admin_access_context(%{
        "domain" => resolve_host(host)
      })

    run(context, tenant_id)
  rescue
    _exception -> unavailable_result()
  catch
    :exit, _reason -> unavailable_result()
  end

  @doc false
  def run(context, tenant_id) when is_map(context) and is_binary(tenant_id) do
    identity_checks =
      context
      |> IdentityReadiness.diagnose()
      |> Map.fetch!(:checks)
      |> Enum.map(&format_identity_check/1)

    (identity_checks ++
       [
         bootstrap_check(context),
         login_credential_check(context, tenant_id)
       ])
    |> result()
  rescue
    _exception -> unavailable_result()
  catch
    :exit, _reason -> unavailable_result()
  end

  def run(_context, _tenant_id), do: unavailable_result()

  def unavailable_result do
    result([
      %{
        id: :diagnostics,
        title: "Identity diagnostics",
        status: :error,
        message: "The diagnostics could not complete. Try again shortly."
      }
    ])
  end

  defp format_identity_check(%{id: id, status: status, reason: reason}) do
    {title, success_message} =
      case id do
        :configuration ->
          {"Identity configuration",
           "The IdP site, public setup client, and callback are configured."}

        :discovery ->
          {"OIDC discovery",
           "The issuer and advertised endpoints match the configured HTTPS origin."}

        :signing_keys ->
          {"OIDC signing keys", "At least one usable public signing key is available."}

        :setup_client ->
          {"Public setup client",
           "The registered SPA client has the expected PKCE callback and scopes."}
      end

    %{
      id: id,
      title: title,
      status: status,
      message: identity_message(status, id, reason, success_message)
    }
  end

  defp identity_message(:ok, _id, _reason, success_message), do: success_message

  defp identity_message(:skipped, _id, _reason, _success_message),
    do: "Not checked because the required identity configuration is unavailable."

  defp identity_message(:error, :configuration, :identity_provider_not_configured, _success),
    do: "Configure the IdP site, public setup client ID, and HTTPS callback URI."

  defp identity_message(:error, :discovery, _reason, _success),
    do: "Discovery is unavailable or its issuer and endpoints do not match the configured origin."

  defp identity_message(:error, :signing_keys, _reason, _success),
    do: "The IdP did not return a usable public signing key set."

  defp identity_message(:error, :setup_client, :application_not_found, _success),
    do: "The configured public setup client was not found in Auth."

  defp identity_message(:error, :setup_client, :setup_client_disconnected, _success),
    do: "The public setup client has no enabled login connection."

  defp identity_message(:error, :setup_client, :setup_client_mismatch, _success),
    do: "The public setup client does not match the required SPA + PKCE callback contract."

  defp identity_message(:error, :setup_client, :unauthorized, _success),
    do: "Auth did not allow the public contract check for this client."

  defp identity_message(:error, :setup_client, _reason, _success),
    do: "The public setup client contract could not be verified."

  defp bootstrap_check(context) do
    response = safe_call(fn -> Remote.preflight(context) end)

    %{
      id: :bootstrap_preflight,
      title: "Auth first-admin preflight",
      status: result_status(response),
      message: bootstrap_message(response)
    }
  end

  defp bootstrap_message(:ok),
    do:
      "Auth accepted the read-only first-admin preflight. This check does not create an IAM user."

  defp bootstrap_message({:error, :not_configured}),
    do: "The server-side Auth bootstrap endpoint or credential is not configured."

  defp bootstrap_message({:error, :unauthorized}),
    do: "Auth rejected the server-side bootstrap credential."

  defp bootstrap_message({:error, :redirect_not_allowed}),
    do: "Auth rejected this instance host for first-admin setup."

  defp bootstrap_message({:error, _reason}),
    do: "Auth could not complete the read-only first-admin preflight."

  defp bootstrap_message(_other),
    do: "Auth returned an unexpected response to the read-only first-admin preflight."

  defp login_credential_check(context, tenant_id) do
    response = safe_call(fn -> fetch_admin_credential(context, tenant_id) end)

    status =
      case response do
        {:ok, credential} ->
          if CredentialStore.valid_admin_access?(credential) and
               credential_value(credential, :connection) == "internal_admin" do
            :ok
          else
            :error
          end

        _other ->
          :error
      end

    %{
      id: :admin_login_credential,
      title: "Admin login registration",
      status: status,
      message:
        if(status == :ok,
          do:
            "Vault contains a complete login registration pinned to the internal admin connection.",
          else: "The tenant's admin login registration is missing or incomplete in Vault."
        )
    }
  end

  defp fetch_admin_credential(context, tenant_id) do
    case Map.get(context, :credential_fetcher) || Map.get(context, "credential_fetcher") do
      fetcher when is_function(fetcher, 1) -> fetcher.(tenant_id)
      _other -> CredentialStore.fetch(tenant_id)
    end
  end

  defp credential_value(credential, key) do
    Map.get(credential, key) || Map.get(credential, Atom.to_string(key))
  end

  defp result_status(:ok), do: :ok
  defp result_status({:error, _reason}), do: :error
  defp result_status(_other), do: :error

  defp safe_call(fun) do
    fun.()
  rescue
    _exception -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp result(checks) do
    %{checks: checks, checked_at: DateTime.utc_now()}
  end

  defp resolve_host(host) when is_binary(host) and host != "", do: host

  defp resolve_host(_host) do
    Application.get_env(:koe_frame, :auth_callback_redirect_host) ||
      setup_redirect_host()
  end

  defp setup_redirect_host do
    case Application.get_env(:koe_frame, :auth_setup_redirect_uri) do
      uri when is_binary(uri) -> URI.parse(uri).host
      _other -> nil
    end
  end
end
