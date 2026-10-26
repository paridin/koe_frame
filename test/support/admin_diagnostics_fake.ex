defmodule Defdo.KoeFrameWeb.Admin.DiagnosticsFake do
  def run(tenant_id, host) do
    if test_pid = Application.get_env(:koe_frame, :identity_diagnostics_test_pid) do
      send(test_pid, {:identity_diagnostics_ran, tenant_id, host})
    end

    %{
      checked_at: DateTime.utc_now(),
      checks: [
        %{
          id: :test_check,
          title: "Test identity connection",
          status: :ok,
          message: "The test runner completed."
        }
      ]
    }
  end
end
