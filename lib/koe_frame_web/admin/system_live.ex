defmodule Defdo.KoeFrameWeb.Admin.SystemLive do
  @moduledoc false

  use Defdo.KoeFrameWeb, :live_view
  use Defdo.Theme.Components

  on_mount({Defdo.KoeFrameWeb.Hook.RequireAdmin, :ensure})

  alias Defdo.KoeFrame.Admin.Authorization
  alias Defdo.KoeFrame.Admin.IdentityDiagnostics

  @async_timeout 20_000

  defmodule Model do
    @moduledoc false
    defstruct diagnostics: :loading, checked_at: nil, admin_scope: nil, current_user: nil
  end

  @impl true
  def mount(_params, _session, socket) do
    model = %Model{
      admin_scope: Authorization.admin_scope(),
      current_user: socket.assigns[:current_user]
    }

    socket = assign(socket, :model, model)

    if connected?(socket) do
      {:ok, run_cmds(socket, [:load_diagnostics])}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event(name, params, socket) when is_binary(name) and is_map(params) do
    case parse_msg(name, params) do
      {:ok, msg} -> {:noreply, dispatch(msg, socket)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event(name, _params, socket) do
    require Logger
    Logger.debug("ignored admin system event #{inspect(name)}")
    {:noreply, socket}
  end

  @impl true
  def handle_async(:identity_diagnostics, {:ok, result}, socket) do
    {:noreply, dispatch({:diagnostics_loaded, {:ok, result}}, socket)}
  end

  def handle_async(:identity_diagnostics, {:exit, _reason}, socket) do
    {:noreply, dispatch({:diagnostics_loaded, :error}, socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin_shell
      flash={@flash}
      page_title="System status"
      subtitle="Check the identity services behind this KoeFrame instance."
      current_page={:system}
    >
      <:actions>
        <button
          id="refresh-identity-diagnostics"
          type="button"
          class="btn btn-primary btn-sm"
          phx-click="refresh"
          disabled={loading?(@model)}
        >
          <.icon :if={loading?(@model)} name="hero-arrow-path" class="size-4 animate-spin" />
          {if loading?(@model), do: "Checking…", else: "Check again"}
        </button>
      </:actions>

      <div class="w-full max-w-7xl space-y-6">
        <section class="flex flex-col gap-3 border-b border-base-300 pb-5 sm:flex-row sm:items-end sm:justify-between">
          <div class="min-w-0">
            <p class="text-sm text-base-content/65">Signed in as</p>
            <h2 class="break-words text-lg font-semibold">
              {user_label(@model.current_user)}
            </h2>
          </div>
          <div class="flex flex-wrap items-center gap-3">
            <.badge
              :if={!loading?(@model)}
              variant={overall_variant(checks(@model))}
              label={overall_label(checks(@model))}
            />
            <time
              :if={@model.checked_at}
              class="font-mono text-xs text-base-content/60"
              datetime={DateTime.to_iso8601(@model.checked_at)}
            >
              Checked {format_time(@model.checked_at)}
            </time>
          </div>
        </section>

        <div
          :if={loading?(@model)}
          id="identity-diagnostics-loading"
          class="flex items-center gap-3 py-8 text-sm text-base-content/70"
          role="status"
        >
          <span class="loading loading-spinner loading-sm text-primary" aria-hidden="true"></span>
          Checking OIDC, the Auth preflight, and the stored admin login registration…
        </div>

        <div
          :if={!loading?(@model)}
          id="identity-diagnostics"
          class="grid grid-cols-1 gap-3 md:grid-cols-2"
          aria-live="polite"
        >
          <.panel
            :for={check <- checks(@model)}
            id={"identity-check-#{check.id}"}
            scroll={false}
            class="h-full"
            padding="p-4"
          >
            <:header>
              <div class="flex min-w-0 items-start justify-between gap-3">
                <h3 class="min-w-0 break-words text-base font-semibold">{check.title}</h3>
                <.badge variant={check_variant(check.status)} label={check_label(check.status)} />
              </div>
            </:header>
            <p class="mt-3 text-sm leading-6 text-base-content/75">{check.message}</p>
          </.panel>
        </div>

        <.panel id="identity-check-admin-authorization" scroll={false} padding="p-4">
          <:header>
            <div class="flex min-w-0 items-start justify-between gap-3">
              <h3 class="min-w-0 break-words text-base font-semibold">Admin authorization</h3>
              <.badge variant="success" label="Passed" />
            </div>
          </:header>
          <p class="mt-3 text-sm leading-6 text-base-content/75">
            Admin access verified with an active IdP token carrying {@model.admin_scope} for this tenant.
          </p>
        </.panel>

        <.alert variant="info" live={false} class="items-start">
          <p>
            These checks are read-only. The Auth first-admin preflight validates readiness; it does not create an IAM user.
          </p>
        </.alert>
      </div>
    </Layouts.admin_shell>
    """
  end

  def parse_msg("refresh", params) when is_map(params), do: {:ok, :refresh}
  def parse_msg(_name, _params), do: :error

  def update(:refresh, %Model{diagnostics: :loading} = model), do: {model, []}
  def update(:refresh, model), do: {%{model | diagnostics: :loading}, [:load_diagnostics]}

  def update({:diagnostics_loaded, {:ok, result}}, model) when is_map(result) do
    {%{model | diagnostics: {:ready, result.checks}, checked_at: result.checked_at}, []}
  end

  def update({:diagnostics_loaded, _error}, model) do
    result = IdentityDiagnostics.unavailable_result()
    {%{model | diagnostics: {:ready, result.checks}, checked_at: result.checked_at}, []}
  end

  def update(_message, model), do: {model, []}

  defp dispatch(msg, socket) do
    {model, cmds} = update(msg, socket.assigns.model)
    socket |> assign(:model, model) |> run_cmds(cmds)
  end

  defp run_cmds(socket, []), do: socket

  defp run_cmds(socket, [:load_diagnostics | rest]) do
    tenant_id = socket.assigns.current_tenant_id
    host = socket.assigns.admin_host
    runner = Application.get_env(:koe_frame, :identity_diagnostics_runner, IdentityDiagnostics)

    socket =
      start_async(socket, :identity_diagnostics, fn -> runner.run(tenant_id, host) end,
        timeout: @async_timeout
      )

    run_cmds(socket, rest)
  end

  defp loading?(%Model{diagnostics: :loading}), do: true
  defp loading?(%Model{}), do: false
  defp checks(%Model{diagnostics: {:ready, checks}}), do: checks
  defp checks(%Model{}), do: []

  defp user_label(%{name: name}) when is_binary(name) and name != "", do: name
  defp user_label(%{email: email}) when is_binary(email) and email != "", do: email
  defp user_label(_user), do: "Authenticated administrator"

  defp overall_variant(checks) do
    if Enum.all?(checks, &(&1.status == :ok)), do: "success", else: "warning"
  end

  defp overall_label(checks) do
    if Enum.all?(checks, &(&1.status == :ok)), do: "All checks passed", else: "Needs attention"
  end

  defp check_variant(:ok), do: "success"
  defp check_variant(:error), do: "error"
  defp check_variant(:skipped), do: "ghost"

  defp check_label(:ok), do: "Passed"
  defp check_label(:error), do: "Needs attention"
  defp check_label(:skipped), do: "Not checked"

  defp format_time(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")
end
