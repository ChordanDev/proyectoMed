defmodule BackendWeb.ErrorJSONTest do
  use BackendWeb.ConnCase, async: true

  test "renders 404" do
    assert BackendWeb.ErrorJSON.render("404.json", %{}) == %{
             error: "not_found",
             message: "Recurso não encontrado"
           }
  end

  test "renders 500" do
    assert BackendWeb.ErrorJSON.render("500.json", %{}) == %{
             error: "internal_server_error",
             message: "Erro interno do servidor"
           }
  end
end
