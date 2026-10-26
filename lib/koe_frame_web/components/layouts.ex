defmodule Defdo.KoeFrameWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use Defdo.KoeFrameWeb, :html
  import Defdo.Theme.Components.Admin.PageShell, only: [admin_page_shell: 1]
  import Defdo.Theme.Components.Admin.NavGroup, only: [nav_group: 1]

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :page_title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :current_page, :atom, values: [:system, :speech_models], required: true
  slot :actions
  slot :inner_block, required: true

  def admin_shell(assigns) do
    ~H"""
    <.admin_page_shell
      id="koe-frame-admin-shell"
      title={@page_title}
      subtitle={@subtitle}
      nav_label={gettext("Admin navigation")}
      nav_trigger_label={gettext("Open admin navigation")}
      container={false}
    >
      <:logo>
        <.link
          navigate="/admin"
          class="flex items-center gap-3"
          aria-label={gettext("KoeFrame admin home")}
        >
          <span class="flex size-9 shrink-0 items-center justify-center rounded-box border border-base-content/10 bg-base-200 text-xs font-semibold tracking-tight">
            KF
          </span>
          <span class="text-sm font-semibold tracking-tight">KoeFrame</span>
        </.link>
      </:logo>

      <:nav>
        <.nav_group id="koe-frame-admin-navigation" label={gettext("Workspace")} open>
          <:item>
            <.link
              navigate="/admin"
              aria-current={if @current_page == :system, do: "page", else: nil}
              class={admin_nav_class(@current_page == :system)}
            >
              <.icon name="hero-heart" class="size-4 shrink-0" />
              <span>{gettext("System status")}</span>
            </.link>
          </:item>
          <:item>
            <.link
              navigate="/admin/speech-models"
              aria-current={if @current_page == :speech_models, do: "page", else: nil}
              class={admin_nav_class(@current_page == :speech_models)}
            >
              <.icon name="hero-cpu-chip" class="size-4 shrink-0" />
              <span>{gettext("Speech models")}</span>
            </.link>
          </:item>
        </.nav_group>
      </:nav>

      <:actions>{render_slot(@actions)}</:actions>

      <.flash_group flash={@flash} />
      {render_slot(@inner_block)}
    </.admin_page_shell>
    """
  end

  defp admin_nav_class(true), do: "btn btn-ghost btn-sm justify-start active"
  defp admin_nav_class(false), do: "btn btn-ghost btn-sm justify-start"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href="/" class="flex-1 flex w-fit items-center gap-2">
          <img src={~p"/images/logo.svg"} width="36" />
          <span class="text-sm font-semibold">v{Application.spec(:phoenix, :vsn)}</span>
        </a>
      </div>
      <div class="flex-none">
        <ul class="flex flex-column px-1 space-x-4 items-center">
          <li>
            <a href="https://phoenixframework.org/" class="btn btn-ghost">Website</a>
          </li>
          <li>
            <a href="https://github.com/phoenixframework/phoenix" class="btn btn-ghost">GitHub</a>
          </li>
          <li>
            <.theme_toggle />
          </li>
          <li>
            <a href="https://phoenix.hexdocs.pm/overview.html" class="btn btn-primary">
              Get Started <span aria-hidden="true">&rarr;</span>
            </a>
          </li>
        </ul>
      </div>
    </header>

    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
