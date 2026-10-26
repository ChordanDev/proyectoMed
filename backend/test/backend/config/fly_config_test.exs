defmodule Backend.Config.FlyConfigTest do
  @moduledoc """
  Fly deploy settings read by `config/runtime.exs` (#344): the machine id that
  names a session's owner, and the concurrent-session cap.
  """

  # Mutates operating system environment variables.
  use ExUnit.Case, async: false

  @runtime_config Path.expand("../../../config/runtime.exs", __DIR__)
  @variables ~w(DATABASE_URL SECRET_KEY_BASE MAILER_PROVIDER FLY_MACHINE_ID MAX_CONCURRENT_SESSIONS)

  setup do
    original = Map.new(@variables, &{&1, System.get_env(&1)})
    Enum.each(@variables, &System.delete_env/1)

    on_exit(fn ->
      for {name, value} <- original do
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end
    end)

    :ok
  end

  defp backend_config(env \\ :prod) do
    System.put_env("DATABASE_URL", "ecto://app:example@db.example.test/proyectomed")
    System.put_env("SECRET_KEY_BASE", String.duplicate("a", 64))
    System.put_env("MAILER_PROVIDER", "local")

    @runtime_config
    |> Config.Reader.read!(env: env, target: :host)
    |> Keyword.get(:backend, [])
  end

  describe "FLY_MACHINE_ID" do
    test "names the machine that owns the sessions it starts" do
      System.put_env("FLY_MACHINE_ID", "e2865013b45e78")
      assert backend_config()[:machine_id] == "e2865013b45e78"
    end

    test "unset outside Fly, so session ids carry no owner" do
      refute Keyword.has_key?(backend_config(), :machine_id)
    end

    test "refuses to boot on a value that cannot be a machine id" do
      System.put_env("FLY_MACHINE_ID", "not a machine;id")

      error = assert_raise ArgumentError, fn -> backend_config() end
      assert error.message =~ "FLY_MACHINE_ID"
    end

    test "test reads none of it" do
      System.put_env("FLY_MACHINE_ID", "e2865013b45e78")
      refute Keyword.has_key?(backend_config(:test), :machine_id)
    end
  end
end
