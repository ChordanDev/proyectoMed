defmodule Backend.Config.E2EStationDurationConfigTest do
  # Reads config/runtime.exs with a controlled environment: not async, because the
  # operating system environment is global.
  use ExUnit.Case, async: false

  @runtime_config Path.expand("../../../config/runtime.exs", __DIR__)
  @variable "E2E_STATION_DURATION_MS"

  setup do
    saved = System.get_env(@variable)
    System.delete_env(@variable)

    on_exit(fn ->
      if saved, do: System.put_env(@variable, saved), else: System.delete_env(@variable)
    end)
  end

  defp station_duration_ms(value, config_env \\ :dev) do
    if value, do: System.put_env(@variable, value)

    @runtime_config
    |> Config.Reader.read!(env: config_env, target: :host)
    |> get_in([:backend, :station_duration_ms])
  end

  test "a positive E2E_STATION_DURATION_MS sets the station duration under dev" do
    assert station_duration_ms("8000") == 8_000
  end

  test "without the variable the compiled default stays in place" do
    assert station_duration_ms(nil) == nil
  end

  test "a value that is not a positive integer is ignored" do
    assert station_duration_ms("0") == nil
    assert station_duration_ms("-5") == nil
    assert station_duration_ms("fast") == nil
  end

  test "only dev honors the variable" do
    assert station_duration_ms("8000", :test) == nil
  end
end
