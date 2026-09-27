defmodule Defdo.KoeFrameWeb.PageController do
  use Defdo.KoeFrameWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
