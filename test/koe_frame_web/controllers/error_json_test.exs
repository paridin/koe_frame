defmodule Defdo.KoeFrameWeb.ErrorJSONTest do
  use Defdo.KoeFrameWeb.ConnCase, async: true

  test "renders 404" do
    assert Defdo.KoeFrameWeb.ErrorJSON.render("404.json", %{}) == %{
             errors: %{detail: "Not Found"}
           }
  end

  test "renders 500" do
    assert Defdo.KoeFrameWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
