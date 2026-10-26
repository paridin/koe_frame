defmodule Defdo.KoeFrameWeb.PageControllerTest do
  use Defdo.KoeFrameWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)

    assert response =~ "KoeFrame"
    assert response =~ "href=\"/admin\""
    assert response =~ "does not create an IAM user"
  end

  test "GET /admin/forbidden explains that authenticated users still need admin permission", %{
    conn: conn
  } do
    conn = get(conn, "/admin/forbidden")
    response = html_response(conn, 403)

    assert response =~ "Administrator access required"
    assert response =~ "does not carry KoeFrame's administrator permission"
  end
end
