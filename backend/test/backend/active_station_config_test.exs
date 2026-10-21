defmodule Backend.ActiveStationConfigTest do
  # Restarts the supervised Station Loader and edits application env: not async.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Backend.Stations
  alias Backend.Stations.StationLoader

  @runtime_config Path.expand("../../config/runtime.exs", __DIR__)
  @default_station_id "chest-pain-initial-assessment"

  setup do
    original = Application.fetch_env(:backend, :active_station_id)

    on_exit(fn ->
      case original do
        {:ok, value} -> Application.put_env(:backend, :active_station_id, value)
        :error -> Application.delete_env(:backend, :active_station_id)
      end

      restart_loader()
    end)

    :ok
  end

  describe "active station selection at boot" do
    test "the configured acute-appendicitis station becomes the active station" do
      Application.put_env(:backend, :active_station_id, "acute-appendicitis")
      restart_loader()

      assert Stations.get_active_station()["station_id"] == "acute-appendicitis"
    end

    test "without a configured id the active station is chest-pain" do
      Application.delete_env(:backend, :active_station_id)
      restart_loader()

      assert Stations.get_active_station()["station_id"] == @default_station_id
    end

    test "the default configuration selects chest-pain" do
      assert Application.fetch_env!(:backend, :active_station_id) == @default_station_id
    end

    test "an unknown station id fails with an error naming the id" do
      Application.put_env(:backend, :active_station_id, "no-such-station")

      log =
        capture_log(fn ->
          error = assert_raise RuntimeError, fn -> StationLoader.load_active() end
          assert error.message =~ ~s("no-such-station")
          assert error.message =~ "arquivo não encontrado"
        end)

      assert log =~ ~s("no-such-station")
    end

    for malformed <- ["../fixtures", "Acute-Appendicitis", "acute/appendicitis", "a b", ".."] do
      test "a malformed station id #{inspect(malformed)} fails with an error naming the id" do
        Application.put_env(:backend, :active_station_id, unquote(malformed))

        log =
          capture_log(fn ->
            error = assert_raise RuntimeError, fn -> StationLoader.load_active() end
            assert error.message =~ inspect(unquote(malformed))
            assert error.message =~ "inválido"
          end)

        assert log =~ inspect(unquote(malformed))
      end
    end
  end

  describe "ACTIVE_STATION_ID in config/runtime.exs" do
    setup do
      original = System.get_env("ACTIVE_STATION_ID")

      on_exit(fn ->
        if original,
          do: System.put_env("ACTIVE_STATION_ID", original),
          else: System.delete_env("ACTIVE_STATION_ID")
      end)

      :ok
    end

    test "sets the active station id outside test" do
      System.put_env("ACTIVE_STATION_ID", "acute-appendicitis")

      assert runtime_station_id(:dev) == "acute-appendicitis"
      assert runtime_station_id(:prod) == "acute-appendicitis"
    end

    test "trims surrounding whitespace" do
      System.put_env("ACTIVE_STATION_ID", "  acute-appendicitis \n")

      assert runtime_station_id(:dev) == "acute-appendicitis"
    end

    test "leaves the default in place when unset or empty" do
      System.delete_env("ACTIVE_STATION_ID")
      assert runtime_station_id(:dev) == nil

      System.put_env("ACTIVE_STATION_ID", "   ")
      assert runtime_station_id(:dev) == nil
    end

    test "is ignored in test so the suite stays deterministic" do
      System.put_env("ACTIVE_STATION_ID", "acute-appendicitis")

      assert runtime_station_id(:test) == nil
    end
  end

  defp runtime_station_id(env) do
    # `:prod` requires a secret; give it one only for the duration of the read.
    secret = System.get_env("SECRET_KEY_BASE")
    System.put_env("SECRET_KEY_BASE", String.duplicate("a", 64))

    try do
      @runtime_config
      |> Config.Reader.read!(env: env, target: :host)
      |> Keyword.get(:backend, [])
      |> Keyword.get(:active_station_id)
    after
      if secret,
        do: System.put_env("SECRET_KEY_BASE", secret),
        else: System.delete_env("SECRET_KEY_BASE")
    end
  end

  defp restart_loader do
    :ok = Supervisor.terminate_child(Backend.Supervisor, StationLoader)
    {:ok, _pid} = Supervisor.restart_child(Backend.Supervisor, StationLoader)
  end
end
