defmodule Backend.Config.StationSourceConfigTest do
  @moduledoc """
  Production serves stations only from the database (issue #334): it never
  boots the file loader from `priv/stations`, which stays for tests and local
  development.
  """

  # Mutates operating system environment variables and the supervised loader.
  use ExUnit.Case, async: false

  alias Backend.Stations.StationLoader

  @runtime_config Path.expand("../../../config/runtime.exs", __DIR__)
  @variables ~w(DATABASE_URL SECRET_KEY_BASE MAILER_PROVIDER ACTIVE_STATION_ID)

  setup do
    original = Map.new(@variables, &{&1, System.get_env(&1)})
    Enum.each(@variables, &System.delete_env/1)
    loader = Application.fetch_env(:backend, :file_station_loader)

    on_exit(fn ->
      for {name, value} <- original do
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end

      case loader do
        {:ok, value} -> Application.put_env(:backend, :file_station_loader, value)
        :error -> Application.delete_env(:backend, :file_station_loader)
      end
    end)

    :ok
  end

  defp backend_config(env) do
    System.put_env("DATABASE_URL", "ecto://app:example@db.example.test/proyectomed")
    System.put_env("SECRET_KEY_BASE", String.duplicate("a", 64))
    System.put_env("MAILER_PROVIDER", "local")

    @runtime_config
    |> Config.Reader.read!(env: env, target: :host)
    |> Keyword.get(:backend, [])
  end

  test "prod turns the file station loader off" do
    assert backend_config(:prod)[:file_station_loader] == false
  end

  test "prod refuses to boot with ACTIVE_STATION_ID" do
    System.put_env("ACTIVE_STATION_ID", "acute-appendicitis")

    error = assert_raise RuntimeError, fn -> backend_config(:prod) end
    assert error.message =~ "ACTIVE_STATION_ID"
    assert error.message =~ "priv/stations"
  end

  test "dev keeps the file station loader and its ACTIVE_STATION_ID" do
    System.put_env("ACTIVE_STATION_ID", "acute-appendicitis")

    config = backend_config(:dev)
    refute Keyword.has_key?(config, :file_station_loader)
    assert config[:active_station_id] == "acute-appendicitis"
  end

  test "tests and dev enable the file station loader by default" do
    assert Application.fetch_env!(:backend, :file_station_loader) == true
  end

  test "the file station loader does not start when it is off" do
    Application.put_env(:backend, :file_station_loader, false)
    assert StationLoader.start_link(name: :station_source_config_test_loader) == :ignore
    assert Process.whereis(:station_source_config_test_loader) == nil
  end
end
