defmodule Defdo.KoeFrameWeb.Hook.RequireAdmin do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [redirect: 2]

  alias Defdo.KoeFrame.Admin.Authorization
  alias Defdo.KoeFrame.Admin.Scope

  @login_path "/auth/callback"
  @forbidden_path "/admin/forbidden"

  def on_mount(:ensure, _params, session, socket) do
    case Scope.for_session(session) do
      {:ok, scope} ->
        if Authorization.authorized?(scope.user) do
          {:cont,
           socket
           |> assign(:current_user, scope.user)
           |> assign(:current_tenant_id, scope.tenant_id)
           |> assign(:admin_host, scope.host)}
        else
          {:halt, redirect(socket, to: @forbidden_path)}
        end

      {:error, _reason} ->
        {:halt, redirect(socket, to: @login_path)}
    end
  end
end
