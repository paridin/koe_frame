defmodule Defdo.KoeFrameWeb.Admin.SystemLive do
  @moduledoc false

  use Defdo.KoeFrameWeb, :live_view
  use Defdo.Theme.Components

  on_mount({Defdo.KoeFrameWeb.Hook.RequireAdmin, :ensure})

  alias Defdo.KoeFrame.Admin.Authorization
  alias Defdo.KoeFrame.Admin.IdentityDiagnostics

  @async_timeout 20_000

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:checks, [])
      |> assign(:checked_at, nil)
      |> assign(:loading?, true)
      |> assign(:admin_scope, Authorization.admin_scope())

    if connected?(socket) do
      {:ok, start_diagnostics(socket)}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, start_diagnostics(socket)}
  end

  @impl true
  def handle_async(:identity_diagnostics, {:ok, result}, socket) do
    {:noreply,
     socket
     |> assign(:checks, result.checks)
     |> assign(:checked_at, result.checked_at)
     |> assign(:loading?, false)}
  end

  def handle_async(:identity_diagnostics, {:exit, _reason}, socket) do
    result = IdentityDiagnostics.unavailable_result()

    {:noreply,
     socket
     |> assign(:checks, result.checks)
     |> assign(:checked_at, result.checked_at)
     |> assign(:loading?, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="min-h-screen bg-base-200 text-base-content">
      <.page_header
        title="System status"
        subtitle="Check the identity services behind this KoeFrame instance."
        container={false}
        surface="bg-base-100"
        class="border-b border-base-300"
      >
        <:meta>
          <span>KoeFrame</span>
          <span aria-hidden="true">/</span>
          <span>Admin</span>
        </:meta>
        <:actions>
          <a href="/" class="btn btn-ghost btn-sm">Home</a>
          <.link navigate="/admin/speech-models" class="btn btn-ghost btn-sm">Speech models</.link>
          <button
            id="refresh-identity-diagnostics"
            type="button"
            class="btn btn-primary btn-sm"
            phx-click="refresh"
            disabled={@loading?}
          >
            <.icon :if={@loading?} name="hero-arrow-path" class="size-4 animate-spin" />
            {if @loading?, do: "Checking…", else: "Check again"}
          </button>
        </:actions>
      </.page_header>

      <div class="mx-auto max-w-5xl space-y-6 px-4 py-8 sm:px-6 lg:px-8">
        <section class="flex flex-col gap-3 border-b border-base-300 pb-5 sm:flex-row sm:items-end sm:justify-between">
          <div class="min-w-0">
            <p class="text-sm text-base-content/65">Signed in as</p>
            <h2 class="break-words text-lg font-semibold">
              {user_label(@current_user)}
            </h2>
          </div>
          <div class="flex flex-wrap items-center gap-3">
            <.badge
              :if={!@loading?}
              variant={overall_variant(@checks)}
              label={overall_label(@checks)}
            />
            <time
              :if={@checked_at}
              class="font-mono text-xs text-base-content/60"
              datetime={DateTime.to_iso8601(@checked_at)}
            >
              Checked {format_time(@checked_at)}
            </time>
          </div>
        </section>

        <div
          :if={@loading?}
          id="identity-diagnostics-loading"
          class="flex items-center gap-3 py-8 text-sm text-base-content/70"
          role="status"
        >
          <span class="loading loading-spinner loading-sm text-primary" aria-hidden="true"></span>
          Checking OIDC, the Auth preflight, and the stored admin login registration…
        </div>

        <div
          :if={!@loading?}
          id="identity-diagnostics"
          class="grid grid-cols-1 gap-3 md:grid-cols-2"
          aria-live="polite"
        >
          <.panel
            :for={check <- @checks}
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
            Admin access verified with an active IdP token carrying {@admin_scope} for this tenant.
          </p>
        </.panel>

        <.alert variant="info" live={false} class="items-start">
          <p>
            These checks are read-only. The Auth first-admin preflight validates readiness; it does not create an IAM user.
          </p>
        </.alert>
      </div>
    </main>
    """
  end

  defp start_diagnostics(socket) do
    tenant_id = socket.assigns.current_tenant_id
    host = socket.assigns.admin_host

    runner = Application.get_env(:koe_frame, :identity_diagnostics_runner, IdentityDiagnostics)

    socket
    |> assign(:loading?, true)
    |> start_async(
      :identity_diagnostics,
      fn -> runner.run(tenant_id, host) end,
      timeout: @async_timeout
    )
  end

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
