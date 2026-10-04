defmodule Defdo.KoeFrameWeb.PageController do
  use Defdo.KoeFrameWeb, :controller

  def home(conn, _params), do: render(conn, :home)

  def forbidden(conn, _params) do
    conn
    |> put_status(:forbidden)
    |> render(:forbidden)
  end
end
