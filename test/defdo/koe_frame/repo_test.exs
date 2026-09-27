defmodule Defdo.KoeFrame.RepoTest do
  use ExUnit.Case, async: true

  alias Defdo.KoeFrame.Repo

  test "tenant scoping skips shared infrastructure and keeps app tables scoped" do
    assert Repo.skip_table({"tenant_profiles", "defdo_koe_frame"})
    assert Repo.skip_table({"oban_jobs", "defdo_koe_frame"})
    assert Repo.skip_table({"shared_domain_policies", "defdo_koe_frame"})
    refute Repo.skip_table({"koe_frame_integrations", "defdo_koe_frame"})
  end
end
