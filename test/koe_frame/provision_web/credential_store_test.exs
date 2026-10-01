defmodule Defdo.KoeFrame.ProvisionWeb.CredentialStoreTest do
  use ExUnit.Case, async: true

  alias Defdo.KoeFrame.ProvisionWeb.CredentialStore

  @complete_credentials %{
    "site" => "https://idp.example.test",
    "client_id" => "client-test",
    "client_secret" => "secret-test",
    "redirect_uri" => "https://koe.example.test/auth/callback",
    "connection" => "koe-frame-users"
  }

  test "accepts a complete credential returned by Vault" do
    assert CredentialStore.valid_admin_access?(@complete_credentials)
  end

  test "rejects partial Vault data as usable admin access" do
    refute CredentialStore.valid_admin_access?(Map.delete(@complete_credentials, "connection"))
    refute CredentialStore.valid_admin_access?(Map.delete(@complete_credentials, "redirect_uri"))
    refute CredentialStore.valid_admin_access?(%{"client_id" => "client-test"})
  end

  test "accepts the adapter's atom-keyed credential shape" do
    credential = %{
      site: @complete_credentials["site"],
      client_id: @complete_credentials["client_id"],
      client_secret: @complete_credentials["client_secret"],
      redirect_uri: @complete_credentials["redirect_uri"],
      connection: @complete_credentials["connection"]
    }

    assert CredentialStore.valid_admin_access?(credential)
  end
end
