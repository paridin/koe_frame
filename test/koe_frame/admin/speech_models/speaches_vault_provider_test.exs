defmodule Defdo.KoeFrame.Admin.SpeechModels.SpeachesVaultProviderTest do
  use ExUnit.Case, async: true

  alias Defdo.KoeFrame.Admin.SpeechModels.SpeachesVaultProvider
  alias Defdo.Tenant.Context

  defmodule FakeSDK do
    def build_uri(resource, project, code, opts) do
      send(Process.get(:speaches_vault_owner), {:built_reference, resource, project, code, opts})
      {:ok, "vault://secret/koe_frame/speaches_asr?otp_app=koe_frame&env=test"}
    end

    def resolve_value_from(reference) do
      send(Process.get(:speaches_vault_owner), {:resolved_reference, reference})
      Process.get(:speaches_vault_result)
    end
  end

  test "resolves tenant-scoped connection data from Vault" do
    Context.with_context("tenant-speech-test", fn ->
      Process.put(:speaches_vault_owner, self())
      Process.put(:speaches_vault_result, {:ok, %{"base_url" => "http://speaches.test.invalid"}})

      assert {:ok, %{base_url: "http://speaches.test.invalid", api_key: nil}} =
               SpeachesVaultProvider.fetch(resolver: FakeSDK)

      assert_received {:built_reference, :secret, "koe_frame", "speaches_asr",
                       [query: %{otp_app: "koe_frame", env: "test"}]}

      assert_received {:resolved_reference,
                       "vault://secret/koe_frame/speaches_asr?otp_app=koe_frame&env=test"}
    end)
  end

  test "does not query Vault without tenant context" do
    Context.clear()
    Process.put(:speaches_vault_owner, self())

    assert {:error, :missing_tenant_context} = SpeachesVaultProvider.fetch(resolver: FakeSDK)
    refute_received {:resolved_reference, _reference}
  end

  test "rejects invalid endpoint data and sanitizes Vault failures" do
    Context.with_context("tenant-speech-test", fn ->
      Process.put(:speaches_vault_owner, self())
      Process.put(:speaches_vault_result, {:ok, %{"base_url" => "http://user:pass@example.test"}})

      assert {:error, :speaches_credentials_unavailable} =
               SpeachesVaultProvider.fetch(resolver: FakeSDK)

      Process.put(:speaches_vault_result, {:error, {:database_error, "private detail"}})

      assert {:error, :speaches_credentials_unavailable} =
               SpeachesVaultProvider.fetch(resolver: FakeSDK)
    end)
  end
end
