defmodule BackendWeb.MeResultController do
  @moduledoc """
  The learner's results history for the Unreal client (#338, ADR-013
  amendment on #209): `GET /me/results` lists the learner's stored
  Educational Results newest first, with the optional `area`, `page` and
  `page_size` query parameters; `GET /me/results/:id` shows one, its `result`
  exactly as served at the end of the session. Another learner's result is
  `404 result_not_found`. Nothing is aggregated across sessions.
  """

  use BackendWeb, :controller

  alias Backend.Stations

  @max_page_size 100
  @max_page 100_000

  def index(conn, params) do
    with {:ok, page} <- positive_integer(params, "page", 1, @max_page),
         {:ok, page_size} <- positive_integer(params, "page_size", 20, @max_page_size),
         {:ok, area} <- area(params) do
      body =
        Stations.list_results(conn.assigns.current_scope.user.id,
          area: area,
          page: page,
          page_size: page_size
        )

      conn
      |> put_resp_header("cache-control", "no-store")
      |> json(body)
    else
      :error ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "invalid_parameters",
          message:
            "Parâmetros inválidos: 'page' deve ser um inteiro de 1 a #{@max_page}, 'page_size' um inteiro " <>
              "de 1 a #{@max_page_size} e 'area' um texto."
        })
    end
  end

  def show(conn, %{"id" => id}) do
    case Stations.get_result(conn.assigns.current_scope.user.id, id) do
      {:ok, result} ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> json(result)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "result_not_found", message: "Resultado não encontrado."})
    end
  end

  defp positive_integer(params, key, default, max) do
    case Map.fetch(params, key) do
      :error ->
        {:ok, default}

      {:ok, value} when is_binary(value) ->
        case Integer.parse(value) do
          {number, ""} when number > 0 and number <= max -> {:ok, number}
          _other -> :error
        end

      {:ok, _value} ->
        :error
    end
  end

  defp area(%{"area" => area}) when is_binary(area) do
    case String.trim(area) do
      "" -> {:ok, nil}
      area -> {:ok, area}
    end
  end

  defp area(%{"area" => _area}), do: :error
  defp area(_params), do: {:ok, nil}
end
