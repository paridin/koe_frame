defmodule Defdo.KoeFrame.Subtitler.VaultTokenProviderTest do
  use ExUnit.Case, async: true

  alias Defdo.KoeFrame.Subtitler.VaultTokenProvider
  alias Defdo.Tenant.Context

  defmodule FakeSDK do
    def resolve_value_from(reference) do
      send(Process.get(:resolver_test_owner), {:vault_reference, reference})
      Process.get(:resolver_test_result)
    end
  end

  @reference "vault://secret/subtitler/koe_frame_cue_api_token?otp_app=koe_frame&env=test"
  @token String.duplicate("v", 40)

  test "resolves the reference only after the tenant edge established context" do
    Context.with_context("tenant-cue-client", fn ->
      Process.put(:resolver_test_owner, self())
      Process.put(:resolver_test_result, {:ok, %{token: @token}})

      assert {:ok, @token} = VaultTokenProvider.fetch_token(@reference, resolver: FakeSDK)
      assert_received {:vault_reference, @reference}
    end)
  end

  test "does not resolve a secret when tenant context is absent" do
    Context.clear()
    Process.put(:resolver_test_owner, self())

    assert {:error, :missing_tenant_context} =
             VaultTokenProvider.fetch_token(@reference, resolver: FakeSDK)

    refute_received {:vault_reference, _reference}
  end

  test "rejects short or malformed Vault payloads without returning them" do
    Context.with_context("tenant-cue-client", fn ->
      Process.put(:resolver_test_owner, self())
      Process.put(:resolver_test_result, {:ok, %{"token" => "short"}})

      assert {:error, :credential_unavailable} =
               VaultTokenProvider.fetch_token(@reference, resolver: FakeSDK)
    end)
  end

  test "sanitizes Vault lookup failures" do
    Context.with_context("tenant-cue-client", fn ->
      Process.put(:resolver_test_owner, self())
      Process.put(:resolver_test_result, {:error, {:database_error, "private data"}})

      assert {:error, :credential_unavailable} =
               VaultTokenProvider.fetch_token(@reference, resolver: FakeSDK)
    end)
  end
end
