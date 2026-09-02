defmodule BackendWeb.ErrorJSON do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on JSON requests.

  See config/config.exs.
  """

  # If you want to customize a particular status code,
  # you may add your own clauses, such as:
  #
  # def render("500.json", _assigns) do
  #   %{errors: %{detail: "Internal Server Error"}}
  # end

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.json" becomes
  # "Not Found".
  def render(template, _assigns) do
    %{error: error_code(template), message: error_message(template)}
  end

  defp error_code("400.json"), do: "bad_request"
  defp error_code("401.json"), do: "unauthorized"
  defp error_code("403.json"), do: "forbidden"
  defp error_code("404.json"), do: "not_found"
  defp error_code("410.json"), do: "gone"
  defp error_code("422.json"), do: "unprocessable_entity"
  defp error_code("500.json"), do: "internal_server_error"
  defp error_code(_), do: "error"

  defp error_message("400.json"), do: "Solicitação inválida"
  defp error_message("401.json"), do: "Não autorizado"
  defp error_message("403.json"), do: "Acesso negado"
  defp error_message("404.json"), do: "Recurso não encontrado"
  defp error_message("410.json"), do: "Recurso expirado"
  defp error_message("422.json"), do: "Entidade não processável"
  defp error_message("500.json"), do: "Erro interno do servidor"
  defp error_message(_), do: "Erro"
end
