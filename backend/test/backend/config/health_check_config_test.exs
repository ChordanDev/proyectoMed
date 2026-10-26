defmodule Backend.Config.HealthCheckConfigTest do
  @moduledoc """
  Fly's health checks reach the machine over plain HTTP (#344), so `/health`
  must stay outside the production HTTPS redirect.
  """

  use ExUnit.Case, async: true

  import Plug.Test

  @prod_config Path.expand("../../../config/prod.exs", __DIR__)

  defp force_ssl do
    @prod_config
    |> Config.Reader.read!(env: :prod, target: :host)
    |> get_in([:backend, BackendWeb.Endpoint, :force_ssl])
  end

  test "prod redirects plain HTTP but not the health check" do
    ssl = Plug.SSL.init(force_ssl())

    health = :get |> conn("http://backend.example.test/health") |> Plug.SSL.call(ssl)
    refute health.halted

    other = :get |> conn("http://backend.example.test/sessions") |> Plug.SSL.call(ssl)
    assert other.halted
    assert other.status == 301
  end
end
