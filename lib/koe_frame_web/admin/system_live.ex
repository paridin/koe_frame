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

      <div class="mx-auto w-full max-w-6xl space-y-8">
        <section
          data-slot="identity-summary"
          data-state={summary_state(@model)}
          class="flex flex-col gap-4 border-b border-base-300 pb-5 sm:flex-row sm:items-center sm:justify-between"
        >
          <div class="flex min-w-0 items-center gap-4">
            <span class={summary_mark_class(@model)} aria-hidden="true">
              <.icon name={summary_icon(@model)} class="size-5" />
            </span>
            <div class="min-w-0">
              <p class="text-sm font-semibold">{summary_label(@model)}</p>
              <p class="mt-1 break-words text-sm text-base-content/70">
                Signed in as
                <span class="font-medium text-base-content">{user_label(@model.current_user)}</span>
              </p>
            </div>
          </div>
          <div class="flex shrink-0 flex-col gap-1 text-sm text-base-content/65 sm:items-end">
            <time
              :if={@model.checked_at}
              class="font-mono text-xs"
              datetime={DateTime.to_iso8601(@model.checked_at)}
            >
              Last checked {format_time(@model.checked_at)}
            </time>
            <span :if={!@model.checked_at}>Checks run when this page opens</span>
            <span class="font-mono text-xs">Scope: {@model.admin_scope}</span>
          </div>
        </section>

        <div
          :if={loading?(@model)}
          id="identity-diagnostics-loading"
          class="flex min-h-32 items-center gap-3 text-sm text-base-content/70"
          role="status"
        >
          <span class="loading loading-spinner loading-sm text-primary" aria-hidden="true"></span>
          Checking identity services…
        </div>

        <section
          :if={!loading?(@model)}
          id="identity-diagnostics"
          aria-labelledby="identity-checks-heading"
          aria-live="polite"
        >
          <div class="mb-3 flex items-baseline justify-between gap-3">
            <h2 id="identity-checks-heading" class="text-base font-semibold">Service checks</h2>
            <span class="text-xs text-base-content/60">Read-only</span>
          </div>
          <ul class="divide-y divide-base-300 border-y border-base-300">
            <li
              :for={check <- checks(@model)}
              id={"identity-check-#{check.id}"}
              data-slot="service-check"
              data-state={check.status}
              class="grid grid-cols-[1.5rem_minmax(0,1fr)] gap-x-3 gap-y-1 py-4 sm:grid-cols-[1.5rem_minmax(10rem,0.8fr)_minmax(0,2fr)_auto] sm:items-center"
            >
              <span aria-hidden="true">
                <.icon
                  name={check_icon(check.status)}
                  class={check_icon_class(check.status)}
                />
              </span>
              <h3 class="min-w-0 break-words text-sm font-semibold">{check.title}</h3>
              <p class="col-start-2 text-sm leading-5 text-base-content/70 sm:col-start-auto">
                {check.message}
              </p>
              <.badge
                class="col-start-2 mt-1 w-fit sm:col-start-auto sm:mt-0"
                variant={check_variant(check.status)}
                label={check_label(check.status)}
              />
            </li>
            <li
              id="identity-check-admin-authorization"
              data-slot="service-check"
              data-state="ok"
              class="grid grid-cols-[1.5rem_minmax(0,1fr)] gap-x-3 gap-y-1 py-4 sm:grid-cols-[1.5rem_minmax(10rem,0.8fr)_minmax(0,2fr)_auto] sm:items-center"
            >
              <span aria-hidden="true">
                <.icon name="hero-check-circle" class="size-5 text-success" />
              </span>
              <h3 class="min-w-0 text-sm font-semibold">Admin authorization</h3>
              <p class="col-start-2 text-sm leading-5 text-base-content/70 sm:col-start-auto">
                Active IdP token carries the required tenant scope.
              </p>
              <.badge
                class="col-start-2 mt-1 w-fit sm:col-start-auto sm:mt-0"
                variant="success"
                label="Passed"
              />
            </li>
          </ul>
          <p class="mt-4 max-w-3xl border-l-2 border-base-300 pl-3 text-sm leading-5 text-base-content/65">
            The Auth first-admin preflight checks readiness only; it does not create an IAM user.
          </p>
        </section>
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

  defp check_variant(:ok), do: "success"
  defp check_variant(:error), do: "error"
  defp check_variant(:skipped), do: "ghost"

  defp check_icon(:ok), do: "hero-check-circle"
  defp check_icon(:error), do: "hero-exclamation-circle"
  defp check_icon(:skipped), do: "hero-minus-circle"
  defp check_icon(_status), do: "hero-question-mark-circle"

  defp check_icon_class(:ok), do: "size-5 text-success"
  defp check_icon_class(:error), do: "size-5 text-error"
  defp check_icon_class(:skipped), do: "size-5 text-base-content/50"
  defp check_icon_class(_status), do: "size-5 text-base-content/50"

  defp summary_state(%Model{diagnostics: :loading}), do: "loading"

  defp summary_state(%Model{diagnostics: {:ready, checks}}) do
    if Enum.all?(checks, &(&1.status == :ok)), do: "ok", else: "attention"
  end

  defp summary_label(%Model{diagnostics: :loading}), do: "Checking identity services"

  defp summary_label(%Model{diagnostics: {:ready, checks}}) do
    if Enum.all?(checks, &(&1.status == :ok)), do: "All checks passed", else: "Attention required"
  end

  defp summary_mark_class(%Model{diagnostics: :loading}),
    do:
      "flex size-10 shrink-0 items-center justify-center border border-base-300 text-base-content/60"

  defp summary_mark_class(%Model{diagnostics: {:ready, checks}}) do
    if Enum.all?(checks, &(&1.status == :ok)),
      do:
        "flex size-10 shrink-0 items-center justify-center border border-success/40 bg-success/10 text-success",
      else:
        "flex size-10 shrink-0 items-center justify-center border border-warning/40 bg-warning/10 text-warning"
  end

  defp summary_icon(%Model{diagnostics: :loading}), do: "hero-arrow-path"

  defp summary_icon(%Model{diagnostics: {:ready, checks}}) do
    if Enum.all?(checks, &(&1.status == :ok)), do: "hero-check", else: "hero-exclamation-triangle"
  end

  defp check_label(:ok), do: "Passed"
  defp check_label(:error), do: "Needs attention"
  defp check_label(:skipped), do: "Not checked"

  defp format_time(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")
end
