defmodule Defdo.KoeFrame.ProvisionWebAdapterTest do
  use ExUnit.Case, async: true

  alias Defdo.KoeFrame.ProvisionWebAdapter

  test "uses the current canonical host for first-admin preflight" do
    context = ProvisionWebAdapter.admin_access_context(%{"domain" => "koe-frame.example.test"})

    assert context.redirect_host == "koe-frame.example.test"
  end
end
