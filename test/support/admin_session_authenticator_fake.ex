defmodule Defdo.KoeFrame.Admin.SessionAuthenticatorFake do
  @behaviour Defdo.KoeFrame.Admin.SessionAuthenticator

  @impl true
  def authenticate(cache_key, tenant_id) do
    if pid = Application.get_env(:koe_frame, :admin_session_authenticator_test_pid) do
      send(pid, {:session_authentication_requested, cache_key, tenant_id})
    end

    Application.get_env(
      :koe_frame,
      :admin_session_authenticator_test_result,
      {:error, :identity_session_unavailable}
    )
  end
end

defmodule Defdo.KoeFrame.Admin.TokenVerifierFake do
  @behaviour Defdo.KoeFrame.Admin.TokenVerifier

  @impl true
  def introspect(token, config) do
    if pid = Application.get_env(:koe_frame, :admin_token_verifier_test_pid) do
      send(pid, {:token_introspection_requested, token, Map.delete(config, :client_secret)})
    end

    Application.get_env(:koe_frame, :admin_token_verifier_test_result, {:error, :unavailable})
  end
end
